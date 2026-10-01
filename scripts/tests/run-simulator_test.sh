#!/usr/bin/env bash
# Tests for scripts/run-simulator.sh: the simctl calls it makes, in order, and the
# named failure for each way installing and launching the build can fail.
#
# No simulator is ever booted, installed on, or launched: `xcrun` and `open` are
# stubbed in every case. The script finds scripts/bundle-id.sh and
# scripts/simulator-destination.sh next to itself, so each case copies all three into
# a fixture root's scripts/ and runs that copy with --root pointing at the fixture: a
# project.yml declaring com.example.MyApp and a fake .app at the Debug simulator
# products path. The real simulator-destination.sh and bundle-id.sh run against it.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

APP_RELATIVE_PATH="build/dev-derived-data/Build/Products/Debug-iphonesimulator/MyApp.app"
UDID="NEW-IPHONE-17"
unset SIMULATOR_DEVICE

# make_fixture_root [--no-app] — a checkout-shaped directory holding copies of the
# three scripts, a project.yml, and (unless --no-app) a built simulator app bundle.
make_fixture_root() {
    local root name
    # Normalized (no doubled slash from TMPDIR), the way the script resolves --root.
    root=$(cd "$(make_temp_dir)" && pwd)
    mkdir "${root}/scripts"
    for name in run-simulator.sh bundle-id.sh simulator-destination.sh; do
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
    if [ "${1:-}" != "--no-app" ]; then
        mkdir -p "${root}/${APP_RELATIVE_PATH}"
    fi
    echo "${root}"
}

# stub_simctl [FAILING_SUBCOMMAND] — xcrun answers `simctl list` with a one-iPhone
# fixture, and every other simctl call with success, except FAILING_SUBCOMMAND
# (bootstatus, install, or launch), which prints an error and exits 1. FAILING_SUBCOMMAND
# `open` makes the stubbed `open` fail instead, the way it does on a Mac without the app.
stub_simctl() {
    cat >"${CASE_DIR}/devices.json" <<EOF
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
  {"name": "iPhone 17", "udid": "${UDID}", "isAvailable": true}
]}}
EOF
    export XCRUN_FIXTURE="${CASE_DIR}/devices.json" XCRUN_FAIL="${1:-}"
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command xcrun 'case "$2" in
    list) cat "${XCRUN_FIXTURE}" ;;
    bootstatus | install | launch)
        if [ "$2" = "${XCRUN_FAIL}" ]; then
            echo "simctl $2: stubbed failure" >&2
            exit 1
        fi
        if [ "$2" = launch ]; then echo "com.example.MyApp: 4242"; fi
        ;;
    *)
        echo "unexpected xcrun call: $*" >&2
        exit 64
        ;;
esac'
    if [ "${1:-}" = open ]; then
        stub_command open 'echo "Unable to find application with bundle identifier com.apple.dt.Devices" >&2; exit 1'
    else
        stub_command open 'exit 0'
    fi
}

# The simctl calls after the device pick, one per line, in the order they were made.
simctl_calls_after_list() {
    grep -v '^simctl list ' "${STUB_BIN}/xcrun.log" || true
}

assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not $1"
}

case_boots_installs_then_launches() {
    local root expected
    root=$(make_fixture_root)
    stub_simctl

    capture "${BASH}" "${root}/scripts/run-simulator.sh" --root "${root}"
    assert_exit 0
    expected="simctl bootstatus ${UDID} -b
simctl install ${UDID} ${root}/${APP_RELATIVE_PATH}
simctl launch --terminate-running-process ${UDID} com.example.MyApp"
    [ "$(simctl_calls_after_list)" = "${expected}" ] ||
        _fail "the simctl calls were not bootstatus, install, launch, in that order: $(cat "${STUB_BIN}/xcrun.log")"
    grep -qxF -- "-b com.apple.dt.Devices" "${STUB_BIN}/open.log" ||
        _fail "Device Hub was not opened"
    assert_stdout_contains "run: com.example.MyApp launched on simulator ${UDID}"
}

