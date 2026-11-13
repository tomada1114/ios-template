#!/usr/bin/env bash
# Waits for a booted simulator to finish its own post-boot work before a UI test runs.
#
#   scripts/wait-simulator-settled.sh <udid>
#
# `simctl bootstatus -b` returns once the device has booted, but a cold-booted simulator
# then spends minutes on work of its own (wallpaper and widget extensions, scoring and
# engagement daemons), each process at 50-100% CPU. While that lasts, an XCUITest
# accessibility snapshot takes seconds and the launch test's waits time out (#141).
#
# Those processes are visible from the host: their executables live under the runtime's
# `.simruntime/Contents/Resources/RuntimeRoot/` (the simulator's system processes) or
# under `CoreSimulator/Devices/<udid>/` (apps installed on this device). Every interval,
# the script sums the %CPU of those processes from `ps -Ao pcpu=,command=`; once the sum
# stays below the threshold for the given number of consecutive samples, it prints how
# long it waited and exits 0. A busy sample resets the count. Processes of another
# device's apps and the host's own (xcodebuild, Spotlight) are not counted; every
# runtime-root process is, since the path does not say which device runs it.
#
# The bound is not a failure: past it the script prints one `still busy` line to stderr,
# with the simulator's CPU and the host's load averages, and exits 0, so the test runs
# anyway and the load it ran under is on record. A `ps` that fails is treated the same
# way: one notice, exit 0, because the wait only ever improves a run's odds.
#
# Environment (each a positive integer):
#   SIM_SETTLE_INTERVAL   seconds between samples (default 5)
#   SIM_SETTLE_THRESHOLD  summed %CPU a sample must stay below to count as quiet
#                         (default 100, about one core)
#   SIM_SETTLE_SAMPLES    consecutive quiet samples that mean settled (default 3)
#   SIM_SETTLE_TIMEOUT    seconds after which it stops waiting (default 300)
#
# Tools: ps, sleep, date, awk, and (for the load averages) sysctl, falling back to
# /proc/loadavg; all come with macOS.
#
# Git work tree: not required — it reads nothing from the tree.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_SETTLE_USAGE    no udid, more than one argument, or an option
#   ERR_SETTLE_BAD_ENV  a SIM_SETTLE_* variable is not a positive integer
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

if [ $# != 1 ] || [ -z "$1" ]; then
    fail ERR_SETTLE_USAGE "expected exactly one simulator udid" "one argument, the udid" \
        "$# argument(s)" "pass the udid: ${USAGE} (\`scripts/simulator-destination.sh --udid\` prints it)"
fi
case "$1" in
    -*) fail ERR_SETTLE_USAGE "unknown option '$1'" "one argument, the udid" "argument '$1'" "${USAGE}" ;;
esac
UDID="$1"

# positive_int NAME DEFAULT — prints the variable's value, or DEFAULT when it is unset.
positive_int() {
    local value="${!1-$2}"
    case "${value}" in
        '' | *[!0-9]* | 0 | 0*) fail ERR_SETTLE_BAD_ENV "$1 is not a positive integer" \
            "$1 unset (default $2) or a positive integer" "$1='${value}'" \
            "unset $1, or set it to a positive integer such as $2" ;;
    esac
    echo "${value}"
}
INTERVAL=$(positive_int SIM_SETTLE_INTERVAL 5)
THRESHOLD=$(positive_int SIM_SETTLE_THRESHOLD 100)
SAMPLES=$(positive_int SIM_SETTLE_SAMPLES 3)
TIMEOUT=$(positive_int SIM_SETTLE_TIMEOUT 300)

# Prints the summed %CPU of this simulator's processes, rounded to a whole number.
simulator_cpu() {
    local listing
    listing=$(ps -Ao pcpu=,command=) || return 1
    awk -v device="/CoreSimulator/Devices/${UDID}/" '
        index($0, ".simruntime/Contents/Resources/RuntimeRoot/") || index($0, device) { sum += $1 }
        END { printf "%d\n", sum + 0.5 }
    ' <<<"${listing}"
}

load_averages() {
    local load
    load=$(sysctl -n vm.loadavg 2>/dev/null) || load=$(cut -d ' ' -f 1-3 /proc/loadavg 2>/dev/null) || load="unknown"
    load="${load#\{ }"
    echo "${load% \}}"
}

START=$(date +%s)
quiet=0
while :; do
    if ! cpu=$(simulator_cpu); then
        echo "${NAME}: ps failed; continuing without waiting" >&2
        exit 0
    fi
    elapsed=$(($(date +%s) - START))
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
        echo "${NAME}: still busy after ${elapsed} s (simulator CPU ${cpu}%, load $(load_averages)); continuing under load" >&2
        exit 0
    fi
    sleep "${INTERVAL}"
done
