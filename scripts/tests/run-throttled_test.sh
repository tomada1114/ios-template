#!/usr/bin/env bash
# Tests for scripts/run-throttled.sh. sysctl, getconf, and taskpolicy are stubbed in
# every case (CI runs this on Ubuntu, which has no taskpolicy), and the lock lives
# under the case's own RUN_THROTTLED_LOCK_DIR, never the real ~/.cache.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SCRIPT="${REPO_ROOT}/scripts/run-throttled.sh"

# setup [CPUS] — stubs sysctl to report CPUS (8 by default), getconf to fail, and
# taskpolicy to drop `-c CLAMP` and run the rest; clears the environment knobs.
setup() {
    stub_command sysctl "echo ${1:-8}"
    stub_command getconf 'exit 1'
    stub_command taskpolicy 'shift 2; "$@"'
    unset CI CHECK_JOBS CHECK_QOS RUN_THROTTLED_LOCK_HELD RUN_THROTTLED_WAIT_TIMEOUT
    export RUN_THROTTLED_LOCK_DIR="${CASE_DIR}/locks"
}

first_line_is() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "first stderr line is not $1"
}

case_jobs_halves() {
    setup 8
    capture "${BASH}" "${SCRIPT}" --print-jobs
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = 4 ] || _fail "expected 4"
}

case_jobs_minimum_one() {
    setup 1
    capture "${BASH}" "${SCRIPT}" --print-jobs
    [ "$(cat "${CASE_DIR}/stdout")" = 1 ] || _fail "expected 1"
}

case_jobs_ci_all() {
    setup 8
    CI=true capture "${BASH}" "${SCRIPT}" --print-jobs
    [ "$(cat "${CASE_DIR}/stdout")" = 8 ] || _fail "expected 8"
}

case_jobs_override() {
    setup 8
    CHECK_JOBS=3 capture "${BASH}" "${SCRIPT}" --print-jobs
    [ "$(cat "${CASE_DIR}/stdout")" = 3 ] || _fail "expected 3"
}

case_jobs_fallbacks() {
    setup 8
    stub_command sysctl 'exit 1'
    stub_command getconf 'echo 6'
    capture "${BASH}" "${SCRIPT}" --print-jobs
    [ "$(cat "${CASE_DIR}/stdout")" = 3 ] || _fail "expected 3 from getconf"
    stub_command getconf 'exit 1'
    capture "${BASH}" "${SCRIPT}" --print-jobs
    [ "$(cat "${CASE_DIR}/stdout")" = 1 ] || _fail "expected 1 from the fallback of 2"
}

case_jobs_bad() {
    setup
    CHECK_JOBS=0 capture "${BASH}" "${SCRIPT}" --print-jobs
    assert_exit 1
    first_line_is ERR_THROTTLE_BAD_JOBS
    CHECK_JOBS=abc capture "${BASH}" "${SCRIPT}" -- true
    assert_exit 1
    first_line_is ERR_THROTTLE_BAD_JOBS
}

case_exports_jobs() {
    setup 8
    # shellcheck disable=SC2016 # expanded by the inner sh, not here
    capture "${BASH}" "${SCRIPT}" -- sh -c 'echo "jobs=${THROTTLE_JOBS}"'
    assert_exit 0
    assert_stdout_contains "jobs=4"
}

case_qos_default_utility() {
    setup
    capture "${BASH}" "${SCRIPT}" -- true
    assert_exit 0
    grep -qx -- "-c utility true" "${STUB_BIN}/taskpolicy.log" || _fail "taskpolicy not called with utility"
}

case_qos_background() {
    setup
    CHECK_QOS=background capture "${BASH}" "${SCRIPT}" -- true
    grep -qx -- "-c background true" "${STUB_BIN}/taskpolicy.log" || _fail "taskpolicy not called with background"
}

case_qos_off_and_ci_skip_taskpolicy() {
    setup
    CHECK_QOS=off capture "${BASH}" "${SCRIPT}" -- true
    assert_exit 0
    CI=true capture "${BASH}" "${SCRIPT}" -- true
    assert_exit 0
    [ ! -e "${STUB_BIN}/taskpolicy.log" ] || _fail "taskpolicy was called"
}

case_qos_bad() {
    setup
    CHECK_QOS=fast capture "${BASH}" "${SCRIPT}" -- true
    assert_exit 1
    first_line_is ERR_THROTTLE_BAD_QOS
}

case_usage() {
    setup
    capture "${BASH}" "${SCRIPT}" true
    assert_exit 1
    first_line_is ERR_THROTTLE_USAGE
    capture "${BASH}" "${SCRIPT}" --lock --
    assert_exit 1
    first_line_is ERR_THROTTLE_USAGE
}

case_exit_status_propagates() {
    setup
    capture "${BASH}" "${SCRIPT}" --lock -- sh -c 'exit 7'
    assert_exit 7
    [ ! -e "${RUN_THROTTLED_LOCK_DIR}/xcode.lock" ] || _fail "the lock outlived a failing command"
}

