#!/usr/bin/env bash
# Tests for scripts/lint.sh's argument and tool checks. Only the number-separator
# case reaches a real linter, so it alone needs swiftformat and swiftlint on PATH;
# each tool-missing case builds its own restricted PATH.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

LINT="${REPO_ROOT}/scripts/lint.sh"

# A bin/ holding only the POSIX utilities lint.sh needs before its tool check,
# so every linter (and git) is absent whatever the caller's PATH holds.
restricted_path() {
    local dir
    dir=$(make_temp_dir)
    ln -s "$(command -v dirname)" "${dir}/dirname"
    echo "${dir}"
}

case_unknown_flag() {
    capture "${BASH}" "${LINT}" --bogus value
    assert_exit 1
    assert_stderr_contains "ERR_LINT_USAGE: unknown argument '--bogus'"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual: arguments: --bogus value"
    assert_stderr_contains "Next: usage: scripts/lint.sh [--staged-tree DIR]"
}

case_wrong_argument_count() {
    capture "${BASH}" "${LINT}" --staged-tree
    assert_exit 1
    assert_stderr_contains "ERR_LINT_USAGE: unexpected arguments: --staged-tree"
}

case_staged_tree_missing_dir() {
    local missing
    missing="$(make_temp_dir)/does-not-exist"
    capture "${BASH}" "${LINT}" --staged-tree "${missing}"
    assert_exit 1
    assert_stderr_contains "ERR_LINT_USAGE: --staged-tree directory '${missing}' does not exist"
    assert_stderr_contains "Actual: no directory at '${missing}'"
}

case_tool_missing_whole_repo() {
    capture env PATH="$(restricted_path)" "${BASH}" "${LINT}"
    assert_exit 1
    assert_stderr_contains "ERR_LINT_TOOL_MISSING: 'git' is not on PATH"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next: run it through mise"
}

# swiftformat is stubbed present and swiftlint absent: the check names the
# missing tool and exits before running any linter, stubbed or not.
case_tool_missing_staged_tree() {
    local tree
    tree=$(make_temp_repo)
    stub_command swiftformat 'exit 0'
    capture env PATH="${STUB_BIN}:$(restricted_path)" "${BASH}" "${LINT}" --staged-tree "${tree}"
    assert_exit 1
    assert_stderr_contains "ERR_LINT_TOOL_MISSING: 'swiftlint' is not on PATH"
    [ ! -e "${STUB_BIN}/swiftformat.log" ] || _fail "swiftformat ran before the tool check"
}

# A copy of lint.sh in a directory that is not a git work tree, with every linter
# stubbed present: the whole-repository mode refuses before running any of them.
case_whole_repo_outside_work_tree() {
    local dir tool
    dir=$(make_temp_dir)
    mkdir "${dir}/scripts"
    cp "${LINT}" "${dir}/scripts/lint.sh"
    for tool in swiftformat swiftlint shellcheck actionlint typos; do
        stub_command "${tool}" 'exit 0'
    done
    capture env GIT_CEILING_DIRECTORIES="${dir}" "${BASH}" "${dir}/scripts/lint.sh"
    assert_exit 1
    assert_stderr_contains "ERR_LINT_NOT_A_REPO: whole-repository lint needs a git work tree"
    assert_stderr_contains "Next:"
    [ ! -e "${STUB_BIN}/swiftformat.log" ] || _fail "swiftformat ran outside a work tree"
}

# A throwaway repository holding a copy of lint.sh, one authored skill script, and
# its generated mirror copy, with every tool stubbed: shellcheck is handed the
# authored script and never the mirror.
case_shellcheck_skips_skills_mirror() {
    local repo tool
    repo=$(make_temp_repo)
    mkdir -p "${repo}/scripts" "${repo}/.githooks" "${repo}/.agents/skills/s/scripts" \
        "${repo}/.claude/skills/s/scripts"
    cp "${LINT}" "${repo}/scripts/lint.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' >"${repo}/scripts/sync-agents.sh"
    chmod +x "${repo}/scripts/sync-agents.sh"
    : >"${repo}/.githooks/pre-commit"
    : >"${repo}/.agents/skills/s/scripts/run.sh"
    : >"${repo}/.claude/skills/s/scripts/run.sh"
    git -C "${repo}" add -A
    for tool in swiftformat swiftlint shellcheck actionlint typos; do
        stub_command "${tool}" 'exit 0'
    done
    capture "${BASH}" "${repo}/scripts/lint.sh"
    assert_exit 0
    grep -q '.agents/skills/s/scripts/run.sh' "${STUB_BIN}/shellcheck.log" \
        || _fail "shellcheck was not given the authored skill script"
    if grep -q '.claude/skills/' "${STUB_BIN}/shellcheck.log"; then
        _fail "shellcheck was given the generated .claude/skills/ mirror"
    fi
}

# typos reads its scope from typos.toml, so the exclusion is asserted there.
case_typos_skips_skills_mirror() {
    grep -q '^extend-exclude = .*"\.claude/skills"' "${REPO_ROOT}/typos.toml" \
        || _fail "typos.toml does not exclude .claude/skills"
}

# The real linters, not stubs: .swiftformat's --decimalgrouping and SwiftLint's
# number_separator must agree on where a separator goes, or the formatter strips one
# the linter then demands. `just test-scripts` runs through `mise exec --` and CI's
# lint job installs both tools, so a missing one is a failure, never a skip.
case_number_separators_pass_both_linters() {
    local dir
    if ! command -v swiftformat >/dev/null 2>&1 || ! command -v swiftlint >/dev/null 2>&1; then
        _fail "swiftformat/swiftlint not on PATH — run through mise exec"
    fi
    dir=$(make_temp_dir)
    printf 'let first = 3_600\nlet second = 36_000\n' >"${dir}/Separators.swift"
    capture swiftformat --lint --config "${REPO_ROOT}/.swiftformat" "${dir}/Separators.swift"
    assert_exit 0
    capture swiftlint lint --strict --quiet --config "${REPO_ROOT}/.swiftlint.yml" "${dir}/Separators.swift"
    assert_exit 0
}

run_case "an unknown flag fails ERR_LINT_USAGE" case_unknown_flag
run_case "a wrong argument count fails ERR_LINT_USAGE" case_wrong_argument_count
run_case "--staged-tree with a missing directory fails ERR_LINT_USAGE" case_staged_tree_missing_dir
run_case "a PATH without git fails ERR_LINT_TOOL_MISSING" case_tool_missing_whole_repo
run_case "--staged-tree without swiftlint fails ERR_LINT_TOOL_MISSING" case_tool_missing_staged_tree
run_case "whole-repository mode outside a work tree fails ERR_LINT_NOT_A_REPO" case_whole_repo_outside_work_tree
run_case "shellcheck skips the generated .claude/skills/ mirror" case_shellcheck_skips_skills_mirror
run_case "typos.toml excludes the generated .claude/skills/ mirror" case_typos_skips_skills_mirror
run_case "a 4- and a 5-digit literal pass both linters" case_number_separators_pass_both_linters
finish
