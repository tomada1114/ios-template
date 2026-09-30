#!/usr/bin/env bash
# Build the Debug app for a connected iPhone or iPad, install it there, and launch it.
# What `just run-device` runs after regenerating the project.
#
#   scripts/run-device.sh [--root DIR]
#
# 1. Reads the resolved DEVELOPMENT_TEAM from `xcodebuild -showBuildSettings` and stops
#    if it is empty. The team comes only from the gitignored Config/Local.xcconfig,
#    which Config/Debug.xcconfig includes; this script never reads that file and never
#    prints the team, on success or failure — it tests for emptiness only.
# 2. Picks a device from `xcrun devicectl list devices --json-output <tmp>`: the first
#    paired, physical iOS device whose tunnel is not "unavailable", or the one whose
#    name or identifier IOS_DEVICE names (the way SIMULATOR_DEVICE picks a simulator).
# 3. Builds with -allowProvisioningUpdates -allowProvisioningDeviceRegistration, so
#    automatic signing can create the profile and register the phone.
# 4. Installs the .app with `devicectl device install app`.
# 5. Launches it with `devicectl device process launch --terminate-existing`, so a
#    relaunch runs the fresh build rather than foregrounding the old process.
#
# Device identifiers (checked 2026-09-30 against Xcode's devicectl on this Mac): each
# device in the JSON's result.devices has a CoreDevice `identifier` (a UUID) and a
# separate `hardwareProperties.udid` (the classic 00008xxx-… UDID). xcodebuild's
# `-destination id=` takes the classic UDID; devicectl's --device accepts
# "uuid|ecid|serial_number|udid|name|dns_name" (its --help), so the script passes
# hardwareProperties.udid to both. IOS_DEVICE matches deviceProperties.name,
# `identifier`, or hardwareProperties.udid. Unverified: the tunnelState values a
# connected phone reports (only "unavailable" was observed, on a disconnected one).
#
# Needs xcodebuild and xcrun (Xcode), python3, and mise (for xcbeautify).
#
# Git work tree: not required — the project and the build products are read under
# --root, which defaults to the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_DEVICE_USAGE           unknown argument, or a --root DIR that does not exist
#   ERR_DEVICE_SETTINGS_FAILED xcodebuild -showBuildSettings failed
#   ERR_DEVICE_NO_TEAM         the resolved DEVELOPMENT_TEAM is empty
#   ERR_DEVICE_NONE            no paired, connected device (or none matching IOS_DEVICE)
#   ERR_DEVICE_BUILD_FAILED    the device build failed
#   ERR_DEVICE_INSTALL_FAILED  devicectl refused to install the app
#   ERR_DEVICE_LAUNCH_FAILED   devicectl refused to launch the app
set -euo pipefail

