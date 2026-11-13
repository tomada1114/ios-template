#!/usr/bin/env bash
# Boots a simulator and, after a cold boot, waits for it to finish its own post-boot work
# before a UI test runs.
#
#   scripts/wait-simulator-settled.sh <udid>
#
# `simctl bootstatus -b` returns once the device has booted, but a cold-booted simulator
# then spends minutes on work of its own (wallpaper and widget extensions, scoring and
# engagement daemons), each process at 50-100% CPU. While that lasts, an XCUITest
# accessibility snapshot takes seconds and the launch test's waits time out (#141).
#
# The script reads the device's state from `xcrun simctl list devices`, then boots it
# with `xcrun simctl bootstatus <udid> -b`. A device that was already Booted is past
# that work: the script says so and exits 0 at once. After a cold boot it finds the
# device's `launchd_sim` (the host process whose executable is named launchd_sim and
# whose arguments name `CoreSimulator/Devices/<udid>/`) and measures the CPU time that
# process and all its descendants use. Every interval it samples the cumulative CPU time
# of each of those pids (`ps -Ao pid=,ppid=,time=`) and divides what they used since the
# last sample by the wall-clock time between them: 100% is one core busy for the whole
# interval. A pid first seen counts from 0, and a pid that vanished drops out. The first
# sample is only the baseline. Once that rate stays below the threshold for the given
# number of consecutive samples, it prints how long it waited and exits 0; a busy sample
# resets the count. Another booted simulator, and host processes whose arguments merely
# mention the device's path, are not its descendants and are not counted.
#
# The bound is not a failure: past it the script prints one `still busy` line to stderr,
# with the simulator's CPU and the host's load averages, and exits 0, so the test runs
# anyway and the load it ran under is on record. A failure to measure is treated the
# same way, with a one-line notice naming what failed, because the wait only ever
# improves a run's odds. A failed boot is an error.
#
# Environment (each a positive integer):
#   SIM_SETTLE_INTERVAL   seconds between samples (default 5)
#   SIM_SETTLE_THRESHOLD  the simulator's CPU over one interval, in percent of one core
#                         (100 = one core busy for the whole interval), that a sample
#                         must stay below to count as quiet (default 100)
#   SIM_SETTLE_SAMPLES    consecutive quiet samples that mean settled (default 3)
#   SIM_SETTLE_TIMEOUT    seconds after the boot at which it stops waiting (default 300)
#
# Tools: xcrun (Xcode); ps, sleep, date, awk, tr, and (for the load averages) sysctl,
# falling back to /proc/loadavg, from macOS.
#
# Git work tree: not required — it reads nothing from the tree.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_SETTLE_USAGE        no udid, more than one argument, or an option
#   ERR_SETTLE_BAD_ENV      a SIM_SETTLE_* variable is not a positive integer
#   ERR_SETTLE_BOOT_FAILED  `xcrun simctl bootstatus <udid> -b` failed
set -euo pipefail

NAME="wait-simulator-settled"
USAGE="usage: scripts/wait-simulator-settled.sh <udid>"

fail() { # fail CODE WHAT EXPECTED ACTUAL NEXT
    {
        echo "$1: $2"
        echo "Expected: $3"
        echo "Actual: $4"
        echo "Next: $5"
    } >&2
    exit 1
}

# continue_without_waiting WHAT — the one-line notice for a failure to measure.
continue_without_waiting() {
    echo "${NAME}: $1; continuing without waiting" >&2
    exit 0
}

if [ $# != 1 ] || [ -z "$1" ]; then
    fail ERR_SETTLE_USAGE "expected exactly one simulator udid" "one argument, the udid" \
        "$# argument(s)" "pass the udid: ${USAGE} (\`scripts/simulator-destination.sh --udid\` prints it)"
fi
case "$1" in
    -*) fail ERR_SETTLE_USAGE "unknown option '$1'" "one argument, the udid" "argument '$1'" "${USAGE}" ;;
esac
# simctl prints UDIDs in uppercase, and so do the device paths the match looks for.
UDID=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')

# positive_int NAME DEFAULT — prints the variable's value, or DEFAULT when it is unset.
positive_int() {
    local value="${!1-$2}"
    case "${value}" in
        '' | *[!0-9]* | 0*) fail ERR_SETTLE_BAD_ENV "$1 is not a positive integer" \
            "$1 unset (default $2) or a positive integer" "$1='${value}'" \
            "unset $1, or set it to a positive integer such as $2" ;;
    esac
    echo "${value}"
}
INTERVAL=$(positive_int SIM_SETTLE_INTERVAL 5)
THRESHOLD=$(positive_int SIM_SETTLE_THRESHOLD 100)
SAMPLES=$(positive_int SIM_SETTLE_SAMPLES 3)
TIMEOUT=$(positive_int SIM_SETTLE_TIMEOUT 300)

