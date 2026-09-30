#!/usr/bin/env bash
# Runs the Python unittest suite each skill bundles for its own scripts: every
# .agents/skills/<name>/scripts/tests/ directory holding a test_*.py file becomes one
# case, run with `python3 -m unittest discover`. A failing unittest fails its case, so
# `just test-scripts` (scripts/tests/run.sh) and CI's lint job fail with it.
#
# The authored tree is tested, not the .claude/skills/ mirror: the two are byte-
# identical (scripts/sync-agents.sh --check), and .agents/skills/ is the one edited.
# PYTHONDONTWRITEBYTECODE=1 keeps __pycache__ out of that tree, and each case then
# asserts none appeared, since a stray one would break the mirror check. Every write
# the suite makes goes to its own temp directories.
#
# python3 is assumed on PATH like git (not a mise tool). Its absence fails the file.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SUITES=()
for dir in "${REPO_ROOT}"/.agents/skills/*/scripts/tests; do
    [ -d "${dir}" ] || continue
    for file in "${dir}"/test_*.py; do
        if [ -e "${file}" ]; then
            SUITES[${#SUITES[@]}]="${dir}"
        fi
        break
    done
done

run_suite() {
    local dir="${SUITE_DIR}"
    command -v python3 >/dev/null 2>&1 || _fail "python3 is not on PATH"
    capture env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "${dir}" -t "${dir}" -p 'test_*.py'
    assert_exit 0
    assert_stderr_contains "OK"
    if [ -n "$(find "${dir}/.." -name __pycache__ -print)" ]; then
        _fail "__pycache__ appeared under ${dir}/.."
    fi
    grep '^Ran ' "${CASE_DIR}/stderr" || true
}

case_suites_found() {
    [ "${#SUITES[@]}" -gt 0 ] || _fail "no .agents/skills/*/scripts/tests/test_*.py found"
}
run_case "at least one skill bundles a unittest suite" case_suites_found

for SUITE_DIR in ${SUITES[@]+"${SUITES[@]}"}; do
    run_case "unittest suite passes: ${SUITE_DIR#"${REPO_ROOT}"/}" run_suite
done

finish