APP_NAME="MyApp"
DERIVED_DATA="build/device-derived-data"
APP_RELATIVE_PATH="${DERIVED_DATA}/Build/Products/Debug-iphoneos/${APP_NAME}.app"
USAGE="usage: scripts/run-device.sh [--root DIR]"

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
            [ $# -ge 2 ] && [ -d "$2" ] || fail ERR_DEVICE_USAGE "--root needs an existing directory" \
                "--root followed by an existing directory" "'${2:-}'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *) fail ERR_DEVICE_USAGE "unknown argument '$1'" "no arguments, or --root DIR" "argument '$1'" "${USAGE}" ;;
    esac
    shift
done
[ -n "${ROOT}" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT}"

# 1. Team check. The settings output is kept in a variable and never echoed: it holds
# the team value when one is set.
if ! SETTINGS=$(xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Debug \
    -showBuildSettings -destination 'generic/platform=iOS' 2>/dev/null); then
    fail ERR_DEVICE_SETTINGS_FAILED "xcodebuild could not resolve the Debug build settings" \
        "\`xcodebuild -showBuildSettings\` to succeed for ${APP_NAME}.xcodeproj" "it failed" \
        "run \`just generate\`, then \`just run-device\` again (the recipe regenerates the project itself)"
fi
TEAM_SET=$(python3 -c '
import re, sys
for line in sys.stdin:
    m = re.match(r"^\s*DEVELOPMENT_TEAM = (.*)$", line)
    if m and m.group(1).strip():
        print("yes")
        break
' <<<"${SETTINGS}")
unset SETTINGS
if [ "${TEAM_SET}" != "yes" ]; then
    fail ERR_DEVICE_NO_TEAM "no development team is set for the Debug build" \
        "a non-empty DEVELOPMENT_TEAM, set in the gitignored Config/Local.xcconfig" \
        "DEVELOPMENT_TEAM resolves to an empty value" \
        "create Config/Local.xcconfig holding \`DEVELOPMENT_TEAM = <your team ID>\` (docs/running-on-device.md), then rerun \`just run-device\`"
fi

# 2. Device.
DEVICES_JSON=$(mktemp "${TMPDIR:-/tmp}/run-device.XXXXXX")
trap 'rm -f "${DEVICES_JSON}"' EXIT
LIST_ERROR=""
if ! LIST_OUTPUT=$(xcrun devicectl list devices --json-output "${DEVICES_JSON}" 2>&1); then
    LIST_ERROR=" (devicectl list devices failed: ${LIST_OUTPUT})"
fi
if ! UDID=$(IOS_DEVICE="${IOS_DEVICE:-}" python3 -c '
import json, os, sys

wanted = os.environ["IOS_DEVICE"]
try:
    with open(sys.argv[1]) as handle:
        devices = json.load(handle)["result"]["devices"]
except (OSError, ValueError, KeyError, TypeError):
    sys.exit(1)
for device in devices:
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    udid = hardware.get("udid")
    if not udid or hardware.get("platform") != "iOS" or hardware.get("reality") != "physical":
        continue
    if connection.get("pairingState") != "paired" or connection.get("tunnelState") == "unavailable":
        continue
    names = {udid, device.get("identifier"), device.get("deviceProperties", {}).get("name")}
    if not wanted or wanted in names:
        print(udid)
        sys.exit(0)
sys.exit(1)
' "${DEVICES_JSON}"); then
    if [ -n "${IOS_DEVICE:-}" ]; then
        WANTED="a paired, connected device named or identified \"${IOS_DEVICE}\""
        ACTUAL="no connected device matches IOS_DEVICE=\"${IOS_DEVICE}\""
    else
        WANTED="a paired, connected iPhone or iPad"
        ACTUAL="none among \`xcrun devicectl list devices\`"
    fi
    fail ERR_DEVICE_NONE "no device to run on" "${WANTED}" "${ACTUAL}${LIST_ERROR}" \
        "connect and unlock the phone, tap Trust for this Mac, and enable Settings › Privacy & Security › Developer Mode; set IOS_DEVICE to a name from \`xcrun devicectl list devices\` to pick one"
fi

# 3. Build.
if ! (set -o pipefail && xcodebuild build -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
    -configuration Debug -destination "id=${UDID}" -derivedDataPath "${DERIVED_DATA}" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration | mise exec -- xcbeautify --quiet); then
    fail ERR_DEVICE_BUILD_FAILED "the Debug build for device ${UDID} failed" \
        "\`xcodebuild build\` to sign and build ${APP_NAME} for the device" "it failed (the output above says why)" \
        "sign in under Xcode › Settings › Accounts; check the team in Config/Local.xcconfig is that account's; a bundle identifier Apple will not register for this team needs the app's own prefix (docs/running-on-device.md)"
fi

# 4. Install.
APP_PATH="${ROOT}/${APP_RELATIVE_PATH}"
if ! INSTALL_OUTPUT=$(xcrun devicectl device install app --device "${UDID}" "${APP_PATH}" 2>&1); then
    fail ERR_DEVICE_INSTALL_FAILED "devicectl could not install ${APP_PATH}" \
        "the Debug device build to install on ${UDID}" "${INSTALL_OUTPUT}" \
        "unlock the phone and keep it connected, then rerun \`just run-device\`"
fi

# 5. Launch.
BUNDLE_ID=$("${SCRIPTS}/bundle-id.sh" --root "${ROOT}")
if ! LAUNCH_OUTPUT=$(xcrun devicectl device process launch --terminate-existing --device "${UDID}" "${BUNDLE_ID}" 2>&1); then
    fail ERR_DEVICE_LAUNCH_FAILED "devicectl could not launch ${BUNDLE_ID}" \
        "${BUNDLE_ID} to launch on ${UDID}" "${LAUNCH_OUTPUT}" \
        "unlock the phone; with a free Personal Team, trust the developer under Settings › General › VPN & Device Management, then rerun \`just run-device\`"
fi
echo "run-device: ${BUNDLE_ID} launched on device ${UDID}"
