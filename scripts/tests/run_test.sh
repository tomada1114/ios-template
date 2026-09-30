#!/usr/bin/env bash
# Tests for scripts/tests/run.sh, the runner this very file is run by. Every case
# copies run.sh into a throwaway tree of its own (run.sh resolves its glob relative
# to its own location, so a copy at TREE/scripts/tests/run.sh globs TREE's fixture
# files and never the real checkout's) and writes fake *_test.sh files into it.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

RUN_SRC="${REPO_ROOT}/scripts/tests/run.sh"

# Prints the path of a throwaway tree holding a copy of run.sh and no test file yet.
make_runner_tree() {
    local tree
    tree=$(make_temp_dir)
    mkdir -p "${tree}/scripts/tests"
    cp "${RUN_SRC}" "${tree}/scripts/tests/run.sh"
    echo "${tree}"
}

# write_test_file TREE NAME BODY — writes TREE/scripts/tests/NAME_test.sh.
write_test_file() {
    printf '%s\n' "$3" >"$1/scripts/tests/$2_test.sh"
}

case_all_passing_files_run() {
    local tree
    tree=$(make_runner_tree)
    write_test_file "${tree}" aaa 'echo "from aaa"'
    write_test_file "${tree}" bbb 'echo "from bbb"'

    capture "${BASH}" "${tree}/scripts/tests/run.sh"
    assert_exit 0
    assert_stdout_contains "==> scripts/tests/aaa_test.sh"
    assert_stdout_contains "from aaa"
    assert_stdout_contains "==> scripts/tests/bbb_test.sh"
    assert_stdout_contains "from bbb"
    assert_stdout_contains "script tests: 2 file(s) passed"
}

case_no_test_file_fails_tests_none() {
    local tree
    tree=$(make_runner_tree)

    capture "${BASH}" "${tree}/scripts/tests/run.sh"
    assert_exit 1
    grep -q '^ERR_TESTS_NONE: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not ERR_TESTS_NONE"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
}

case_every_file_runs_after_a_failure() {
    local tree
    tree=$(make_runner_tree)
    write_test_file "${tree}" aaa 'echo "from aaa"; exit 1'
    write_test_file "${tree}" bbb 'echo "from bbb"'
    write_test_file "${tree}" ccc 'echo "from ccc"; exit 1'

    capture "${BASH}" "${tree}/scripts/tests/run.sh"
    assert_exit 1
    # The file after the first failure still ran, and so did the one after it.
    assert_stdout_contains "from bbb"
    assert_stdout_contains "from ccc"
    grep -q '^ERR_TESTS_FAILED: 2 of 3 ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line does not count 2 of 3 failures"
    assert_stderr_contains "scripts/tests/aaa_test.sh"
    assert_stderr_contains "scripts/tests/ccc_test.sh"
    assert_stderr_not_contains "scripts/tests/bbb_test.sh" "the passing file"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
}

case_output_is_printed_whole_per_file() {
    local tree
    tree=$(make_runner_tree)
    # aaa is slow between its two lines, and bbb prints while aaa is still running,
    # so unbuffered output would interleave them. Each file's log is printed whole.
    write_test_file "${tree}" aaa 'echo "AAA-1"; sleep 1; echo "AAA-2"'
    write_test_file "${tree}" bbb 'echo "BBB-1"'

    capture "${BASH}" "${tree}/scripts/tests/run.sh"
    assert_exit 0
    [ "$(grep -A1 -- 'AAA-1' "${CASE_DIR}/stdout" | tail -n 1)" = "AAA-2" ] ||
        _fail "another file's output landed between AAA-1 and AAA-2"
}

case_files_run_concurrently() {
    local tree
    tree=$(make_runner_tree)
    # Each file announces itself and then waits for all three announcements. Run
    # sequentially the first one would wait alone until its timeout and exit 1, so
    # a passing run is itself the proof that the three ran at the same time.
    local name target
    for name in aaa bbb ccc; do
        target="${tree}/scripts/tests/${name}_test.sh"
        # TREE is the fixture root, shell-quoted with %q so a TMPDIR holding a space
        # cannot break the fixture; the rest of the body is taken verbatim.
        printf 'TREE=%q\n' "${tree}" >"${target}"
        cat >>"${target}" <<'BODY'
: >"${TREE}/started.$$"
i=0
while [ "${i}" -lt 200 ]; do
    started=$(ls "${TREE}"/started.* 2>/dev/null | wc -l)
    [ "${started}" -lt 3 ] || exit 0
    sleep 0.05
    i=$((i + 1))
done
echo "timed out waiting for the other files to start" >&2
exit 1
BODY
    done

    capture "${BASH}" "${tree}/scripts/tests/run.sh"
    assert_exit 0
    assert_stdout_contains "script tests: 3 file(s) passed"
}

