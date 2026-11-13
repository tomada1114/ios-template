#!/usr/bin/env bash
# Run the launch UI test on an iPad simulator, then shut that simulator down — or skip
# it with a one-line notice when the app builds no iOS target for iPad.
#
#   scripts/uitest-ipad.sh [--root DIR]
#
# `just uitest-ipad`, which `just check-release` runs after `CHECK_ALL=1 just check`
# has run the same test on an iPhone. The skip is scripts/targets-ipad.sh's answer:
# only an exact `false` (every iOS target in project.yml sets TARGETED_DEVICE_FAMILY
# "1", starting-an-app's iPhone-only choice) skips; any failure to answer fails the run
# instead of skipping it. Otherwise it resolves the iPad first
# (`SIMULATOR_FAMILY=ipad scripts/simulator-destination.sh --udid`, so a Mac with no
# iPad simulator fails as ERR_SIM_NO_DEVICE before any build), then runs
# `just uitest-build` and `just uitest-run` with SIMULATOR_FAMILY=ipad on those two
# commands alone: both recipes resolve their device through
# scripts/simulator-destination.sh, so they build for, boot, settle, and test that same
# iPad. SIMULATOR_DEVICE, when set, must name an iPad. The device is chosen at run
# time, never pinned by name, for the reason in simulator-destination.sh's header.
#
# The iPad is shut down afterwards whether the test passed, failed, or was
# interrupted: several booted simulators exhaust a Mac's memory. The shutdown runs
# under `scripts/run-throttled.sh --lock`, so it never lands in the middle of another
# worktree's run on the same device; a failed shutdown (a device never booted, because
# the build failed) is a one-line warning on stderr and leaves the exit status alone.
# The exit status is the test's. The run's result bundle replaces the iPhone one at
# build/LaunchUITests.xcresult (uitest-run's fixed path).
#
# Needs `just` on PATH (the caller's, as for every recipe) and what the recipes need:
# Xcode's xcrun and python3.
#
# Git work tree: not required — it reads project.yml and runs the recipes under
# --root, which defaults to the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_UITEST_IPAD_USAGE         unknown argument, or a --root DIR that does not exist
#   ERR_UITEST_IPAD_JUST_MISSING  `just` is not on PATH (checked before any device work)
# scripts/targets-ipad.sh's ERR_IPAD_* and scripts/simulator-destination.sh's ERR_SIM_*
# pass through unchanged; a failing recipe exits with its own status.
set -euo pipefail

USAGE="usage: scripts/uitest-ipad.sh [--root DIR]"
SCRIPTS=$(cd "$(dirname "$0")" && pwd)

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || fail ERR_UITEST_IPAD_USAGE "--root needs a directory" \
                "--root followed by an existing directory" "no value after --root" "${USAGE}"
            [ -d "$2" ] || fail ERR_UITEST_IPAD_USAGE "--root directory '$2' does not exist" \
                "--root followed by an existing directory" "no directory at '$2'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *)
            fail ERR_UITEST_IPAD_USAGE "unknown argument '$1'" \
                "no arguments, or --root DIR" "argument '$1'" "${USAGE}"
            ;;
    esac
    shift
done
[ -n "${ROOT}" ] || ROOT=$(cd "${SCRIPTS}/.." && pwd)

TARGETS_IPAD=$("${SCRIPTS}/targets-ipad.sh" --root "${ROOT}")
if [ "${TARGETS_IPAD}" = false ]; then
    echo "Skipped uitest-ipad: project.yml builds no iOS target for iPad (TARGETED_DEVICE_FAMILY \"1\")"
    exit 0
fi

command -v just >/dev/null 2>&1 || fail ERR_UITEST_IPAD_JUST_MISSING "just is not on PATH" \
    "\`just\` on PATH, to run uitest-build and uitest-run" "\`command -v just\` found nothing" \
    "run \`mise install\` and call this through \`just uitest-ipad\`, or put the mise.toml-pinned just on PATH"

UDID=$(SIMULATOR_FAMILY=ipad "${SCRIPTS}/simulator-destination.sh" --udid)

shutdown_ipad() {
    if ! "${SCRIPTS}/run-throttled.sh" --lock -- xcrun simctl shutdown "${UDID}" >/dev/null 2>&1; then
        echo "warning: could not shut down the iPad simulator ${UDID}; run \`xcrun simctl shutdown ${UDID}\` if it is still booted" >&2
    fi
}
# An interrupted run shuts the iPad down too; a finished one calls it below.
trap 'shutdown_ipad; exit 130' INT TERM

cd "${ROOT}"
STATUS=0
SIMULATOR_FAMILY=ipad just uitest-build || STATUS=$?
if [ "${STATUS}" = 0 ]; then
    SIMULATOR_FAMILY=ipad just uitest-run || STATUS=$?
fi
trap - INT TERM
shutdown_ipad
exit "${STATUS}"
