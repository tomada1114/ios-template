#!/usr/bin/env bash
# Tests for scripts/smoke_launch.sh: the build, the simctl calls it makes in order, the
# alive-window poll, and the named failure for each way the smoke launch can fail.
#
# Nothing is built, signed, booted, installed, or launched: xcodegen, xcodebuild,
# xcbeautify, plutil, codesign, and xcrun are stubbed in every case, and so is `sleep`,
# which makes the ten one-second polls instant while its log still counts them. The
# script finds scripts/simulator-destination.sh next to itself and builds the checkout
# above it, so each case copies both scripts into a fixture root's scripts/ and runs
# that copy; the real simulator-destination.sh runs against the stubbed `xcrun`.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

APP_RELATIVE_PATH="build/smoke-derived-data/Build/Products/Release-iphonesimulator/MyApp.app"
BUNDLE_ID="com.example.MyApp"
UDID="NEW-IPHONE-17"
unset SIMULATOR_DEVICE

# make_fixture_root [--no-app] — a checkout-shaped directory holding copies of the two
# scripts and (unless --no-app) the app bundle the Release build would leave behind.
make_fixture_root() {
    local root name
    # Normalized (no doubled slash from TMPDIR), the way the script resolves its root.
    root=$(cd "$(make_temp_dir)" && pwd)
    mkdir "${root}/scripts"
    for name in smoke_launch.sh simulator-destination.sh; do
        cp "${REPO_ROOT}/scripts/${name}" "${root}/scripts/${name}"
        chmod +x "${root}/scripts/${name}"
    done
    if [ "${1:-}" != "--no-app" ]; then
        make_app "${root}/${APP_RELATIVE_PATH}"
    fi
    echo "${root}"
}

make_app() { # make_app PATH — an app-shaped directory: plutil and codesign are stubbed
    mkdir -p "$1"
    : >"$1/Info.plist"
}

# stub_tools [VARIABLE=VALUE …] — stubs every external tool the script calls; each
# assignment is exported first and picks a failure:
#   XCODEGEN_EXIT, XCODEBUILD_EXIT  the tool's exit status (default 0)
#   PLUTIL_FAIL=1, CODESIGN_FAIL=1  the tool rejects the bundle
#   NO_DEVICES=1                    `simctl list` shows no iPhone
#   XCRUN_FAIL=<subcommand>         that simctl subcommand (bootstatus, install, launch) fails
#   JOB_GONE_AT=<n>                 from the n-th `launchctl list`, the app's job is missing
#   JOB_PID=<field>                 the app job's PID field (default 4242)
stub_tools() {
    local assignment
    export XCODEGEN_EXIT=0 XCODEBUILD_EXIT=0 PLUTIL_FAIL="" CODESIGN_FAIL="" NO_DEVICES=""
    export XCRUN_FAIL="" JOB_GONE_AT="" JOB_PID=4242
    for assignment in "$@"; do
        export "${assignment?}"
    done
    export SPAWN_COUNT="${CASE_DIR}/spawn-count" XCRUN_FIXTURE="${CASE_DIR}/devices.json"
    if [ -n "${NO_DEVICES}" ]; then
        echo '{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-1": []}}' >"${XCRUN_FIXTURE}"
    else
        cat >"${XCRUN_FIXTURE}" <<EOF
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-1": [
  {"name": "iPhone 17", "udid": "${UDID}", "isAvailable": true}
]}}
EOF
    fi
    # shellcheck disable=SC2016 # the stub bodies expand their variables when they run
    {
        stub_command xcodegen 'exit "${XCODEGEN_EXIT}"'
        stub_command xcodebuild 'echo "stub xcodebuild output"; exit "${XCODEBUILD_EXIT}"'
        stub_command xcbeautify 'cat'
        stub_command plutil 'if [ -n "${PLUTIL_FAIL}" ]; then echo "plutil: stubbed: no value" >&2; exit 1; fi
echo com.example.MyApp'
        stub_command codesign 'if [ -n "${CODESIGN_FAIL}" ]; then echo "codesign: stubbed: invalid signature" >&2; exit 1; fi'
        stub_command sleep 'exit 0'
        stub_command xcrun 'case "$2" in
    list) cat "${XCRUN_FIXTURE}" ;;
    bootstatus | install | launch)
        if [ "$2" = "${XCRUN_FAIL}" ]; then
            echo "simctl $2: stubbed failure" >&2
            exit 1
        fi
        if [ "$2" = launch ]; then echo "com.example.MyApp: 4242"; fi
        ;;
    getenv) echo "iPhone 17" ;;
    spawn)
        n=$(($(cat "${SPAWN_COUNT}" 2>/dev/null || echo 0) + 1))
        echo "${n}" >"${SPAWN_COUNT}"
        printf "PID\tStatus\tLabel\n"
        printf "101\t0\tcom.apple.springboard\n"
        printf "999\t0\tUIKitApplication:com.example.MyAppWidget[1a2b][rb-legacy]\n"
        if [ -z "${JOB_GONE_AT}" ] || [ "${n}" -lt "${JOB_GONE_AT}" ]; then
            printf "%s\t0\tUIKitApplication:com.example.MyApp[5c3d][rb-legacy]\n" "${JOB_PID}"
        fi
        ;;
    terminate) ;;
    *)
        echo "unexpected xcrun call: $*" >&2
        exit 64
        ;;
