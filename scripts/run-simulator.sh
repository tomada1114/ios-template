#!/usr/bin/env bash
# Install and launch the Debug build on an iOS Simulator. What `just run` runs after
# its build step.
#
#   scripts/run-simulator.sh [--root DIR]
#
# Boots the device scripts/simulator-destination.sh picks (SIMULATOR_DEVICE chooses
# another), brings Simulator.app to the front, installs the bundle `just build` just
# produced, and launches it with --terminate-running-process: launching an app that is
# already running only foregrounds the old process, so the freshly built binary would
# never start and whoever is checking a change would watch stale behavior.
#
# The app is identified by the bundle identifier project.yml declares
# (scripts/bundle-id.sh), so a rename by scripts/bootstrap.sh needs no edit here.
#
# Git work tree: not required — the manifest and the build products are read under
# --root, which defaults to the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_RUN_USAGE          unknown argument, or a --root DIR that does not exist
#   ERR_RUN_APP_MISSING    there is no built .app at the Debug simulator products path
#   ERR_RUN_BOOT_FAILED    the simulator could not be booted
#   ERR_RUN_INSTALL_FAILED simctl refused to install the bundle
#   ERR_RUN_LAUNCH_FAILED  simctl refused to launch the app
set -euo pipefail

APP_NAME="MyApp"
APP_RELATIVE_PATH="build/dev-derived-data/Build/Products/Debug-iphonesimulator/${APP_NAME}.app"
USAGE="usage: scripts/run-simulator.sh [--root DIR]"

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
            [ $# -ge 2 ] && [ -d "$2" ] || fail ERR_RUN_USAGE "--root needs an existing directory" \
                "--root followed by an existing directory" "'${2:-}'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *) fail ERR_RUN_USAGE "unknown argument '$1'" "no arguments, or --root DIR" "argument '$1'" "${USAGE}" ;;
    esac
    shift
done
[ -n "${ROOT}" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

APP_PATH="${ROOT}/${APP_RELATIVE_PATH}"
[ -d "${APP_PATH}" ] || fail ERR_RUN_APP_MISSING "there is no Debug simulator build to run" \
    "a built app at ${APP_PATH}" "no directory there" "run \`just build\` first (\`just run\` does both)"

BUNDLE_ID=$("${SCRIPTS}/bundle-id.sh" --root "${ROOT}")
UDID=$("${SCRIPTS}/simulator-destination.sh" --udid)

# `bootstatus -b` boots the device if needed and waits until it can take an install;
# an already-booted device returns at once.
if ! BOOT_OUTPUT=$(xcrun simctl bootstatus "${UDID}" -b 2>&1); then
    fail ERR_RUN_BOOT_FAILED "simulator ${UDID} did not boot" \
        "\`xcrun simctl bootstatus ${UDID} -b\` to succeed" "${BOOT_OUTPUT}" \
        "open Simulator.app and boot the device by hand, then rerun \`just run\`"
fi
open -a Simulator --args -CurrentDeviceUDID "${UDID}"

if ! INSTALL_OUTPUT=$(xcrun simctl install "${UDID}" "${APP_PATH}" 2>&1); then
    fail ERR_RUN_INSTALL_FAILED "simctl could not install ${APP_PATH}" \
        "the Debug simulator build to install on ${UDID}" "${INSTALL_OUTPUT}" \
        "rerun \`just build\`; if it persists, \`xcrun simctl erase ${UDID}\` resets the device"
fi

if ! LAUNCH_OUTPUT=$(xcrun simctl launch --terminate-running-process "${UDID}" "${BUNDLE_ID}" 2>&1); then
    fail ERR_RUN_LAUNCH_FAILED "simctl could not launch ${BUNDLE_ID}" \
        "${BUNDLE_ID} to launch on ${UDID}" "${LAUNCH_OUTPUT}" \
        "check the app's own crash log: \`just logs\` in another terminal, then rerun \`just run\`"
fi
echo "run: ${BUNDLE_ID} launched on simulator ${UDID} (${LAUNCH_OUTPUT})"
