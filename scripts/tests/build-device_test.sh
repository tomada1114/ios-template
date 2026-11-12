#!/usr/bin/env bash
# Tests for scripts/build-device.sh: the unsigned Release device build it asks
# xcodebuild for, and the named failure for a failed build, a build that leaves no
# linked executable, a missing, invalid, or different privacy manifest, a stale bundle
# from an earlier run, and a bad argument.
#
# No real build is ever run: `xcodebuild`, `xcbeautify`, and `plutil` are stubbed in
# every case (CI runs this file on Ubuntu, which has no plutil).
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
# and then: `ok` links an executable and copies App/PrivacyInfo.xcprivacy; `nomanifest`
# links it but copies no manifest (a project.yml that excludes it); `emptymanifest` and
# `othermanifest` link it and write an empty or a different manifest; `noexe` stops after
# the Info.plist and exits 0; `fail` exits 65. xcbeautify passes the build log through.
# plutil: `-lint` fails on an empty file, `-convert xml1 -o - FILE` prints FILE.
stub_tools() {
    export STUB_MODE="$1" STUB_APP_DIR="${APP_DIR}"
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command xcodebuild 'mkdir -p "${STUB_APP_DIR}"
: >"${STUB_APP_DIR}/Info.plist"
link() { printf "#!/bin/sh\n" >"${STUB_APP_DIR}/MyApp"; chmod +x "${STUB_APP_DIR}/MyApp"; }
case "${STUB_MODE}" in
    ok) link; cp App/PrivacyInfo.xcprivacy "${STUB_APP_DIR}/PrivacyInfo.xcprivacy" ;;
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
    -convert) cat "$5" ;;
    *) echo "plutil stub: unexpected $*" >&2; exit 2 ;;
esac'
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
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command plutil 'case "$1" in
    -lint) echo "$2: OK" ;;
    -convert) echo "<plist><dict/></plist>" ;;
esac'
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
run_case "an unknown argument fails ERR_BUILD_DEVICE_USAGE" case_unknown_argument
finish
