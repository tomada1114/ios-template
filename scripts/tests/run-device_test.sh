#!/usr/bin/env bash
# Tests for scripts/run-device.sh: the team check, the device pick, and the named
# failure for each way building, installing, and launching on a phone can fail.
#
# No phone, no Apple account, and no real build are ever touched: `xcodebuild`,
# `xcrun`, and `mise` are stubbed in every case. Each case copies run-device.sh and
# bundle-id.sh into a fixture root's scripts/ and runs that copy with --root pointing
# at a fixture project.yml declaring com.example.MyApp.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

UDID="00008101-000A11B22C33D44E"
COREDEVICE_ID="C0FFEE00-1111-2222-3333-444455556666"
TEAM="ZZTEAM1234"
unset IOS_DEVICE

make_fixture_root() {
    local root name
    root=$(cd "$(make_temp_dir)" && pwd)
    mkdir "${root}/scripts"
    for name in run-device.sh bundle-id.sh; do
        cp "${REPO_ROOT}/scripts/${name}" "${root}/scripts/${name}"
        chmod +x "${root}/scripts/${name}"
    done
    cat >"${root}/project.yml" <<'EOF'
name: MyApp
targets:
  MyApp:
    type: application
    platform: iOS
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyApp
EOF
    echo "${root}"
}

# stub_tools TEAM_VALUE DEVICES(none|phone) [FAILING_STEP] — xcodebuild answers
# -showBuildSettings with TEAM_VALUE and succeeds a build unless FAILING_STEP is
# build; xcrun writes the device fixture for `list devices` and fails install or
# launch when FAILING_STEP names it; mise passes the build log through.
stub_tools() {
    export STUB_TEAM="$1" STUB_FAIL="${3:-}" DEVICES_FIXTURE="${CASE_DIR}/devices.json"
    if [ "$2" = phone ]; then
        cat >"${DEVICES_FIXTURE}" <<EOF
{"info": {}, "result": {"devices": [
  {"identifier": "${COREDEVICE_ID}",
   "connectionProperties": {"pairingState": "paired", "tunnelState": "connected"},
   "deviceProperties": {"name": "Test Phone"},
   "hardwareProperties": {"platform": "iOS", "reality": "physical", "udid": "${UDID}"}}
]}}
EOF
    else
        echo '{"info": {}, "result": {"devices": []}}' >"${DEVICES_FIXTURE}"
    fi
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command xcodebuild 'case " $* " in
    *" -showBuildSettings "*)
        echo "Build settings for action build and target MyApp:"
        echo "    CODE_SIGN_STYLE = Automatic"
        echo "    DEVELOPMENT_TEAM = ${STUB_TEAM}"
        ;;
    *)
        echo "building"
        [ "${STUB_FAIL}" != build ] || exit 65
        ;;
esac'
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command xcrun 'case "$2 $3" in
    "list devices") cp "${DEVICES_FIXTURE}" "$5" ;;
    "device install")
        if [ "${STUB_FAIL}" = install ]; then echo "install: stubbed failure" >&2; exit 1; fi ;;
    "device process")
        if [ "${STUB_FAIL}" = launch ]; then echo "launch: stubbed failure" >&2; exit 1; fi ;;
    *) echo "unexpected xcrun call: $*" >&2; exit 64 ;;
esac'
    stub_command mise 'cat'
}

assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not $1"
}

assert_no_device_writes() {
    if [ -e "${STUB_BIN}/xcrun.log" ] && grep -qE '^devicectl device (install|process)' "${STUB_BIN}/xcrun.log"; then
        _fail "devicectl installed or launched after a failure: $(cat "${STUB_BIN}/xcrun.log")"
    fi
}

assert_team_never_printed() {
    assert_stdout_not_contains "${TEAM}" "the team ID"
    assert_stderr_not_contains "${TEAM}" "the team ID"
}

case_no_team() {
    local root
    root=$(make_fixture_root)
    stub_tools "" phone
    capture "${BASH}" "${root}/scripts/run-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_DEVICE_NO_TEAM
    assert_stderr_contains "Config/Local.xcconfig"
    assert_stderr_contains "docs/running-on-device.md"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "devicectl ran without a team"
    [ "$(grep -c '' "${STUB_BIN}/xcodebuild.log")" = 1 ] || _fail "xcodebuild built without a team"
}

case_no_device_team_hidden() {
    local root
    root=$(make_fixture_root)
    stub_tools "${TEAM}" none
    capture "${BASH}" "${root}/scripts/run-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_DEVICE_NONE
    assert_stderr_contains "Developer Mode"
    assert_team_never_printed
    [ "$(grep -c '' "${STUB_BIN}/xcodebuild.log")" = 1 ] || _fail "xcodebuild built with no device"
}

