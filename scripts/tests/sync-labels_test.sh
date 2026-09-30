#!/usr/bin/env bash
# Tests for scripts/sync-labels.sh. Every case stubs `gh` with stub_command, and
# PATH holds only that stub bin plus the tools this test file itself needs (never
# the real checkout's `gh`), so a case can never reach a real repository — including
# the malformed-manifest cases, where `gh` must never be called at all.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SYNC="${REPO_ROOT}/scripts/sync-labels.sh"

write_manifest() {
    local file="$1"
    shift
    printf '%s\n' "$@" >"${file}"
}

case_valid_manifest_applies_each_entry() {
    local manifest
    manifest="${CASE_DIR}/labels.yml"
    write_manifest "${manifest}" \
        '- name: bug' \
        '  color: d73a4a' \
        '  description: "Reproducible incorrect behavior."' \
        '- name: "priority: P0"' \
        '  color: b60205' \
        '  description: "Ship now."'
    stub_command gh 'exit 0'
    capture "${BASH}" "${SYNC}" --manifest "${manifest}"
    assert_exit 0
    assert_stdout_contains "labels: applied bug"
    assert_stdout_contains "labels: applied priority: P0"
    [ "$(grep -c '^label create' "${STUB_BIN}/gh.log")" = 2 ] ||
        _fail "expected exactly one \`label create\` call per entry, got $(cat "${STUB_BIN}/gh.log")"
    grep -qF -- '--color d73a4a --description Reproducible incorrect behavior. --force' "${STUB_BIN}/gh.log" ||
        _fail "gh was not called with the manifest's color/description/--force"
    grep -qF -- 'label create priority: P0 --color b60205' "${STUB_BIN}/gh.log" ||
        _fail "a name with ': ' was not passed to gh unquoted and intact"
}

case_missing_color_fails_before_any_gh_call() {
    local manifest
    manifest="${CASE_DIR}/labels.yml"
    write_manifest "${manifest}" \
        '- name: bug' \
        '  description: "No color on this entry."'
    stub_command gh 'exit 0'
    capture "${BASH}" "${SYNC}" --manifest "${manifest}"
    assert_exit 1
    assert_stderr_contains "ERR_LABELS_MANIFEST_MISSING_FIELD"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
    [ ! -s "${STUB_BIN}/gh.log" ] || _fail "gh was called on a malformed manifest"
}

case_missing_description_fails_before_any_gh_call() {
    local manifest
    manifest="${CASE_DIR}/labels.yml"
    write_manifest "${manifest}" \
        '- name: bug' \
        '  color: d73a4a'
    stub_command gh 'exit 0'
    capture "${BASH}" "${SYNC}" --manifest "${manifest}"
    assert_exit 1
    assert_stderr_contains "ERR_LABELS_MANIFEST_MISSING_FIELD"
    [ ! -s "${STUB_BIN}/gh.log" ] || _fail "gh was called on a malformed manifest"
}

case_bad_color_fails_before_any_gh_call() {
    local manifest
    manifest="${CASE_DIR}/labels.yml"
    write_manifest "${manifest}" \
        '- name: bug' \
        '  color: ZZZZZZ' \
        '  description: "Not six hex digits."'
    stub_command gh 'exit 0'
    capture "${BASH}" "${SYNC}" --manifest "${manifest}"
    assert_exit 1
    assert_stderr_contains "ERR_LABELS_MANIFEST_BAD_COLOR"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
    [ ! -s "${STUB_BIN}/gh.log" ] || _fail "gh was called on a malformed manifest"
}

case_bad_color_uppercase_fails() {
    local manifest
    manifest="${CASE_DIR}/labels.yml"
    write_manifest "${manifest}" \
        '- name: bug' \
        '  color: D73A4A' \
        '  description: "Uppercase hex digits are rejected."'
    stub_command gh 'exit 0'
    capture "${BASH}" "${SYNC}" --manifest "${manifest}"
    assert_exit 1
    assert_stderr_contains "ERR_LABELS_MANIFEST_BAD_COLOR"
    [ ! -s "${STUB_BIN}/gh.log" ] || _fail "gh was called on a malformed manifest"
}

case_gh_failure_reports_the_label() {
    local manifest
    manifest="${CASE_DIR}/labels.yml"
    write_manifest "${manifest}" \
        '- name: bug' \
        '  color: d73a4a' \
        '  description: "Reproducible incorrect behavior."'
    stub_command gh 'exit 1'
    capture "${BASH}" "${SYNC}" --manifest "${manifest}"
    assert_exit 1
    assert_stderr_contains "ERR_LABELS_GH_FAILED"
    assert_stderr_contains "bug"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
}

case_never_calls_label_delete() {
    local manifest
    manifest="${CASE_DIR}/labels.yml"
    write_manifest "${manifest}" \
        '- name: bug' \
        '  color: d73a4a' \
        '  description: "Reproducible incorrect behavior."' \
        '- name: chore' \
        '  color: fef2c0' \
        '  description: "Repository work."'
    stub_command gh 'exit 0'
    capture "${BASH}" "${SYNC}" --manifest "${manifest}"
    assert_exit 0
    ! grep -qi 'delete' "${STUB_BIN}/gh.log" || _fail "gh was called with delete"
}

case_default_manifest_path() {
    local root
    root=$(make_temp_dir)
    mkdir -p "${root}/.github" "${root}/scripts"
    cp "${SYNC}" "${root}/scripts/sync-labels.sh"
    write_manifest "${root}/.github/labels.yml" \
        '- name: bug' \
        '  color: d73a4a' \
        '  description: "Reproducible incorrect behavior."'
    stub_command gh 'exit 0'
    capture "${BASH}" "${root}/scripts/sync-labels.sh"
    assert_exit 0
    assert_stdout_contains "labels: applied bug"
}

case_manifest_not_found() {
    stub_command gh 'exit 0'
    capture "${BASH}" "${SYNC}" --manifest "${CASE_DIR}/does-not-exist.yml"
    assert_exit 1
    assert_stderr_contains "ERR_LABELS_USAGE"
    [ ! -s "${STUB_BIN}/gh.log" ] || _fail "gh was called with no manifest file"
}

case_unknown_flag() {
    stub_command gh 'exit 0'
    capture "${BASH}" "${SYNC}" --bogus
    assert_exit 1
    assert_stderr_contains "ERR_LABELS_USAGE: unknown argument '--bogus'"
    assert_stderr_contains "Next: usage: scripts/sync-labels.sh [--manifest PATH]"
}

run_case "a valid manifest issues one gh label create --force per entry" case_valid_manifest_applies_each_entry
run_case "a missing color: fails ERR_LABELS_MANIFEST_MISSING_FIELD, gh never called" case_missing_color_fails_before_any_gh_call
run_case "a missing description: fails ERR_LABELS_MANIFEST_MISSING_FIELD, gh never called" case_missing_description_fails_before_any_gh_call
run_case "a non-hex color fails ERR_LABELS_MANIFEST_BAD_COLOR, gh never called" case_bad_color_fails_before_any_gh_call
run_case "an uppercase-hex color fails ERR_LABELS_MANIFEST_BAD_COLOR" case_bad_color_uppercase_fails
run_case "a failing gh call fails ERR_LABELS_GH_FAILED naming the label" case_gh_failure_reports_the_label
run_case "the stub log never contains a delete call" case_never_calls_label_delete
run_case "no --manifest defaults to .github/labels.yml next to the script" case_default_manifest_path
run_case "a --manifest that does not exist fails ERR_LABELS_USAGE" case_manifest_not_found
run_case "an unknown flag fails ERR_LABELS_USAGE" case_unknown_flag
finish