esac'
    }
}

# The simctl calls after the device picks, one per line, in the order they were made.
simctl_calls_after_list() {
    grep -v '^simctl list ' "${STUB_BIN}/xcrun.log" || true
}

assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not $1"
}

assert_not_called() { # assert_not_called TOOL WHY
    [ ! -e "${STUB_BIN}/$1.log" ] || _fail "$1 ran $2"
}

assert_no_simctl() { # assert_no_simctl SUBCOMMAND WHY
    if grep -q "^simctl $1 " "${STUB_BIN}/xcrun.log" 2>/dev/null; then
        _fail "simctl $1 ran $2"
    fi
}

expected_calls() { # expected_calls APP_PATH POLLS [--terminate]
    local polls=0
    echo "simctl bootstatus ${UDID} -b"
    echo "simctl getenv ${UDID} SIMULATOR_DEVICE_NAME"
    echo "simctl install ${UDID} $1"
    echo "simctl launch --terminate-running-process ${UDID} ${BUNDLE_ID}"
    while [ "${polls}" -lt "$2" ]; do
        echo "simctl spawn ${UDID} launchctl list"
        polls=$((polls + 1))
    done
    if [ "${3:-}" = "--terminate" ]; then
        echo "simctl terminate ${UDID} ${BUNDLE_ID}"
    fi
}

case_builds_launches_and_watches() {
    local root
    root=$(make_fixture_root)
    stub_tools

    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 0
    [ "$(cat "${STUB_BIN}/xcodegen.log")" = "generate" ] || _fail "xcodegen was not run as \`xcodegen generate\`"
    grep -qxF -- "-project MyApp.xcodeproj -scheme MyApp -configuration Release -sdk iphonesimulator -destination platform=iOS Simulator,id=${UDID} -derivedDataPath build/smoke-derived-data build" \
        "${STUB_BIN}/xcodebuild.log" || _fail "xcodebuild was not a Release simulator build: $(cat "${STUB_BIN}/xcodebuild.log")"
    [ "$(cat "${STUB_BIN}/xcbeautify.log")" = "--quiet" ] || _fail "the build was not piped through \`xcbeautify --quiet\`"
    grep -qxF -- "CFBundleIdentifier raw ${APP_RELATIVE_PATH}/Info.plist" <<<"$(sed 's/^-extract //' "${STUB_BIN}/plutil.log")" ||
        _fail "the bundle id was not read from the flat bundle's Info.plist: $(cat "${STUB_BIN}/plutil.log")"
    grep -qxF -- "--verify --verbose=2 ${APP_RELATIVE_PATH}" "${STUB_BIN}/codesign.log" ||
        _fail "the signature was not verified: $(cat "${STUB_BIN}/codesign.log")"
    [ "$(simctl_calls_after_list)" = "$(expected_calls "${APP_RELATIVE_PATH}" 10 --terminate)" ] ||
        _fail "the simctl calls were not boot, install, launch, ten polls, terminate: $(cat "${STUB_BIN}/xcrun.log")"
    [ "$(grep -c '^1$' "${STUB_BIN}/sleep.log")" = 10 ] || _fail "the alive window was not ten one-second polls"
    assert_stdout_contains "SMOKE OK: MyApp launched and stayed alive on iPhone 17"
}

