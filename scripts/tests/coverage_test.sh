#!/usr/bin/env bash
# Tests for scripts/coverage.sh. `swift` is stubbed in every case, so no case
# needs Xcode or builds the package: the override cases assert the script stops
# before calling it, and the line- and function-floor cases have the stub hand
# back a codecov JSON fixture from this case's temp directory for the real python3
# gate to read.
# The script cds into Packages/MyAppKit but, with swift stubbed, writes nothing.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

unset COVERAGE_MIN

COVERAGE_SRC="${REPO_ROOT}/scripts/coverage.sh"

# Stubs swift: `swift test --show-codecov-path` prints ${CODECOV_FIXTURE}, and every
# call is logged to ${STUB_BIN}/swift.log.
stub_swift() {
    # shellcheck disable=SC2016 # expanded by the stub at run time, not here
    stub_command swift 'if [ "$*" = "test --show-codecov-path" ]; then echo "${CODECOV_FIXTURE}"; fi'
}

# write_fixture LINES_COVERED LINES_COUNT [FUNCTIONS_COVERED FUNCTIONS_COUNT] — a
# codecov JSON with one MyAppCore file at those lines and functions (functions
# default to 1/1) and one UI file at 0% of both that the gate must ignore.
write_fixture() {
    export CODECOV_FIXTURE="${CASE_DIR}/codecov.json"
    cat >"${CODECOV_FIXTURE}" <<JSON
{"data": [{"files": [
  {"filename": "/x/Sources/MyAppCore/Counter.swift", "summary": {
    "lines": {"covered": $1, "count": $2},
    "functions": {"covered": ${3:-1}, "count": ${4:-1}}}},
  {"filename": "/x/Sources/MyAppUI/ContentView.swift", "summary": {
    "lines": {"covered": 0, "count": 50},
    "functions": {"covered": 0, "count": 50}}}
]}]}
JSON
}

# assert_override_rejected VALUE — COVERAGE_MIN=VALUE fails with the contract's
# four lines and never reaches swift.
assert_override_rejected() {
    stub_swift
    capture env COVERAGE_MIN="$1" "${BASH}" "${COVERAGE_SRC}"
    assert_exit 1
    grep -q '^ERR_COVERAGE_OVERRIDE_REMOVED: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "first stderr line is not ERR_COVERAGE_OVERRIDE_REMOVED"
    assert_stderr_contains "Expected: the floor comes from COVERAGE_FLOOR in scripts/coverage.sh"
    assert_stderr_contains "Actual: COVERAGE_MIN is set"
    assert_stderr_contains "Next: "
    [ ! -e "${STUB_BIN}/swift.log" ] || _fail "swift was called before the override was rejected"
}

case_lower_integer_rejected() { assert_override_rejected 50; }
case_lower_decimal_rejected() { assert_override_rejected 50.0; }
case_higher_value_rejected() { assert_override_rejected 90; }
case_empty_value_rejected() { assert_override_rejected ""; }

case_at_floor_passes() {
    stub_swift
    write_fixture 80 100 75 100
    capture "${BASH}" "${COVERAGE_SRC}"
    assert_exit 0
    assert_stdout_contains "MyAppCore line coverage: 80.0% (floor 80.0%)"
    assert_stdout_contains "MyAppCore function coverage: 75.0% (75 of 100 functions; floor 75.0%)"
    grep -qx 'test --enable-code-coverage' "${STUB_BIN}/swift.log" || _fail "swift test was not run with coverage"
}

case_below_floor_fails() {
    stub_swift
    write_fixture 7996 10000
    capture "${BASH}" "${COVERAGE_SRC}"
    assert_exit 1
    assert_stderr_contains "coverage 79.96% is below the 80.0% floor"
    assert_stderr_not_contains "ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR"
}

# Lines are fully covered, so only the function floor can fail the run.
case_functions_below_floor_fails() {
    stub_swift
    write_fixture 100 100 7496 10000
    capture "${BASH}" "${COVERAGE_SRC}"
    assert_exit 1
    grep -qx 'ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR: MyAppCore function coverage 74.96% is below the 75.0% floor' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "first stderr line is not the ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR line"
    assert_stderr_contains "Expected: at least 75.0% of MyAppCore functions run under"
    assert_stderr_contains "Actual: 7496 of 10000 functions ran (74.96%)"
    assert_stderr_contains "Next: "
    assert_stderr_not_contains "is below the 80.0% floor"
}

case_both_below_floor_reports_both() {
    stub_swift
    write_fixture 7996 10000 7496 10000
    capture "${BASH}" "${COVERAGE_SRC}"
    assert_exit 1
    grep -q '^ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "first stderr line is not ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR"
    assert_stderr_contains "coverage 79.96% is below the 80.0% floor"
}

# A MyAppCore file with no functions counts as fully covered rather than dividing
# by zero, as a file with no lines already does.
case_no_functions_passes() {
    stub_swift
    write_fixture 90 100 0 0
    capture "${BASH}" "${COVERAGE_SRC}"
    assert_exit 0
    assert_stdout_contains "MyAppCore function coverage: 100.0% (0 of 0 functions; floor 75.0%)"
}

run_case "COVERAGE_MIN=50 is rejected before any test runs" case_lower_integer_rejected
run_case "COVERAGE_MIN=50.0 is rejected before any test runs" case_lower_decimal_rejected
run_case "COVERAGE_MIN=90 is rejected before any test runs" case_higher_value_rejected
run_case "an empty COVERAGE_MIN is rejected before any test runs" case_empty_value_rejected
run_case "coverage exactly at the 80% line and 75% function floors passes" case_at_floor_passes
run_case "line coverage just below the 80% floor fails" case_below_floor_fails
run_case "function coverage just below the 75% floor fails with its error code" case_functions_below_floor_fails
run_case "both floors missed are both reported" case_both_below_floor_reports_both
run_case "MyAppCore with no functions passes the function floor" case_no_functions_passes
finish
