#!/usr/bin/env bash
# Build the Release app for the iOS device SDK (`iphoneos`), unsigned, and assert the
# linked executable and the privacy manifest are in the bundle. What `just build-device`
# runs after regenerating the project, and what `just check-release` runs through it; no
# pull request's checks run it.
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
# Last, the linked executable is held to that manifest: every required-reason API
# category the binary uses must have an NSPrivacyAccessedAPITypes entry with at least
# one reason in the bundled file. "Uses" is read from the binary, not the source: the
# symbols it imports (`xcrun nm -u`: C functions, Foundation's key constants, Objective-C
# class references, and Swift symbols whose mangled name carries an Objective-C type)
# and the Objective-C selectors it sends (`xcrun otool -v -s __TEXT __objc_methname`),
# matched against REQUIRED_REASON_APIS below, one line per symbol. This is the
# authoritative check, the one that sees code reached through a package, an alias, or
# generated code; RequiredReasonAPITests' source scan stays as `just test`'s fast signal
# (changing-gates › references/enforcement-layers.md says why both run). It reads only
# the main executable, so a framework under MyApp.app/Frameworks/, a symbol looked up
# with dlsym, or a selector built at run time is not seen, and it cannot judge whether
# a declared reason is the right one.
#
# Tools: xcbeautify comes from the caller's PATH (`just build-device` runs this under
# `mise exec --`); xcodebuild, and `nm` and `otool` through xcrun, come with Xcode;
# plutil, cmp, and awk come with macOS.
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
#   ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE        `xcrun nm` or `xcrun otool` could not read
#                                              the executable, or it imports nothing
#   ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API  the executable uses a required-reason
#                                              API category the bundled manifest gives
#                                              no reason for
set -euo pipefail

APP_NAME="MyApp"
DERIVED_DATA="build/device-release-derived-data"
APP_BUNDLE="${DERIVED_DATA}/Build/Products/Release-iphoneos/${APP_NAME}.app"
USAGE="usage: scripts/build-device.sh [--root DIR]"

# Apple's required-reason APIs as a linked arm64 binary spells them, one per line:
# CATEGORY|KIND|VALUE, where CATEGORY follows NSPrivacyAccessedAPICategory and KIND is
#   import       an imported symbol, matched whole (`_stat` is not `_statfs`)
#   import-part  text inside an imported symbol: a Swift API whose mangled name carries
#                the Objective-C type (SwiftUI's AppStorage takes `So14NSUserDefaultsC`)
#   selector     an Objective-C selector the binary sends, matched whole
# Every spelling here was read with `xcrun nm -u` and `xcrun otool` from an iOS
# 27.0-SDK probe that called each API (2026-11-12), and the list follows the symbols
# RequiredReasonAPIScan names from Apple's list under NSPrivacyAccessedAPIType. Swift's
# FileAttributeKey and URLResourceKey members (`.creationDate`,
# `.contentModificationDateKey`, `.volumeTotalCapacityKey`, `.systemSize`) link as the
# Foundation constants below; `getattrlist`, `fgetattrlist`, and `getattrlistat` are in
# two categories, as Apple lists them. A new API is one line.
REQUIRED_REASON_APIS='
FileTimestamp|import|_stat
FileTimestamp|import|_fstat
FileTimestamp|import|_fstatat
FileTimestamp|import|_lstat
FileTimestamp|import|_getattrlist
FileTimestamp|import|_getattrlistbulk
FileTimestamp|import|_fgetattrlist
FileTimestamp|import|_getattrlistat
FileTimestamp|import|_NSFileCreationDate
FileTimestamp|import|_NSFileModificationDate
FileTimestamp|import|_NSURLContentModificationDateKey
FileTimestamp|import|_NSURLCreationDateKey
FileTimestamp|selector|fileModificationDate
SystemBootTime|import|_mach_absolute_time
SystemBootTime|selector|systemUptime
DiskSpace|import|_statfs
DiskSpace|import|_statvfs
DiskSpace|import|_fstatfs
DiskSpace|import|_fstatvfs
DiskSpace|import|_getattrlist
DiskSpace|import|_fgetattrlist
DiskSpace|import|_getattrlistat
DiskSpace|import|_NSURLVolumeAvailableCapacityKey
DiskSpace|import|_NSURLVolumeAvailableCapacityForImportantUsageKey
DiskSpace|import|_NSURLVolumeAvailableCapacityForOpportunisticUsageKey
DiskSpace|import|_NSURLVolumeTotalCapacityKey
DiskSpace|import|_NSFileSystemFreeSize
DiskSpace|import|_NSFileSystemSize
ActiveKeyboards|selector|activeInputModes
UserDefaults|import|_OBJC_CLASS_$_NSUserDefaults
UserDefaults|import-part|So14NSUserDefaultsC
'
CATEGORY_PREFIX="NSPrivacyAccessedAPICategory"

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

EXECUTABLE="${APP_BUNDLE}/${APP_NAME}"
SYMBOLS_NEXT="check that ${EXECUTABLE} is a Mach-O executable (\`file ${EXECUTABLE}\`) and that \`xcrun --find nm\` and \`xcrun --find otool\` resolve in the selected Xcode, then rerun \`just build-device\`"
# Read once with stderr dropped, so a tool's warning cannot land in the list; a failure
# is read again for the message.
if ! IMPORTS=$(xcrun nm -u "${EXECUTABLE}" 2>/dev/null) || [ -z "${IMPORTS}" ]; then
    NM_ERROR=$(xcrun nm -u "${EXECUTABLE}" 2>&1 >/dev/null) || true
    fail ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE "could not read the symbols ${EXECUTABLE} imports" \
        "\`xcrun nm -u ${EXECUTABLE}\` to list them" "${NM_ERROR:-it listed none}" "${SYMBOLS_NEXT}"
