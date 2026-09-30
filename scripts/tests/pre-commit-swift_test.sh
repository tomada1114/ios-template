#!/usr/bin/env bash
# Tests for the "Swift lint" section of .githooks/pre-commit. Each case builds a
# throwaway git repository with its own copy of the hook, scripts/lint.sh,
# scripts/sync-agents.sh, and the "Staged guard" section's scripts/check-staged.sh and
# scripts/guard/ (every commit reaches that section), with core.hooksPath pointing at
# .githooks, so the real checkout is never touched.
#
# `mise` is stubbed, so `mise exec -- scripts/lint.sh --staged-tree DIR` never reaches
# a real linter: the stub records its arguments, copies DIR before the hook's cleanup
# removes it, and exits with MISE_EXIT. What is asserted is the hook's side of the
# contract — whether it calls lint.sh, with which tree, and what a failure does to
# the commit; lint.sh itself is scripts/tests/lint_test.sh's.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

# Prints a repo with .githooks/pre-commit (wired via core.hooksPath), copies of
# scripts/lint.sh, scripts/sync-agents.sh, scripts/check-staged.sh, and
# scripts/guard/, and a README, all committed as the starting point for each case.
make_repo_with_hook() {
    local repo
    repo=$(make_temp_repo)
    mkdir -p "${repo}/.githooks" "${repo}/scripts"
    cp "${REPO_ROOT}/.githooks/pre-commit" "${repo}/.githooks/pre-commit"
    cp "${REPO_ROOT}/scripts/lint.sh" "${repo}/scripts/lint.sh"
    cp "${REPO_ROOT}/scripts/sync-agents.sh" "${repo}/scripts/sync-agents.sh"
    cp "${REPO_ROOT}/scripts/check-staged.sh" "${repo}/scripts/check-staged.sh"
    cp -R "${REPO_ROOT}/scripts/guard" "${repo}/scripts/guard"
    chmod +x "${repo}/.githooks/pre-commit" "${repo}/scripts/lint.sh" "${repo}/scripts/sync-agents.sh" \
        "${repo}/scripts/check-staged.sh"
    git -C "${repo}" config core.hooksPath .githooks
    echo "hello" >"${repo}/README.md"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "initial"
    echo "${repo}"
}

# stub_mise [EXIT_CODE] — the stub copies the tree it was handed ($5, after
# `exec -- scripts/lint.sh --staged-tree`) to ${CASE_DIR}/linted.
stub_mise() {
    export MISE_TREE_COPY="${CASE_DIR}/linted" MISE_EXIT="${1:-0}"
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command mise 'mkdir -p "${MISE_TREE_COPY}" && cp -R "$5/." "${MISE_TREE_COPY}/" && exit "${MISE_EXIT}"'
}

# The staged blob is linted, not the worktree: the worktree is edited after `git add`,
# and only the staged Swift file (not the staged README) is exported.
case_lints_the_staged_blob() {
    local repo files
    repo=$(make_repo_with_hook)
    stub_mise
    mkdir -p "${repo}/Sources"
    echo "let staged = 1" >"${repo}/Sources/Example.swift"
    echo "more" >>"${repo}/README.md"
    git -C "${repo}" add Sources/Example.swift README.md
    echo "let worktree = 2" >"${repo}/Sources/Example.swift"

    capture git -C "${repo}" commit -q -m "add a Swift file"
    assert_exit 0
    # git hands a hook's stdout to its own stderr.
    assert_stderr_contains "pre-commit: Swift lint — checking the staged content of 1 Swift file(s)"
    [ "$(wc -l <"${STUB_BIN}/mise.log" | tr -d ' ')" = 1 ] || _fail "mise was not called exactly once"
    grep -qE '^exec -- scripts/lint\.sh --staged-tree [^ ]+$' "${STUB_BIN}/mise.log" ||
        _fail "mise was not called as exec -- scripts/lint.sh --staged-tree DIR: $(cat "${STUB_BIN}/mise.log")"
    files=$(cd "${CASE_DIR}/linted" && find . -type f | sort)
    [ "${files}" = "./Sources/Example.swift" ] || _fail "the staged tree held more than the Swift file: ${files}"
    [ "$(cat "${CASE_DIR}/linted/Sources/Example.swift")" = "let staged = 1" ] ||
        _fail "the staged tree held the worktree edit, not the staged blob"
}

case_no_swift_file_skips_lint() {
    local repo
    repo=$(make_repo_with_hook)
    stub_mise
    echo "more" >>"${repo}/README.md"
    git -C "${repo}" add README.md

    capture git -C "${repo}" commit -q -m "no Swift file"
    assert_exit 0
    assert_stderr_not_contains "Swift lint" "the Swift lint section's banner"
    [ ! -e "${STUB_BIN}/mise.log" ] || _fail "lint.sh was called for a commit with no Swift file"
}

case_failing_lint_fails_the_commit() {
    local repo before
    repo=$(make_repo_with_hook)
    stub_mise 1
    before=$(git -C "${repo}" rev-parse HEAD)
    echo "let value = 1" >"${repo}/Example.swift"
    git -C "${repo}" add Example.swift

    capture git -C "${repo}" commit -q -m "lint fails"
    [ "${CAPTURED_EXIT}" != 0 ] || _fail "the commit succeeded although lint.sh failed"
    [ -e "${STUB_BIN}/mise.log" ] || _fail "lint.sh was never called"
    [ "$(git -C "${repo}" rev-parse HEAD)" = "${before}" ] || _fail "a commit was made although lint.sh failed"
}

run_case "staging a Swift file lints its staged blob, not the worktree" case_lints_the_staged_blob
run_case "staging no Swift file never calls lint.sh" case_no_swift_file_skips_lint
run_case "a failing lint.sh fails the commit" case_failing_lint_fails_the_commit
finish
