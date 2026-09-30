# shellcheck shell=bash
# Shared helpers for scripts/tests/*_test.sh. Sourced, never executed:
#
#   . "$(dirname "$0")/lib.sh"
#   trap cleanup_temp EXIT
#   case_example() { capture "${REPO_ROOT}/scripts/x.sh" --bad; assert_exit 1; }
#   run_case "rejects a bad flag" case_example
#   finish
#
# Every case runs in its own subshell, so PATH changes, cd, and stubs stay inside it.
# Everything a test creates lives under one temp root that cleanup_temp removes, and
# nothing here writes to the real checkout. Bash 3.2-compatible (macOS /bin/bash).

# Exported so a script under test, or a stub, can read them too.
export REPO_ROOT TEST_TMP_ROOT
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/script-tests.XXXXXX")
TESTS_RUN=0
TESTS_FAILED=0

# A test must never write to the repository that happens to be running it: git
# exports GIT_DIR, GIT_INDEX_FILE and more to hooks, an inherited GIT_DIR outranks
# both cwd and -C, and GIT_CONFIG_*, GIT_CEILING_DIRECTORIES or
# GIT_ALTERNATE_OBJECT_DIRECTORIES would still reshape a fixture repository. So
# every exported GIT_* variable is unset, not a fixed list. `compgen -e` lists
# exported names only (never values), so a multi-line value cannot confuse it.
unset_git_env() {
    local name
    for name in $(compgen -e); do
        case "${name}" in
            GIT_*) unset "${name}" ;;
        esac
    done
}
unset_git_env

# Removes every directory the helpers created. Register it: trap cleanup_temp EXIT
cleanup_temp() {
    rm -rf "${TEST_TMP_ROOT}"
}

# Prints the path of a fresh directory under the temp root.
make_temp_dir() {
    mktemp -d "${TEST_TMP_ROOT}/dir.XXXXXX"
}

# Prints the path of a fresh, empty git repository with a local identity, so a
# script under test can commit without touching any real repository.
make_temp_repo() {
    local repo
    repo=$(make_temp_dir)
    git init -q "${repo}"
    git -C "${repo}" config user.name "Script Test"
    git -C "${repo}" config user.email "script-test@example.com"
    git -C "${repo}" config commit.gpgsign false
    echo "${repo}"
}

# stub_command NAME BODY — writes an executable NAME into this case's stub bin/,
# prepended to PATH. The stub appends its arguments (one line per call) to
# "${STUB_BIN}/NAME.log", then runs BODY. STUB_BIN is set by run_case.
stub_command() {
    local name="$1" body="$2"
    {
        echo "#!${BASH}"
        printf 'printf %s "$*" >> "%s"\n' "'%s\n'" "${STUB_BIN}/${name}.log"
        echo "${body}"
    } >"${STUB_BIN}/${name}"
    chmod +x "${STUB_BIN}/${name}"
    case ":${PATH}:" in
        *":${STUB_BIN}:"*) ;;
        *) PATH="${STUB_BIN}:${PATH}" ;;
    esac
}

# capture CMD... — runs CMD, keeping its exit code, stdout, and stderr for the
# assert_* helpers. Never fails itself, whatever CMD returns.
capture() {
    CAPTURED_EXIT=0
    "$@" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr" || CAPTURED_EXIT=$?
}

# Prints a failure with the captured output, then ends the case (not the file).
_fail() {
    {
        echo "  FAIL: $1"
        echo "  --- stdout of the last capture ---"
        cat "${CASE_DIR}/stdout" 2>/dev/null || true
        echo "  --- stderr of the last capture ---"
        cat "${CASE_DIR}/stderr" 2>/dev/null || true
    } >&2
    exit 1
}

assert_exit() {
    [ "${CAPTURED_EXIT}" = "$1" ] || _fail "expected exit $1, got ${CAPTURED_EXIT}"
}

assert_stdout_contains() {
    grep -qF -- "$1" "${CASE_DIR}/stdout" || _fail "stdout does not contain: $1"
}

assert_stderr_contains() {
    grep -qF -- "$1" "${CASE_DIR}/stderr" || _fail "stderr does not contain: $1"
}

# The negative forms name only what was checked for, never the text itself: a test
# that asserts a secret-shaped value was not printed must not print it either.
assert_stdout_not_contains() {
    ! grep -qF -- "$1" "${CASE_DIR}/stdout" || _fail "stdout contains ${2:-the forbidden text}"
}

assert_stderr_not_contains() {
    ! grep -qF -- "$1" "${CASE_DIR}/stderr" || _fail "stderr contains ${2:-the forbidden text}"
}

# watch_file PATH — snapshots PATH before a capture; assert_file_unchanged PATH
# then fails if the captured command changed, created, or removed it.
watch_file() {
    local key
    key=$(printf '%s' "$1" | cksum | tr -d ' ')
    if [ -e "$1" ]; then
        cp -p "$1" "${CASE_DIR}/watch.${key}"
    else
        : >"${CASE_DIR}/watch.${key}.absent"
    fi
}

assert_file_unchanged() {
    local key
    key=$(printf '%s' "$1" | cksum | tr -d ' ')
    if [ -e "${CASE_DIR}/watch.${key}.absent" ]; then
        [ ! -e "$1" ] || _fail "$1 was created"
    elif [ -e "${CASE_DIR}/watch.${key}" ]; then
        [ -e "$1" ] || _fail "$1 was removed"
        cmp -s "${CASE_DIR}/watch.${key}" "$1" || _fail "$1 was changed"
    else
        _fail "$1 was never passed to watch_file"
    fi
}

# run_case NAME FUNCTION — runs FUNCTION in a subshell with errexit on, and prints
# `ok` or `not ok` with NAME. Each case gets its own CASE_DIR and STUB_BIN.
run_case() {
    local name="$1" fn="$2" status=0 had_errexit=0
    TESTS_RUN=$((TESTS_RUN + 1))
    case $- in *e*) had_errexit=1 ;; esac
    CASE_DIR=$(make_temp_dir)
    STUB_BIN="${CASE_DIR}/bin"
    mkdir "${STUB_BIN}"
    set +e
    (
        set -e
        "${fn}"
    )
    status=$?
    if [ "${had_errexit}" = 1 ]; then set -e; fi
    if [ "${status}" = 0 ]; then
        echo "ok ${TESTS_RUN} - ${name}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "not ok ${TESTS_RUN} - ${name}"
    fi
}

# Ends the test file: exit 1 if any case failed.
finish() {
    echo "# ${TESTS_RUN} case(s), ${TESTS_FAILED} failed"
    [ "${TESTS_FAILED}" = 0 ] || exit 1
}
