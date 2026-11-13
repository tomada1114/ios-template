#!/usr/bin/env bash
# Tests for scripts/uitest-ipad.sh: the one-line skip when the app the launch UI test
# runs in resolves to TARGETED_DEVICE_FAMILY "1", the error (never a skip) when that
# value cannot be read, the two recipes it runs on the iPad
# scripts/simulator-destination.sh picks, the shutdown of an iPad this run booted
# (and of no other), and the exit status on a signal.
#
# Nothing real runs: `just`, `xcodegen`, `xcodebuild`, and `xcrun` are stubbed in every
# case, each by a body file the case writes (sourced by the stub, so it sees "$@").
# xcodebuild answers -showBuildSettings from HOST_FAMILY; xcrun answers `simctl list`
# from a JSON fixture and DEVICE_STATE, and `simctl shutdown` with SHUTDOWN_STATUS.
# scripts/simulator-destination.sh and scripts/run-throttled.sh are the real ones,
# with the lock in the case's directory.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

UITEST_IPAD_SH="${REPO_ROOT}/scripts/uitest-ipad.sh"
# The caller's own device choice and throttle state must not leak into a case.
unset SIMULATOR_DEVICE SIMULATOR_IPAD_DEVICE SIMULATOR_FAMILY CI RUN_THROTTLED_LOCK_HELD
export CHECK_QOS=off

