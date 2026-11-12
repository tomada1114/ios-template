#!/usr/bin/env bash
# Tests for scripts/simulator-relevant.sh, each in its own throwaway repository.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SCRIPT="${REPO_ROOT}/scripts/simulator-relevant.sh"

# repo_on_branch — a repository with one commit on main and a checked-out `work`
# branch; prints its path.
repo_on_branch() {
    local repo
    repo=$(make_temp_repo)
    (
        cd "${repo}"
        git checkout -q -b main
        echo readme >README.md
        git add README.md
        git commit -q -m init
        git checkout -q -b work
    )
    echo "${repo}"
}

commit_file() { # commit_file REPO PATH
    mkdir -p "$(dirname "$1/$2")"
    echo x >"$1/$2"
    git -C "$1" add "$2"
    git -C "$1" commit -q -m "add $2"
}

answer_is() {
    [ "$(cat "${CASE_DIR}/stdout")" = "$1" ] || _fail "expected $1"
}

case_relevant_commit() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" App/Main.swift
    cd "${repo}"
    capture "${BASH}" "${SCRIPT}"
    assert_exit 0
    answer_is true
}

case_irrelevant_only() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" docs/guide.md
    echo y >"${repo}/README.md"
    cd "${repo}"
    capture "${BASH}" "${SCRIPT}"
    assert_exit 0
    answer_is false
    assert_stderr_contains "since main"
    assert_stderr_contains "CHECK_ALL=1"
}

case_untracked_relevant() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" docs/guide.md
    mkdir -p "${repo}/scripts"
    echo z >"${repo}/scripts/new.sh"
    cd "${repo}"
    capture "${BASH}" "${SCRIPT}"
    answer_is true
}

case_staged_relevant() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    echo z >"${repo}/justfile"
    git -C "${repo}" add justfile
    cd "${repo}"
    capture "${BASH}" "${SCRIPT}"
    answer_is true
}

case_swiftlint_config_relevant() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" .swiftlint.yml
    cd "${repo}"
    capture "${BASH}" "${SCRIPT}"
    answer_is true
}

case_check_all() {
    local repo
    repo=$(repo_on_branch)
    commit_file "${repo}" docs/guide.md
    cd "${repo}"
    CHECK_ALL=1 capture "${BASH}" "${SCRIPT}"
    answer_is true
}

case_empty_change_set() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    cd "${repo}"
    capture "${BASH}" "${SCRIPT}"
    answer_is true
}

case_bad_base() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" docs/guide.md
    cd "${repo}"
    capture "${BASH}" "${SCRIPT}" --base no-such-ref
    assert_exit 0
    answer_is true
    assert_stderr_contains "no merge base between HEAD and no-such-ref"
}

case_not_a_repo() {
    unset CHECK_ALL
    cd "$(make_temp_dir)"
    capture "${BASH}" "${SCRIPT}"
    assert_exit 0
    answer_is true
}

case_base_head_mode() {
    local repo base head
    unset CHECK_ALL
    repo=$(repo_on_branch)
    base=$(git -C "${repo}" rev-parse HEAD)
    commit_file "${repo}" docs/guide.md
    head=$(git -C "${repo}" rev-parse HEAD)
    commit_file "${repo}" Packages/A.swift
    cd "${repo}"
    capture "${BASH}" "${SCRIPT}" --base "${base}" --head "${head}"
    assert_exit 0
    answer_is false
    assert_stderr_contains "Changed files:"
    assert_stderr_contains "docs/guide.md"
    capture "${BASH}" "${SCRIPT}" --base "${base}" --head HEAD
    answer_is true
    capture "${BASH}" "${SCRIPT}" --base "${base}" --head no-such-ref
    assert_exit 0
    answer_is true
}

# check_answers REPO UITEST TEST_IOS — asserts both per-check answers for REPO.
check_answers() {
    cd "$1"
    capture "${BASH}" "${SCRIPT}" --check uitest
    assert_exit 0
    answer_is "$2"
    capture "${BASH}" "${SCRIPT}" --check test-ios
    assert_exit 0
    answer_is "$3"
}

case_check_ui_change() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" Packages/MyAppKit/Sources/MyAppUI/RootView.swift
    check_answers "${repo}" true false
    assert_stderr_contains "nothing test-ios exercise changed since main"
}

case_check_platform_change() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" Packages/MyAppKit/Sources/MyAppPlatform/Store.swift
    check_answers "${repo}" false true
}

# A Core change runs neither: the host `just test` covers it, and the CI list (no
# --check) still calls it macOS work.
case_check_core_change() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" Packages/MyAppKit/Sources/MyAppCore/Model.swift
    check_answers "${repo}" false false
    capture "${BASH}" "${SCRIPT}"
    answer_is true
}

case_check_shared_paths() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    commit_file "${repo}" .xcode-version
    check_answers "${repo}" true true
}

case_check_fail_safe() {
    local repo
    unset CHECK_ALL
    repo=$(repo_on_branch)
    check_answers "${repo}" false false
    assert_stderr_contains "nothing changed since main"
    commit_file "${repo}" Package.resolved
    check_answers "${repo}" true true
    CHECK_ALL=1 capture "${BASH}" "${SCRIPT}" --check uitest
    answer_is true
    cd "$(make_temp_dir)"
    capture "${BASH}" "${SCRIPT}" --check test-ios
    assert_exit 0
    answer_is true
}

case_check_usage() {
    capture "${BASH}" "${SCRIPT}" --check smoke
    assert_exit 1
    grep -q '^ERR_RELEVANT_USAGE: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "not ERR_RELEVANT_USAGE"
    capture "${BASH}" "${SCRIPT}" --check uitest --base a --head b
    assert_exit 1
    capture "${BASH}" "${SCRIPT}" --check
    assert_exit 1
}

case_usage() {
    capture "${BASH}" "${SCRIPT}" --head HEAD
    assert_exit 1
    grep -q '^ERR_RELEVANT_USAGE: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "not ERR_RELEVANT_USAGE"
    capture "${BASH}" "${SCRIPT}" --bogus
    assert_exit 1
}

run_case "a committed relevant change prints true" case_relevant_commit
run_case "only irrelevant changes print false, with a notice" case_irrelevant_only
run_case "an untracked relevant file prints true" case_untracked_relevant
run_case "a staged relevant file prints true" case_staged_relevant
run_case "a .swiftlint.yml change prints true" case_swiftlint_config_relevant
run_case "CHECK_ALL=1 prints true" case_check_all
run_case "an empty change set prints true" case_empty_change_set
run_case "a bad base ref prints true" case_bad_base
run_case "outside a git checkout prints true" case_not_a_repo
run_case "--base/--head diffs BASE...HEAD" case_base_head_mode
run_case "--check: a MyAppUI change runs uitest alone" case_check_ui_change
run_case "--check: a MyAppPlatform change runs test-ios alone" case_check_platform_change
run_case "--check: a MyAppCore change runs neither" case_check_core_change
run_case "--check: .xcode-version runs both" case_check_shared_paths
run_case "--check: an empty change set prints false; Package.resolved, CHECK_ALL=1, and no checkout print true" case_check_fail_safe
run_case "--check: an unknown name, --head, or a missing value fail" case_check_usage
run_case "bad arguments fail" case_usage
finish
