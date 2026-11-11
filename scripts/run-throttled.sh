#!/usr/bin/env bash
# Runs a heavy command (xcodebuild, a simulator script, `swift test`) gently on a
# developer's Mac: at a lower CPU QoS, with a job cap, and, with --lock, one at a time
# across every worktree and every repository cut from this template.
#
#   scripts/run-throttled.sh [--lock] -- <command> [args...]
#   scripts/run-throttled.sh --print-jobs
#
# --print-jobs prints the job cap N and exits; a recipe passes it on as
# `xcodebuild -jobs N` or `swift test --jobs N`. When running a command, N is also
# exported to it as THROTTLE_JOBS, so a script that runs its own xcodebuild
# (smoke_launch.sh, run-device.sh) or `swift test` (coverage.sh) can pass it on.
#
# Environment:
#   CHECK_JOBS   the job cap, a positive integer. Unset: every logical CPU under CI,
#                otherwise half of them (at least 1). CPUs come from
#                `sysctl -n hw.ncpu`, then `getconf _NPROCESSORS_ONLN`, then 2.
#   CHECK_QOS    the CPU clamp `taskpolicy -c` runs the command under: utility
#                (default), background, or off (no taskpolicy). Skipped under CI and
#                where taskpolicy does not exist (Linux).
#   CI           set by CI runners: all CPUs, no QoS clamp, and --lock does nothing
#                (each runner is its own machine).
#   RUN_THROTTLED_LOCK_DIR      where the lock lives; default
#                ${XDG_CACHE_HOME:-$HOME/.cache}/run-throttled. Never $TMPDIR or the
#                checkout: those differ between sandboxed and unsandboxed sessions and
#                would silently split one lock into two.
#   RUN_THROTTLED_WAIT_TIMEOUT  seconds to wait for the lock (default 3600).
#   RUN_THROTTLED_LOCK_HELD     exported as 1 while this script holds the lock, so a
#                nested --lock call inside the command does not wait on itself.
#
# The lock is the directory <lock dir>/xcode.lock (mkdir is atomic); its `holder` file
# holds the holder's PID and command line. A lock whose holder PID is no longer alive
# is stale and is taken over. The script stays alive while the command runs (it does
# not exec it), releases the lock on exit, INT, or TERM, and exits with the command's
# status.
#
# Git work tree: not required — it reads nothing from the tree.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_THROTTLE_USAGE         unknown argument, no `--` command, or a bad
#                              RUN_THROTTLED_WAIT_TIMEOUT
#   ERR_THROTTLE_BAD_JOBS      CHECK_JOBS is not a positive integer
#   ERR_THROTTLE_BAD_QOS       CHECK_QOS is not utility, background, or off
#   ERR_THROTTLE_LOCK_DIR      the lock's parent directory cannot be created
#   ERR_THROTTLE_LOCK_TIMEOUT  another holder kept the lock past the wait timeout
set -euo pipefail

fail() { # fail CODE WHAT EXPECTED ACTUAL NEXT
    {
        echo "$1: $2"
        echo "Expected: $3"
        echo "Actual: $4"
        echo "Next: $5"
    } >&2
    exit 1
}

usage_fail() {
    fail ERR_THROTTLE_USAGE "$1" \
        "\`scripts/run-throttled.sh [--lock] -- <command> [args...]\` or \`scripts/run-throttled.sh --print-jobs\`" \
        "$2" "fix the call (the usage is in the header of scripts/run-throttled.sh)"
}

is_uint() {
    case "$1" in
        '' | *[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

cpu_count() {
    local n
    n=$(sysctl -n hw.ncpu 2>/dev/null) || n=""
    if ! is_uint "${n}" || [ "$((10#${n}))" -lt 1 ]; then
        n=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || n=""
    fi
    if ! is_uint "${n}" || [ "$((10#${n}))" -lt 1 ]; then
        n=2
    fi
    echo "$((10#${n}))"
}

job_count() {
    local cpus
    if [ -n "${CHECK_JOBS+set}" ]; then
        if ! is_uint "${CHECK_JOBS}" || [ "$((10#${CHECK_JOBS}))" -lt 1 ]; then
            fail ERR_THROTTLE_BAD_JOBS "CHECK_JOBS is not a positive integer" \
                "CHECK_JOBS unset, or a whole number of 1 or more" "CHECK_JOBS='${CHECK_JOBS}'" \
                "set CHECK_JOBS to a number such as 4, or unset it to use half the CPUs"
        fi
        echo "$((10#${CHECK_JOBS}))"
        return
    fi
    cpus=$(cpu_count)
    if [ -n "${CI:-}" ]; then
        echo "${cpus}"
    elif [ "${cpus}" -ge 2 ]; then
        echo "$((cpus / 2))"
    else
        echo 1
    fi
}

LOCK_WANTED=0
case "${1:-}" in
    --print-jobs)
        [ "$#" = 1 ] || usage_fail "--print-jobs takes no other argument" "arguments: $*"
        job_count
        exit 0
        ;;
    --lock)
        LOCK_WANTED=1
        shift
        ;;
