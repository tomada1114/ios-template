#!/usr/bin/env bash
# Tests for scripts/tests/lib.sh itself: that sourcing it leaves no exported
# GIT_* variable behind, so no inherited git environment (GIT_DIR, GIT_CONFIG_*,
# GIT_CEILING_DIRECTORIES, ...) reaches a fixture repository. Each case sources
# lib.sh in a fresh bash with a seeded environment; nothing touches the checkout.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

LIB="${REPO_ROOT}/scripts/tests/lib.sh"

# Sources lib.sh in a child bash that inherits the given GIT_* variables, then
# prints every exported GIT_* name still set (one per line; empty means none).
remaining_git_names() {
    # shellcheck disable=SC2016 # expanded by the child bash, not here
    env "$@" "${BASH}" -c '
        . "$1"
        cleanup_temp
        for name in $(compgen -e); do
            case "${name}" in GIT_*) echo "${name}" ;; esac
        done
    ' lib_probe "${LIB}"
}

case_unsets_every_git_variable() {
    local left
    left=$(remaining_git_names \
        GIT_DIR=/nonexistent GIT_INDEX_FILE=/nonexistent/index \
        GIT_WORK_TREE=/nonexistent GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.bare \
        GIT_CONFIG_VALUE_0=true GIT_CEILING_DIRECTORIES=/ \
        GIT_ALTERNATE_OBJECT_DIRECTORIES=/nonexistent GIT_SOMETHING_NEW=x)
    [ -z "${left}" ] || _fail "GIT_* variables survived sourcing lib.sh: ${left}"
}

# A multi-line value must not smuggle a GIT_*-looking line past the unset loop
# or break it.
case_multiline_value_is_harmless() {
    local left
    left=$(remaining_git_names "GIT_MULTI=first
GIT_FAKE=second" GIT_PLAIN=y)
    [ -z "${left}" ] || _fail "GIT_* variables survived sourcing lib.sh: ${left}"
}

case_leaves_other_variables_alone() {
    local out
    # shellcheck disable=SC2016 # expanded by the child bash, not here
    out=$(env GIT_DIR=/nonexistent NOT_GIT_VAR=kept "${BASH}" -c '. "$1"; cleanup_temp; echo "${NOT_GIT_VAR-}"' lib_probe "${LIB}")
    [ "${out}" = "kept" ] || _fail "NOT_GIT_VAR was changed: '${out}'"
}

run_case "sourcing lib.sh unsets every exported GIT_* variable" case_unsets_every_git_variable
run_case "a multi-line GIT_* value is unset cleanly" case_multiline_value_is_harmless
run_case "non-GIT_* variables are left alone" case_leaves_other_variables_alone
finish
