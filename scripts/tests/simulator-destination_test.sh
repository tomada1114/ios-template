#!/usr/bin/env bash
# Tests for scripts/simulator-destination.sh: which device it picks out of a
# `simctl list` answer, the two forms it prints, and the named failure for each way
# picking one can fail, with and without the iPad family (`--family ipad`,
# SIMULATOR_FAMILY=ipad).
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
unset SIMULATOR_DEVICE SIMULATOR_FAMILY

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

# A runtime with no iPad: nothing matches the iPad family.
write_iphone_only_fixture() {
    cat >"$1" <<'EOF'
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
      {"name": "iPhone 17", "udid": "NEW-IPHONE-17", "isAvailable": true}
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
    assert_stderr_contains "Next: usage: scripts/simulator-destination.sh [--udid] [--family iphone|ipad]"
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

# The newer runtime lists its iPad first, ahead of every iPhone; the older runtime's
# iPad must lose to it.
case_family_ipad_picks_first_ipad_on_newest_runtime() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture "${BASH}" "${DESTINATION_SH}" --family ipad
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "platform=iOS Simulator,id=NEW-IPAD-PRO" ] ||
        _fail "stdout is not the -destination value for NEW-IPAD-PRO"

    capture "${BASH}" "${DESTINATION_SH}" --udid --family ipad
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "NEW-IPAD-PRO" ] || _fail "--udid --family ipad is not the bare UDID NEW-IPAD-PRO"
}

# What scripts/uitest-ipad.sh sets for uitest-build and uitest-run: the variable stands
# in for --family ipad, so every call inside those recipes lands on the iPad.
case_simulator_family_env_picks_an_ipad() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture env SIMULATOR_FAMILY=ipad "${BASH}" "${DESTINATION_SH}" --udid
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "NEW-IPAD-PRO" ] || _fail "SIMULATOR_FAMILY=ipad did not pick NEW-IPAD-PRO"
}

case_family_iphone_is_the_default_pick() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture "${BASH}" "${DESTINATION_SH}" --family iphone --udid
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "NEW-IPHONE-17" ] || _fail "--family iphone did not pick NEW-IPHONE-17"
}

case_family_flag_overrides_simulator_family() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture env SIMULATOR_FAMILY=ipad "${BASH}" "${DESTINATION_SH}" --family iphone --udid
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "NEW-IPHONE-17" ] || _fail "--family iphone did not override SIMULATOR_FAMILY=ipad"
}

case_family_ipad_honors_a_named_ipad() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture env SIMULATOR_DEVICE="iPad Air 11-inch (M2)" SIMULATOR_FAMILY=ipad "${BASH}" "${DESTINATION_SH}" --udid
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "OLD-IPAD-AIR" ] || _fail "SIMULATOR_DEVICE did not select OLD-IPAD-AIR under the iPad family"
}

# With a family set, SIMULATOR_DEVICE must name a device of that family, and the
# failure says how to get out of it.
case_family_ipad_rejects_a_named_iphone() {
    write_two_runtimes_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture env SIMULATOR_DEVICE="iPhone 17" SIMULATOR_FAMILY=ipad "${BASH}" "${DESTINATION_SH}"
    assert_exit 1
    assert_first_stderr_line ERR_SIM_NO_DEVICE
    assert_stderr_contains 'Expected: an iPad named "iPhone 17"'
    assert_stderr_contains "Next: set SIMULATOR_DEVICE to an iPad"
    assert_stdout_not_contains "platform=" "a destination"
}

case_no_ipad_available() {
    write_iphone_only_fixture "${CASE_DIR}/devices.json"
    stub_simctl_list "${CASE_DIR}/devices.json"

    capture "${BASH}" "${DESTINATION_SH}" --family ipad --udid
    assert_exit 1
    assert_first_stderr_line ERR_SIM_NO_DEVICE
    assert_stderr_contains "Expected: an available iPad on an installed iOS runtime"
    assert_stderr_contains "Next: install an iOS simulator runtime"
    [ ! -s "${CASE_DIR}/stdout" ] || _fail "stdout is not empty when no iPad matches"
}

case_unknown_family() {
    stub_command xcrun 'exit 0'
    capture "${BASH}" "${DESTINATION_SH}" --family android
    assert_exit 1
    assert_first_stderr_line ERR_SIM_USAGE
    assert_stderr_contains "unknown family 'android'"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran before the arguments were checked"
}

case_family_without_a_value() {
    stub_command xcrun 'exit 0'
    capture "${BASH}" "${DESTINATION_SH}" --udid --family
    assert_exit 1
    assert_first_stderr_line ERR_SIM_USAGE
    assert_stderr_contains "--family needs a value"
}

case_family_twice() {
    stub_command xcrun 'exit 0'
    capture "${BASH}" "${DESTINATION_SH}" --family ipad --family iphone
    assert_exit 1
    assert_first_stderr_line ERR_SIM_USAGE
    assert_stderr_contains "unexpected arguments: --family ipad --family iphone"
}

case_unknown_simulator_family() {
    stub_command xcrun 'exit 0'
    capture env SIMULATOR_FAMILY=android "${BASH}" "${DESTINATION_SH}"
    assert_exit 1
    assert_first_stderr_line ERR_SIM_USAGE
    assert_stderr_contains "unknown family 'android'"
    assert_stderr_contains "Actual: SIMULATOR_FAMILY='android'"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran before SIMULATOR_FAMILY was checked"
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
run_case "--family ipad picks the first available iPad on the newest runtime" case_family_ipad_picks_first_ipad_on_newest_runtime
run_case "SIMULATOR_FAMILY=ipad picks the first available iPad" case_simulator_family_env_picks_an_ipad
run_case "--family iphone picks what the default picks" case_family_iphone_is_the_default_pick
run_case "--family overrides SIMULATOR_FAMILY" case_family_flag_overrides_simulator_family
run_case "the iPad family with SIMULATOR_DEVICE naming an iPad selects it" case_family_ipad_honors_a_named_ipad
run_case "the iPad family with SIMULATOR_DEVICE naming an iPhone fails ERR_SIM_NO_DEVICE" case_family_ipad_rejects_a_named_iphone
run_case "no available iPad fails ERR_SIM_NO_DEVICE under --family ipad" case_no_ipad_available
run_case "an unknown --family fails ERR_SIM_USAGE" case_unknown_family
run_case "--family with no value fails ERR_SIM_USAGE" case_family_without_a_value
run_case "--family twice fails ERR_SIM_USAGE" case_family_twice
run_case "an unknown SIMULATOR_FAMILY fails ERR_SIM_USAGE" case_unknown_simulator_family
finish
