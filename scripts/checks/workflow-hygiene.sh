#!/usr/bin/env bash
# Every GitHub Actions workflow grants write access only to the job that needs it,
# cancels superseded pull request runs without cancelling runs that must finish, and
# runs every `run:` step in a shell that stops at the first failure — pipelines
# included.
#
#   scripts/checks/workflow-hygiene.sh [--root DIR]
#
# Files: <root>/.github/workflows/*.yml|*.yaml, and for the shell rule also
# <root>/.github/actions/*/action.yml|action.yaml (either directory may be absent).
# Each file is read through check_yaml_flatten (scripts/checks/lib.sh).
#   - permissions: the top-level `permissions:` grants no `write` scope and is not the
#     `read-all`/`write-all` shorthand, so a write reaches only the job that declares
#     it; no job uses the shorthand either. A missing top-level key is
#     workflow-pins-and-permissions.sh's to report.
#   - concurrency: a workflow triggered by `pull_request` or `pull_request_target` has
#     a top-level `concurrency:`. Wherever one is declared:
#       - its group names something that differs between runs — a constant group makes
#         every run queue behind one another, and GitHub drops all but the newest
#         pending run. `github.ref`, `github.ref_name`, `github.sha`, `github.run_id`,
#         and `github.run_number` count for any trigger; `github.head_ref`,
#         `github.event.number`, and `github.event.pull_request.…` only when every
#         trigger is a pull request event, because they are empty on a push or a
#         schedule (write `${{ github.head_ref || github.run_id }}` to mix them);
#       - a group that does not mention `github.workflow` is unique to its file, or
#         two workflows cancel or queue behind each other;
#       - a workflow triggered by `push` never cancels a push run: its
#         `cancel-in-progress:` is absent, `false`, or an expression testing
#         `github.event_name == 'pull_request'` (or `pull_request_target`) or
#         `github.event_name != 'push'`, as ci.yml does.
#     Job-level `concurrency:` is not checked.
#   - fail-closed shells, for the sh family only (`sh`, `bash`, `dash`, `ksh`, `zsh`,
#     by the first word's basename; `pwsh`, `python`, and other interpreters are
#     outside this rule): every such `shell:` (a workflow's or job's
#     `defaults.run.shell`, or a step's) is `bash` — which GitHub runs as
#     `bash --noprofile --norc -eo pipefail {0}` — or a custom `bash … {0}` template
#     that sets errexit (`-e` or `-o errexit`) and `pipefail`. Every `run:` step
#     resolves to an explicit shell (step, then job defaults, then workflow
#     defaults), or its first line that is not a comment is a `set` enabling
#     `pipefail` (and not turning errexit off): a step with no explicit shell runs as
#     `bash -e {0}` on a Linux or macOS runner, where a failing command before a `|`
#     goes unnoticed. The check assumes those runners; a Windows job's implicit shell
#     is pwsh, and naming it is enough.
#   The reading is line-based, not a YAML parser (see check_yaml_flatten). A one-line
#   flow `on:` (`on: [push, pull_request]`, `on: {pull_request: {}}`) is read for its
#   event names; any other setting spelled as a flow collection — a
#   `defaults: { run: { shell: bash } }`, a `concurrency: { group: … }` — is not seen,
#   so write those in block style.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE                     unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_WORKFLOW_PERMISSION_SCOPE a write scope or a `read-all`/`write-all` shorthand is granted too widely
#   ERR_CHECK_WORKFLOW_CONCURRENCY      a pull request workflow has no concurrency, or a concurrency setting is unsafe
#   ERR_CHECK_WORKFLOW_SHELL            a `shell:` is not fail-closed, or a `run:` step has no fail-closed shell
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/workflow-hygiene.sh" "$@"