case_prebuilt_app_skips_the_build() {
    local root elsewhere app
    root=$(make_fixture_root --no-app)
    elsewhere=$(cd "$(make_temp_dir)" && pwd)
    app="${elsewhere}/Built/Other.app"
    make_app "${app}"
    stub_tools

    # A relative path with a trailing slash, from a directory outside the checkout.
    capture sh -c 'cd "$1" && "$2" "$3" "$4"' sh "${elsewhere}" "${BASH}" "${root}/scripts/smoke_launch.sh" "Built/Other.app/"
    assert_exit 0
    assert_not_called xcodegen "with a pre-built bundle"
    assert_not_called xcodebuild "with a pre-built bundle"
    [ "$(simctl_calls_after_list)" = "$(expected_calls "${app}" 10 --terminate)" ] ||
        _fail "the pre-built bundle was not installed by its absolute path: $(cat "${STUB_BIN}/xcrun.log")"
    assert_stdout_contains "SMOKE OK: Other launched and stayed alive on iPhone 17"
}

case_too_many_arguments() {
    local root
    root=$(make_fixture_root)
    stub_tools
    capture "${BASH}" "${root}/scripts/smoke_launch.sh" one two
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_USAGE
    assert_stderr_contains "Next: usage: scripts/smoke_launch.sh [path/to/An.app]"
    assert_not_called xcrun "before the arguments were checked"
}

case_option_argument() {
    local root
    root=$(make_fixture_root)
    stub_tools
    capture "${BASH}" "${root}/scripts/smoke_launch.sh" --help
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_USAGE
    assert_stderr_contains "unknown option '--help'"
    assert_not_called xcodegen "for an unknown option"
}

case_not_an_app_bundle() {
    local root
    root=$(make_fixture_root)
    stub_tools
    capture "${BASH}" "${root}/scripts/smoke_launch.sh" "${root}/does-not-exist.app"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_USAGE
    assert_stderr_contains "is not a simulator app bundle"
    assert_not_called xcrun "without a bundle"
}

case_prebuilt_app_without_bundle_id() {
    local root
    root=$(make_fixture_root)
    stub_tools PLUTIL_FAIL=1
    capture "${BASH}" "${root}/scripts/smoke_launch.sh" "${root}/${APP_RELATIVE_PATH}"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_USAGE
    assert_stderr_contains "declares no bundle identifier"
    assert_not_called codesign "on a bundle with no identifier"
}

case_xcodegen_fails() {
    local root
    root=$(make_fixture_root)
    stub_tools XCODEGEN_EXIT=3
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_BUILD_FAILED
    assert_stderr_contains "it exited 3"
    assert_not_called xcodebuild "after xcodegen failed"
}

case_build_fails() {
    local root
    root=$(make_fixture_root)
    stub_tools XCODEBUILD_EXIT=65
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_BUILD_FAILED
    assert_stderr_contains "the build exited 65"
    assert_not_called codesign "after a failed build"
    assert_no_simctl install "after a failed build"
}

case_build_leaves_no_bundle() {
    local root
    root=$(make_fixture_root --no-app)
    stub_tools
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_BUILD_FAILED
    assert_stderr_contains "produced no app bundle"
    assert_stderr_contains "${APP_RELATIVE_PATH}"
}

case_signature_invalid() {
    local root
    root=$(make_fixture_root)
    stub_tools CODESIGN_FAIL=1
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_SIGNATURE_INVALID
    assert_stderr_contains "codesign: stubbed: invalid signature"
    assert_no_simctl install "after the signature was rejected"
}

