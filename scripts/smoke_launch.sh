#!/usr/bin/env bash
# The "app actually runs" guarantee: build Release for the iOS Simulator (or take a
# pre-built simulator .app), verify the bundle's code signature, install and launch it
# on a simulator, and assert the app process stays alive for ALIVE_SECONDS. What
# `just smoke` runs. GUI assertions belong to the XCUITest (`just uitest`), not here.
#
#   scripts/smoke_launch.sh                  generate + build Release, then smoke-test
#   scripts/smoke_launch.sh path/to/An.app   smoke-test an existing simulator bundle (no build)
#
# `simctl launch` succeeding says nothing about the app surviving its first second, so
# the check is the poll: once a second, the simulator's `launchctl list` must still show
# the app's `UIKitApplication:<bundle-id>` job with a numeric PID. The device is the one
# scripts/simulator-destination.sh picks (SIMULATOR_DEVICE chooses another); the bundle
# identifier is read from the built bundle's Info.plist, so a rename needs no edit here.
#
# Tools: xcodegen and xcbeautify come from the caller's PATH (`just smoke` runs this
# under `mise exec --`); xcodebuild, xcrun, plutil, and codesign come with Xcode and macOS.
#
# Git work tree: not required — it builds the checkout containing this script, which it
# finds from its own path, and a pre-built bundle needs no checkout files beyond
# scripts/simulator-destination.sh.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_SMOKE_USAGE              more than one argument, an option, or a path that is not an app bundle
#   ERR_SMOKE_BUILD_FAILED       xcodegen or the Release build failed, or it produced no app bundle
#   ERR_SMOKE_SIGNATURE_INVALID  `codesign --verify` rejected the bundle
#   ERR_SMOKE_NO_SIMULATOR       no simulator to run on, or it did not boot
#   ERR_SMOKE_INSTALL_FAILED     simctl refused to install the bundle
#   ERR_SMOKE_LAUNCH_FAILED      simctl refused to launch the app
#   ERR_SMOKE_EXITED_EARLY       the app stopped running before ALIVE_SECONDS passed
set -euo pipefail

APP_NAME="MyApp"
DERIVED_DATA="build/smoke-derived-data"
ALIVE_SECONDS=10
USAGE="usage: scripts/smoke_launch.sh [path/to/An.app]"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

APP_BUNDLE=""
case $# in
    0) ;;
    1)
        case "$1" in
            -*) fail ERR_SMOKE_USAGE "unknown option '$1'" "no arguments, or the path of a simulator .app" "argument '$1'" "${USAGE}" ;;
        esac
        # Strip a trailing slash (shell completion appends one) and resolve the path now,
        # before the `cd` below re-roots a relative one at the checkout.
        RAW_ARG="${1%/}"
        [ -d "${RAW_ARG}" ] && [ -f "${RAW_ARG}/Info.plist" ] ||
            fail ERR_SMOKE_USAGE "'${RAW_ARG}' is not a simulator app bundle" \
                "a directory holding an Info.plist, such as ${DERIVED_DATA}/Build/Products/Release-iphonesimulator/${APP_NAME}.app" \
                "no such bundle at '${RAW_ARG}'" "${USAGE}"
        APP_BUNDLE="$(cd "${RAW_ARG}" && pwd)"
        ;;
    *) fail ERR_SMOKE_USAGE "unexpected arguments: $*" "no arguments, or the path of a simulator .app" "$# arguments" "${USAGE}" ;;
esac

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPTS}/.."

