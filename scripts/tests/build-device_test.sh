#!/usr/bin/env bash
# Tests for scripts/build-device.sh: the unsigned Release device build it asks
# xcodebuild for, and the named failure for a failed build, a build that leaves no
# linked executable, a missing, invalid, or different privacy manifest, a stale bundle
# from an earlier run, an executable whose symbols cannot be read (otool reporting on
# stdout with exit 0 included), an app or extension executable that
# uses a required-reason API category the bundled manifest gives no reason for, and a
# bad argument.
#
# No real build is ever run: `xcodebuild`, `xcbeautify`, `xcrun` (its `nm` and
# `otool`), and `plutil` are stubbed in every case (CI runs this file on Ubuntu, which
# has none of them). So these cases prove the plumbing — which symbol kinds match, how
# declared entries are counted, which error names what — and not that the script's
# REQUIRED_REASON_APIS spellings are what a real device binary holds.
# Each case copies build-device.sh into a fixture root's scripts/ and runs that copy
# with --root pointing at the fixture.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

APP_DIR="build/device-release-derived-data/Build/Products/Release-iphoneos/MyApp.app"

make_fixture_root() {
    local root
    root=$(cd "$(make_temp_dir)" && pwd)
    mkdir "${root}/scripts"
    cp "${REPO_ROOT}/scripts/build-device.sh" "${root}/scripts/build-device.sh"
    chmod +x "${root}/scripts/build-device.sh"
    mkdir "${root}/App"
    printf '<plist><dict/></plist>\n' >"${root}/App/PrivacyInfo.xcprivacy"
    echo "${root}"
}

# stub_tools MODE — xcodebuild, run in the fixture root, writes the bundle's Info.plist
# and then: `ok` links an executable and copies App/PrivacyInfo.xcprivacy; `appex` does
# that and adds PlugIns/Widget.appex with an Info.plist and a linked `Widget`, plus its
# own PrivacyInfo.xcprivacy under STUB_APPEX_MANIFEST=1; `nomanifest` links it but copies
# no manifest (a project.yml that excludes it); `emptymanifest` and `othermanifest` link
# it and write an empty or a different manifest; `noexe` stops after the Info.plist and
# exits 0; `fail` exits 65. xcbeautify passes the build log through.
# plutil: `-lint` fails on an empty file, `-convert xml1 -o - FILE` prints FILE (or, under
# STUB_REENCODE=1, the fixture's manifest as a re-encoded copy would read), and
# `-extract KEY raw -o - FILE` exits 1 for a FILE that does not exist, prints
# STUB_APPEX_EXECUTABLE for CFBundleExecutable, and answers the accessed-API keys from
# STUB_DECLARED (STUB_APPEX_DECLARED for a FILE inside an .appex): space-separated
# CATEGORY:REASON_COUNT entries, or `absent` to exit 1 as for a missing key.
# xcrun: `nm -u FILE` prints STUB_IMPORTS (STUB_APPEX_IMPORTS inside an .appex) one per
# line, or fails under STUB_NM_FAIL=1; `otool -v -s __TEXT __objc_methname FILE` prints
# FILE's path line, the section header, and STUB_SELECTORS (STUB_APPEX_SELECTORS) as
# "ADDRESS  SELECTOR" lines, as real otool does — or, under STUB_OTOOL=error, only the
# "is not an object file" line real otool prints on stdout while exiting 0, and under
# STUB_OTOOL=unparsed, its lines with an address shape the script does not read. The
# default executable uses UserDefaults, which the default manifest declares.
stub_tools() {
    export STUB_MODE="$1" STUB_APP_DIR="${APP_DIR}"
    export STUB_DECLARED="NSPrivacyAccessedAPICategoryUserDefaults:1" STUB_SELECTORS="standardUserDefaults"
    export STUB_IMPORTS="_\$s7SwiftUI10AppStorageV12wrappedValue_5storeACySiGSi_SSSo14NSUserDefaultsCSgtcSiRszlufC _OBJC_CLASS_\$_NSUserDefaults _objc_msgSend"
    export STUB_APPEX_EXECUTABLE="Widget" STUB_APPEX_DECLARED="absent" STUB_APPEX_IMPORTS="_objc_msgSend" STUB_APPEX_SELECTORS="init"
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command xcodebuild 'mkdir -p "${STUB_APP_DIR}"
: >"${STUB_APP_DIR}/Info.plist"
link() { printf "#!/bin/sh\n" >"${STUB_APP_DIR}/MyApp"; chmod +x "${STUB_APP_DIR}/MyApp"; }
case "${STUB_MODE}" in
    ok) link; cp App/PrivacyInfo.xcprivacy "${STUB_APP_DIR}/PrivacyInfo.xcprivacy" ;;
    appex)
        link; cp App/PrivacyInfo.xcprivacy "${STUB_APP_DIR}/PrivacyInfo.xcprivacy"
        appex="${STUB_APP_DIR}/PlugIns/Widget.appex"
        mkdir -p "${appex}"
        : >"${appex}/Info.plist"
        printf "#!/bin/sh\n" >"${appex}/Widget"
        if [ "${STUB_APPEX_MANIFEST:-}" = 1 ]; then printf "<plist><dict/></plist>\n" >"${appex}/PrivacyInfo.xcprivacy"; fi
        ;;
    nomanifest) link ;;
    emptymanifest) link; : >"${STUB_APP_DIR}/PrivacyInfo.xcprivacy" ;;
    othermanifest) link; printf "<plist><array/></plist>\n" >"${STUB_APP_DIR}/PrivacyInfo.xcprivacy" ;;
    noexe) ;;
    fail) echo "error: stubbed compile failure"; exit 65 ;;
