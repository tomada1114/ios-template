#!/usr/bin/env bash
# Run the launch UI test on an iPad simulator, then shut that simulator down if this
# run booted it — or skip it with a one-line notice when the app is iPhone only.
#
#   scripts/uitest-ipad.sh [--root DIR]
#
# `just uitest-ipad` (`mise exec -- scripts/uitest-ipad.sh`), which `just check-release`
# runs after `CHECK_ALL=1 SIMULATOR_FAMILY=iphone just check` has run the same test on
# an iPhone. In order, so no simulator is touched before the skip is decided:
#
#   1. `xcodegen generate`, then the resolved TARGETED_DEVICE_FAMILY of the app that
#      hosts the launch UI test: `xcodebuild -showBuildSettings -target
#      MyAppLaunchUITests` names the host (TEST_TARGET_NAME), and the same call on that
#      target gives its family — the value Xcode builds with, whatever project.yml
#      spelling (settings groups, templates, SDK-conditional keys) produced it. Both
#      calls run under `scripts/run-throttled.sh --lock`. Exactly `1` (iPhone only,
#      starting-an-app's choice) skips with one stdout line and exit 0; a family that
#      names 2 runs; anything else, or a call that fails, is an error, never a skip.
#   2. The iPad: `SIMULATOR_FAMILY=ipad scripts/simulator-destination.sh --udid`, the
#      first available iPad on the newest runtime, or the one SIMULATOR_IPAD_DEVICE
#      names. SIMULATOR_DEVICE is ignored here: it is the iPhone legs' choice, and
#      check-release runs both legs in one environment.
#   3. `just uitest-build`, then the iPad's state, then `just uitest-run`, both recipes
#      with SIMULATOR_FAMILY=ipad and SIMULATOR_DEVICE set to SIMULATOR_IPAD_DEVICE (or
#      empty), so both resolve the same iPad. Under SIMULATOR_FAMILY=ipad, uitest-run
#      writes its own result bundle, build/LaunchUITests-ipad.xcresult, beside the
#      iPhone run's build/LaunchUITests.xcresult.
#   4. If the iPad was not booted before uitest-run, it is shut down afterwards, pass
#      or fail (several booted simulators exhaust a Mac's memory), under the lock so
#      it never lands in another worktree's run. A device that was already booted, or
#      a run whose uitest-build failed (the device was never booted), is left alone. A
#      failed shutdown is a one-line warning on stderr; the exit status is the test's.
#
# On INT, TERM, or HUP the iPad is shut down the same way but without the lock (an
# interrupted run must not wait on another holder), and the script exits 130, 143, or
# 129.
#
# Needs `just`, `xcodegen` (the caller's PATH: the recipe runs it through mise), and
# Xcode's xcodebuild and xcrun, plus python3.
#
# Git work tree: not required — it generates and builds the project under --root,
# which defaults to the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_UITEST_IPAD_USAGE         unknown argument, or a --root DIR that does not exist
#   ERR_UITEST_IPAD_TOOL_MISSING  just, xcodegen, or xcodebuild is not on PATH
#   ERR_UITEST_IPAD_GENERATE      `xcodegen generate` failed
#   ERR_UITEST_IPAD_FAMILY        the host app or its TARGETED_DEVICE_FAMILY could not be
#                                 read, or the family is neither `1` nor one naming 2
# scripts/simulator-destination.sh's ERR_SIM_* pass through unchanged; a failing recipe
# exits with its own status.
set -euo pipefail

USAGE="usage: scripts/uitest-ipad.sh [--root DIR]"
SCRIPTS=$(cd "$(dirname "$0")" && pwd)
UITEST_TARGET="MyAppLaunchUITests"
PROJECT="MyApp.xcodeproj"

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

for tool in just xcodegen xcodebuild; do
    command -v "${tool}" >/dev/null 2>&1 || fail ERR_UITEST_IPAD_TOOL_MISSING "${tool} is not on PATH" \
        "\`${tool}\` on PATH" "\`command -v ${tool}\` found nothing" \
        "run \`mise install\` and call this through \`just uitest-ipad\` (xcodebuild comes from Xcode: check \`xcode-select -p\`)"
done

cd "${ROOT}"

# 1. The decision, before any simulator is touched.
if ! GENERATE_OUT=$(xcodegen generate 2>&1); then
    fail ERR_UITEST_IPAD_GENERATE "xcodegen generate failed" \
        "\`xcodegen generate\` to write ${PROJECT} from project.yml" "${GENERATE_OUT}" \
        "fix project.yml, then run \`just generate\` and this again"