esac
[ "${1:-}" = "--" ] || usage_fail "expected \`--\` before the command" "arguments: ${*:-none}"
shift
[ "$#" -gt 0 ] || usage_fail "no command after \`--\`" "nothing follows \`--\`"

JOBS=$(job_count)

QOS="${CHECK_QOS:-utility}"
case "${QOS}" in
    utility | background | off) ;;
    *)
        fail ERR_THROTTLE_BAD_QOS "CHECK_QOS is not utility, background, or off" \
            "CHECK_QOS unset (utility), utility, background, or off" "CHECK_QOS='${QOS}'" \
            "set CHECK_QOS=utility, background, or off, or unset it"
        ;;
esac
PREFIX=()
if [ -z "${CI:-}" ] && [ "${QOS}" != off ] && command -v taskpolicy >/dev/null 2>&1; then
    PREFIX=(taskpolicy -c "${QOS}")
fi

LOCK=""
release_lock() {
    local holder=""
    [ -n "${LOCK}" ] || return 0
    holder=$(sed -n 1p "${LOCK}/holder" 2>/dev/null) || holder=""
    if [ "${holder}" = "$$" ]; then
        rm -rf "${LOCK}"
    fi
    LOCK=""
}

acquire_lock() {
    local root timeout start holder cmd noticed=0 empty_since=""
    root="${RUN_THROTTLED_LOCK_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/run-throttled}"
    timeout="${RUN_THROTTLED_WAIT_TIMEOUT:-3600}"
    is_uint "${timeout}" || usage_fail "RUN_THROTTLED_WAIT_TIMEOUT is not a whole number of seconds" \
        "RUN_THROTTLED_WAIT_TIMEOUT='${timeout}'"
    timeout=$((10#${timeout}))
    if ! mkdir -p "${root}" 2>/dev/null || [ ! -d "${root}" ]; then
        fail ERR_THROTTLE_LOCK_DIR "cannot create the lock directory ${root}" \
            "a writable directory to hold xcode.lock" "\`mkdir -p ${root}\` failed" \
            "make ${root} writable, or point RUN_THROTTLED_LOCK_DIR at a writable directory every session on this Mac shares"
    fi
    start=${SECONDS}
    while ! mkdir "${root}/xcode.lock" 2>/dev/null; do
        holder=$(sed -n 1p "${root}/xcode.lock/holder" 2>/dev/null) || holder=""
        cmd=$(sed -n 2p "${root}/xcode.lock/holder" 2>/dev/null) || cmd=""
        if [ -n "${holder}" ]; then
            empty_since=""
            if ! kill -0 "${holder}" 2>/dev/null; then
                echo "run-throttled: removing the stale xcode lock of pid ${holder}, which is no longer running" >&2
                rm -rf "${root}/xcode.lock"
                continue
            fi
        elif [ -z "${empty_since}" ]; then
            empty_since=${SECONDS}
        elif [ "$((SECONDS - empty_since))" -ge 5 ]; then
            # A holder that died between its mkdir and writing its PID leaves an empty lock.
            echo "run-throttled: removing an xcode lock that has named no holder for 5 s" >&2
            rm -rf "${root}/xcode.lock"
            empty_since=""
            continue
        fi
        if [ "${noticed}" = 0 ]; then
            echo "run-throttled: waiting for the xcode lock held by pid ${holder:-unknown}: ${cmd:-unknown}" >&2
            noticed=1
        fi
        if [ "$((SECONDS - start))" -ge "${timeout}" ]; then
            fail ERR_THROTTLE_LOCK_TIMEOUT "gave up waiting for the xcode lock after ${timeout} s" \
                "the lock at ${root}/xcode.lock to be released" \
                "pid ${holder:-unknown} still holds it: ${cmd:-unknown}" \
                "wait for that command to finish and rerun; if it is hung, stop pid ${holder:-unknown}, or raise RUN_THROTTLED_WAIT_TIMEOUT"
        fi
        sleep 1
    done
    LOCK="${root}/xcode.lock"
    trap release_lock EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '%s\n%s\n' "$$" "$*" >"${LOCK}/holder"
    export RUN_THROTTLED_LOCK_HELD=1
}

if [ "${LOCK_WANTED}" = 1 ] && [ -z "${CI:-}" ] && [ "${RUN_THROTTLED_LOCK_HELD:-}" != 1 ]; then
    acquire_lock "$@"
fi

export THROTTLE_JOBS="${JOBS}"
STATUS=0
${PREFIX[@]+"${PREFIX[@]}"} "$@" || STATUS=$?
release_lock
exit "${STATUS}"
