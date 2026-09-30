#!/usr/bin/env bash
# Every required status check in the main branch ruleset names a job that actually
# reports on a pull request, so renaming a CI job cannot leave a required check that
# never reports and blocks every PR.
#
#   scripts/checks/ruleset-contexts.sh [--root DIR]
#
# Files: <root>/.github/rulesets/main.json (required) and
# <root>/.github/workflows/*.yml|*.yaml.
#   - contexts: every `"context": "<name>"` in main.json. The JSON is read with grep
#     and sed, not a JSON parser: a context whose value contains an escaped quote,
#     or whose key and value are split across lines, is not seen.
#   - jobs: only workflows triggered on `pull_request` count — a column-0 `on:` whose
#     inline value mentions `pull_request` (`on: pull_request`, `on: [push,
#     pull_request]`), or whose block has a `  pull_request:` key or a
#     `  - pull_request` item. `pull_request_target` does not count: it runs the base
#     branch's workflow, so a job renamed in a PR would not report under it either.
#     Each job is a two-space-indented `<id>:` under a column-0 `jobs:`; its reported
#     name is its four-space-indented `name:` (quotes stripped, a trailing ` # …`
#     comment dropped) or, without one, its id.
#   - matching: a context must equal some job's reported name. A name containing a
#     `${{ … }}` expression cannot be evaluated statically, so each expression is
#     treated as a wildcard matching any text. A matrix job without an expression in
#     its name reports as `<name> (<values>)`, which this check does not model.
#   The check is line-based, not YAML-aware: flow-style `jobs: {…}` and names on a
#   continuation line are not seen.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE               unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING       .github/rulesets/main.json does not exist
#   ERR_CHECK_RULESET_CONTEXT     a required context matches no job in a pull_request workflow
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/ruleset-contexts.sh" "$@"

RULESET=".github/rulesets/main.json"
check_require_file "${RULESET}"

# pr_job_names FILE — prints one reported job name per line if FILE is a workflow
# triggered on pull_request, nothing otherwise.
pr_job_names() {
    awk '
        function unquote(v) {
            sub(/[[:space:]]+#.*$/, "", v)
            sub(/[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
            return v
        }
        function flush() { if (id != "") names[++n] = (name != "" ? name : id); id = ""; name = "" }
        /^[^[:space:]#]/ {
            flush()
            section = ""
            if ($0 ~ /^"?on"?:/) {
                section = "on"
                rest = $0; sub(/^"?on"?:/, "", rest)
                if (rest ~ /(^|[^A-Za-z0-9_])pull_request([^A-Za-z0-9_]|$)/) pr = 1
            } else if ($0 ~ /^jobs:/) {
                section = "jobs"
            }
            next
        }
        section == "on" && /^  (- )?"?pull_request"?(:|[[:space:]]*$)/ { pr = 1 }
        section == "jobs" && /^  [A-Za-z0-9_-]+:/ {
            flush()
            id = $0; sub(/^  /, "", id); sub(/:.*$/, "", id)
            next
        }
        section == "jobs" && id != "" && /^    name:/ {
            v = $0; sub(/^    name:[[:space:]]*/, "", v)
            name = unquote(v)
        }
        END { flush(); if (pr) for (i = 1; i <= n; i++) print names[i] }
    ' "$1"
}

# name_matches CONTEXT NAME — exit 0 if CONTEXT equals NAME, with every `${{ … }}`
# in NAME matching any text.
name_matches() {
    awk -v ctx="$1" -v name="$2" 'BEGIN {
        nseg = 0
        while ((s = index(name, "${{")) > 0) {
            seg[++nseg] = substr(name, 1, s - 1)
            rest = substr(name, s + 3)
            e = index(rest, "}}")
            if (e == 0) { name = substr(name, s); break }
            name = substr(rest, e + 2)
        }
        seg[++nseg] = name
        if (nseg == 1) exit (ctx == name ? 0 : 1)
        # first segment is a prefix, last a suffix, the middle ones appear in order.
        if (substr(ctx, 1, length(seg[1])) != seg[1]) exit 1
        pos = length(seg[1]) + 1
        for (i = 2; i < nseg; i++) {
            k = index(substr(ctx, pos), seg[i])
            if (k == 0) exit 1
            pos += k - 1 + length(seg[i])
        }
        last = seg[nseg]
        if (length(ctx) - pos + 1 < length(last)) exit 1
        exit (substr(ctx, length(ctx) - length(last) + 1) == last ? 0 : 1)
    }'
}

NAMES=""
for file in "${CHECK_ROOT}"/.github/workflows/*.yml "${CHECK_ROOT}"/.github/workflows/*.yaml; do
    [ -f "${file}" ] || continue
    found=$(pr_job_names "${file}")
    if [ -n "${found}" ]; then
        NAMES="${NAMES}${found}
"
    fi
done

while IFS= read -r ctx; do
    [ -n "${ctx}" ] || continue
    matched=0
    while IFS= read -r job; do
        [ -n "${job}" ] || continue
        if name_matches "${ctx}" "${job}"; then
            matched=1
            break
        fi
    done <<EOF
${NAMES}
EOF
    if [ "${matched}" = 0 ]; then
        check_problem "${RULESET}: required context \"${ctx}\" matches no job in a pull_request-triggered workflow"
    fi
done <<EOF
$(grep -oE '"context"[[:space:]]*:[[:space:]]*"[^"]*"' "${CHECK_ROOT}/${RULESET}" | sed -E 's/^"context"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)
EOF
check_report ERR_CHECK_RULESET_CONTEXT "a required status check would never report on a pull request" \
    "every required context in ${RULESET} to equal a job's \`name:\` (or id) in a .github/workflows/*.yml triggered on pull_request" \
    "rename the context in ${RULESET} to the job's current name, or restore the job (and run \`just ruleset\` after merging if the live ruleset must change)"

check_finish "ruleset-contexts: every required status check names a job that reports on pull requests."
