#!/usr/bin/env bash
# Tests for scripts/label-pr.sh. `gh` is stubbed: `gh pr view` prints the labels in
# ${STUB_BIN}/current, and every call is logged to ${STUB_BIN}/gh.log.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SCRIPT="${REPO_ROOT}/scripts/label-pr.sh"

stub_gh() { # stub_gh [EDIT_EXIT] — current labels come from ${STUB_BIN}/current
    : >>"${STUB_BIN}/current"
    stub_command gh "case \"\$1 \$2\" in
    'pr view') cat '${STUB_BIN}/current' ;;
    'pr edit') exit ${1:-0} ;;
    *) exit 3 ;;
esac"
}

expect_label() { # expect_label TITLE LABEL
    stub_gh
    capture "${SCRIPT}" 7 "$1"
    assert_exit 0
    grep -qxF -- "pr edit 7 --add-label $2" "${STUB_BIN}/gh.log" || _fail "gh.log lacks --add-label $2"
}

case_feat() { expect_label "feat: add a thing" enhancement; }
case_feat_bang() { expect_label "feat!: drop an API" enhancement; }
case_scope_bang() { expect_label "fix(core)!: change a return" bug; }
case_docs() { expect_label "docs: explain" documentation; }
case_ci() { expect_label "ci: pin an action" ci; }
case_chore() { expect_label "chore: tidy" chore; }
case_deps() { expect_label "deps: bump swift-foo" dependencies; }
case_refactor() { expect_label "refactor(ui): split a view" chore; }

case_every_type_declared() {
    local t
    for t in feat fix docs style refactor perf test build ci chore revert deps; do
        : >"${STUB_BIN}/gh.log"
        stub_gh
        capture "${SCRIPT}" 7 "${t}: x"
        assert_exit 0
        grep -q -- "--add-label" "${STUB_BIN}/gh.log" || _fail "type ${t} applied no label"
    done
}

case_retitle_drops_stale() {
    printf 'enhancement\npriority: P3\n' >"${STUB_BIN}/current"
    stub_gh
    capture "${SCRIPT}" 7 "fix: it was a bug after all"
    assert_exit 0
    grep -qxF -- "pr edit 7 --add-label bug --remove-label enhancement" "${STUB_BIN}/gh.log" ||
        _fail "stale enhancement label was not removed"
}

case_keeps_dependencies() {
    printf 'dependencies\n' >"${STUB_BIN}/current"
    stub_gh
    capture "${SCRIPT}" 7 "ci: bump actions/checkout"
    assert_exit 0
    grep -qxF -- "pr edit 7 --add-label ci" "${STUB_BIN}/gh.log" || _fail "dependencies was removed"
}

case_never_creates() {
    stub_gh
    capture "${SCRIPT}" 7 "feat: x"
    ! grep -q "^label" "${STUB_BIN}/gh.log" || _fail "gh label was called"
}

case_unknown_type() {
    stub_gh
    capture "${SCRIPT}" 7 "wip: something"
    assert_exit 0
    assert_stdout_contains "No label mapping for type: wip"
    [ ! -s "${STUB_BIN}/gh.log" ] || _fail "gh was called"
}

case_no_type() {
    stub_gh
    capture "${SCRIPT}" 7 "Update README"
    assert_exit 0
    [ ! -s "${STUB_BIN}/gh.log" ] || _fail "gh was called"
}

case_undeclared_label() {
    local manifest
    manifest="${CASE_DIR}/labels.yml"
    printf -- '- name: bug\n  color: d73a4a\n  description: "x"\n' >"${manifest}"
    stub_gh
    capture "${SCRIPT}" --manifest "${manifest}" 7 "ci: x"
    assert_exit 1
    assert_stderr_contains "ERR_LABELPR_UNDECLARED"
    assert_stderr_contains "Next:"
}

case_fork_token() {
    stub_gh 1
    capture "${SCRIPT}" 7 "feat: x"
    assert_exit 0
    assert_stdout_contains "::notice::Could not apply label 'enhancement'"
}

case_view_fails() {
    stub_command gh "exit 1"
    capture "${SCRIPT}" 7 "feat: x"
    assert_exit 1
    assert_stderr_contains "ERR_LABELPR_GH_FAILED"
}

case_usage() {
    capture "${SCRIPT}" 7
    assert_exit 1
    assert_stderr_contains "ERR_LABELPR_USAGE"
    capture "${SCRIPT}" abc "feat: x"
    assert_exit 1
    assert_stderr_contains "ERR_LABELPR_USAGE"
}

run_case "feat maps to enhancement" case_feat
run_case "feat! maps to enhancement" case_feat_bang
run_case "a scope and ! still map" case_scope_bang
run_case "docs maps to documentation" case_docs
run_case "ci maps to ci" case_ci
run_case "chore maps to chore" case_chore
run_case "deps maps to dependencies" case_deps
run_case "refactor maps to chore" case_refactor
run_case "every title-check type applies a declared label" case_every_type_declared
run_case "a retitle removes the stale type label" case_retitle_drops_stale
run_case "dependencies is never removed" case_keeps_dependencies
run_case "never calls gh label" case_never_creates
run_case "an unknown type labels nothing" case_unknown_type
run_case "a title with no type labels nothing" case_no_type
run_case "an undeclared label fails" case_undeclared_label
run_case "a rejected edit is a notice" case_fork_token
run_case "a failed gh pr view fails" case_view_fails
run_case "bad arguments fail with usage" case_usage
finish
