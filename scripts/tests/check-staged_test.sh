#!/usr/bin/env bash
# Tests for scripts/check-staged.sh and the pre-commit hook's "Staged guard" section.
# Every case works in a throwaway repository, never the real checkout. Script-level
# cases run the real scripts/check-staged.sh from inside the temp repo; hook-level
# cases copy the hook, scripts/check-staged.sh, and scripts/guard/ into the temp repo
# (core.hooksPath .githooks) and run `git commit`. No case stages a Swift file, so
# the hook's Swift-lint section never runs and no case needs mise.
#
# Fixture safety: credential-shaped values are assembled at runtime from pieces that
# do not match on their own, so this file passes the guard it tests and GitHub push
# protection. Never write a whole value as one literal here.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

CHECK="${REPO_ROOT}/scripts/check-staged.sh"
TOKEN="gh""p_0123456789abcdefghijABCDEFGHIJ0123456789"

# Prints a temp repo with one committed README.md.
make_repo() {
    local repo
    repo=$(make_temp_repo)
    echo "hello" >"${repo}/README.md"
    git -C "${repo}" add README.md
    git -C "${repo}" commit -q -m "initial"
    echo "${repo}"
}

# Prints a temp repo like make_repo, plus the hook and the guard scripts it runs,
# wired via core.hooksPath.
make_repo_with_hook() {
    local repo
    repo=$(make_repo)
    mkdir -p "${repo}/.githooks" "${repo}/scripts"
    cp "${REPO_ROOT}/.githooks/pre-commit" "${repo}/.githooks/pre-commit"
    cp "${CHECK}" "${repo}/scripts/check-staged.sh"
    cp -R "${REPO_ROOT}/scripts/guard" "${repo}/scripts/guard"
    chmod +x "${repo}/.githooks/pre-commit" "${repo}/scripts/check-staged.sh"
    git -C "${repo}" add .githooks scripts
    git -C "${repo}" commit -q -m "add the hook"
    git -C "${repo}" config core.hooksPath .githooks
    echo "${repo}"
}

case_force_added_env_blocked() {
    local repo
    repo=$(make_repo)
    echo "*.env*" >"${repo}/.gitignore"
    echo "API_URL=https://example.com" >"${repo}/.env"
    git -C "${repo}" add -f .env
    cd "${repo}"
    capture "${CHECK}"
    assert_exit 1
    assert_stderr_contains "ERR_STAGED_BLOCKED_PATH: .env"
    assert_stderr_contains "Next: unstage each file with \`git restore --staged <path>\`"
    assert_stderr_not_contains "https://example.com" "the file content"
}

case_credential_content_blocked_without_echo() {
    local repo
    repo=$(make_repo)
    mkdir -p "${repo}/Sources"
    printf 'let token = "%s"\n' "${TOKEN}" >"${repo}/Sources/Config.txt"
    git -C "${repo}" add Sources/Config.txt
    cd "${repo}"
    capture "${CHECK}"
    assert_exit 1
    assert_stderr_contains "ERR_STAGED_CREDENTIAL_SHAPED: Sources/Config.txt"
    assert_stderr_contains "github-token"
    assert_stderr_not_contains "${TOKEN}" "the token"
    assert_stdout_not_contains "${TOKEN}" "the token"
}

# The staged blob is judged, not the worktree: a token removed on disk but still
# staged is blocked.
case_staged_content_not_worktree_judged() {
    local repo
    repo=$(make_repo)
    printf 'token=%s\n' "${TOKEN}" >"${repo}/notes.txt"
    git -C "${repo}" add notes.txt
    echo "clean now" >"${repo}/notes.txt"
    cd "${repo}"
    capture "${CHECK}"
    assert_exit 1
    assert_stderr_contains "ERR_STAGED_CREDENTIAL_SHAPED: notes.txt"
}

case_all_findings_collected() {
    local repo
    repo=$(make_repo)
    echo "X=1" >"${repo}/.env"
    printf '%s\n' "${TOKEN}" >"${repo}/a.txt"
    mkdir -p "${repo}/secrets"
    echo "x" >"${repo}/secrets/b.txt"
    git -C "${repo}" add -f .env a.txt secrets/b.txt
    cd "${repo}"
    capture "${CHECK}"
    assert_exit 1
    assert_stderr_contains "ERR_STAGED_BLOCKED_PATH: .env"
    assert_stderr_contains "ERR_STAGED_BLOCKED_PATH: secrets/b.txt"
    assert_stderr_contains "ERR_STAGED_CREDENTIAL_SHAPED: a.txt"
    assert_stderr_contains "Actual: 2 staged path(s) blocked by name, 1 by content"
}