case_no_simulator() {
    local root
    root=$(make_fixture_root)
    stub_tools NO_DEVICES=1
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_NO_SIMULATOR
    assert_stderr_contains "ERR_SIM_NO_DEVICE"
    assert_not_called xcodebuild "with no simulator to build for"
}

case_boot_fails() {
    local root
    root=$(make_fixture_root)
    stub_tools XCRUN_FAIL=bootstatus
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_NO_SIMULATOR
    assert_stderr_contains "simctl bootstatus: stubbed failure"
    assert_no_simctl install "after a failed boot"
}

case_install_fails() {
    local root
    root=$(make_fixture_root)
    stub_tools XCRUN_FAIL=install
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_INSTALL_FAILED
    assert_stderr_contains "simctl install: stubbed failure"
    assert_no_simctl launch "after a failed install"
}

case_launch_fails() {
    local root
    root=$(make_fixture_root)
    stub_tools XCRUN_FAIL=launch
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_LAUNCH_FAILED
    assert_stderr_contains "simctl launch: stubbed failure"
    assert_no_simctl spawn "after a failed launch"
    assert_stdout_not_contains "SMOKE OK" "a success line"
}

case_job_vanishes_on_third_poll() {
    local root
    root=$(make_fixture_root)
    stub_tools JOB_GONE_AT=3
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_EXITED_EARLY
    # The widget job left in the list shares the app's id as a prefix; it must not count.
    assert_stderr_contains "no UIKitApplication:${BUNDLE_ID} job in launchctl list after 3s"
    [ "$(simctl_calls_after_list)" = "$(expected_calls "${APP_RELATIVE_PATH}" 3)" ] ||
        _fail "the poll did not stop at the third launchctl list: $(cat "${STUB_BIN}/xcrun.log")"
    assert_stdout_not_contains "SMOKE OK" "a success line"
}

case_job_without_pid() {
    local root
    root=$(make_fixture_root)
    stub_tools JOB_PID=-
    capture "${BASH}" "${root}/scripts/smoke_launch.sh"
    assert_exit 1
    assert_first_stderr_line ERR_SMOKE_EXITED_EARLY
    assert_stderr_contains "PID field was '-' after 1s"
}

run_case "builds Release, installs, launches, and watches ten polls" case_builds_launches_and_watches
run_case "a pre-built bundle skips the build and installs by absolute path" case_prebuilt_app_skips_the_build
run_case "two arguments fail ERR_SMOKE_USAGE" case_too_many_arguments
run_case "an option fails ERR_SMOKE_USAGE" case_option_argument
run_case "a path that is not an app bundle fails ERR_SMOKE_USAGE" case_not_an_app_bundle
run_case "a pre-built bundle with no bundle id fails ERR_SMOKE_USAGE" case_prebuilt_app_without_bundle_id
run_case "a failed xcodegen fails ERR_SMOKE_BUILD_FAILED" case_xcodegen_fails
run_case "a failed Release build fails ERR_SMOKE_BUILD_FAILED" case_build_fails
run_case "a build that leaves no bundle fails ERR_SMOKE_BUILD_FAILED" case_build_leaves_no_bundle
run_case "a rejected signature fails ERR_SMOKE_SIGNATURE_INVALID" case_signature_invalid
run_case "no available simulator fails ERR_SMOKE_NO_SIMULATOR" case_no_simulator
run_case "a device that does not boot fails ERR_SMOKE_NO_SIMULATOR" case_boot_fails
run_case "a refused install fails ERR_SMOKE_INSTALL_FAILED" case_install_fails
run_case "a refused launch fails ERR_SMOKE_LAUNCH_FAILED" case_launch_fails
run_case "a job that vanishes on the third poll fails ERR_SMOKE_EXITED_EARLY" case_job_vanishes_on_third_poll
run_case "a job whose PID field is - fails ERR_SMOKE_EXITED_EARLY" case_job_without_pid
finish
