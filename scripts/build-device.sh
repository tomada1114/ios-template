#!/usr/bin/env bash
# Build the Release app for the iOS device SDK (`iphoneos`), unsigned, and assert the
# linked executable and the privacy manifest are in the bundle. What `just build-device` runs after regenerating the
# project, and what CI's `Test & Coverage Gate` runs through it.
#
#   scripts/build-device.sh [--root DIR]
#
# It is the one device-SDK compile any gate runs: every other recipe builds for the
# simulator, so a device-only branch (`#if !targetEnvironment(simulator)`), an API one
# SDK lacks, or a Release device failure in asset-catalog validation or the linker would
# otherwise reach main unseen. CODE_SIGNING_ALLOWED=NO, so it needs no development team;
# nothing is archived, exported, signed, or installed (`scripts/run-device.sh` is the
# signed Debug route to a phone, and keeps its own derived data).
#
# The bundle an earlier run left is removed first, and the check is the executable the
# linker writes last, not the Info.plist written early in the build, so a build that
# stops short cannot pass on what is already there.
#
# The bundle must also hold PrivacyInfo.xcprivacy at its root: App Store Connect reads
# the manifest from there, and PrivacyManifestTests and RequiredReasonAPITests read only
# the source file, so a `project.yml` edit that drops App/PrivacyInfo.xcprivacy from the
# app target would pass every other gate and ship an app without one. The bundled file
# must also pass `plutil -lint` and match App/PrivacyInfo.xcprivacy — byte for byte, or
# as XML after `plutil -convert xml1` on both sides, should Xcode ever re-encode it — so
# an empty, corrupt, or stale manifest fails too.
#
# Tools: xcbeautify comes from the caller's PATH (`just build-device` runs this under
# `mise exec --`); xcodebuild comes with Xcode; plutil and cmp come with macOS.
#
# Git work tree: not required — it builds the project under --root, which defaults to
# the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_BUILD_DEVICE_USAGE   unknown argument, or a --root DIR that does not exist
#   ERR_BUILD_DEVICE_FAILED  the Release device build failed
#   ERR_BUILD_DEVICE_NO_APP  the build exited 0 but left no linked executable
#   ERR_BUILD_DEVICE_NO_PRIVACY_MANIFEST       the bundle holds no PrivacyInfo.xcprivacy
#   ERR_BUILD_DEVICE_PRIVACY_MANIFEST_INVALID  the bundled manifest fails `plutil -lint`
#   ERR_BUILD_DEVICE_PRIVACY_MANIFEST_MISMATCH the bundled manifest differs from
#                                              App/PrivacyInfo.xcprivacy
set -euo pipefail

APP_NAME="MyApp"
DERIVED_DATA="build/device-release-derived-data"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release-iphoneos/${APP_NAME}.app"
USAGE="usage: scripts/build-device.sh [--root DIR]"

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
            [ $# -ge 2 ] && [ -d "$2" ] || fail ERR_BUILD_DEVICE_USAGE "--root needs an existing directory" \
                "--root followed by an existing directory" "'${2:-}'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *) fail ERR_BUILD_DEVICE_USAGE "unknown argument '$1'" "no arguments, or --root DIR" "argument '$1'" "${USAGE}" ;;
    esac
    shift
done
[ -n "${ROOT}" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "${ROOT}"

rm -rf "${APP_BUNDLE}"

echo "==> Building ${APP_NAME} (Release, iOS device, unsigned)"
# The job cap scripts/run-throttled.sh exports (`just build-device`), when there is one.
JOBS_ARGS=()
if [ -n "${THROTTLE_JOBS:-}" ]; then JOBS_ARGS=(-jobs "${THROTTLE_JOBS}"); fi
BUILD_STATUS=0
xcodebuild ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    build | xcbeautify --quiet || BUILD_STATUS=$?
[ "${BUILD_STATUS}" = 0 ] || fail ERR_BUILD_DEVICE_FAILED "the Release device build of ${APP_NAME} failed" \
    "\`xcodebuild -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build\` to succeed" \
    "the build exited ${BUILD_STATUS} (xcbeautify's errors are above)" \
    "fix the first error above; a simulator-only success (\`just build\`, \`just smoke\`) can hide a device-only or Release-only failure"

[ -f "${APP_BUNDLE}/${APP_NAME}" ] && [ -x "${APP_BUNDLE}/${APP_NAME}" ] ||
    fail ERR_BUILD_DEVICE_NO_APP "the Release device build produced no linked app" \
        "an executable at ${APP_BUNDLE}/${APP_NAME}" \
        "no executable there, though xcodebuild exited 0" \
        "check the scheme's product name in project.yml, then rerun \`just build-device\`"

SOURCE_MANIFEST="App/PrivacyInfo.xcprivacy"
BUNDLED_MANIFEST="${APP_BUNDLE}/PrivacyInfo.xcprivacy"
[ -f "${BUNDLED_MANIFEST}" ] ||
    fail ERR_BUILD_DEVICE_NO_PRIVACY_MANIFEST "the Release device bundle holds no privacy manifest" \
        "${SOURCE_MANIFEST} copied to ${BUNDLED_MANIFEST}" \
        "no PrivacyInfo.xcprivacy there" \
        "keep ${SOURCE_MANIFEST} in the app target's sources in project.yml (not excluded), then rerun \`just build-device\`"

if ! LINT_OUTPUT=$(plutil -lint "${BUNDLED_MANIFEST}" 2>&1); then
    fail ERR_BUILD_DEVICE_PRIVACY_MANIFEST_INVALID "the bundled privacy manifest is not a valid property list" \
        "\`plutil -lint ${BUNDLED_MANIFEST}\` to pass" "${LINT_OUTPUT}" \
        "run \`plutil -lint ${SOURCE_MANIFEST}\`, fix the file, then rerun \`just build-device\`"
fi

# Byte-equal is the usual case (Xcode copies the file as is); comparing both sides as
# XML keeps a re-encoding by a later Xcode from reading as a different manifest.
if ! cmp -s "${SOURCE_MANIFEST}" "${BUNDLED_MANIFEST}"; then
    SOURCE_XML=$(plutil -convert xml1 -o - "${SOURCE_MANIFEST}" 2>&1) || SOURCE_XML="unreadable: ${SOURCE_XML}"
    BUNDLED_XML=$(plutil -convert xml1 -o - "${BUNDLED_MANIFEST}" 2>&1) || BUNDLED_XML="unreadable: ${BUNDLED_XML}"
    [ "${SOURCE_XML}" = "${BUNDLED_XML}" ] ||
        fail ERR_BUILD_DEVICE_PRIVACY_MANIFEST_MISMATCH "the bundled privacy manifest is not ${SOURCE_MANIFEST}" \
            "${BUNDLED_MANIFEST} to hold what ${SOURCE_MANIFEST} holds" \
            "the two differ (compare them with \`diff ${SOURCE_MANIFEST} ${BUNDLED_MANIFEST}\`)" \
            "check that project.yml copies ${SOURCE_MANIFEST} and no other PrivacyInfo.xcprivacy into the app target, then rerun \`just build-device\`"
fi

echo "BUILD-DEVICE OK: ${APP_BUNDLE}"
