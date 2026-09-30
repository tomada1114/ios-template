#!/usr/bin/env bash
# Tests for scripts/sync-agents.sh. Every case builds its own root in a temp
# directory and passes it with --root, so the real checkout is never read or written.
# The cases use the real rsync and diff: GNU on CI's Ubuntu, openrsync and BSD diff
# on macOS, so the drift parsing is exercised against both message formats.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SYNC="${REPO_ROOT}/scripts/sync-agents.sh"

# Prints a root whose .agents/skills/ holds two skills, one with a nested file,
# and whose .claude/skills/ is an exact copy.
make_synced_root() {
    local root
    root=$(make_temp_dir)
    mkdir -p "${root}/.agents/skills/alpha/references" "${root}/.agents/skills/beta"
    echo "alpha skill" >"${root}/.agents/skills/alpha/SKILL.md"
    echo "alpha reference" >"${root}/.agents/skills/alpha/references/notes.md"
    echo "beta skill" >"${root}/.agents/skills/beta/SKILL.md"
    mkdir -p "${root}/.claude"
    cp -R "${root}/.agents/skills" "${root}/.claude/skills"
    echo "${root}"
}

case_in_sync() {
    local root
    root=$(make_synced_root)
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 0
    assert_stdout_contains "agents:check: .claude/skills/ is in sync."
}

case_missing_from_mirror() {
    local root
    root=$(make_synced_root)
    echo "new" >"${root}/.agents/skills/alpha/references/new.md"
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_DRIFT: missing from the mirror: .claude/skills/alpha/references/new.md"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual: 1 difference(s)"
    assert_stderr_contains "Next: run \`just agents-sync\` and commit both trees"
    grep -q '^ERR_AGENTS_DRIFT: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "first stderr line is not ERR_AGENTS_DRIFT"
}

case_extra_in_mirror() {
    local root
    root=$(make_synced_root)
    echo "stale" >"${root}/.claude/skills/stale.md"
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_DRIFT: extra in the mirror: .claude/skills/stale.md"
}

case_differing_file() {
    local root
    root=$(make_synced_root)
    echo "hand edit" >>"${root}/.claude/skills/beta/SKILL.md"
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_DRIFT: differs: .claude/skills/beta/SKILL.md"
}

case_every_drift_named() {
    local root
    root=$(make_synced_root)
    echo "new" >"${root}/.agents/skills/beta/new.md"
    echo "stale" >"${root}/.claude/skills/alpha/stale.md"
    echo "hand edit" >>"${root}/.claude/skills/alpha/SKILL.md"
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 1
    assert_stderr_contains "missing from the mirror: .claude/skills/beta/new.md"
    assert_stderr_contains "extra in the mirror: .claude/skills/alpha/stale.md"
    assert_stderr_contains "differs: .claude/skills/alpha/SKILL.md"
    assert_stderr_contains "Actual: 3 difference(s)"
}

case_ds_store_ignored() {
    local root
    root=$(make_synced_root)
    echo "finder" >"${root}/.agents/skills/.DS_Store"
    echo "finder" >"${root}/.claude/skills/alpha/.DS_Store"
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 0
    assert_stdout_contains "is in sync."
}

case_source_missing() {
    local root
    root=$(make_temp_dir)
    capture "${BASH}" "${SYNC}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_SOURCE_MISSING: .agents/skills/ does not exist"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
    [ ! -e "${root}/.claude" ] || _fail "sync created .claude/ without a source"
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_SOURCE_MISSING"
}

# Sync removes a stale mirror file, repairs every drift, and touches nothing outside
# .claude/skills/ — including a .claude/ sibling and a file at the root.
case_sync_repairs_and_stays_inside_mirror() {
    local root
    root=$(make_synced_root)
    echo "stale" >"${root}/.claude/skills/stale.md"
    echo "hand edit" >>"${root}/.claude/skills/beta/SKILL.md"
    echo "new" >"${root}/.agents/skills/beta/new.md"
    echo "sentinel" >"${root}/sentinel.txt"
    echo '{}' >"${root}/.claude/settings.json"
    watch_file "${root}/sentinel.txt"
    watch_file "${root}/.claude/settings.json"
    capture "${BASH}" "${SYNC}" --root "${root}"
    assert_exit 0
    assert_stdout_contains "agents:sync: .claude/skills/ regenerated from .agents/skills/."
    [ ! -e "${root}/.claude/skills/stale.md" ] || _fail "sync kept the stale mirror file"
    assert_file_unchanged "${root}/sentinel.txt"
    assert_file_unchanged "${root}/.claude/settings.json"
    diff -r "${root}/.agents/skills" "${root}/.claude/skills" >/dev/null || _fail "trees differ after sync"
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 0
}

case_sync_creates_absent_mirror() {
    local root
    root=$(make_temp_dir)
    mkdir -p "${root}/.agents/skills/alpha"
    echo "alpha skill" >"${root}/.agents/skills/alpha/SKILL.md"
    capture "${BASH}" "${SYNC}" --root "${root}"
    assert_exit 0
    cmp -s "${root}/.agents/skills/alpha/SKILL.md" "${root}/.claude/skills/alpha/SKILL.md" ||
        _fail "the mirror file is not byte-identical"
}

