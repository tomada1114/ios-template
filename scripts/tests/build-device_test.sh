#!/usr/bin/env bash
# Tests for scripts/build-device.sh: the unsigned Release device build it asks
# xcodebuild for, and the named failure for a failed build, a build that leaves no
# linked executable, a stale bundle from an earlier run, and a bad argument.
#
# No real build is ever run: `xcodebuild` and `xcbeautify` are stubbed in every case.
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
    echo "${root}"
}

# stub_tools MODE — xcodebuild, run in the fixture root, writes the bundle's Info.plist
# and then: `ok` links an executable, `noexe` stops there and exits 0, `fail` exits 65.
# xcbeautify passes the build log through.
stub_tools() {
    export STUB_MODE="$1" STUB_APP_DIR="${APP_DIR}"
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command xcodebuild 'mkdir -p "${STUB_APP_DIR}"
: >"${STUB_APP_DIR}/Info.plist"
case "${STUB_MODE}" in
    ok) printf "#!/bin/sh\n" >"${STUB_APP_DIR}/MyApp"; chmod +x "${STUB_APP_DIR}/MyApp" ;;
    noexe) ;;
    fail) echo "error: stubbed compile failure"; exit 65 ;;
esac'
    stub_command xcbeautify 'cat'
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
run_case "an unknown argument fails ERR_BUILD_DEVICE_USAGE" case_unknown_argument
finish