write_devices_fixture() {
    cat >"$1" <<'EOF'
{
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
      {"name": "iPhone 17", "udid": "NEW-IPHONE-17", "isAvailable": true},
      {"name": "iPad Pro 13-inch (M5)", "udid": "NEW-IPAD-PRO", "isAvailable": true},
      {"name": "iPad Air 11-inch (M3)", "udid": "NEW-IPAD-AIR", "isAvailable": true}
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

# setup_case [DEVICES_WRITER] — a fixture root and the four stubs. The just stub
# records each call's recipe, SIMULATOR_FAMILY, SIMULATOR_DEVICE, and directory; it
# fails the recipe FAIL_RECIPE names with exit 65, and for the one SLOW_RECIPE names it
# touches ${CASE_DIR}/started and sleeps a second.
setup_case() {
    # The path the script itself resolves (`cd … && pwd`), for the PWD it hands `just`.
    ROOT=$(cd "$(make_temp_dir)" && pwd)
    "${1:-write_devices_fixture}" "${CASE_DIR}/devices.json"
    export RUN_THROTTLED_LOCK_DIR="${CASE_DIR}/lock" FIXTURE_DIR="${CASE_DIR}"
    JUST_ENV_LOG="${CASE_DIR}/just.env"

    cat >"${CASE_DIR}/xcodegen.sh" <<'EOF'
if [ "${GENERATE_STATUS:-0}" != 0 ]; then echo "Spec validation error"; exit "${GENERATE_STATUS}"; fi
EOF
    cat >"${CASE_DIR}/xcodebuild.sh" <<'EOF'
[ "${SETTINGS_STATUS:-0}" = 0 ] || { echo "xcodebuild: error: unable to read project"; exit "${SETTINGS_STATUS}"; }
target=""
while [ $# -gt 0 ]; do
    if [ "$1" = -target ]; then target="$2"; fi
    shift
done
echo "Build settings for action build and target ${target}:"
echo "    SDKROOT = /Applications/Xcode.app/iPhoneSimulator.sdk"
if [ "${target}" = MyAppLaunchUITests ]; then
    echo "    TARGETED_DEVICE_FAMILY = 1,2"
    [ "${NO_HOST:-}" = 1 ] || echo "    TEST_TARGET_NAME = MyApp"
elif [ "${target}" = MyApp ] && [ "${HOST_FAMILY:-1,2}" != none ]; then
    echo "    TARGETED_DEVICE_FAMILY = ${HOST_FAMILY:-1,2}"
fi
EOF
    cat >"${CASE_DIR}/xcrun.sh" <<'EOF'
if [ "$2" = list ] && [ "$4" = available ]; then
    cat "${FIXTURE_DIR}/devices.json"
elif [ "$2" = list ]; then
    printf '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-1":[{"udid":"NEW-IPAD-PRO","state":"%s"}]}}\n' "${DEVICE_STATE:-Shutdown}"
else
    exit "${SHUTDOWN_STATUS:-0}"
fi
EOF
    cat >"${CASE_DIR}/just.sh" <<'EOF'
echo "$1 SIMULATOR_FAMILY=${SIMULATOR_FAMILY:-unset} SIMULATOR_DEVICE=${SIMULATOR_DEVICE:-unset} PWD=$(pwd)" >>"${FIXTURE_DIR}/just.env"
if [ "$1" = "${SLOW_RECIPE:-}" ]; then touch "${FIXTURE_DIR}/started"; sleep 1; fi
if [ "$1" = "${FAIL_RECIPE:-}" ]; then exit 65; fi
EOF
    local tool
    for tool in xcodegen xcodebuild xcrun just; do
        stub_command "${tool}" ". '${CASE_DIR}/${tool}.sh'"
    done
}

assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "the first stderr line is not $1"
}

# assert_file_is FILE WANT — FILE holds exactly WANT.
assert_file_is() {
    [ -f "$1" ] || _fail "$(basename "$1") was not written"
    [ "$(cat "$1")" = "$2" ] || _fail "$(basename "$1") is not: $2"
}

# xcrun's calls with the device listing, the state read, and (optionally) a shutdown.
XCRUN_LIST="simctl list devices available --json"
XCRUN_STATE="simctl list devices --json"
XCRUN_SHUTDOWN="simctl shutdown NEW-IPAD-PRO"

case_iphone_only_host_skips_with_one_line() {
    setup_case
    capture env HOST_FAMILY=1 "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_file_is "${CASE_DIR}/stdout" 'Skipped uitest-ipad: MyApp targets iPhone only (TARGETED_DEVICE_FAMILY "1")'
    [ ! -s "${CASE_DIR}/stderr" ] || _fail "stderr is not empty on a skip"
    assert_file_is "${STUB_BIN}/xcodegen.log" "generate"
    [ ! -e "${STUB_BIN}/just.log" ] || _fail "a recipe ran for an iPhone-only app"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "a simulator was touched for an iPhone-only app"
}

# The decision is the host app's resolved value: the UI-test target's own "1,2" is not it.
case_reads_the_host_apps_resolved_family() {
    setup_case
    capture env HOST_FAMILY=1 "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    grep -qx -- "-showBuildSettings -project MyApp.xcodeproj -target MyAppLaunchUITests -sdk iphonesimulator" "${STUB_BIN}/xcodebuild.log" ||
        _fail "the UI-test target's settings were not read"
    grep -qx -- "-showBuildSettings -project MyApp.xcodeproj -target MyApp -sdk iphonesimulator" "${STUB_BIN}/xcodebuild.log" ||
        _fail "the host app's settings were not read"
}

case_runs_both_recipes_on_the_ipad_then_shuts_it_down() {
    setup_case
    capture "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_file_is "${JUST_ENV_LOG}" "uitest-build SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE=unset PWD=${ROOT}
uitest-run SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE=unset PWD=${ROOT}"
    assert_file_is "${STUB_BIN}/xcrun.log" "${XCRUN_LIST}
${XCRUN_STATE}
${XCRUN_SHUTDOWN}"
}

case_family_without_ipad_or_iphone_fails() {
    setup_case
    capture env HOST_FAMILY=3 "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_FAMILY
    assert_stderr_contains 'Actual: "3"'
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "a simulator was touched"
}

# Each way the value cannot be read fails; none reads as a skip.
case_unreadable_family_fails_never_skips() {
    setup_case
    capture env HOST_FAMILY=none "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_FAMILY
    assert_stderr_contains "could not read MyApp's TARGETED_DEVICE_FAMILY"
    assert_stdout_not_contains "Skipped" "a skip notice"

    capture env NO_HOST=1 "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_FAMILY
    assert_stderr_contains "could not read the app the launch UI test runs in"

    capture env SETTINGS_STATUS=74 "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_FAMILY
    assert_stderr_contains "unable to read project"
    assert_stdout_not_contains "Skipped" "a skip notice"
    [ ! -e "${STUB_BIN}/just.log" ] || _fail "a recipe ran"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "a simulator was touched"
}

case_failed_generate_fails() {
    setup_case
    capture env GENERATE_STATUS=1 "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_GENERATE
    assert_stderr_contains "Spec validation error"
    [ ! -e "${STUB_BIN}/xcodebuild.log" ] || _fail "settings were read from a project that failed to generate"
}

case_failed_test_still_shuts_down() {
    setup_case
    capture env FAIL_RECIPE=uitest-run "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 65
    assert_file_is "${STUB_BIN}/xcrun.log" "${XCRUN_LIST}
${XCRUN_STATE}
${XCRUN_SHUTDOWN}"
}

# The device was never booted: nothing to shut down, and its state is not even read.
case_failed_build_skips_the_run_and_the_shutdown() {
    setup_case
    capture env FAIL_RECIPE=uitest-build "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 65
    assert_file_is "${STUB_BIN}/just.log" "uitest-build"
    assert_file_is "${STUB_BIN}/xcrun.log" "${XCRUN_LIST}"
}

# Someone else's booted iPad is left booted.
case_already_booted_ipad_is_left_alone() {
    setup_case
    capture env DEVICE_STATE=Booted "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_file_is "${STUB_BIN}/xcrun.log" "${XCRUN_LIST}
${XCRUN_STATE}"
}

case_failed_shutdown_warns_and_keeps_the_status() {
    setup_case
    capture env SHUTDOWN_STATUS=149 "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_stderr_contains "warning: could not shut down the iPad simulator NEW-IPAD-PRO"
}

# SIMULATOR_DEVICE is the iPhone legs' choice: an iPhone name there neither fails the
# iPad leg nor reaches its recipes; SIMULATOR_IPAD_DEVICE picks the iPad.
case_simulator_device_is_ignored_and_ipad_device_picks() {
    setup_case
    capture env SIMULATOR_DEVICE="iPhone 17" "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_file_is "${JUST_ENV_LOG}" "uitest-build SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE=unset PWD=${ROOT}
uitest-run SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE=unset PWD=${ROOT}"

    mv "${JUST_ENV_LOG}" "${CASE_DIR}/just.env.first"
    capture env SIMULATOR_DEVICE="iPhone 17" SIMULATOR_IPAD_DEVICE="iPad Air 11-inch (M3)" "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 0
    assert_file_is "${JUST_ENV_LOG}" "uitest-build SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE=iPad Air 11-inch (M3) PWD=${ROOT}
uitest-run SIMULATOR_FAMILY=ipad SIMULATOR_DEVICE=iPad Air 11-inch (M3) PWD=${ROOT}"
    grep -qx "simctl shutdown NEW-IPAD-AIR" "${STUB_BIN}/xcrun.log" || _fail "the named iPad was not the one shut down"
}

case_no_ipad_fails_before_any_build() {
    setup_case write_iphone_only_devices_fixture
    capture "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_SIM_NO_DEVICE
    assert_stderr_contains "Expected: an available iPad on an installed iOS runtime"
    [ ! -e "${STUB_BIN}/just.log" ] || _fail "a recipe ran with no iPad to run on"
    assert_file_is "${STUB_BIN}/xcrun.log" "${XCRUN_LIST}"
}

# TERM during the test: the iPad is shut down without the lock — which another holder
# keeps here, past a short wait timeout — and the script exits 143.
case_term_during_the_test_shuts_down_unlocked() {
    setup_case
    export SLOW_RECIPE=uitest-run RUN_THROTTLED_WAIT_TIMEOUT=3
    "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr" &
    local pid=$! waited=0 status=0
    while [ ! -e "${CASE_DIR}/started" ] && [ "${waited}" -lt 100 ]; do
        sleep 0.1
        waited=$((waited + 1))
    done
    [ -e "${CASE_DIR}/started" ] || _fail "the stubbed uitest-run never started"
    mkdir -p "${RUN_THROTTLED_LOCK_DIR}/xcode.lock"
    printf '%s\n%s\n' "$$" "another worktree's run" >"${RUN_THROTTLED_LOCK_DIR}/xcode.lock/holder"
    kill -TERM "${pid}"
    wait "${pid}" || status=$?
    [ "${status}" = 143 ] || _fail "expected exit 143 after TERM, got ${status}"
    grep -qx "${XCRUN_SHUTDOWN}" "${STUB_BIN}/xcrun.log" || _fail "the iPad was not shut down on TERM"
}

case_tool_missing_fails_before_any_work() {
    setup_case
    mv "${STUB_BIN}/just" "${CASE_DIR}/just.aside"
    capture env PATH="${STUB_BIN}:/usr/bin:/bin" "${BASH}" "${UITEST_IPAD_SH}" --root "${ROOT}"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_TOOL_MISSING
    assert_stderr_contains "just is not on PATH"
    [ ! -e "${STUB_BIN}/xcodegen.log" ] || _fail "xcodegen ran with no just to run the recipes"
}

case_unknown_argument() {
    setup_case
    capture "${BASH}" "${UITEST_IPAD_SH}" --bogus
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_USAGE
    assert_stderr_contains "Next: usage: scripts/uitest-ipad.sh [--root DIR]"
    [ ! -e "${STUB_BIN}/xcodegen.log" ] || _fail "xcodegen ran before the arguments were checked"
}

case_root_missing() {
    setup_case
    capture "${BASH}" "${UITEST_IPAD_SH}" --root "${CASE_DIR}/nowhere"
    assert_exit 1
    assert_first_stderr_line ERR_UITEST_IPAD_USAGE
    assert_stderr_contains "does not exist"
}

run_case "a host app resolving to family \"1\" skips with a one-line notice" case_iphone_only_host_skips_with_one_line
run_case "the decision reads the host app's resolved settings" case_reads_the_host_apps_resolved_family
run_case "with iPad, runs uitest-build then uitest-run on the iPad, then shuts it down" case_runs_both_recipes_on_the_ipad_then_shuts_it_down
run_case "a family naming neither 1 alone nor 2 fails ERR_UITEST_IPAD_FAMILY" case_family_without_ipad_or_iphone_fails
run_case "an unreadable family fails ERR_UITEST_IPAD_FAMILY, never a skip" case_unreadable_family_fails_never_skips
run_case "a failed xcodegen generate fails ERR_UITEST_IPAD_GENERATE" case_failed_generate_fails
run_case "a failing uitest-run keeps its status and still shuts the iPad down" case_failed_test_still_shuts_down
run_case "a failing uitest-build skips uitest-run and the shutdown" case_failed_build_skips_the_run_and_the_shutdown
run_case "an iPad already booted before the run is left booted" case_already_booted_ipad_is_left_alone
run_case "a failed shutdown warns and keeps the test's status" case_failed_shutdown_warns_and_keeps_the_status
run_case "SIMULATOR_DEVICE is ignored; SIMULATOR_IPAD_DEVICE picks the iPad" case_simulator_device_is_ignored_and_ipad_device_picks
run_case "no available iPad fails ERR_SIM_NO_DEVICE before any build" case_no_ipad_fails_before_any_build
run_case "TERM during the test shuts the iPad down without the lock and exits 143" case_term_during_the_test_shuts_down_unlocked
run_case "a missing tool fails ERR_UITEST_IPAD_TOOL_MISSING before any work" case_tool_missing_fails_before_any_work
run_case "an unknown argument fails ERR_UITEST_IPAD_USAGE" case_unknown_argument
run_case "a --root that does not exist fails ERR_UITEST_IPAD_USAGE" case_root_missing
finish