case_check_writes_nothing() {
    local root file
    root=$(make_synced_root)
    echo "new" >"${root}/.agents/skills/beta/new.md"
    echo "stale" >"${root}/.claude/skills/stale.md"
    echo "hand edit" >>"${root}/.claude/skills/alpha/SKILL.md"
    for file in .claude/skills/beta/new.md .claude/skills/stale.md .claude/skills/alpha/SKILL.md \
        .agents/skills/beta/new.md .agents/skills/alpha/SKILL.md; do
        watch_file "${root}/${file}"
    done
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 1
    for file in .claude/skills/beta/new.md .claude/skills/stale.md .claude/skills/alpha/SKILL.md \
        .agents/skills/beta/new.md .agents/skills/alpha/SKILL.md; do
        assert_file_unchanged "${root}/${file}"
    done
}

case_check_absent_mirror() {
    local root
    root=$(make_temp_dir)
    mkdir -p "${root}/.agents/skills/alpha"
    echo "alpha skill" >"${root}/.agents/skills/alpha/SKILL.md"
    capture "${BASH}" "${SYNC}" --check --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_DRIFT: .claude/skills/ does not exist"
    [ ! -e "${root}/.claude" ] || _fail "--check created .claude/"
}

case_symlinked_mirror_refused() {
    local root
    root=$(make_temp_dir)
    mkdir -p "${root}/.agents/skills/alpha" "${root}/.claude"
    echo "alpha skill" >"${root}/.agents/skills/alpha/SKILL.md"
    ln -s ../.agents/skills "${root}/.claude/skills"
    capture "${BASH}" "${SYNC}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_SYMLINK: .claude/skills is a symlink"
}

case_symlink_in_source_refused() {
    local root
    root=$(make_synced_root)
    ln -s SKILL.md "${root}/.agents/skills/alpha/link.md"
    capture "${BASH}" "${SYNC}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_SYMLINK: .agents/skills/ contains a symlink"
    [ ! -e "${root}/.claude/skills/alpha/link.md" ] || _fail "sync mirrored the symlink"
}

# PATH holds only what the script needs before its tool check, so rsync is absent.
case_rsync_missing() {
    local root bin tool
    root=$(make_synced_root)
    bin=$(make_temp_dir)
    for tool in find tr; do
        ln -s "$(command -v "${tool}")" "${bin}/${tool}"
    done
    capture env PATH="${bin}" "${BASH}" "${SYNC}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_TOOL_MISSING: 'rsync' is not on PATH"
    assert_stderr_contains "Next:"
}

case_unknown_flag() {
    capture "${BASH}" "${SYNC}" --bogus
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_USAGE: unknown argument '--bogus'"
    assert_stderr_contains "Next: usage: scripts/sync-agents.sh [--check] [--root DIR]"
}

case_root_missing_dir() {
    local missing
    missing="$(make_temp_dir)/does-not-exist"
    capture "${BASH}" "${SYNC}" --root "${missing}"
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_USAGE: --root directory '${missing}' does not exist"
}

case_default_root_outside_work_tree() {
    local dir
    dir=$(make_temp_dir)
    cd "${dir}"
    capture env GIT_CEILING_DIRECTORIES="${dir}" "${BASH}" "${SYNC}" --check
    assert_exit 1
    assert_stderr_contains "ERR_AGENTS_NOT_A_REPO"
}

case_default_root_is_work_tree() {
    local repo
    repo=$(make_temp_repo)
    mkdir -p "${repo}/.agents/skills/alpha" "${repo}/sub"
    echo "alpha skill" >"${repo}/.agents/skills/alpha/SKILL.md"
    cd "${repo}/sub"
    capture "${BASH}" "${SYNC}"
    assert_exit 0
    [ -f "${repo}/.claude/skills/alpha/SKILL.md" ] || _fail "sync did not default --root to the work tree top"
}

run_case "in-sync trees: --check exits 0" case_in_sync
run_case "a file missing from the mirror is ERR_AGENTS_DRIFT naming it" case_missing_from_mirror
run_case "an extra file in the mirror is ERR_AGENTS_DRIFT naming it" case_extra_in_mirror
run_case "a differing file is ERR_AGENTS_DRIFT naming it" case_differing_file
run_case "every kind of drift is named in one run" case_every_drift_named
run_case "a .DS_Store on one side only is still in sync" case_ds_store_ignored
run_case "no .agents/skills fails ERR_AGENTS_SOURCE_MISSING" case_source_missing
run_case "sync removes a stale mirror file and writes nothing outside .claude/skills/" case_sync_repairs_and_stays_inside_mirror
run_case "sync creates an absent mirror byte-identical to the source" case_sync_creates_absent_mirror
run_case "--check changes no file" case_check_writes_nothing
run_case "--check with no mirror is ERR_AGENTS_DRIFT and creates nothing" case_check_absent_mirror
run_case "a symlinked mirror fails ERR_AGENTS_SYMLINK" case_symlinked_mirror_refused
run_case "a symlink in the source fails ERR_AGENTS_SYMLINK" case_symlink_in_source_refused
run_case "sync without rsync fails ERR_AGENTS_TOOL_MISSING" case_rsync_missing
run_case "an unknown flag fails ERR_AGENTS_USAGE" case_unknown_flag
run_case "a --root that does not exist fails ERR_AGENTS_USAGE" case_root_missing_dir
run_case "no --root outside a work tree fails ERR_AGENTS_NOT_A_REPO" case_default_root_outside_work_tree
run_case "no --root defaults to the work tree top" case_default_root_is_work_tree
finish