# --- Boot, remembering whether it was already booted ---

WAS_BOOTED=0
if devices=$(xcrun simctl list devices 2>/dev/null); then
    line=$(grep -F -- "(${UDID})" <<<"${devices}" || true)
    case "${line}" in
        *"(Booted)"*) WAS_BOOTED=1 ;;
    esac
else
    echo "${NAME}: \`xcrun simctl list devices\` failed; treating the boot as cold" >&2
fi

if ! xcrun simctl bootstatus "${UDID}" -b >&2; then
    fail ERR_SETTLE_BOOT_FAILED "the simulator ${UDID} did not boot" \
        "\`xcrun simctl bootstatus ${UDID} -b\` to boot the device and exit 0" \
        "it exited non-zero (its output is above)" \
        "check the udid with \`xcrun simctl list devices\`, or erase the device with \`xcrun simctl erase ${UDID}\` and rerun"
fi

if [ "${WAS_BOOTED}" = 1 ]; then
    echo "${NAME}: ${UDID} was already booted; not waiting"
    exit 0
fi

# --- Find the device's launchd_sim ---

listing=$(ps -Ao pid=,comm=) || continue_without_waiting "ps failed"
candidates=$(awk '{ pid = $1; sub(/^[ \t]*[0-9]+[ \t]+/, ""); n = split($0, parts, "/"); if (parts[n] == "launchd_sim") print pid }' <<<"${listing}") ||
    continue_without_waiting "reading the ps process list failed"
ROOT=""
for pid in ${candidates}; do
    argv=$(ps -o command= -p "${pid}") || continue
    case "${argv}" in
        *"/CoreSimulator/Devices/${UDID}/"*)
            ROOT="${pid}"
            break
            ;;
    esac
done
[ -n "${ROOT}" ] || continue_without_waiting "no launchd_sim for ${UDID} among the host's processes"

# --- Sample ---

# measure — reads the previous sample's "pid centiseconds" lines, a line "@@", then
# `ps -Ao pid=,ppid=,time=`. Prints the centiseconds ROOT and its descendants used since
# the previous sample, then this sample's "pid centiseconds" lines.
measure() {
    awk -v root="${ROOT}" '
        function centiseconds(t,    days, parts, fields, i, s) {
            days = 0
            if (index(t, "-")) { split(t, parts, "-"); days = parts[1]; t = parts[2] }
            fields = split(t, parts, ":")
            s = 0
            for (i = 1; i <= fields; i++) s = s * 60 + parts[i]
            return int((s + days * 86400) * 100 + 0.5)
        }
        $0 == "@@" { listing = 1; next }
        !listing { if (NF == 2) previous[$1] = $2; next }
        NF >= 3 { parent[$1] = $2; used[$1] = centiseconds($3) }
        END {
            delta = 0
            for (pid in used) {
                p = pid
                for (depth = 0; depth < 64 && p != root && p != "" && p != 0; depth++) p = parent[p]
                if (p != root) continue
                since = (pid in previous) ? previous[pid] : 0
                if (used[pid] > since) delta += used[pid] - since
                state = state pid " " used[pid] "\n"
            }
            print delta
            printf "%s", state
        }
    '
}

START=$(date +%s)
previous=""
previous_time=""
quiet=0
while :; do
    sample=$(ps -Ao pid=,ppid=,time=) || continue_without_waiting "ps failed"
    now=$(date +%s)
    result=$(measure <<<"${previous}"$'\n@@\n'"${sample}") ||
        continue_without_waiting "measuring the simulator's CPU time failed"
    delta="${result%%$'\n'*}"
    case "${result}" in
        *$'\n'*) previous="${result#*$'\n'}" ;;
        *) previous="" ;;
    esac
    elapsed=$((now - START))
    if [ -n "${previous_time}" ]; then
        wall=$((now - previous_time))
        [ "${wall}" -gt 0 ] || wall=1
        # centiseconds of CPU per second of wall time is percent of one core.
        cpu=$(((delta + wall / 2) / wall))
        if [ "${cpu}" -lt "${THRESHOLD}" ]; then
            quiet=$((quiet + 1))
        else
            quiet=0
        fi
        if [ "${quiet}" -ge "${SAMPLES}" ]; then
            echo "${NAME}: settled after ${elapsed} s (simulator CPU ${cpu}%)"
            exit 0
        fi
        if [ "${elapsed}" -ge "${TIMEOUT}" ]; then
            load=$(sysctl -n vm.loadavg 2>/dev/null) || load=$(cut -d ' ' -f 1-3 /proc/loadavg 2>/dev/null) || load="unknown"
            load="${load#\{ }"
            echo "${NAME}: still busy after ${elapsed} s (simulator CPU ${cpu}%, load ${load% \}}); continuing under load" >&2
            exit 0
        fi
    fi
    previous_time="${now}"
    sleep "${INTERVAL}"
done