# A committed .env staged for deletion is never inspected: removing it is the fix.
case_staged_deletion_allowed() {
    local repo
    repo=$(make_repo)
    printf 'token=%s\n' "${TOKEN}" >"${repo}/.env"
    git -C "${repo}" add -f .env
    git -C "${repo}" commit -q -m "an old mistake"
    git -C "${repo}" rm -q --cached .env
    cd "${repo}"
    capture "${CHECK}"
    assert_exit 0
}

case_env_example_allowed() {
    local repo
    repo=$(make_repo)
    echo "API_URL=" >"${repo}/.env.example"
    git -C "${repo}" add .env.example
    cd "${repo}"
    capture "${CHECK}"
    assert_exit 0
}

# A rename of a clean file is judged by its new path.
case_rename_into_blocked_path_blocked() {
    local repo
    repo=$(make_repo)
    git -C "${repo}" mv README.md .env
    cd "${repo}"
    capture "${CHECK}"
    assert_exit 1
    assert_stderr_contains "ERR_STAGED_BLOCKED_PATH: .env"
}

case_outside_repo_refused() {
    local dir
    dir=$(make_temp_dir)
    cd "${dir}"
    capture "${CHECK}"
    assert_exit 1
    assert_stderr_contains "ERR_STAGED_NOT_A_REPO"
}

# Hook level: the guard runs on a commit that stages no Swift file.
case_hook_blocks_env_without_swift() {
    local repo
    repo=$(make_repo_with_hook)
    echo "X=1" >"${repo}/.env"
    git -C "${repo}" add -f .env
    capture git -C "${repo}" commit -q -m "add env"
    assert_exit 1
    assert_stderr_contains "ERR_STAGED_BLOCKED_PATH: .env"
    [ -z "$(git -C "${repo}" log --oneline -1 -- .env)" ] || _fail "the .env commit landed"
}

case_hook_blocks_credential_without_echo() {
    local repo
    repo=$(make_repo_with_hook)
    printf 'token=%s\n' "${TOKEN}" >"${repo}/notes.md"
    git -C "${repo}" add notes.md
    capture git -C "${repo}" commit -q -m "add notes"
    assert_exit 1
    assert_stderr_contains "ERR_STAGED_CREDENTIAL_SHAPED: notes.md"
    assert_stderr_not_contains "${TOKEN}" "the token"
}

case_hook_allows_clean_commit() {
    local repo
    repo=$(make_repo_with_hook)
    echo "more" >>"${repo}/README.md"
    git -C "${repo}" add README.md
    capture git -C "${repo}" commit -q -m "clean change"
    assert_exit 0
    # git hands a hook's stdout to the committer's stderr.
    assert_stderr_contains "pre-commit: Staged guard"
}

# The commit that removes an earlier mistake must get through the hook.
case_hook_allows_env_deletion() {
    local repo
    repo=$(make_repo_with_hook)
    git -C "${repo}" config core.hooksPath /dev/null
    echo "X=1" >"${repo}/.env"
    git -C "${repo}" add -f .env
    git -C "${repo}" commit -q -m "an old mistake, committed before the hook was installed"
    git -C "${repo}" config core.hooksPath .githooks
    git -C "${repo}" rm -q --cached .env
    capture git -C "${repo}" commit -q -m "remove .env"
    assert_exit 0
    [ -z "$(git -C "${repo}" ls-files -- .env)" ] || _fail ".env is still tracked"
}

run_case "a force-added .env fails ERR_STAGED_BLOCKED_PATH" case_force_added_env_blocked
run_case "a staged token fails ERR_STAGED_CREDENTIAL_SHAPED without echoing it" case_credential_content_blocked_without_echo
run_case "the staged blob is judged, not the worktree" case_staged_content_not_worktree_judged
run_case "every finding is collected before failing once" case_all_findings_collected
run_case "a committed .env staged for deletion passes" case_staged_deletion_allowed
run_case ".env.example passes" case_env_example_allowed
run_case "a rename into a blocked path is blocked" case_rename_into_blocked_path_blocked
run_case "outside a git work tree fails ERR_STAGED_NOT_A_REPO" case_outside_repo_refused
run_case "hook: a staged .env blocks a commit with no Swift file" case_hook_blocks_env_without_swift
run_case "hook: a staged token blocks the commit without echoing it" case_hook_blocks_credential_without_echo
run_case "hook: a clean commit passes through the guard" case_hook_allows_clean_commit
run_case "hook: a commit that only deletes a tracked .env passes" case_hook_allows_env_deletion
finish