# analyze FILE REL — prints one `<PERM|CONC|SHELL>\t<problem>` row per finding in
# FILE (named REL in messages), plus a `GROUP\t<group>\t<where>` row for each
# concurrency group that does not mention github.workflow (compared across files
# below).
analyze() {
    check_yaml_flatten "$1" | awk -F '\t' -v f="$2" '
    # add_events(v) — records the event names of a one-line `on:` value: a scalar,
    # a flow list, or a flow mapping (its top-level keys; nested values skipped).
    function add_event(e) {
        sub(/:.*$/, "", e)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", e)
        gsub(/^"|"$/, "", e)
        gsub(/^\047|\047$/, "", e)
        if (e != "") ev[e] = 1
    }
    function add_events(v,    i, c, depth, item) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if (v ~ /^[[{]/) v = substr(v, 2, length(v) - 2)
        depth = 0; item = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "{" || c == "[") depth++
            else if (c == "}" || c == "]") depth--
            if (c == "," && depth == 0) { add_event(item); item = ""; continue }
            if (depth == 0) item = item c
        }
        add_event(item)
    }
    function sh_family(v,    w) {
        w = v; sub(/[[:space:]].*$/, "", w); sub(/^.*\//, "", w)
        return w ~ /^(sh|bash|dash|ksh|zsh)$/
    }
    function errexit(s) { return s ~ /[[:space:]]-[A-Za-z]*e/ || s ~ /-o[[:space:]]+errexit/ }
    function pipefail(s) { return s ~ /-[A-Za-z]*o[[:space:]]+pipefail/ }
    function fail_closed_shell(v,    w) {
        w = v; sub(/[[:space:]].*$/, "", w); sub(/^.*\//, "", w)
        return v == "bash" || (w == "bash" && errexit(v) && pipefail(v) && v ~ /\{0\}/)
    }
    # The implicit shell is already `bash -e {0}`: a leading `set` needs only to add
    # pipefail, and must not switch errexit back off.
    function fail_closed_set(s) {
        return s ~ /^set[[:space:]]/ && pipefail(s) && s !~ /[[:space:]]\+[A-Za-z]*e/ && s !~ /\+o[[:space:]]+errexit/
    }
    function shell_value(line, v) {
        if (sh_family(v) && !fail_closed_shell(v)) print "SHELL\t" f ":" line ": `shell: " v "` does not stop at a failing command (`-e`) or a failing pipeline stage (`pipefail`)"
    }
    function step_key(p) { sub(/\.(run|shell)(\.\|)?$/, "", p); return p }
    { line = $1; p = $2; v = $3 }

    p == "permissions" && (v == "read-all" || v == "write-all") {
        print "PERM\t" f ":" line ": top-level `permissions: " v "` grants every scope to every job"
    }
    p == "permissions" && v ~ /:[[:space:]]*write/ {
        print "PERM\t" f ":" line ": top-level `permissions: " v "` grants a write scope to every job"
    }
    p ~ /^permissions\.[^.]+$/ && v == "write" {
        print "PERM\t" f ":" line ": top-level `" substr(p, 13) ": write` is granted to every job"
    }
    p ~ /^jobs\.[^.]+\.permissions$/ && (v == "read-all" || v == "write-all") {
        print "PERM\t" f ":" line ": job `" substr(p, 6, length(p) - 17) "` uses `permissions: " v "`, which grants every scope"
    }

    p == "on" && v != "" { add_events(v) }
    p ~ /^on\.[^.]+$/ { k = substr(p, 4); if (k ~ /^[0-9]+$/) add_events(v); else ev[k] = 1 }

    p == "concurrency" { hasconc = 1; concline = line; if (v != "") { group = v; groupline = line } }
    p == "concurrency.group" { group = v; groupline = line }
    p == "concurrency.cancel-in-progress" { cancel = v; cancelline = line }

    p == "defaults.run.shell" { wfshell = v; shell_value(line, v) }
    p ~ /^jobs\.[^.]+\.defaults\.run\.shell$/ {
        split(p, parts, "."); jobshell[parts[2]] = v; shell_value(line, v)
    }
    p ~ /^(jobs\.[^.]+|runs)\.steps\.[0-9]+\.shell$/ { stepshell[step_key(p)] = v; shell_value(line, v) }
    p ~ /^(jobs\.[^.]+|runs)\.steps\.[0-9]+\.run$/ {
        k = step_key(p); nruns++; runs[nruns] = k; runline[k] = line
        if (v !~ /^[|>]/) first[k] = v
    }
    p ~ /^(jobs\.[^.]+|runs)\.steps\.[0-9]+\.run\.\|$/ {
        k = step_key(p); if (!(k in first) && v !~ /^#/) first[k] = v
    }

    END {
        for (i = 1; i <= nruns; i++) {
            k = runs[i]
            job = ""
            if (k ~ /^jobs\./) { split(k, parts, "."); job = parts[2] }
            if ((k in stepshell) || (job != "" && (job in jobshell)) || wfshell != "") continue
            if (!fail_closed_set(first[k])) {
                where = (job == "" ? "a composite step" : "job `" job "`")
                print "SHELL\t" f ":" runline[k] ": a `run:` step in " where " names no shell, so it runs as `bash -e {0}` without `pipefail`"
            }
        }

        pr = ("pull_request" in ev) || ("pull_request_target" in ev)
        pr_only = pr
        for (e in ev) if (e != "pull_request" && e != "pull_request_target") pr_only = 0
        if (pr && !hasconc) print "CONC\t" f ": runs on pull requests but has no top-level `concurrency:`, so a superseded run keeps its runner until it finishes"
        if (!hasconc) exit
        if (group == "") {
            print "CONC\t" f ":" concline ": `concurrency:` has no `group:`"
        } else if (group !~ /github\.(ref|ref_name|sha|run_id|run_number)([^A-Za-z0-9_.]|$)/) {
            if (pr_only && group ~ /github\.(head_ref([^A-Za-z0-9_.]|$)|event\.number([^A-Za-z0-9_.]|$)|event\.pull_request\.)/) {
                # keyed by the pull request: fine while nothing else triggers the workflow
            } else if (group ~ /github\.(head_ref([^A-Za-z0-9_.]|$)|event\.number([^A-Za-z0-9_.]|$)|event\.pull_request\.)/) {
                print "CONC\t" f ":" groupline ": group `" group "` is keyed by the pull request, which is empty for the workflow\047s other triggers, so their runs share one group"
            } else {
                print "CONC\t" f ":" groupline ": group `" group "` is the same for every run, so runs queue behind one another and all but the newest pending one are dropped"
            }
        }
        if ("push" in ev) {
            if (cancel == "true") {
                print "CONC\t" f ":" cancelline ": `cancel-in-progress: true` on a push-triggered workflow lets a newer push cancel the run of an earlier one"
            } else if (index(cancel, "{{") > 0 && cancel !~ /github\.event_name[[:space:]]*==[[:space:]]*(\047|")pull_request(_target)?(\047|")/ && cancel !~ /github\.event_name[[:space:]]*!=[[:space:]]*(\047|")push(\047|")/) {
                print "CONC\t" f ":" cancelline ": `cancel-in-progress: " cancel "` on a push-triggered workflow is not limited to pull request runs (`github.event_name == \047pull_request\047`), so it may cancel a push run"
            }
        }
        if (group != "" && group !~ /github\.workflow/) print "GROUP\t" group "\t" f ":" groupline
    }
'
}

FILES=()
for file in "${CHECK_ROOT}"/.github/workflows/*.yml "${CHECK_ROOT}"/.github/workflows/*.yaml \
    "${CHECK_ROOT}"/.github/actions/*/action.yml "${CHECK_ROOT}"/.github/actions/*/action.yaml; do
    if [ -f "${file}" ]; then FILES+=("${file}"); fi
done

FINDINGS=""
for file in ${FILES[@]+"${FILES[@]}"}; do
    rows=$(check_read "${file#"${CHECK_ROOT}"/}" analyze "${file}" "${file#"${CHECK_ROOT}"/}")
    if [ -n "${rows}" ]; then
        FINDINGS="${FINDINGS}${rows}
"
    fi
done

# report_category CATEGORY — records every finding of that category as a problem.
report_category() {
    local category text
    while IFS="$(printf '\t')" read -r category text; do
        if [ "${category}" = "$1" ]; then check_problem "${text}"; fi
    done <<EOF
${FINDINGS}
EOF
}

report_category PERM
check_report ERR_CHECK_WORKFLOW_PERMISSION_SCOPE "a workflow grants permissions wider than the job that needs them" \
    "a top-level \`permissions:\` of read or none scopes only (e.g. \`contents: read\`, or \`{}\`), each \`write\` on the job that needs it, and no \`read-all\`/\`write-all\`" \
    "move each write scope into the \`permissions:\` block of the job that uses it, and spell a shorthand out as the scopes the jobs actually read"

report_category CONC
# Two files sharing one group (that does not include github.workflow) cancel or queue
# behind each other's runs.
DUPLICATES=$(printf '%s' "${FINDINGS}" | awk -F '\t' '
    $1 != "GROUP" { next }
    ($2 in first) { print $3 ": group `" $2 "` is also used by " first[$2] ", so the two workflows queue behind or cancel each other"; next }
    { first[$2] = $3 }
')
while IFS= read -r text; do
    if [ -n "${text}" ]; then check_problem "${text}"; fi
done <<EOF
${DUPLICATES}
EOF
check_report ERR_CHECK_WORKFLOW_CONCURRENCY "a workflow's concurrency is missing or unsafe" \
    "a top-level \`concurrency:\` on every pull request workflow, a group keyed per run (\`\${{ github.workflow }}-\${{ github.ref }}\`), and no in-progress cancel a push run could trigger" \
    "copy ci.yml's \`concurrency:\` block (group on github.workflow plus the ref, cancel only when \`github.event_name == 'pull_request'\`), or key the group to what must not overlap"

report_category SHELL
check_report ERR_CHECK_WORKFLOW_SHELL "a workflow step does not run in a fail-closed shell" \
    "every sh-family \`shell:\` to be \`bash\` (or a \`bash … {0}\` template with -e and pipefail), and every \`run:\` step to resolve to an explicit shell (step, job, or workflow \`defaults.run.shell\`) or to start with \`set -euo pipefail\`" \
    "add a top-level block-style \`defaults:\` key to the workflow — \`defaults:\`, then \`  run:\`, then \`    shell: bash\`, one per line (a flow mapping is not read) — give a composite step \`shell: bash\`, or start the script with \`set -euo pipefail\`"

check_finish "workflow-hygiene: write permissions are job-level, concurrency is safe, and every run: step fails closed."
