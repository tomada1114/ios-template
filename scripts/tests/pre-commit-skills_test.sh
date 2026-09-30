#!/usr/bin/env bash
# Tests for the "Skills mirror" section of .githooks/pre-commit. Each case builds a
# throwaway git repository with its own copy of the hook, scripts/lint.sh, and
# scripts/sync-agents.sh, with core.hooksPath pointing at .githooks, so the real
# checkout is never touched. None of these commits stage a Swift file, so the
# Swift-lint section never runs and no case needs swiftformat, swiftlint, or mise —
# only git, diff, and the shell, which every machine running these tests already has.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

HOOK_SRC="${REPO_ROOT}/.githooks/pre-commit"
LINT_SRC="${REPO_ROOT}/scripts/lint.sh"
SYNC_SRC="${REPO_ROOT}/scripts/sync-agents.sh"

# Prints a repo with .githooks/pre-commit (wired via core.hooksPath), copies of
# scripts/lint.sh and scripts/sync-agents.sh, and a synced .agents/skills/ +
# .claude/skills/ pair, all committed as the starting point for each case.
make_repo_with_hook() {
    local repo
    repo=$(make_temp_repo)
    mkdir -p "${repo}/.githooks" "${repo}/scripts"
    cp "${HOOK_SRC}" "${repo}/.githooks/pre-commit"
    cp "${LINT_SRC}" "${repo}/scripts/lint.sh"
    cp "${SYNC_SRC}" "${repo}/scripts/sync-agents.sh"
    chmod +x "${repo}/.githooks/pre-commit" "${repo}/scripts/lint.sh" "${repo}/scripts/sync-agents.sh"
    git -C "${repo}" config core.hooksPath .githooks

    mkdir -p "${repo}/.agents/skills/alpha" "${repo}/.claude"
    echo "alpha skill" >"${repo}/.agents/skills/alpha/SKILL.md"
    cp -R "${repo}/.agents/skills" "${repo}/.claude/skills"
    echo "hello" >"${repo}/README.md"

    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "initial"
    echo "${repo}"
}

case_unsynced_agents_edit_fails() {
    local repo
    repo=$(make_repo_with_hook)
    echo "changed" >>"${repo}/.agents/skills/alpha/SKILL.md"
    git -C "${repo}" add .agents/skills/alpha/SKILL.md
    capture git -C "${repo}" commit -q -m "edit .agents side only, no sync"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_DRIFT"
}

# The working tree is back in sync after the sync runs, but only the .agents side is
# staged: the index — what will actually land in the commit — is still drifted.
case_synced_but_only_agents_side_staged_fails() {
    local repo
    repo=$(make_repo_with_hook)
    echo "changed" >>"${repo}/.agents/skills/alpha/SKILL.md"
    "${BASH}" "${repo}/scripts/sync-agents.sh" --root "${repo}"
    git -C "${repo}" add .agents/skills/alpha/SKILL.md
    capture git -C "${repo}" commit -q -m "sync ran, only .agents side staged"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_DRIFT"
}

case_claude_hand_edit_fails() {
    local repo
    repo=$(make_repo_with_hook)
    echo "hand edit" >>"${repo}/.claude/skills/alpha/SKILL.md"
    git -C "${repo}" add .claude/skills/alpha/SKILL.md
    capture git -C "${repo}" commit -q -m "hand edit the mirror only"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_DRIFT"
}

# A deletion is a staged change too: removing a skill from the .agents side only
# must still reach the check.
case_agents_side_deletion_fails() {
    local repo
    repo=$(make_repo_with_hook)
    mkdir -p "${repo}/.agents/skills/beta" "${repo}/.claude/skills/beta"
    echo "beta skill" >"${repo}/.agents/skills/beta/SKILL.md"
    echo "beta skill" >"${repo}/.claude/skills/beta/SKILL.md"
    git -C "${repo}" add -A
    git -C "${repo}" commit -q -m "add beta on both sides"
    git -C "${repo}" rm -q .agents/skills/beta/SKILL.md
    capture git -C "${repo}" commit -q -m "delete beta from .agents only"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_DRIFT"
}

case_both_sides_staged_after_sync_succeeds() {
    local repo
    repo=$(make_repo_with_hook)
    echo "changed" >>"${repo}/.agents/skills/alpha/SKILL.md"
    "${BASH}" "${repo}/scripts/sync-agents.sh" --root "${repo}"
    git -C "${repo}" add .agents/skills .claude/skills
    capture git -C "${repo}" commit -q -m "sync both sides"
    assert_exit 0
}

# The working tree is drifted (no sync ran), but the staged path is unrelated, so the
# section is skipped entirely and the commit succeeds.
case_unrelated_staged_path_skips_check() {
    local repo
    repo=$(make_repo_with_hook)
    echo "changed" >>"${repo}/.agents/skills/alpha/SKILL.md"
    echo "more" >>"${repo}/README.md"
    git -C "${repo}" add README.md
    capture git -C "${repo}" commit -q -m "unrelated change, tree left drifted"
    assert_exit 0
}

run_case "an unsynced .agents/skills edit fails ERR_AGENTS_DRIFT" case_unsynced_agents_edit_fails
run_case "a sync that ran but staged only the .agents side still fails" case_synced_but_only_agents_side_staged_fails
run_case "a hand edit staged only in .claude/skills fails" case_claude_hand_edit_fails
run_case "deleting a skill from the .agents side only fails" case_agents_side_deletion_fails
run_case "both sides staged after a sync succeeds" case_both_sides_staged_after_sync_succeeds
run_case "staging an unrelated path skips the check" case_unrelated_staged_path_skips_check
finish