case_a_file_that_does_not_parse_fails_only_itself() {
    local tree
    tree=$(make_runner_tree)
    # An unterminated `case`: rejected by `bash -n` under every bash. The real defect
    # this guards against was narrower — bash 3.2 aborts a file whose `$(…)` holds a
    # heredoc and still exits 0, so `wait` reported it as passing — but `bash -n`
    # rejects that file too, which is what makes it the right guard.
    write_test_file "${tree}" aaa 'case x in'
    write_test_file "${tree}" bbb 'echo "from bbb"'

    capture "${BASH}" "${tree}/scripts/tests/run.sh"
    assert_exit 1
    grep -q '^ERR_TESTS_FAILED: 1 of 2 ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the unparsable file was not counted as the one failure"
    assert_stderr_contains "scripts/tests/aaa_test.sh"
    assert_stderr_not_contains "scripts/tests/bbb_test.sh" "the file that parses"
    # The reason is under that file's own header, and the other file still ran.
    assert_stdout_contains "==> scripts/tests/aaa_test.sh"
    assert_stdout_contains "syntax error"
    assert_stdout_contains "from bbb"
}

case_term_kills_the_files_it_started() {
    local tree runner_pid status=0 fixture_pid i=0
    tree=$(make_runner_tree)
    # TERM, not INT: this case has to start the runner in the background, and a
    # non-interactive shell starts a background job with SIGINT ignored — the very
    # asymmetry the runner's handler exists for. Both signals share one handler.
    #
    # The fixture records its own pid, then sleeps far longer than this case runs, so
    # it can only be gone because the runner killed it — never because it finished.
    printf 'TREE=%q\n' "${tree}" >"${tree}/scripts/tests/aaa_test.sh"
    cat >>"${tree}/scripts/tests/aaa_test.sh" <<'BODY'
echo "aaa started"
echo "$$" >"${TREE}/fixture.pid"
sleep 60
: >"${TREE}/completed"
BODY

    "${BASH}" "${tree}/scripts/tests/run.sh" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr" &
    runner_pid=$!
    while [ ! -s "${tree}/fixture.pid" ]; do
        [ "${i}" -lt 200 ] || _fail "the fixture never started"
        sleep 0.05
        i=$((i + 1))
    done
    fixture_pid=$(cat "${tree}/fixture.pid")

    kill -TERM "${runner_pid}"
    wait "${runner_pid}" || status=$?
    CAPTURED_EXIT="${status}"
    assert_exit 1
    grep -q '^ERR_TESTS_INTERRUPTED: SIGTERM ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not ERR_TESTS_INTERRUPTED for SIGTERM"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
    # The log of the file that never finished is still shown, marked and with its
    # header, instead of vanishing with the log directory.
    assert_stdout_contains "==> scripts/tests/aaa_test.sh (interrupted)"
    assert_stdout_contains "aaa started"

    i=0
    while kill -0 "${fixture_pid}" 2>/dev/null; do
        [ "${i}" -lt 60 ] || _fail "the test file outlived the runner"
        sleep 0.05
        i=$((i + 1))
    done
    [ ! -e "${tree}/completed" ] || _fail "the killed test file still ran to completion"
}

run_case "every passing file runs and is announced" case_all_passing_files_run
run_case "no test file fails ERR_TESTS_NONE" case_no_test_file_fails_tests_none
run_case "every file runs after a failure and ERR_TESTS_FAILED names each" case_every_file_runs_after_a_failure
run_case "each file's output is printed whole, never interleaved" case_output_is_printed_whole_per_file
run_case "the files run concurrently, not one after another" case_files_run_concurrently
run_case "a file that does not parse fails, and only it" case_a_file_that_does_not_parse_fails_only_itself
run_case "TERM kills the files it started and shows their logs" case_term_kills_the_files_it_started
finish