if [ -z "${APP_BUNDLE}" ]; then
    if ! DESTINATION=$("${SCRIPTS}/simulator-destination.sh" 2>&1); then
        fail ERR_SMOKE_NO_SIMULATOR "no iOS Simulator to build for" \
            "scripts/simulator-destination.sh to pick a device" "${DESTINATION}" \
            "install an iOS simulator runtime (Xcode › Settings › Components), or set SIMULATOR_DEVICE to a listed device name"
    fi

    echo "==> Generating Xcode project"
    GENERATE_STATUS=0
    xcodegen generate || GENERATE_STATUS=$?
    [ "${GENERATE_STATUS}" = 0 ] || fail ERR_SMOKE_BUILD_FAILED "xcodegen could not generate ${APP_NAME}.xcodeproj" \
        "\`xcodegen generate\` to succeed" "it exited ${GENERATE_STATUS} (its output is above)" \
        "run \`just smoke\`, which puts the pinned xcodegen on PATH; if it still fails, fix project.yml and rerun"

    echo "==> Building ${APP_NAME} (Release, iOS Simulator)"
    BUILD_STATUS=0
    xcodebuild \
        -project "${APP_NAME}.xcodeproj" \
        -scheme "${APP_NAME}" \
        -configuration Release \
        -sdk iphonesimulator \
        -destination "${DESTINATION}" \
        -derivedDataPath "${DERIVED_DATA}" \
        build | xcbeautify --quiet || BUILD_STATUS=$?
    [ "${BUILD_STATUS}" = 0 ] || fail ERR_SMOKE_BUILD_FAILED "the Release build of ${APP_NAME} failed" \
        "\`xcodebuild -configuration Release -sdk iphonesimulator … build\` to succeed" \
        "the build exited ${BUILD_STATUS} (xcbeautify's errors are above)" \
        "fix the first error above; a Debug-only success (\`just build\`) can hide a Release-only failure"

    APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release-iphonesimulator/${APP_NAME}.app"
    [ -f "${APP_BUNDLE}/Info.plist" ] || fail ERR_SMOKE_BUILD_FAILED "the Release build produced no app bundle" \
        "a built app at ${APP_BUNDLE}" "no Info.plist there" \
        "check the scheme's product name in project.yml, then rerun \`just smoke\`"
fi

APP_LABEL="$(basename "${APP_BUNDLE}" .app)"
# An iOS bundle is flat: Info.plist sits at its top level, with no Contents/.
if ! BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "${APP_BUNDLE}/Info.plist" 2>&1); then
    if [ -n "${RAW_ARG:-}" ]; then
        fail ERR_SMOKE_USAGE "${APP_BUNDLE} declares no bundle identifier" \
            "a CFBundleIdentifier in ${APP_BUNDLE}/Info.plist" "${BUNDLE_ID}" \
            "pass a simulator .app built by \`just smoke\` or \`just build\`, or run \`just smoke\` with no argument"
    fi
    fail ERR_SMOKE_BUILD_FAILED "the Release build produced a bundle with no bundle identifier" \
        "a CFBundleIdentifier in ${APP_BUNDLE}/Info.plist" "${BUNDLE_ID}" \
        "check PRODUCT_BUNDLE_IDENTIFIER in project.yml, then rerun \`just smoke\`"
fi

echo "==> Verifying code signature"
# Simulator builds are ad hoc signed; a valid signature proves the bundle is intact.
if ! SIGNATURE_OUTPUT=$(codesign --verify --verbose=2 "${APP_BUNDLE}" 2>&1); then
    fail ERR_SMOKE_SIGNATURE_INVALID "codesign rejected ${APP_BUNDLE}" \
        "\`codesign --verify --verbose=2\` to accept the bundle" "${SIGNATURE_OUTPUT}" \
        "rebuild it (\`just smoke\` with no argument); a bundle edited after signing fails here"
fi

if ! UDID=$("${SCRIPTS}/simulator-destination.sh" --udid 2>&1); then
    fail ERR_SMOKE_NO_SIMULATOR "no iOS Simulator to launch on" \
        "scripts/simulator-destination.sh --udid to pick a device" "${UDID}" \
        "install an iOS simulator runtime (Xcode › Settings › Components), or set SIMULATOR_DEVICE to a listed device name"
fi

# `bootstatus -b` boots the device if needed and waits until it can take an install;
# an already-booted device returns at once.
if ! BOOT_OUTPUT=$(xcrun simctl bootstatus "${UDID}" -b 2>&1); then
    fail ERR_SMOKE_NO_SIMULATOR "simulator ${UDID} did not boot" \
        "\`xcrun simctl bootstatus ${UDID} -b\` to succeed" "${BOOT_OUTPUT}" \
        "open Simulator.app and boot the device by hand, then rerun \`just smoke\`"