fi

# build_setting TARGET KEY — prints KEY's resolved value for TARGET (iOS Simulator SDK).
build_setting() {
    local out
    out=$("${SCRIPTS}/run-throttled.sh" --lock -- xcodebuild -showBuildSettings \
        -project "${PROJECT}" -target "$1" -sdk iphonesimulator 2>&1) || {
        echo "xcodebuild -showBuildSettings -target $1 failed: ${out}"
        return 1
    }
    awk -v key="$2" '$1 == key && $2 == "=" { sub(/^[^=]*= ?/, ""); print; exit }' <<<"${out}"
}

FAMILY_NEXT="check project.yml's ${UITEST_TARGET} target and the app target it tests (TARGETED_DEVICE_FAMILY \"1\" or \"1,2\"), run \`just generate\`, then this again"
if ! HOST=$(build_setting "${UITEST_TARGET}" TEST_TARGET_NAME) || [ -z "${HOST}" ]; then
    fail ERR_UITEST_IPAD_FAMILY "could not read the app the launch UI test runs in" \
        "TEST_TARGET_NAME in ${UITEST_TARGET}'s resolved build settings" "${HOST:-no TEST_TARGET_NAME}" "${FAMILY_NEXT}"
fi
if ! FAMILY=$(build_setting "${HOST}" TARGETED_DEVICE_FAMILY) || [ -z "${FAMILY}" ]; then
    fail ERR_UITEST_IPAD_FAMILY "could not read ${HOST}'s TARGETED_DEVICE_FAMILY" \
        "TARGETED_DEVICE_FAMILY in ${HOST}'s resolved build settings" "${FAMILY:-no TARGETED_DEVICE_FAMILY}" "${FAMILY_NEXT}"
fi
case ",${FAMILY// /}," in
    ,1,)
        echo "Skipped uitest-ipad: ${HOST} targets iPhone only (TARGETED_DEVICE_FAMILY \"1\")"
        exit 0
        ;;
    *,2,*) ;;
    *) fail ERR_UITEST_IPAD_FAMILY "${HOST}'s TARGETED_DEVICE_FAMILY is neither iPhone only nor one with iPad" \
        "\"1\" (skip) or a list naming 2 (run)" "\"${FAMILY}\"" "${FAMILY_NEXT}" ;;
esac

# 2. The iPad.
IPAD_DEVICE="${SIMULATOR_IPAD_DEVICE:-}"
UDID=$(SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE="${IPAD_DEVICE}" "${SCRIPTS}/simulator-destination.sh" --udid)

# device_state — prints the iPad's state (Booted, Shutdown, ...), or nothing.
device_state() {
    local json
    json=$(xcrun simctl list devices --json 2>/dev/null) || return 0
    UDID="${UDID}" python3 -c '
import json, os, sys
for devices in json.load(sys.stdin).get("devices", {}).values():
    for device in devices:
        if device.get("udid") == os.environ["UDID"]:
            print(device.get("state", ""))
            sys.exit(0)
' <<<"${json}" 2>/dev/null || true
}

WE_BOOT_IT=0
# shutdown_ipad lock|nolock — shuts the iPad down when this run booted it.
shutdown_ipad() {
    [ "${WE_BOOT_IT}" = 1 ] || return 0
    WE_BOOT_IT=0
    local status=0
    if [ "$1" = lock ]; then
        "${SCRIPTS}/run-throttled.sh" --lock -- xcrun simctl shutdown "${UDID}" >/dev/null 2>&1 || status=$?
    else
        xcrun simctl shutdown "${UDID}" >/dev/null 2>&1 || status=$?
    fi
    [ "${status}" = 0 ] ||
        echo "warning: could not shut down the iPad simulator ${UDID}; run \`xcrun simctl shutdown ${UDID}\` if it is still booted" >&2
}
trap 'shutdown_ipad nolock; exit 130' INT
trap 'shutdown_ipad nolock; exit 143' TERM
trap 'shutdown_ipad nolock; exit 129' HUP

# 3. Build, then run.
STATUS=0
SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE="${IPAD_DEVICE}" just uitest-build || STATUS=$?
if [ "${STATUS}" = 0 ]; then
    if [ "$(device_state)" != Booted ]; then
        WE_BOOT_IT=1
    fi
    SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE="${IPAD_DEVICE}" just uitest-run || STATUS=$?
fi

# 4. Shut down what this run booted.
trap - INT TERM HUP
shutdown_ipad lock
exit "${STATUS}"
