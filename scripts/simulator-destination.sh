#!/usr/bin/env bash
# Pick the iOS Simulator device the recipes run on, and print it.
#
#   scripts/simulator-destination.sh                  print an xcodebuild -destination value
#   scripts/simulator-destination.sh --udid           print only the device's UDID
#   scripts/simulator-destination.sh --family ipad    pick an iPad instead of an iPhone
#
# The device is the one named by SIMULATOR_DEVICE (e.g. "iPhone 17") when that is
# set, otherwise the first available device of the family (`--family iphone`, the
# default, or `--family ipad`) on the newest installed iOS runtime. SIMULATOR_FAMILY
# (iphone or ipad) sets the family when no `--family` is given, so
# `SIMULATOR_FAMILY=ipad just uitest` lands every recipe that calls this script on an
# iPad (`scripts/uitest-ipad.sh`, in `just check-release`, does that). With a family
# set either way, a SIMULATOR_DEVICE of the other family matches nothing; with none,
# SIMULATOR_DEVICE matches any device by its exact name. Chosen at run time rather
# than pinned in the justfile or CI: a device name that exists under one Xcode is
# missing under the next, and a pinned name is the most common way a simulator job
# breaks after an Xcode bump. `just uitest` passes the destination to xcodebuild;
# `just run` (scripts/run-simulator.sh) boots the UDID.
#
# Needs xcrun (Xcode) and python3, both present wherever Xcode is.
#
# Git work tree: not required — it reads nothing from the checkout.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_SIM_USAGE      unknown argument, a repeated one, or a family (--family or
#                      SIMULATOR_FAMILY) other than iphone or ipad
#   ERR_SIM_LIST       `xcrun simctl list` failed (no Xcode, or no simulator service)
#   ERR_SIM_NO_DEVICE  no available device matches
set -euo pipefail

USAGE='usage: scripts/simulator-destination.sh [--udid] [--family iphone|ipad]'
EXPECTED_ARGS='at most one --udid, and at most one --family iphone|ipad'

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

ALL_ARGS="$*"
FORMAT=destination
FAMILY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --udid)
            [ "${FORMAT}" = "destination" ] || fail ERR_SIM_USAGE "unexpected arguments: ${ALL_ARGS}" \
                "${EXPECTED_ARGS}" "--udid given twice" "${USAGE}"
            FORMAT=udid
            ;;
        --family)
            [ -z "${FAMILY}" ] || fail ERR_SIM_USAGE "unexpected arguments: ${ALL_ARGS}" \
                "${EXPECTED_ARGS}" "--family given twice" "${USAGE}"
            [ $# -ge 2 ] || fail ERR_SIM_USAGE "--family needs a value" \
                "--family iphone or --family ipad" "--family with no value" "${USAGE}"
            case "$2" in
                iphone | ipad) FAMILY="$2" ;;
                *) fail ERR_SIM_USAGE "unknown family '$2'" \
                    "--family iphone or --family ipad" "--family '$2'" "${USAGE}" ;;
            esac
            shift
            ;;
        *) fail ERR_SIM_USAGE "unknown argument '$1'" "${EXPECTED_ARGS}" "argument '$1'" "${USAGE}" ;;
    esac
    shift
done
if [ -z "${FAMILY}" ] && [ -n "${SIMULATOR_FAMILY:-}" ]; then
    case "${SIMULATOR_FAMILY}" in
        iphone | ipad) FAMILY="${SIMULATOR_FAMILY}" ;;
        *) fail ERR_SIM_USAGE "unknown family '${SIMULATOR_FAMILY}'" \
            "SIMULATOR_FAMILY unset, iphone, or ipad" "SIMULATOR_FAMILY='${SIMULATOR_FAMILY}'" \
            "unset SIMULATOR_FAMILY, or set it to iphone or ipad" ;;
    esac
fi

if ! DEVICES_JSON=$(xcrun simctl list devices available --json 2>&1); then
    fail ERR_SIM_LIST "xcrun simctl could not list simulators" \
        "\`xcrun simctl list devices available --json\` to succeed" \
        "it failed: ${DEVICES_JSON}" \
        "check \`xcode-select -p\` points at Xcode (.xcode-version) and that Xcode's iOS platform is installed"
fi

# Runtimes are keyed like com.apple.CoreSimulator.SimRuntime.iOS-26-1; newest first by
# version, then the runtime's own device order, which lists current models first. The
# family is a name prefix; with none, SIMULATOR_DEVICE alone decides (any family), and
# the default pick is an iPhone.
case "${FAMILY}" in
    ipad) PREFIX="iPad" ;;
    iphone) PREFIX="iPhone" ;;
    *) PREFIX="" ;;
esac
if ! UDID=$(SIMULATOR_DEVICE="${SIMULATOR_DEVICE:-}" PREFIX="${PREFIX}" python3 -c '
import json, os, re, sys

wanted = os.environ["SIMULATOR_DEVICE"]
prefix = os.environ["PREFIX"] or ("" if wanted else "iPhone")
runtimes = []
for key, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", key)
    if match:
        runtimes.append((tuple(int(part or 0) for part in match.groups()), devices))
for _, devices in sorted(runtimes, key=lambda runtime: runtime[0], reverse=True):
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        if (not wanted or device["name"] == wanted) and device["name"].startswith(prefix):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
' <<<"${DEVICES_JSON}"); then
    case "${FAMILY}" in
        ipad) KIND="iPad" ;;
        *) KIND="iPhone" ;;
    esac
    NEXT="install an iOS simulator runtime (Xcode › Settings › Components), or set SIMULATOR_DEVICE to a listed device name"
    if [ -n "${SIMULATOR_DEVICE:-}" ] && [ -n "${FAMILY}" ]; then
        WANTED="an ${KIND} named \"${SIMULATOR_DEVICE}\""
        NEXT="set SIMULATOR_DEVICE to an ${KIND} \`xcrun simctl list devices available\` lists, or unset it to pick the first available ${KIND}"
    elif [ -n "${SIMULATOR_DEVICE:-}" ]; then
        WANTED="a device named \"${SIMULATOR_DEVICE}\""
    else
        WANTED="an available ${KIND}"
    fi
    fail ERR_SIM_NO_DEVICE "no available simulator matches" \
        "${WANTED} on an installed iOS runtime" \
        "none among \`xcrun simctl list devices available\`" \
        "${NEXT}"
fi

if [ "${FORMAT}" = "udid" ]; then
    echo "${UDID}"
else
    echo "platform=iOS Simulator,id=${UDID}"
fi