fi
DEVICE_NAME=$(xcrun simctl getenv "${UDID}" SIMULATOR_DEVICE_NAME 2>/dev/null) || DEVICE_NAME=""
[ -n "${DEVICE_NAME}" ] || DEVICE_NAME="simulator ${UDID}"

echo "==> Installing ${APP_LABEL} on ${DEVICE_NAME}"
if ! INSTALL_OUTPUT=$(xcrun simctl install "${UDID}" "${APP_BUNDLE}" 2>&1); then
    fail ERR_SMOKE_INSTALL_FAILED "simctl could not install ${APP_BUNDLE}" \
        "the bundle to install on ${UDID}" "${INSTALL_OUTPUT}" \
        "rerun \`just smoke\`; if it persists, \`xcrun simctl erase ${UDID}\` resets the device"
fi

echo "==> Launching ${BUNDLE_ID}"
# --terminate-running-process: an instance left running from an earlier run would only
# be foregrounded, and the poll below would watch it instead of this build.
if ! LAUNCH_OUTPUT=$(xcrun simctl launch --terminate-running-process "${UDID}" "${BUNDLE_ID}" 2>&1); then
    fail ERR_SMOKE_LAUNCH_FAILED "simctl could not launch ${BUNDLE_ID}" \
        "${BUNDLE_ID} to launch on ${UDID}" "${LAUNCH_OUTPUT}" \
        "run \`just logs\` in another terminal, then rerun \`just smoke\` to see why it does not start"
fi

# The app's launchd job is `UIKitApplication:<bundle-id>[<suffix>]…`; its first field is
# the PID while it runs and `-` once it has exited. Prints that field, or nothing.
job_pid() { # job_pid LAUNCHCTL_LIST
    awk -v want="UIKitApplication:${BUNDLE_ID}" '
        $NF == want || index($NF, want "[") == 1 { print $1; exit }
    ' <<<"$1"
}

echo "==> Watching ${APP_LABEL} for ${ALIVE_SECONDS}s"
ELAPSED=0
while [ "${ELAPSED}" -lt "${ALIVE_SECONDS}" ]; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))
    if ! JOBS=$(xcrun simctl spawn "${UDID}" launchctl list 2>&1); then
        fail ERR_SMOKE_EXITED_EARLY "could not confirm ${APP_LABEL} was still running after ${ELAPSED}s" \
            "\`xcrun simctl spawn ${UDID} launchctl list\` to list the app's job for ${ALIVE_SECONDS}s" "${JOBS}" \
            "check the device with \`xcrun simctl list devices booted\`, then rerun \`just smoke\`"
    fi
    PID_FIELD=$(job_pid "${JOBS}")
    case "${PID_FIELD}" in
        "" | *[!0-9]*)
            if [ -z "${PID_FIELD}" ]; then
                ACTUAL="no UIKitApplication:${BUNDLE_ID} job in launchctl list after ${ELAPSED}s"
            else
                ACTUAL="the UIKitApplication:${BUNDLE_ID} job's PID field was '${PID_FIELD}' after ${ELAPSED}s"
            fi
            fail ERR_SMOKE_EXITED_EARLY "${APP_LABEL} exited early (launched as ${LAUNCH_OUTPUT})" \
                "the app to stay running for ${ALIVE_SECONDS}s" "${ACTUAL}" \
                "run \`just logs\` in another terminal and rerun \`just smoke\` to catch the crash, or read the crash report under ~/Library/Logs/DiagnosticReports"
            ;;
    esac
done

echo "==> Terminating ${APP_LABEL}"
# The app has already passed; a terminate that fails (it exited in the last instant)
# does not undo that, so it is reported rather than failed on.
if ! TERMINATE_OUTPUT=$(xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" 2>&1); then
    echo "smoke: simctl terminate did not stop ${BUNDLE_ID}: ${TERMINATE_OUTPUT}" >&2
fi

echo "SMOKE OK: ${APP_LABEL} launched and stayed alive on ${DEVICE_NAME}"
