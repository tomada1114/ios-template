#!/usr/bin/env bash
# Tests for scripts/apply-ruleset.sh. Every case stubs `gh` with stub_command, and
# PATH holds only that stub bin plus the tools this test file itself needs (never
# the real checkout's `gh`), so a case can never reach a real repository — including
# the ruleset-content case, which reads .github/rulesets/main.json but never calls
# `gh` at all.
#
# Each stub body is one single-quoted literal, not `"$(cat <<'EOF' … EOF)"`: bash 3.2
# scans a command substitution for its closing `)` without understanding the heredoc
# inside it, so a body containing a `case` pattern ends early and the file dies with a
# syntax error — while still exiting 0, which is why nothing caught it.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

APPLY="${REPO_ROOT}/scripts/apply-ruleset.sh"
RULESET_FILE="${REPO_ROOT}/.github/rulesets/main.json"

# make_sandbox [--no-ruleset-file] — a throwaway copy of just enough of the repo
# layout (scripts/apply-ruleset.sh plus .github/rulesets/main.json) for the script
# to run against, since it resolves its ruleset file relative to its own location
# (`cd "$(dirname "$0")/.."`). Never touches the real checkout.
make_sandbox() {
    local sandbox
    sandbox=$(make_temp_dir)
    mkdir -p "${sandbox}/scripts" "${sandbox}/.github/rulesets"
    cp "${APPLY}" "${sandbox}/scripts/apply-ruleset.sh"
    if [ "${1-}" != "--no-ruleset-file" ]; then
        cp "${RULESET_FILE}" "${sandbox}/.github/rulesets/main.json"
    fi
    echo "${sandbox}"
}

case_no_existing_ruleset_posts_it() {
    local sandbox
    sandbox=$(make_sandbox)
    # shellcheck disable=SC2016 # expanded by the stub at run time, not here
    stub_command gh 'case "$1" in
    repo) echo "acme/widget" ;;
    api)
        shift
        case " $* " in
            *" --method POST "*) exit 0 ;;
            *" --method PUT "*) exit 0 ;;
            *) echo "" ;;
        esac
        ;;
esac'
    capture "${BASH}" "${sandbox}/scripts/apply-ruleset.sh"
    assert_exit 0
    grep -qF -- 'api repos/acme/widget/rulesets --method POST --input .github/rulesets/main.json' "${STUB_BIN}/gh.log" ||
        _fail "did not POST the ruleset file when no ruleset named main existed"
    ! grep -q -- '--method PUT' "${STUB_BIN}/gh.log" || _fail "PUT was called although no ruleset existed"
}

case_existing_ruleset_puts_it_by_id() {
    local sandbox
    sandbox=$(make_sandbox)
    # shellcheck disable=SC2016 # expanded by the stub at run time, not here
    stub_command gh 'case "$1" in
    repo) echo "acme/widget" ;;
    api)
        shift
        case " $* " in
            *" --method POST "*) exit 0 ;;
            *" --method PUT "*) exit 0 ;;
            *) echo "42" ;;
        esac
        ;;
esac'
    capture "${BASH}" "${sandbox}/scripts/apply-ruleset.sh"
    assert_exit 0
    grep -qF -- 'api repos/acme/widget/rulesets/42 --method PUT --input .github/rulesets/main.json' "${STUB_BIN}/gh.log" ||
        _fail "did not PUT to the existing ruleset's id"
    ! grep -q -- '--method POST' "${STUB_BIN}/gh.log" || _fail "POST was called although a ruleset already existed"
}

case_plan_unsupported_message_maps_to_plan_error() {
    local sandbox
    sandbox=$(make_sandbox)
    # shellcheck disable=SC2016 # expanded by the stub at run time, not here
    stub_command gh 'case "$1" in
    repo) echo "acme/widget" ;;
    api)
        echo "gh: Upgrade to GitHub Team or GitHub Enterprise Cloud to use this feature (HTTP 403)" >&2
        exit 1
        ;;
esac'
    capture "${BASH}" "${sandbox}/scripts/apply-ruleset.sh"
    assert_exit 1
    assert_stderr_contains "ERR_RULESET_PLAN_UNSUPPORTED"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
}

case_plain_403_maps_to_forbidden_error() {
    local sandbox
    sandbox=$(make_sandbox)
    # shellcheck disable=SC2016 # expanded by the stub at run time, not here
    stub_command gh 'case "$1" in
    repo) echo "acme/widget" ;;
    api)
        echo "gh: Resource not accessible by integration (HTTP 403)" >&2
        exit 1
        ;;
esac'
    capture "${BASH}" "${sandbox}/scripts/apply-ruleset.sh"
    assert_exit 1
    assert_stderr_contains "ERR_RULESET_FORBIDDEN"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
}

case_missing_ruleset_file_fails_before_any_gh_call() {
    local sandbox
    sandbox=$(make_sandbox --no-ruleset-file)
    stub_command gh 'exit 0'
    capture "${BASH}" "${sandbox}/scripts/apply-ruleset.sh"
    assert_exit 1
    assert_stderr_contains "ERR_RULESET_FILE_MISSING"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
    [ ! -e "${STUB_BIN}/gh.log" ] || _fail "gh was called although the ruleset file was missing"
}

# The ruleset's required_status_checks must name a job that actually exists today —
# grepped straight from the workflow files, not from any cached list — so a job
# rename in .github/workflows/ (without a matching update here) fails this case
# instead of silently going unenforced.
case_ruleset_contexts_match_workflow_job_names() {
    [ -f "${RULESET_FILE}" ] || _fail "missing ${RULESET_FILE}"

    local contexts
    contexts=$(python3 - "${RULESET_FILE}" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

assert data.get("name") == "main"
assert data.get("target") == "branch"
assert data.get("enforcement") == "active"

checks = []
for rule in data.get("rules", []):
    if rule.get("type") == "required_status_checks":
        checks.extend(rule["parameters"]["required_status_checks"])

if not checks:
    sys.exit("no required_status_checks entries found")

for check in checks:
    if check.get("integration_id") != 15368:
        sys.exit("context %r has no integration_id 15368" % check.get("context"))
    print(check["context"])
PY
    ) || _fail "main.json failed validation: ${contexts}"
    [ -n "${contexts}" ] || _fail "no required_status_checks contexts found in ${RULESET_FILE}"

    local job_names
    job_names=$(grep -h '^    name: ' "${REPO_ROOT}"/.github/workflows/*.yml | sed 's/^    name: //')

    local context
    while IFS= read -r context; do
        [ -n "${context}" ] || continue
        grep -qxF "${context}" <<<"${job_names}" ||
            _fail "ruleset context \"${context}\" is not a job name: in any .github/workflows/*.yml file"
    done <<EOF
${contexts}
EOF
}

run_case "no ruleset named main issues one POST with the file as input" case_no_existing_ruleset_posts_it
run_case "an existing ruleset named main issues a PUT to its id" case_existing_ruleset_puts_it_by_id
run_case "an upgrade-plan API message fails ERR_RULESET_PLAN_UNSUPPORTED" case_plan_unsupported_message_maps_to_plan_error
run_case "a plain 403 API message fails ERR_RULESET_FORBIDDEN" case_plain_403_maps_to_forbidden_error
run_case "a missing ruleset file fails ERR_RULESET_FILE_MISSING, gh never called" case_missing_ruleset_file_fails_before_any_gh_call
run_case "main.json parses and every required context is a current job name" case_ruleset_contexts_match_workflow_job_names
finish
