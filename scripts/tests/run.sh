#!/usr/bin/env bash
# Runs every scripts/tests/*_test.sh, each in its own bash process (the same bash
# running this script, so `/bin/bash scripts/tests/run.sh` tests under bash 3.2).
#
# The files run concurrently: each builds its own throwaway repository under its own
# mktemp root and only ever reads the checkout, so they share no state. Every file's
# output is captured to its own log and printed whole, in glob order, once that file
# is waited for — so a concurrent run reads exactly like a sequential one and two
# files can never interleave a line. Every file runs even after one fails; the exit
# code is 1 if any failed.
#
# Each file is parsed with `bash -n` before it is started, because bash 3.2 can abort
# a file on a syntax error and still exit 0 — a file that does not parse would
# otherwise be counted as passing. A parse failure fails that file and no other.
#
# On INT or TERM the started files are killed rather than orphaned (a non-interactive
# shell starts a background job with SIGINT ignored, so Ctrl-C reaches this runner
# alone), and every log not printed yet is printed before the log directory goes.
#
#   scripts/tests/run.sh    (what `just test-scripts` and CI's lint job run)
#
# Git work tree: not required — each test builds its own throwaway repository.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_TESTS_NONE         no *_test.sh file was found
#   ERR_TESTS_FAILED       at least one test file failed to parse or exited non-zero
#   ERR_TESTS_INTERRUPTED  INT or TERM arrived; the files still running were killed
set -euo pipefail

cd "$(dirname "$0")/../.."

LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/script-tests-run.XXXXXX")
trap 'rm -rf "${LOG_DIR}"' EXIT

# Indexed arrays and `wait <pid>` are the bash 3.2 subset: no associative array, no
# `wait -n`, no `wait -p`. PIDS[i] is empty for a file that never started.
TOTAL=0
PRINTED=0
PIDS=()
FILES=()
RUNNING=()

# print_log INDEX [SUFFIX] — that file's header and its whole captured log.
print_log() {
    echo "==> ${FILES[$1]}${2-}"
    cat "${LOG_DIR}/$1.log" 2>/dev/null || true
}

# Kills what is still running, then shows the logs that were never reported — the
# EXIT trap is about to remove them with LOG_DIR, and on a Ctrl-C or a cancelled CI
# job they are the only record of how far the run got.
on_signal() {
    local signal="$1" unreported
    trap - INT TERM
    # Bash announces a job it reaps after a signal ("… Terminated: 15 …") on its own
    # stderr. Reap them behind /dev/null, so the first stderr line a caller reads is
    # still the ERR_ line the failure contract promises.
    exec 3>&2 2>/dev/null
    kill ${RUNNING[@]+"${RUNNING[@]}"} 2>/dev/null || true
    wait || true
    exec 2>&3 3>&-
    unreported=$((TOTAL - PRINTED))
    while [ "${PRINTED}" -lt "${TOTAL}" ]; do
        print_log "${PRINTED}" " (interrupted)"
        PRINTED=$((PRINTED + 1))
    done
    echo "ERR_TESTS_INTERRUPTED: ${signal} arrived; ${unreported} of ${TOTAL} test file(s) had not been reported" >&2
    echo "Expected: every scripts/tests/*_test.sh to run to completion" >&2
    echo "Actual: ${signal} ended the run; each unreported file was killed and its output so far is above, marked (interrupted)" >&2
    echo "Next: re-run \`just test-scripts\`" >&2
    exit 1
}
trap 'on_signal SIGINT' INT
trap 'on_signal SIGTERM' TERM

for file in scripts/tests/*_test.sh; do
    [ -e "${file}" ] || continue
    FILES[TOTAL]="${file}"
    if "${BASH}" -n "${file}" >"${LOG_DIR}/${TOTAL}.log" 2>&1; then
        # A simple command, not a group: $! is then the test file's own bash, so the
        # signal handler's `kill` reaches the process that is running the test.
        "${BASH}" "${file}" >"${LOG_DIR}/${TOTAL}.log" 2>&1 &
        PIDS[TOTAL]=$!
        RUNNING[TOTAL]=$!
    else
        PIDS[TOTAL]=""
    fi
    TOTAL=$((TOTAL + 1))
done

if [ "${TOTAL}" = 0 ]; then
    echo "ERR_TESTS_NONE: no test file to run" >&2
    echo "Expected: at least one scripts/tests/*_test.sh" >&2
    echo "Actual: the glob matched nothing" >&2
    echo "Next: add scripts/tests/<script-name>_test.sh for the script you changed" >&2
    exit 1
fi

FAILED_COUNT=0
FAILED_FILES=""
while [ "${PRINTED}" -lt "${TOTAL}" ]; do
    STATUS=0
    if [ -n "${PIDS[PRINTED]}" ]; then
        wait "${PIDS[PRINTED]}" || STATUS=$?
    else
        # It never started: `bash -n` rejected it, and the log holds the reason.
        STATUS=2
    fi
    print_log "${PRINTED}"
    if [ "${STATUS}" != 0 ]; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_FILES="${FAILED_FILES} ${FILES[PRINTED]}"
    fi
    PRINTED=$((PRINTED + 1))
done

if [ "${FAILED_COUNT}" -gt 0 ]; then
    echo "ERR_TESTS_FAILED: ${FAILED_COUNT} of ${TOTAL} test file(s) failed:${FAILED_FILES}" >&2
    echo "Expected: every scripts/tests/*_test.sh to parse and exit 0" >&2
    echo "Actual: failed:${FAILED_FILES}" >&2
    echo "Next: run \`bash -n <file>\`, then \`bash <file>\` and read its \`not ok\` cases and FAIL lines" >&2
    exit 1
fi
echo "script tests: ${TOTAL} file(s) passed"