case_ios_device_unmatched() {
    local root
    root=$(make_fixture_root)
    stub_tools "${TEAM}" phone
    IOS_DEVICE="Someone Else's iPhone" capture "${BASH}" "${root}/scripts/run-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_DEVICE_NONE
    grep -qF "Actual: no connected device matches IOS_DEVICE=\"Someone Else's iPhone\"" "${CASE_DIR}/stderr" ||
        _fail "Actual: does not name IOS_DEVICE"
}

case_ios_device_matches_coredevice_id() {
    local root
    root=$(make_fixture_root)
    stub_tools "${TEAM}" phone
    IOS_DEVICE="${COREDEVICE_ID}" capture "${BASH}" "${root}/scripts/run-device.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "launched on device ${UDID}"
}

case_build_failure() {
    local root
    root=$(make_fixture_root)
    stub_tools "${TEAM}" phone build
    capture "${BASH}" "${root}/scripts/run-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_DEVICE_BUILD_FAILED
    assert_stderr_contains "Xcode › Settings › Accounts"
    assert_no_device_writes
    assert_team_never_printed
}

case_install_failure() {
    local root
    root=$(make_fixture_root)
    stub_tools "${TEAM}" phone install
    capture "${BASH}" "${root}/scripts/run-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_DEVICE_INSTALL_FAILED
    assert_stderr_contains "install: stubbed failure"
    if grep -q '^devicectl device process' "${STUB_BIN}/xcrun.log"; then
        _fail "devicectl launched after a failed install"
    fi
}

case_launch_failure() {
    local root
    root=$(make_fixture_root)
    stub_tools "${TEAM}" phone launch
    capture "${BASH}" "${root}/scripts/run-device.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_DEVICE_LAUNCH_FAILED
    assert_stderr_contains "VPN & Device Management"
    assert_stdout_not_contains "launched on device" "a success line"
}

case_happy_path() {
    local root expected
    root=$(make_fixture_root)
    stub_tools "${TEAM}" phone
    capture "${BASH}" "${root}/scripts/run-device.sh" --root "${root}"
    assert_exit 0
    grep -qxF -- "build -project MyApp.xcodeproj -scheme MyApp -configuration Debug -destination id=${UDID} -derivedDataPath build/device-derived-data -allowProvisioningUpdates -allowProvisioningDeviceRegistration" \
        "${STUB_BIN}/xcodebuild.log" || _fail "the build call was not as expected: $(cat "${STUB_BIN}/xcodebuild.log")"
    expected="devicectl device install app --device ${UDID} ${root}/build/device-derived-data/Build/Products/Debug-iphoneos/MyApp.app
devicectl device process launch --terminate-existing --device ${UDID} com.example.MyApp"
    [ "$(grep -v '^devicectl list ' "${STUB_BIN}/xcrun.log")" = "${expected}" ] ||
        _fail "devicectl calls were not install, then launch: $(cat "${STUB_BIN}/xcrun.log")"
    assert_stdout_contains "run-device: com.example.MyApp launched on device ${UDID}"
    assert_team_never_printed
}

case_unknown_argument() {
    local root
    root=$(make_fixture_root)
    stub_tools "${TEAM}" phone
    capture "${BASH}" "${root}/scripts/run-device.sh" --bogus
    assert_exit 1
    assert_first_stderr_line ERR_DEVICE_USAGE
    assert_stderr_contains "unknown argument '--bogus'"
    [ ! -e "${STUB_BIN}/xcodebuild.log" ] || _fail "xcodebuild ran before the arguments were checked"
}

run_case "an empty team fails ERR_DEVICE_NO_TEAM before any build" case_no_team
run_case "no connected device fails ERR_DEVICE_NONE, and the team is never printed" case_no_device_team_hidden
run_case "IOS_DEVICE naming no device fails ERR_DEVICE_NONE and names it" case_ios_device_unmatched
run_case "IOS_DEVICE matches a CoreDevice identifier" case_ios_device_matches_coredevice_id
run_case "a failed build fails ERR_DEVICE_BUILD_FAILED, with no install or launch" case_build_failure
run_case "a refused install fails ERR_DEVICE_INSTALL_FAILED" case_install_failure
run_case "a refused launch fails ERR_DEVICE_LAUNCH_FAILED" case_launch_failure
run_case "builds, installs, then launches the bundle id from project.yml" case_happy_path
run_case "an unknown argument fails ERR_DEVICE_USAGE" case_unknown_argument
finish
