#!/usr/bin/env bash
# Tests for scripts/reset-permissions.sh: that it resets exactly the identifier
# project.yml declares on the booted simulator, and the named failure for each way it
# can refuse.
#
# No simulator is ever touched: `xcrun` is stubbed in every case. The script finds
# scripts/bundle-id.sh next to itself, so each case copies both into a fixture root's
# scripts/ and runs that copy with --root pointing at the fixture's project.yml; the
# real bundle-id.sh runs against it.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

# make_fixture_root [IDENTIFIER] — a checkout-shaped directory holding copies of the two
# scripts and a project.yml declaring IDENTIFIER (com.example.MyApp by default); with
# the empty string, no identifier at all.
make_fixture_root() {
    local root name identifier="${1-com.example.MyApp}"
    # Normalized (no doubled slash from TMPDIR), the way the script resolves --root.
    root=$(cd "$(make_temp_dir)" && pwd)
    mkdir "${root}/scripts"
    for name in reset-permissions.sh bundle-id.sh; do
        cp "${REPO_ROOT}/scripts/${name}" "${root}/scripts/${name}"
        chmod +x "${root}/scripts/${name}"
    done
    {
        echo "name: MyApp"
        echo "targets:"
        echo "  MyApp:"
        echo "    type: application"
        echo "    platform: iOS"
        echo "    settings:"
        echo "      base:"
        [ -z "${identifier}" ] || echo "        PRODUCT_BUNDLE_IDENTIFIER: ${identifier}"
    } >"${root}/project.yml"
    echo "${root}"
}

# stub_simctl booted|none [fail] — xcrun answers `simctl list devices booted` with one
# booted iPhone (or none), and `simctl privacy` with success (or, given `fail`, an
# error and exit 1). Any other call is unexpected.
stub_simctl() {
    export XCRUN_BOOTED="$1" XCRUN_FAIL="${2:-}"
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command xcrun 'case "$2" in
    list)
        echo "== Devices =="
        echo "-- iOS 26.5 --"
        if [ "${XCRUN_BOOTED}" = booted ]; then
            echo "    iPhone 17 (NEW-IPHONE-17) (Booted) "
        fi
        ;;
    privacy)
        if [ "${XCRUN_FAIL}" = fail ]; then
            echo "simctl privacy: stubbed failure" >&2
            exit 1
        fi
        ;;
    *)
        echo "unexpected xcrun call: $*" >&2
        exit 64
        ;;
esac'
}

# The simctl privacy calls, one per line; empty when none was made.
privacy_calls() {
    [ -f "${STUB_BIN}/xcrun.log" ] || return 0
    grep '^simctl privacy ' "${STUB_BIN}/xcrun.log" || true
}

assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not $1"
}

case_resets_the_declared_identifier() {
    local root
    root=$(make_fixture_root)
    stub_simctl booted
    capture "${BASH}" "${root}/scripts/reset-permissions.sh" --root "${root}"
    assert_exit 0
    [ "$(privacy_calls)" = "simctl privacy booted reset all com.example.MyApp" ] ||
        _fail "simctl privacy was not called once with reset all com.example.MyApp: $(privacy_calls)"
    assert_stdout_contains "reset-permissions: com.example.MyApp will be asked"
}

# The identifier comes from the manifest, so a bootstrapped app resets its own.
case_follows_a_renamed_manifest() {
    local root
    root=$(make_fixture_root com.acme.Widget)
    stub_simctl booted
    capture "${BASH}" "${root}/scripts/reset-permissions.sh" --root "${root}"
    assert_exit 0
    [ "$(privacy_calls)" = "simctl privacy booted reset all com.acme.Widget" ] ||
        _fail "the renamed identifier was not reset: $(privacy_calls)"
}

case_no_booted_device() {
    local root
    root=$(make_fixture_root)
    stub_simctl none
    capture "${BASH}" "${root}/scripts/reset-permissions.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_RESETPERM_NO_BOOTED_DEVICE
    assert_stderr_contains "Next: run \`just run\`"
    [ -z "$(privacy_calls)" ] || _fail "simctl privacy ran with no booted device"
}

case_manifest_without_an_identifier() {
    local root
    root=$(make_fixture_root "")
    stub_simctl booted
    capture "${BASH}" "${root}/scripts/reset-permissions.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_RESETPERM_BUNDLE_ID
    assert_stderr_contains "Actual: ERR_BUNDLEID_NOT_FOUND"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran without an identifier to reset"
}

case_simctl_failure() {
    local root
    root=$(make_fixture_root)
    stub_simctl booted fail
    capture "${BASH}" "${root}/scripts/reset-permissions.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_RESETPERM_SIMCTL_FAILED
    assert_stderr_contains "simctl privacy: stubbed failure"
    assert_stdout_not_contains "will be asked" "a success line"
}

case_unknown_argument() {
    local root
    root=$(make_fixture_root)
    stub_simctl booted
    capture "${BASH}" "${root}/scripts/reset-permissions.sh" --root "${root}" com.somebody.Else
    assert_exit 1
    assert_first_stderr_line ERR_RESETPERM_USAGE
    assert_stderr_contains "unknown argument 'com.somebody.Else'"
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran before the arguments were checked"
}

case_root_missing() {
    local root
    root=$(make_fixture_root)
    stub_simctl booted
    capture "${BASH}" "${root}/scripts/reset-permissions.sh" --root "${root}/does-not-exist"
    assert_exit 1
    assert_first_stderr_line ERR_RESETPERM_USAGE
    capture "${BASH}" "${root}/scripts/reset-permissions.sh" --root
    assert_exit 1
    assert_first_stderr_line ERR_RESETPERM_USAGE
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "xcrun ran with a bad --root"
}

run_case "resets the identifier project.yml declares on the booted simulator" case_resets_the_declared_identifier
run_case "follows a renamed manifest" case_follows_a_renamed_manifest
run_case "no booted simulator fails ERR_RESETPERM_NO_BOOTED_DEVICE" case_no_booted_device
run_case "a manifest with no identifier fails ERR_RESETPERM_BUNDLE_ID" case_manifest_without_an_identifier
run_case "a failing simctl fails ERR_RESETPERM_SIMCTL_FAILED" case_simctl_failure
run_case "an unknown argument fails ERR_RESETPERM_USAGE, and nothing is reset" case_unknown_argument
run_case "a missing or nonexistent --root fails ERR_RESETPERM_USAGE" case_root_missing
finish