esac'
    stub_command xcbeautify 'cat'
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command plutil 'case "$1" in
    -lint) if [ -s "$2" ]; then echo "$2: OK"; else echo "$2: stubbed: empty file" >&2; exit 1; fi ;;
    -convert) if [ "${STUB_REENCODE:-}" = 1 ]; then echo "<plist><dict/></plist>"; else cat "$5"; fi ;;
    -extract)
        key="$2" file="$6"
        [ -f "${file}" ] || { echo "stubbed: no such file" >&2; exit 1; }
        if [ "${key}" = CFBundleExecutable ]; then printf "%s" "${STUB_APPEX_EXECUTABLE}"; exit 0; fi
        case "${file}" in
            *.appex/*) entries="${STUB_APPEX_DECLARED}" ;;
            *) entries="${STUB_DECLARED}" ;;
        esac
        [ "${entries}" != absent ] || { echo "stubbed: No value at that key path" >&2; exit 1; }
        set -- ${entries}
        case "${key}" in
            NSPrivacyAccessedAPITypes) printf "%s" "$#" ;;
            NSPrivacyAccessedAPITypes.*)
                index="${key#NSPrivacyAccessedAPITypes.}"
                index="${index%%.*}"
                shift "${index}"
                case "${key}" in
                    *.NSPrivacyAccessedAPIType) printf "%s" "${1%%:*}" ;;
                    *.NSPrivacyAccessedAPITypeReasons) printf "%s" "${1##*:}" ;;
                esac
                ;;
        esac
        ;;
    *) echo "plutil stub: unexpected $*" >&2; exit 2 ;;
esac'
    # The body is a quoted heredoc sourced by the stub, so nothing in it expands here.
    cat >"${STUB_BIN}/xcrun.body" <<'EOF'
case "$1" in
    nm)
        [ "${STUB_NM_FAIL:-}" != 1 ] || { echo "stubbed: truncated or malformed object" >&2; exit 1; }
        case "$3" in *.appex/*) list="${STUB_APPEX_IMPORTS}" ;; *) list="${STUB_IMPORTS}" ;; esac
        for symbol in ${list}; do echo "${symbol}"; done
        ;;
    otool)
        case "$6" in *.appex/*) list="${STUB_APPEX_SELECTORS}" ;; *) list="${STUB_SELECTORS}" ;; esac
        case "${STUB_OTOOL:-ok}" in
            error) echo "$6: is not an object file" ;;
            unparsed)
                echo "$6:"
                echo "Contents of (__TEXT,__objc_methname) section"
                for selector in ${list}; do echo "0x0000000100008000  ${selector}"; done
                ;;
            *)
                echo "$6:"
                echo "Contents of (__TEXT,__objc_methname) section"
                for selector in ${list}; do echo "0000000100008000  ${selector}"; done
                ;;
        esac
        ;;
    *) echo "xcrun stub: unexpected $*" >&2; exit 2 ;;
esac
EOF
    stub_command xcrun ". \"${STUB_BIN}/xcrun.body\""
}

assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not $1"
}

case_happy_path() {
    local root args want
    root=$(make_fixture_root)
    stub_tools ok
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "BUILD-DEVICE OK: ${APP_DIR}"
    args=$(cat "${STUB_BIN}/xcodebuild.log")
    for want in "-scheme MyApp" "-configuration Release" "-destination generic/platform=iOS" \
        "-derivedDataPath build/device-release-derived-data" "CODE_SIGNING_ALLOWED=NO" " build"; do
        grep -qF -- "${want}" <<<"${args}" || _fail "xcodebuild was not called with '${want}': ${args}"
    done
    if grep -qE -- 'archive|-exportArchive|-allowProvisioning' <<<"${args}"; then
        _fail "xcodebuild was asked to archive, export, or provision: ${args}"
    fi
    grep -qxF -- "-lint ${APP_DIR}/PrivacyInfo.xcprivacy" "${STUB_BIN}/plutil.log" ||
        _fail "the bundled manifest was not linted: $(cat "${STUB_BIN}/plutil.log")"
    grep -qxF -- "nm -u ${APP_DIR}/MyApp" "${STUB_BIN}/xcrun.log" ||
        _fail "the executable's imports were not read: $(cat "${STUB_BIN}/xcrun.log")"
    grep -qxF -- "otool -v -s __TEXT __objc_methname ${APP_DIR}/MyApp" "${STUB_BIN}/xcrun.log" ||
        _fail "the executable's selectors were not read: $(cat "${STUB_BIN}/xcrun.log")"
    grep -qxF -- "-extract NSPrivacyAccessedAPITypes raw -o - ${APP_DIR}/PrivacyInfo.xcprivacy" \
        "${STUB_BIN}/plutil.log" || _fail "the bundled manifest's entries were not read: $(cat "${STUB_BIN}/plutil.log")"
    assert_stdout_contains "${APP_DIR}/MyApp: NSPrivacyAccessedAPICategoryUserDefaults declared (import _OBJC_CLASS_\$_NSUserDefaults, import-part So14NSUserDefaultsC)"
}

case_throttle_jobs() {
    local root
    root=$(make_fixture_root)
    stub_tools ok
    THROTTLE_JOBS=3 capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 0
    grep -qF -- "-jobs 3" "${STUB_BIN}/xcodebuild.log" || _fail "THROTTLE_JOBS was not passed as -jobs"
}

case_build_failure() {
    local root
    root=$(make_fixture_root)
    stub_tools fail
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_FAILED
    assert_stderr_contains "the build exited 65"
    assert_stdout_not_contains "BUILD-DEVICE OK"
}

case_no_executable() {
    local root
    root=$(make_fixture_root)
    stub_tools noexe
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_NO_APP
    assert_stderr_contains "an executable at ${APP_DIR}/MyApp"
    assert_stderr_contains "Next: "
}

case_stale_bundle_removed() {
    local root
    root=$(make_fixture_root)
    mkdir -p "${root}/${APP_DIR}"
    printf '#!/bin/sh\n' >"${root}/${APP_DIR}/MyApp"
    chmod +x "${root}/${APP_DIR}/MyApp"
    stub_tools noexe
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_NO_APP
}

case_no_privacy_manifest() {
    local root
    root=$(make_fixture_root)
    stub_tools nomanifest
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_NO_PRIVACY_MANIFEST
    assert_stderr_contains "App/PrivacyInfo.xcprivacy copied to ${APP_DIR}/PrivacyInfo.xcprivacy"
    assert_stderr_contains "Next: "
    assert_stdout_not_contains "BUILD-DEVICE OK"
}

case_invalid_privacy_manifest() {
    local root
    root=$(make_fixture_root)
    stub_tools emptymanifest
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_PRIVACY_MANIFEST_INVALID
    assert_stderr_contains "stubbed: empty file"
    assert_stdout_not_contains "BUILD-DEVICE OK"
}

case_different_privacy_manifest() {
    local root
    root=$(make_fixture_root)
    stub_tools othermanifest
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_PRIVACY_MANIFEST_MISMATCH
    assert_stderr_contains "the bundled privacy manifest is not App/PrivacyInfo.xcprivacy"
    assert_stdout_not_contains "BUILD-DEVICE OK"
}

case_reencoded_privacy_manifest() {
    local root
    root=$(make_fixture_root)
    stub_tools othermanifest
    # A re-encoded copy: different bytes, the same plist once both sides are XML.
    export STUB_REENCODE=1
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "BUILD-DEVICE OK"
}

case_stale_privacy_manifest_removed() {
    local root
    root=$(make_fixture_root)
    mkdir -p "${root}/${APP_DIR}"
    : >"${root}/${APP_DIR}/PrivacyInfo.xcprivacy"
    stub_tools nomanifest
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_NO_PRIVACY_MANIFEST
}

case_unknown_argument() {
    local root
    root=$(make_fixture_root)
    stub_tools ok
    capture "${BASH}" "${root}/scripts/build-device.sh" --bogus
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_USAGE
    assert_stderr_contains "unknown argument '--bogus'"
    [ ! -e "${STUB_BIN}/xcodebuild.log" ] || _fail "xcodebuild ran before the arguments were checked"
}

# run_with_symbols IMPORTS SELECTORS DECLARED — a build whose executable imports IMPORTS
# and sends SELECTORS (space-separated), bundling a manifest that declares DECLARED.
run_with_symbols() {
    local root
    root=$(make_fixture_root)
    stub_tools ok
    export STUB_IMPORTS="$1" STUB_SELECTORS="$2" STUB_DECLARED="$3"
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
}

case_undeclared_import() {
    run_with_symbols "_OBJC_CLASS_\$_NSUserDefaults _mach_absolute_time _objc_msgSend" \
        "standardUserDefaults" "NSPrivacyAccessedAPICategoryUserDefaults:1"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API
    assert_stderr_contains "undeclared: ${APP_DIR}/MyApp against ${APP_DIR}/PrivacyInfo.xcprivacy: NSPrivacyAccessedAPICategorySystemBootTime (import _mach_absolute_time)"
    assert_stderr_not_contains "NSPrivacyAccessedAPICategoryUserDefaults ("
    assert_stderr_contains "Next: add an entry with Apple's reason for each category to that bundle's manifest (App/PrivacyInfo.xcprivacy for the app"
    assert_stdout_not_contains "BUILD-DEVICE OK"
}

case_undeclared_selectors() {
    run_with_symbols "_OBJC_CLASS_\$_NSUserDefaults _OBJC_CLASS_\$_UITextInputMode" \
        "activeInputModes systemUptime" "NSPrivacyAccessedAPICategoryUserDefaults:1"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API
    assert_stderr_contains ": NSPrivacyAccessedAPICategorySystemBootTime (selector systemUptime); NSPrivacyAccessedAPICategoryActiveKeyboards (selector activeInputModes)"
    assert_stderr_contains "A \`selector\` match can be the app's own @objc member of the same name rather than Apple's API: rename that member"
}

case_undeclared_mangled_swift() {
    run_with_symbols "_\$s7SwiftUI10AppStorageV12wrappedValue_5storeACySiGSi_SSSo14NSUserDefaultsCSgtcSiRszlufC _objc_msgSend" \
        "init" "absent"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API
    assert_stderr_contains ": NSPrivacyAccessedAPICategoryUserDefaults (import-part So14NSUserDefaultsC)"
}

case_entry_without_reasons() {
    run_with_symbols "_OBJC_CLASS_\$_NSUserDefaults" "init" "NSPrivacyAccessedAPICategoryUserDefaults:0"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API
    assert_stderr_contains ": NSPrivacyAccessedAPICategoryUserDefaults (import _OBJC_CLASS_\$_NSUserDefaults)"
}

case_every_category_declared() {
    run_with_symbols "_OBJC_CLASS_\$_NSUserDefaults _stat _getattrlist _mach_absolute_time _NSURLVolumeTotalCapacityKey" \
        "activeInputModes fileModificationDate" \
        "NSPrivacyAccessedAPICategoryUserDefaults:1 NSPrivacyAccessedAPICategoryFileTimestamp:1 NSPrivacyAccessedAPICategorySystemBootTime:2 NSPrivacyAccessedAPICategoryDiskSpace:1 NSPrivacyAccessedAPICategoryActiveKeyboards:1"
    assert_exit 0
    assert_stdout_contains "MyApp: NSPrivacyAccessedAPICategoryFileTimestamp declared (import _stat, import _getattrlist, selector fileModificationDate)"
    assert_stdout_contains "MyApp: NSPrivacyAccessedAPICategoryDiskSpace declared (import _getattrlist, import _NSURLVolumeTotalCapacityKey)"
    assert_stdout_contains "BUILD-DEVICE OK"
}

case_lookalikes_are_no_use() {
    # Each resembles a listed API without being one: a longer C name, a Swift type of the
    # app's own, a longer selector, and a listed name inside a longer selector.
    run_with_symbols "_statx_np _status_update _\$s10MyAppCore23UserDefaultsPreferencesV" \
        "systemUptimeOffset activeInputModesDidChange" "absent"
    assert_exit 0
    assert_stdout_not_contains " declared ("
    assert_stdout_contains "BUILD-DEVICE OK"
}

case_unreadable_imports() {
    local root
    root=$(make_fixture_root)
    stub_tools ok
    export STUB_NM_FAIL=1
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE
    assert_stderr_contains "Actual: stubbed: truncated or malformed object"
    assert_stdout_not_contains "BUILD-DEVICE OK"
}

case_no_imports() {
    run_with_symbols "" "" "NSPrivacyAccessedAPICategoryUserDefaults:1"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE
    assert_stderr_contains "Actual: it listed none"
}

case_otool_error_on_stdout() {
    local root
    root=$(make_fixture_root)
    stub_tools ok
    export STUB_OTOOL=error
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE
    assert_stderr_contains "could not read the Objective-C selectors in ${APP_DIR}/MyApp"
    assert_stderr_contains "is not an object file"
    assert_stdout_not_contains "BUILD-DEVICE OK"
}

case_otool_unparsed_lines() {
    local root
    root=$(make_fixture_root)
    stub_tools ok
    export STUB_OTOOL=unparsed STUB_SELECTORS="systemUptime"
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE
    assert_stderr_contains "no ADDRESS SELECTOR line"
}

case_appex_undeclared_against_its_manifest() {
    local root
    root=$(make_fixture_root)
    stub_tools appex
    # The app's manifest declares SystemBootTime; the extension's own declares nothing.
    export STUB_APPEX_MANIFEST=1 STUB_APPEX_IMPORTS="_mach_absolute_time _objc_msgSend"
    export STUB_DECLARED="NSPrivacyAccessedAPICategoryUserDefaults:1 NSPrivacyAccessedAPICategorySystemBootTime:1"
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API
    assert_stderr_contains "undeclared: ${APP_DIR}/PlugIns/Widget.appex/Widget against ${APP_DIR}/PlugIns/Widget.appex/PrivacyInfo.xcprivacy: NSPrivacyAccessedAPICategorySystemBootTime (import _mach_absolute_time)"
    assert_stderr_not_contains "MyApp against" "the app's own executable reported"
    assert_stdout_contains "${APP_DIR}/MyApp: NSPrivacyAccessedAPICategoryUserDefaults declared"
    grep -qxF -- "otool -v -s __TEXT __objc_methname ${APP_DIR}/PlugIns/Widget.appex/Widget" "${STUB_BIN}/xcrun.log" ||
        _fail "the extension's selectors were not read: $(cat "${STUB_BIN}/xcrun.log")"
}

case_appex_declared_passes() {
    local root
    root=$(make_fixture_root)
    stub_tools appex
    export STUB_APPEX_MANIFEST=1 STUB_APPEX_IMPORTS="_mach_absolute_time" STUB_APPEX_DECLARED="NSPrivacyAccessedAPICategorySystemBootTime:1"
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "Widget.appex/Widget: NSPrivacyAccessedAPICategorySystemBootTime declared (import _mach_absolute_time)"
    assert_stdout_contains "BUILD-DEVICE OK"
}

case_appex_without_executable_name() {
    local root
    root=$(make_fixture_root)
    stub_tools appex
    export STUB_APPEX_EXECUTABLE=""
    capture "${BASH}" "${root}/scripts/build-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE
    assert_stderr_contains "no CFBundleExecutable naming a file in ${APP_DIR}/PlugIns/Widget.appex"
}

run_case "builds Release for generic/platform=iOS, unsigned, and reports the bundle" case_happy_path
run_case "passes THROTTLE_JOBS to xcodebuild as -jobs" case_throttle_jobs
run_case "a failed build fails ERR_BUILD_DEVICE_FAILED" case_build_failure
run_case "a build that links no executable fails ERR_BUILD_DEVICE_NO_APP" case_no_executable
run_case "an earlier run's executable cannot pass a build that links none" case_stale_bundle_removed
run_case "a bundle without PrivacyInfo.xcprivacy fails ERR_BUILD_DEVICE_NO_PRIVACY_MANIFEST" case_no_privacy_manifest
run_case "a bundled manifest that fails plutil -lint fails ERR_BUILD_DEVICE_PRIVACY_MANIFEST_INVALID" case_invalid_privacy_manifest
run_case "a bundled manifest unlike App/PrivacyInfo.xcprivacy fails ERR_BUILD_DEVICE_PRIVACY_MANIFEST_MISMATCH" case_different_privacy_manifest
run_case "a re-encoded manifest equal as XML passes" case_reencoded_privacy_manifest
run_case "an earlier run's manifest cannot pass a build that copies none" case_stale_privacy_manifest_removed
run_case "an imported API of an undeclared category fails ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API" case_undeclared_import
run_case "a sent selector of an undeclared category fails, naming every category" case_undeclared_selectors
run_case "a Swift import that carries NSUserDefaults needs the UserDefaults entry" case_undeclared_mangled_swift
run_case "an entry with no reasons declares nothing" case_entry_without_reasons
run_case "an executable whose every category is declared passes" case_every_category_declared
run_case "names that only resemble a listed API are no use of one" case_lookalikes_are_no_use
run_case "an executable nm cannot read fails ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE" case_unreadable_imports
run_case "an executable that imports nothing fails ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE" case_no_imports
run_case "otool's error on stdout with exit 0 fails ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE" case_otool_error_on_stdout
run_case "otool output with no parseable selector line fails ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE" case_otool_unparsed_lines
run_case "an extension is held to its own manifest, not the app's" case_appex_undeclared_against_its_manifest
run_case "an extension whose categories its own manifest declares passes" case_appex_declared_passes
run_case "an extension naming no executable fails ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE" case_appex_without_executable_name
run_case "an unknown argument fails ERR_BUILD_DEVICE_USAGE" case_unknown_argument
finish
