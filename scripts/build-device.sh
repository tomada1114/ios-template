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
# matched against REQUIRED_REASON_APIS below, one line per symbol. Each app extension
# (PlugIns/*.appex, its executable named by CFBundleExecutable) is held the same way to
# the PrivacyInfo.xcprivacy in its own bundle. This is the
# authoritative check, the one that sees code reached through a package, an alias, or
# generated code; RequiredReasonAPITests' source scan stays as `just test`'s fast signal
# (changing-gates › references/enforcement-layers.md says why both run). It reads only
# the app's and its extensions' executables, so a framework under MyApp.app/Frameworks/,
# a symbol looked up with dlsym, or a selector built at run time is not seen; a
# `selector` row also matches the app's own @objc member of that name; and it cannot
# judge whether a declared reason is the right one. Keep the table's categories in step
# with RequiredReasonAPIScan's (scripts/checks/required-reason-tables-agree.sh).
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
#                                              an executable (no imports, no selector
#                                              section), or an .appex names none
#   ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API  the app's or an extension's
#                                              executable uses a required-reason API
#                                              category its bundled manifest gives no
#                                              reason for
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
# two categories, as Apple lists them. A new API is one line (a `$` written `\$`).
REQUIRED_REASON_APIS="
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
UserDefaults|import|_OBJC_CLASS_\$_NSUserDefaults
UserDefaults|import-part|So14NSUserDefaultsC
"
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

# fail_unreadable <executable> <what could not be read> <command> <actual>
fail_unreadable() {
    fail ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE "could not read $2 in $1" "\`$3\` to list them" "$4" \
        "check that $1 is a Mach-O executable (\`file $1\`) and that \`xcrun --find nm\` and \`xcrun --find otool\` resolve in the selected Xcode, then rerun \`just build-device\`"
}

# declared_categories <manifest> — each category with an entry holding at least one
# reason, one per line, as RequiredReasonAPITests counts it. `plutil -extract … raw`
# prints an array's count and exits 1 for a missing key or file, which counts as nothing
# declared.
declared_categories() {
    local manifest="$1" count index entry type reasons
    count=$(plutil -extract NSPrivacyAccessedAPITypes raw -o - "${manifest}" 2>/dev/null) || count=0
    case "${count}" in '' | *[!0-9]*) count=0 ;; esac
    index=0
    while [ "${index}" -lt "${count}" ]; do
        entry="NSPrivacyAccessedAPITypes.${index}"
        type=$(plutil -extract "${entry}.NSPrivacyAccessedAPIType" raw -o - "${manifest}" 2>/dev/null) || type=""
        reasons=$(plutil -extract "${entry}.NSPrivacyAccessedAPITypeReasons" raw -o - "${manifest}" 2>/dev/null) || reasons=0
        case "${reasons}" in '' | *[!0-9]*) reasons=0 ;; esac
        if [ -n "${type}" ] && [ "${reasons}" -gt 0 ]; then echo "${type}"; fi
        index=$((index + 1))
    done
}