fi
if ! METHNAMES=$(xcrun otool -v -s __TEXT __objc_methname "${EXECUTABLE}" 2>/dev/null); then
    OTOOL_ERROR=$(xcrun otool -v -s __TEXT __objc_methname "${EXECUTABLE}" 2>&1 >/dev/null) || true
    fail ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE "could not read the Objective-C selectors in ${EXECUTABLE}" \
        "\`xcrun otool -v -s __TEXT __objc_methname ${EXECUTABLE}\` to list them" \
        "${OTOOL_ERROR:-it failed and printed nothing}" "${SYMBOLS_NEXT}"
fi
# otool prints a path line and a "Contents of" line, then "ADDRESS  SELECTOR" per string.
SELECTORS=$(awk 'NF == 2 && $1 ~ /^[0-9a-fA-F]+$/ { print $2 }' <<<"${METHNAMES}")

# USES: one "CATEGORY|KIND VALUE" line per table row the executable matches.
USES=""
while IFS='|' read -r CATEGORY KIND VALUE; do
    [ -n "${CATEGORY}" ] || continue
    MATCHED=false
    case "${KIND}" in
        import) grep -qxF -- "${VALUE}" <<<"${IMPORTS}" && MATCHED=true ;;
        import-part) grep -qF -- "${VALUE}" <<<"${IMPORTS}" && MATCHED=true ;;
        selector) grep -qxF -- "${VALUE}" <<<"${SELECTORS}" && MATCHED=true ;;
    esac
    if [ "${MATCHED}" = true ]; then
        USES="${USES}${CATEGORY_PREFIX}${CATEGORY}|${KIND} ${VALUE}"$'\n'
    fi
done <<<"${REQUIRED_REASON_APIS}"

# DECLARED: each category with an entry holding at least one reason, as
# RequiredReasonAPITests counts it. `plutil -extract … raw` prints an array's count and
# exits 1 for a missing key, which counts as nothing declared.
DECLARED=""
ENTRY_COUNT=$(plutil -extract NSPrivacyAccessedAPITypes raw -o - "${BUNDLED_MANIFEST}" 2>/dev/null) || ENTRY_COUNT=0
case "${ENTRY_COUNT}" in '' | *[!0-9]*) ENTRY_COUNT=0 ;; esac
INDEX=0
while [ "${INDEX}" -lt "${ENTRY_COUNT}" ]; do
    ENTRY="NSPrivacyAccessedAPITypes.${INDEX}"
    DECLARED_TYPE=$(plutil -extract "${ENTRY}.NSPrivacyAccessedAPIType" raw -o - "${BUNDLED_MANIFEST}" 2>/dev/null) || DECLARED_TYPE=""
    REASON_COUNT=$(plutil -extract "${ENTRY}.NSPrivacyAccessedAPITypeReasons" raw -o - "${BUNDLED_MANIFEST}" 2>/dev/null) || REASON_COUNT=0
    case "${REASON_COUNT}" in '' | *[!0-9]*) REASON_COUNT=0 ;; esac
    if [ -n "${DECLARED_TYPE}" ] && [ "${REASON_COUNT}" -gt 0 ]; then
        DECLARED="${DECLARED}${DECLARED_TYPE}"$'\n'
    fi
    INDEX=$((INDEX + 1))
done

# Each category used, in table order, with every symbol that put the executable in it.
USED_CATEGORIES=""
while IFS='|' read -r CATEGORY _; do
    [ -n "${CATEGORY}" ] || continue
    grep -qxF -- "${CATEGORY}" <<<"${USED_CATEGORIES}" || USED_CATEGORIES="${USED_CATEGORIES}${CATEGORY}"$'\n'
done <<<"${USES}"
UNDECLARED=""
while read -r CATEGORY; do
    [ -n "${CATEGORY}" ] || continue
    EVIDENCE=""
    while IFS='|' read -r USE_CATEGORY USE_SYMBOL; do
        [ "${USE_CATEGORY}" = "${CATEGORY}" ] || continue
        EVIDENCE="${EVIDENCE:+${EVIDENCE}, }${USE_SYMBOL}"
    done <<<"${USES}"
    if grep -qxF -- "${CATEGORY}" <<<"${DECLARED}"; then
        echo "==> ${CATEGORY}: declared (${EVIDENCE})"
    else
        UNDECLARED="${UNDECLARED:+${UNDECLARED}; }${CATEGORY} (${EVIDENCE})"
    fi
done <<<"${USED_CATEGORIES}"
[ -z "${UNDECLARED}" ] ||
    fail ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API "${EXECUTABLE} uses a required-reason API the bundled privacy manifest declares no reason for" \
        "an NSPrivacyAccessedAPITypes entry with at least one reason in ${BUNDLED_MANIFEST} for every required-reason API category the executable uses" \
        "undeclared: ${UNDECLARED}" \
        "add an entry with Apple's reason for each category to ${SOURCE_MANIFEST} (integrating-system-apis › references/permissions.md), or remove the call; if a listed symbol is not that API, report it rather than editing REQUIRED_REASON_APIS to pass; then rerun \`just build-device\`"

echo "BUILD-DEVICE OK: ${APP_BUNDLE}"