case_lock_acquire_release() {
    setup
    # shellcheck disable=SC2016 # expanded by the inner sh, not here
    capture "${BASH}" "${SCRIPT}" --lock -- sh -c 'cat "${RUN_THROTTLED_LOCK_DIR}/xcode.lock/holder"; echo "held=${RUN_THROTTLED_LOCK_HELD}"'
    assert_exit 0
    assert_stdout_contains "sh -c"
    assert_stdout_contains "held=1"
    [ ! -e "${RUN_THROTTLED_LOCK_DIR}/xcode.lock" ] || _fail "the lock was not released"
}

case_lock_waits_then_times_out() {
    local holder
    setup
    sleep 30 &
    holder=$!
    mkdir -p "${RUN_THROTTLED_LOCK_DIR}/xcode.lock"
    printf '%s\n%s\n' "${holder}" "xcodebuild build" >"${RUN_THROTTLED_LOCK_DIR}/xcode.lock/holder"
    RUN_THROTTLED_WAIT_TIMEOUT=2 capture "${BASH}" "${SCRIPT}" --lock -- echo ran
    kill "${holder}" 2>/dev/null || true
    wait "${holder}" 2>/dev/null || true
    assert_exit 1
    assert_stderr_contains "waiting for the xcode lock held by pid ${holder}: xcodebuild build"
    assert_stderr_contains "ERR_THROTTLE_LOCK_TIMEOUT: "
    assert_stdout_not_contains "ran" "the command ran without the lock"
    [ -e "${RUN_THROTTLED_LOCK_DIR}/xcode.lock/holder" ] || _fail "the live holder's lock was removed"
}

case_lock_reclaims_stale() {
    local dead
    setup
    sh -c 'exit 0' &
    dead=$!
    wait "${dead}" || true
    mkdir -p "${RUN_THROTTLED_LOCK_DIR}/xcode.lock"
    printf '%s\n%s\n' "${dead}" "old" >"${RUN_THROTTLED_LOCK_DIR}/xcode.lock/holder"
    RUN_THROTTLED_WAIT_TIMEOUT=5 capture "${BASH}" "${SCRIPT}" --lock -- echo ran
    assert_exit 0
    assert_stdout_contains "ran"
    assert_stderr_contains "removing the stale xcode lock of pid ${dead}"
}

case_lock_reentrant() {
    setup
    capture "${BASH}" "${SCRIPT}" --lock -- "${BASH}" "${SCRIPT}" --lock -- echo inner
    assert_exit 0
    assert_stdout_contains "inner"
    assert_stderr_not_contains "waiting" "a nested call waited on its own lock"
}

case_lock_ci_noop() {
    setup
    # shellcheck disable=SC2016 # expanded by the inner sh, not here
    CI=true capture "${BASH}" "${SCRIPT}" --lock -- sh -c 'echo "held=${RUN_THROTTLED_LOCK_HELD:-}"'
    assert_exit 0
    assert_stdout_contains "held="
    assert_stdout_not_contains "held=1" "CI took the lock"
    [ ! -e "${RUN_THROTTLED_LOCK_DIR}" ] || _fail "CI created the lock directory"
}

case_lock_dir_uncreatable() {
    setup
    : >"${CASE_DIR}/file"
    RUN_THROTTLED_LOCK_DIR="${CASE_DIR}/file/locks" capture "${BASH}" "${SCRIPT}" --lock -- echo ran
    assert_exit 1
    first_line_is ERR_THROTTLE_LOCK_DIR
    assert_stdout_not_contains "ran" "the command ran unlocked"
}

run_case "jobs: half the CPUs by default" case_jobs_halves
run_case "jobs: at least 1" case_jobs_minimum_one
run_case "jobs: every CPU under CI" case_jobs_ci_all
run_case "jobs: CHECK_JOBS overrides" case_jobs_override
run_case "jobs: getconf, then 2, when sysctl fails" case_jobs_fallbacks
run_case "jobs: a bad CHECK_JOBS fails" case_jobs_bad
run_case "jobs: exported as THROTTLE_JOBS" case_exports_jobs
run_case "qos: utility by default" case_qos_default_utility
run_case "qos: background" case_qos_background
run_case "qos: off and CI skip taskpolicy" case_qos_off_and_ci_skip_taskpolicy
run_case "qos: a bad CHECK_QOS fails" case_qos_bad
run_case "usage: no -- or no command fails" case_usage
run_case "status: the command's exit status propagates and the lock is released" case_exit_status_propagates
run_case "lock: acquired, recorded, and released" case_lock_acquire_release
run_case "lock: waits on a live holder, then times out" case_lock_waits_then_times_out
run_case "lock: a dead holder's lock is reclaimed" case_lock_reclaims_stale
run_case "lock: a nested --lock does not wait on itself" case_lock_reentrant
run_case "lock: a no-op under CI" case_lock_ci_noop
run_case "lock: an uncreatable lock directory fails" case_lock_dir_uncreatable
finish