case_device_hub_unavailable_still_launches() {
    local root
    root=$(make_fixture_root)
    stub_simctl open
    capture "${BASH}" "${root}/scripts/run-simulator.sh" --root "${root}"
    assert_exit 0
    assert_stderr_contains "run: could not open Device Hub"
    grep -q '^simctl launch ' "${STUB_BIN}/xcrun.log" ||
        _fail "simctl launch did not run after Device Hub failed to open"
    assert_stdout_contains "run: com.example.MyApp launched on simulator ${UDID}"
}

case_unknown_argument() {
    local root
    root=$(make_fixture_root)
    stub_simctl
    capture "${BASH}" "${root}/scripts/run-simulator.sh" --bogus
    assert_exit 1
    assert_first_stderr_line ERR_RUN_USAGE
    assert_stderr_contains "unknown argument '--bogus'"
    assert_stderr_contains "Next: usage: scripts/run-simulator.sh [--root DIR]"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran before the arguments were checked"
}

case_root_missing() {
    local root
    root=$(make_fixture_root)
    stub_simctl
    capture "${BASH}" "${root}/scripts/run-simulator.sh" --root "${root}/does-not-exist"
    assert_exit 1
    assert_first_stderr_line ERR_RUN_USAGE
    assert_stderr_contains "--root needs an existing directory"
}

case_app_missing() {
    local root
    root=$(make_fixture_root --no-app)
    stub_simctl
    capture "${BASH}" "${root}/scripts/run-simulator.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_RUN_APP_MISSING
    assert_stderr_contains "${root}/${APP_RELATIVE_PATH}"
    assert_stderr_contains "just build"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran without a build to install"
    [ ! -e "${STUB_BIN}/open.log" ] || _fail "Device Hub was opened without a build to install"
}

case_boot_failure() {
    local root
    root=$(make_fixture_root)
    stub_simctl bootstatus
    capture "${BASH}" "${root}/scripts/run-simulator.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_RUN_BOOT_FAILED
    assert_stderr_contains "simctl bootstatus: stubbed failure"
    [ "$(simctl_calls_after_list)" = "simctl bootstatus ${UDID} -b" ] ||
        _fail "simctl went on past a failed boot: $(cat "${STUB_BIN}/xcrun.log")"
    [ ! -e "${STUB_BIN}/open.log" ] || _fail "Device Hub was opened after a failed boot"
}

case_install_failure() {
    local root
    root=$(make_fixture_root)
    stub_simctl install
    capture "${BASH}" "${root}/scripts/run-simulator.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_RUN_INSTALL_FAILED
    assert_stderr_contains "simctl install: stubbed failure"
    if grep -q '^simctl launch ' "${STUB_BIN}/xcrun.log"; then
        _fail "simctl launch ran after a failed install"
    fi
}

case_launch_failure() {
    local root
    root=$(make_fixture_root)
    stub_simctl launch
    capture "${BASH}" "${root}/scripts/run-simulator.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_RUN_LAUNCH_FAILED
    assert_stderr_contains "simctl could not launch com.example.MyApp"
    assert_stderr_contains "simctl launch: stubbed failure"
    assert_stdout_not_contains "launched on simulator" "a success line"
}

run_case "boots, installs, then launches the build, in that order" case_boots_installs_then_launches
run_case "a Device Hub that cannot be opened still installs and launches" case_device_hub_unavailable_still_launches
run_case "an unknown argument fails ERR_RUN_USAGE" case_unknown_argument
run_case "a --root that does not exist fails ERR_RUN_USAGE" case_root_missing
run_case "no Debug simulator build fails ERR_RUN_APP_MISSING" case_app_missing
run_case "a device that does not boot fails ERR_RUN_BOOT_FAILED" case_boot_failure
run_case "a refused install fails ERR_RUN_INSTALL_FAILED" case_install_failure
run_case "a refused launch fails ERR_RUN_LAUNCH_FAILED" case_launch_failure
finish
