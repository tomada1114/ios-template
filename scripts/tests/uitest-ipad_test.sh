#!/usr/bin/env bash
# Tests for scripts/uitest-ipad.sh: the one-line skip for an iPhone-only project.yml,
# the two recipes it runs on the iPad scripts/simulator-destination.sh picks, the
# shutdown that follows whatever the test did, and the failures it passes through.
#
# Nothing real runs: `just` and `xcrun` are stubbed in every case. The xcrun stub
# answers `simctl list` with a JSON fixture and `simctl shutdown` with
# SHUTDOWN_STATUS. scripts/targets-ipad.sh, scripts/simulator-destination.sh, and
# scripts/run-throttled.sh are the real ones, with the lock in the case's directory.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

UITEST_IPAD_SH="${REPO_ROOT}/scripts/uitest-ipad.sh"
# The caller's own device choice and throttle state must not leak into a case.
unset SIMULATOR_DEVICE SIMULATOR_FAMILY CI RUN_THROTTLED_LOCK_HELD
export CHECK_QOS=off

# write_manifest ROOT FAMILY — a project.yml with an app and a UI-test target, both
# on FAMILY.
write_manifest() {
    printf '%s\n' \
        'name: MyApp' \
        'targets:' \
        '  MyApp:' \
        '    type: application' \
        '    platform: iOS' \
        '    settings:' \
        '      base:' \
        "        TARGETED_DEVICE_FAMILY: \"$2\"" \
        '  MyAppLaunchUITests:' \
        '    type: bundle.ui-testing' \
        '    platform: iOS' \
        '    settings:' \
        '      base:' \
        "        TARGETED_DEVICE_FAMILY: \"$2\"" >"$1/project.yml"
}

write_devices_fixture() {
    cat >"$1" <<'EOF'
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
      {"name": "iPhone 17", "udid": "NEW-IPHONE-17", "isAvailable": true},
      {"name": "iPad Pro 13-inch (M5)", "udid": "NEW-IPAD-PRO", "isAvailable": true}
    ]
  }
}
EOF
}