# check_required_reason_apis <executable> <manifest> — prints each category the
# executable uses that <manifest> declares, and appends each one it does not declare,
# with the symbols behind it, to UNDECLARED. Not run in a subshell, so a read failure
# ends the script.
UNDECLARED=""
check_required_reason_apis() {
    local executable="$1" manifest="$2" imports methnames selectors uses declared
    local used category kind value matched evidence use_category use_symbol missing
    # Read with stderr dropped, so a tool's warning cannot land in the list; a failure is
    # read again for the message.
    if ! imports=$(xcrun nm -u "${executable}" 2>/dev/null) || [ -z "${imports}" ]; then
        local nm_error
        nm_error=$(xcrun nm -u "${executable}" 2>&1 >/dev/null) || true
        fail_unreadable "${executable}" "the imported symbols" "xcrun nm -u ${executable}" \
            "${nm_error:-it listed none}"
    fi
    # otool reports an unreadable file on stdout and exits 0, so the read counts only when
    # it printed the section header and at least one "ADDRESS  SELECTOR" line: an app or
    # extension executable always sends some selectors.
    methnames=$(xcrun otool -v -s __TEXT __objc_methname "${executable}" 2>&1) || true
    selectors=$(awk 'NF == 2 && $1 ~ /^[0-9a-fA-F]+$/ { print $2 }' <<<"${methnames}")
    if ! grep -qxF -- "Contents of (__TEXT,__objc_methname) section" <<<"${methnames}" || [ -z "${selectors}" ]; then
        fail_unreadable "${executable}" "the Objective-C selectors" \
            "xcrun otool -v -s __TEXT __objc_methname ${executable}" \
            "$(head -n 3 <<<"${methnames}" | tr '\n' ' ')(no section header, or no ADDRESS SELECTOR line)"
    fi

    # uses: one "CATEGORY|KIND VALUE" line per table row the executable matches.
    uses=""
    while IFS='|' read -r category kind value; do
        [ -n "${category}" ] || continue
        matched=false
        case "${kind}" in
            import) grep -qxF -- "${value}" <<<"${imports}" && matched=true ;;
            import-part) grep -qF -- "${value}" <<<"${imports}" && matched=true ;;
            selector) grep -qxF -- "${value}" <<<"${selectors}" && matched=true ;;
        esac
        if [ "${matched}" = true ]; then
            uses="${uses}${CATEGORY_PREFIX}${category}|${kind} ${value}"$'\n'
        fi
    done <<<"${REQUIRED_REASON_APIS}"
    declared=$(declared_categories "${manifest}")

    # Each category used, in table order, with every symbol that put the executable in it.
    used=""
    while IFS='|' read -r category _; do
        [ -n "${category}" ] || continue
        grep -qxF -- "${category}" <<<"${used}" || used="${used}${category}"$'\n'
    done <<<"${uses}"
    missing=""
    while read -r category; do
        [ -n "${category}" ] || continue
        evidence=""
        while IFS='|' read -r use_category use_symbol; do
            [ "${use_category}" = "${category}" ] || continue
            evidence="${evidence:+${evidence}, }${use_symbol}"
        done <<<"${uses}"
        if grep -qxF -- "${category}" <<<"${declared}"; then
            echo "==> ${executable}: ${category} declared (${evidence})"
        else
            missing="${missing:+${missing}; }${category} (${evidence})"
        fi
    done <<<"${used}"
    if [ -n "${missing}" ]; then
        UNDECLARED="${UNDECLARED:+${UNDECLARED} | }${executable} against ${manifest}: ${missing}"
    fi
}

check_required_reason_apis "${APP_BUNDLE}/${APP_NAME}" "${BUNDLED_MANIFEST}"

# Each app extension is held to its own bundled manifest, which Apple requires it to
# carry; one without a PrivacyInfo.xcprivacy declares nothing.
for APPEX in "${APP_BUNDLE}"/PlugIns/*.appex; do
    [ -d "${APPEX}" ] || continue
    APPEX_EXECUTABLE=$(plutil -extract CFBundleExecutable raw -o - "${APPEX}/Info.plist" 2>/dev/null) || APPEX_EXECUTABLE=""
    [ -n "${APPEX_EXECUTABLE}" ] && [ -f "${APPEX}/${APPEX_EXECUTABLE}" ] ||
        fail_unreadable "${APPEX}" "the executable" "plutil -extract CFBundleExecutable raw -o - ${APPEX}/Info.plist" \
            "no CFBundleExecutable naming a file in ${APPEX}"
    check_required_reason_apis "${APPEX}/${APPEX_EXECUTABLE}" "${APPEX}/PrivacyInfo.xcprivacy"
done

[ -z "${UNDECLARED}" ] ||
    fail ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API "an executable in ${APP_NAME}.app uses a required-reason API its bundled privacy manifest declares no reason for" \
        "an NSPrivacyAccessedAPITypes entry with at least one reason, in the PrivacyInfo.xcprivacy bundled beside each executable, for every required-reason API category that executable uses" \
        "undeclared: ${UNDECLARED}" \
        "add an entry with Apple's reason for each category to that bundle's manifest (${SOURCE_MANIFEST} for the app, the extension target's own PrivacyInfo.xcprivacy for an .appex; integrating-system-apis › references/permissions.md), or remove the call. A \`selector\` match can be the app's own @objc member of the same name rather than Apple's API: rename that member. Never delete a REQUIRED_REASON_APIS row to pass; then rerun \`just build-device\`"

echo "BUILD-DEVICE OK: ${APP_BUNDLE}"
