#!/usr/bin/env bash
# Tests for scripts/simulator-destination.sh: which device it picks out of a
# `simctl list` answer, the two forms it prints, and the named failure for each way
# picking one can fail.
#
# No real simulator is ever listed: `xcrun` is stubbed in every case, and its
# `simctl list devices available --json` answer is a JSON fixture the test writes.
# CI's lint job runs on Linux, where there is no xcrun at all. python3 is the real
# one, assumed on PATH like git.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

DESTINATION_SH="${REPO_ROOT}/scripts/simulator-destination.sh"
# The caller's own choice of device must not leak into a case that asserts the default.
unset SIMULATOR_DEVICE

# Two iOS runtimes, the older listed first so the pick has to sort by version, each
# with iPhones and an iPad; the newer one also lists an iPad first and an iPhone
# marked unavailable before the one that should win. A watchOS runtime is ignored.
write_two_runtimes_fixture() {
    cat >"$1" <<'EOF'
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
      {"name": "iPhone 16", "udid": "OLD-IPHONE-16", "isAvailable": true},
      {"name": "iPhone 16 Pro", "udid": "OLD-IPHONE-16-PRO", "isAvailable": true},
      {"name": "iPad Air 11-inch (M2)", "udid": "OLD-IPAD-AIR", "isAvailable": true}
    ],
    "com.apple.CoreSimulator.SimRuntime.watchOS-11-5": [
      {"name": "Apple Watch Series 10 (46mm)", "udid": "WATCH", "isAvailable": true}
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
      {"name": "iPad Pro 13-inch (M5)", "udid": "NEW-IPAD-PRO", "isAvailable": true},
      {"name": "iPhone 17 Pro Max", "udid": "NEW-IPHONE-17-PRO-MAX", "isAvailable": false},
      {"name": "iPhone 17", "udid": "NEW-IPHONE-17", "isAvailable": true},
      {"name": "iPhone 17 Pro", "udid": "NEW-IPHONE-17-PRO", "isAvailable": true}
    ]
  }
}
EOF
}

# A runtime with no iPhone: nothing matches the default pick.
write_ipad_only_fixture() {
    cat >"$1" <<'EOF'
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
      {"name": "iPad Pro 13-inch (M5)", "udid": "NEW-IPAD-PRO", "isAvailable": true}
    ]
  }
}
EOF
}

# stub_simctl_list FIXTURE — xcrun answers every call with FIXTURE's contents.
stub_simctl_list() {
    stub_command xcrun "cat '$1'"
}

# The first stderr line is the failure code, as the failure contract promises.
assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not $1"
}

case_default_picks_first_iphone_on_newest_runtime() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture "${BASH}" "${DESTINATION_SH}"
    assert_exit 0
    # The exact -destination value `just uitest` splices into xcodebuild.
    [ "$(cat "${CASE_DIR}/stdout")" = "platform=iOS Simulator,id=NEW-IPHONE-17" ] ||
        _fail "stdout is not the -destination value for NEW-IPHONE-17"
    [ "$(cat "${STUB_BIN}/xcrun.log")" = "simctl list devices available --json" ] ||
        _fail "xcrun was not called exactly once, as simctl list devices available --json"
}

case_udid_prints_only_the_udid() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture "${BASH}" "${DESTINATION_SH}" --udid
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "NEW-IPHONE-17" ] || _fail "stdout is not the bare UDID NEW-IPHONE-17"
}

case_simulator_device_selects_an_ipad() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture env SIMULATOR_DEVICE="iPad Air 11-inch (M2)" "${BASH}" "${DESTINATION_SH}" --udid
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "OLD-IPAD-AIR" ] || _fail "SIMULATOR_DEVICE did not select OLD-IPAD-AIR"
}

case_unknown_argument() {
    stub_command xcrun 'exit 0'
    capture "${BASH}" "${DESTINATION_SH}" --bogus
    assert_exit 1
    assert_first_stderr_line ERR_SIM_USAGE
    assert_stderr_contains "unknown argument '--bogus'"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next: usage: scripts/simulator-destination.sh [--udid]"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran before the arguments were checked"
}

case_too_many_arguments() {
    stub_command xcrun 'exit 0'
    capture "${BASH}" "${DESTINATION_SH}" --udid --udid
    assert_exit 1
    assert_first_stderr_line ERR_SIM_USAGE
    assert_stderr_contains "unexpected arguments: --udid --udid"
}

case_list_failure() {
    stub_command xcrun 'echo "xcrun: error: unable to find utility \"simctl\"" >&2; exit 72'
    capture "${BASH}" "${DESTINATION_SH}"
    assert_exit 1
    assert_first_stderr_line ERR_SIM_LIST
    assert_stderr_contains 'unable to find utility'
    assert_stderr_contains "Next: check \`xcode-select -p\`"
}

case_no_iphone_available() {
    write_ipad_only_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture "${BASH}" "${DESTINATION_SH}"
    assert_exit 1
    assert_first_stderr_line ERR_SIM_NO_DEVICE
    assert_stderr_contains "Expected: an available iPhone on an installed iOS runtime"
    assert_stdout_not_contains "platform=" "a destination"
}

case_named_device_missing() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture env SIMULATOR_DEVICE="iPhone 99" "${BASH}" "${DESTINATION_SH}"
    assert_exit 1
    assert_first_stderr_line ERR_SIM_NO_DEVICE
    assert_stderr_contains 'a device named "iPhone 99"'
}

# Listed by simctl but flagged unavailable: never picked, even by name.
case_named_device_unavailable() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture env SIMULATOR_DEVICE="iPhone 17 Pro Max" "${BASH}" "${DESTINATION_SH}"
    assert_exit 1
    assert_first_stderr_line ERR_SIM_NO_DEVICE
}

run_case "with no SIMULATOR_DEVICE, picks the first available iPhone on the newest runtime" case_default_picks_first_iphone_on_newest_runtime
run_case "--udid prints only that device's UDID" case_udid_prints_only_the_udid
run_case "SIMULATOR_DEVICE selects the named iPad" case_simulator_device_selects_an_ipad
run_case "an unknown argument fails ERR_SIM_USAGE" case_unknown_argument
run_case "two arguments fail ERR_SIM_USAGE" case_too_many_arguments
run_case "a failing simctl list fails ERR_SIM_LIST" case_list_failure
run_case "no available iPhone fails ERR_SIM_NO_DEVICE" case_no_iphone_available
run_case "a SIMULATOR_DEVICE nothing lists fails ERR_SIM_NO_DEVICE" case_named_device_missing
run_case "an unavailable SIMULATOR_DEVICE fails ERR_SIM_NO_DEVICE" case_named_device_unavailable
finish