write_iphone_only_devices_fixture() {
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

# setup_case FAMILY [DEVICES_WRITER] — a fixture root, the xcrun stub, and a just stub
# that records each call's SIMULATOR_FAMILY and directory and fails a recipe named in
# FAIL_RECIPE with exit 65.
setup_case() {
    # The path the script itself resolves (`cd … && pwd`), for the PWD it hands `just`.
    ROOT=$(cd "$(make_temp_dir)" && pwd)
    write_manifest "${ROOT}" "$1"
    "${2:-write_devices_fixture}" "${CASE_DIR}/devices.json"
    export RUN_THROTTLED_LOCK_DIR="${CASE_DIR}/lock"
    JUST_ENV_LOG="${CASE_DIR}/just.env"
    stub_command xcrun "if [ \"\$2\" = list ]; then cat '${CASE_DIR}/devices.json'; else exit \"\${SHUTDOWN_STATUS:-0}\"; fi"
    stub_command just "echo \"\$1 SIMULATOR_FAMILY=\${SIMULATOR_FAMILY:-unset} PWD=\$(pwd)\" >>'${JUST_ENV_LOG}'
if [ \"\$1\" = \"\${FAIL_RECIPE:-}\" ]; then exit 65; fi"
}

assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "the first stderr line is not $1"
}

# assert_file_is FILE WANT — FILE holds exactly WANT.
assert_file_is() {
    [ -f "$1" ] || _fail "$(basename "$1") was not written"
    [ "$(cat "$1")" = "$2" ] || _fail "$(basename "$1") is not: $2"
}

case_iphone_only_skips_with_one_line() {
    setup_case 1
    capture "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_file_is "${CASE_DIR}/stdout" 'Skipped uitest-ipad: project.yml builds no iOS target for iPad (TARGETED_DEVICE_FAMILY "1")'
    [ ! -s "${CASE_DIR}/stderr" ] || _fail "stderr is not empty on a skip"
    [ ! -e "${STUB_BIN}/just.log" ] || _fail "a recipe ran for an iPhone-only app"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran for an iPhone-only app"
}

case_runs_both_recipes_on_the_ipad_then_shuts_it_down() {
    setup_case "1,2"
    capture "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_file_is "${JUST_ENV_LOG}" "uitest-build SIMULATOR_FAMILY=ipad PWD=${ROOT}
uitest-run SIMULATOR_FAMILY=ipad PWD=${ROOT}"
    assert_file_is "${STUB_BIN}/xcrun.log" "simctl list devices available --json
simctl shutdown NEW-IPAD-PRO"
}

case_failed_test_still_shuts_down() {
    setup_case "1,2"
    capture env FAIL_RECIPE=uitest-run "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 65
    assert_file_is "${STUB_BIN}/xcrun.log" "simctl list devices available --json
simctl shutdown NEW-IPAD-PRO"
}

case_failed_build_skips_the_run_and_still_shuts_down() {
    setup_case "1,2"
    capture env FAIL_RECIPE=uitest-build "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 65
    assert_file_is "${STUB_BIN}/just.log" "uitest-build"
    assert_file_is "${STUB_BIN}/xcrun.log" "simctl list devices available --json
simctl shutdown NEW-IPAD-PRO"
}

case_failed_shutdown_warns_and_keeps_the_status() {
    setup_case "1,2"
    capture env SHUTDOWN_STATUS=149 "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_stderr_contains "warning: could not shut down the iPad simulator NEW-IPAD-PRO"
}

case_no_ipad_fails_before_any_build() {
    setup_case "1,2" write_iphone_only_devices_fixture
    capture "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_SIM_NO_DEVICE
    assert_stderr_contains "Expected: an available iPad on an installed iOS runtime"
    [ ! -e "${STUB_BIN}/just.log" ] || _fail "a recipe ran with no iPad to run on"
    assert_file_is "${STUB_BIN}/xcrun.log" "simctl list devices available --json"
}

# A manifest targets-ipad.sh cannot answer for fails the run; it never reads as a skip.
case_unreadable_manifest_fails_instead_of_skipping() {
    setup_case "1,2"
    mv "${ROOT}/project.yml" "${CASE_DIR}/project.yml.aside"
    capture "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_IPAD_MANIFEST_MISSING
    assert_stdout_not_contains "Skipped" "a skip notice"
    [ ! -e "${STUB_BIN}/just.log" ] || _fail "a recipe ran"
}

# PATH holds the stub bin and the system directories alone, so `just` is nowhere.
case_just_missing_fails_before_any_device_work() {
    setup_case "1,2"
    mv "${STUB_BIN}/just" "${CASE_DIR}/just.aside"
    capture env PATH="${STUB_BIN}:/usr/bin:/bin" "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_JUST_MISSING
    assert_stderr_contains "Next: run \`mise install\`"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran with no just to run the recipes"
}

case_unknown_argument() {
    setup_case "1,2"
    capture "${BASH}" "${UITEST_IPAD_SH}" --bogus
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_USAGE
    assert_stderr_contains "Next: usage: scripts/uitest-ipad.sh [--root DIR]"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran before the arguments were checked"
}

case_root_missing() {
    setup_case "1,2"
    capture "${BASH}" "${UITEST_IPAD_SH}" --root "${CASE_DIR}/nowhere"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_USAGE
    assert_stderr_contains "does not exist"
}

run_case "an iPhone-only project.yml skips with a one-line notice" case_iphone_only_skips_with_one_line
run_case "with iPad, runs uitest-build then uitest-run on the iPad, then shuts it down" case_runs_both_recipes_on_the_ipad_then_shuts_it_down
run_case "a failing uitest-run keeps its status and still shuts the iPad down" case_failed_test_still_shuts_down
run_case "a failing uitest-build skips uitest-run and still shuts the iPad down" case_failed_build_skips_the_run_and_still_shuts_down
run_case "a failed shutdown warns and keeps the test's status" case_failed_shutdown_warns_and_keeps_the_status
run_case "no available iPad fails ERR_SIM_NO_DEVICE before any build" case_no_ipad_fails_before_any_build
run_case "a missing project.yml fails ERR_IPAD_MANIFEST_MISSING, never a skip" case_unreadable_manifest_fails_instead_of_skipping
run_case "no just on PATH fails ERR_UITEST_IPAD_JUST_MISSING before any device work" case_just_missing_fails_before_any_device_work
run_case "an unknown argument fails ERR_UITEST_IPAD_USAGE" case_unknown_argument
run_case "a --root that does not exist fails ERR_UITEST_IPAD_USAGE" case_root_missing
finish
