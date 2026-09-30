#!/usr/bin/env bash
# Pick the iOS Simulator device the recipes run on, and print it.
#
#   scripts/simulator-destination.sh            print an xcodebuild -destination value
#   scripts/simulator-destination.sh --udid     print only the device's UDID
#
# The device is the one named by SIMULATOR_DEVICE (e.g. "iPhone 17") when that is
# set, otherwise the first available iPhone on the newest installed iOS runtime.
# Chosen at run time rather than pinned in the justfile or CI: a device name that
# exists under one Xcode is missing under the next, and a pinned name is the most
# common way a simulator job breaks after an Xcode bump. `just uitest` passes the
# destination to xcodebuild; `just run` (scripts/run-simulator.sh) boots the UDID.
#
# Needs xcrun (Xcode) and python3, both present wherever Xcode is.
#
# Git work tree: not required — it reads nothing from the checkout.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_SIM_USAGE      unknown argument
#   ERR_SIM_LIST       `xcrun simctl list` failed (no Xcode, or no simulator service)
#   ERR_SIM_NO_DEVICE  no available device matches
set -euo pipefail

USAGE='usage: scripts/simulator-destination.sh [--udid]'

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

FORMAT=destination
case $# in
    0) ;;
    1)
        [ "$1" = "--udid" ] || fail ERR_SIM_USAGE "unknown argument '$1'" \
            "no arguments, or --udid" "argument '$1'" "${USAGE}"
        FORMAT=udid
        ;;
    *) fail ERR_SIM_USAGE "unexpected arguments: $*" "no arguments, or --udid" "$# arguments" "${USAGE}" ;;
esac

if ! DEVICES_JSON=$(xcrun simctl list devices available --json 2>&1); then
    fail ERR_SIM_LIST "xcrun simctl could not list simulators" \
        "\`xcrun simctl list devices available --json\` to succeed" \
        "it failed: ${DEVICES_JSON}" \
        "check \`xcode-select -p\` points at Xcode (.xcode-version) and that Xcode's iOS platform is installed"
fi

# Runtimes are keyed like com.apple.CoreSimulator.SimRuntime.iOS-26-1; newest first by
# version, then the runtime's own device order, which lists current models first.
if ! UDID=$(SIMULATOR_DEVICE="${SIMULATOR_DEVICE:-}" python3 -c '
import json, os, re, sys

wanted = os.environ["SIMULATOR_DEVICE"]
runtimes = []
for key, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", key)
    if match:
        runtimes.append((tuple(int(part or 0) for part in match.groups()), devices))
for _, devices in sorted(runtimes, key=lambda runtime: runtime[0], reverse=True):
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        if device["name"] == wanted or (not wanted and device["name"].startswith("iPhone")):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
' <<<"${DEVICES_JSON}"); then
    if [ -n "${SIMULATOR_DEVICE:-}" ]; then
        WANTED="a device named \"${SIMULATOR_DEVICE}\""
    else
        WANTED="an available iPhone"
    fi
    fail ERR_SIM_NO_DEVICE "no available simulator matches" \
        "${WANTED} on an installed iOS runtime" \
        "none among \`xcrun simctl list devices available\`" \
        "install an iOS simulator runtime (Xcode › Settings › Components), or set SIMULATOR_DEVICE to a listed device name"
fi

if [ "${FORMAT}" = "udid" ]; then
    echo "${UDID}"
else
    echo "platform=iOS Simulator,id=${UDID}"
fi
