#!/usr/bin/env bash
# The gates `just check` runs and the steps CI runs stay the same set, apart from a
# reasoned exception list below, so a gate added to one side cannot silently pass
# locally and fail in CI (or the reverse).
#
#   scripts/checks/just-check-matches-ci.sh [--root DIR]
#
# Files (both required): <root>/justfile and <root>/.github/workflows/ci.yml. CI means
# ci.yml alone — the workflow whose jobs are the merge gate. The other workflows (PR
# title, labels, CodeQL, dependency review, OSV, Scorecard, release) check things no
# local recipe could, and are not compared.
#   - `just check`'s gates: the recipes on the column-0 `check:` line (its
#     dependencies), plus any `just <recipe>` in its indented body. A dependency's own
#     dependencies are not followed.
#   - what a recipe runs: every `scripts/….sh` path in its indented body, so CI calling
#     `scripts/lint.sh` counts as running `just lint` (`mise exec -- scripts/lint.sh`).
#     A recipe that calls no repository script is only seen through `just <recipe>`.
#   - CI's steps: every `run:` value in ci.yml, a single line or a `|`/`>` block (the
#     lines indented deeper than the `run:` key; a line starting with `#` is dropped).
#     A step runs recipe R when it says `just R`, or calls a `scripts/….sh` path some
#     recipe's body calls. `uses:` steps (checkout, setup, upload, zizmor's action) are
#     actions, not steps a recipe could run, and are not compared.
#   Both directions are checked:
#     - every `just check` gate runs in some CI step, unless it is in LOCAL_ONLY;
#     - every CI `run:` step outside a CI_ONLY_JOBS job runs at least one recipe, and
#       every recipe it runs is a `just check` gate or in CI_ONLY.
#   An exception naming a recipe that is no longer on its side (a LOCAL_ONLY recipe
#   `just check` stopped running, a CI_ONLY recipe no CI step runs) is reported as
#   stale, so the list cannot outlive its reason. CI_ONLY_JOBS is not: bootstrap
#   retires its job from an app cut from the template.
#   The parsing is line-based, not YAML- or just-aware: a `run:` in flow style, a
#   recipe line continued with `\`, or a script reached through a variable is not seen.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE               unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING       justfile or .github/workflows/ci.yml does not exist
#   ERR_CHECK_JUST_CI_NO_CHECK    the justfile has no `check:` recipe with a gate
#   ERR_CHECK_JUST_CI_DIVERGED    a gate runs on one side only and is not an exception
#   ERR_CHECK_JUST_CI_STALE       an exception names a recipe no longer on its side
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/just-check-matches-ci.sh" "$@"

JUSTFILE="justfile"
CI=".github/workflows/ci.yml"
check_require_file "${JUSTFILE}"
check_require_file "${CI}"

# The exception list, one reason per entry.
#
# LOCAL_ONLY — `just check` gates CI deliberately does not run:
#   verify-hooks  asserts git runs this checkout's .githooks/; a CI checkout has no
#                 installed hooks (the script skips under CI), and CI runs what the
#                 hook runs, scripts/lint.sh, directly.
#   fmt           rewrites files; CI checks the same formatting read-only through
#                 scripts/lint.sh's `swiftformat --lint` (`just lint`).
#   build         compiles the Debug app for the generic simulator destination; CI's
#                 app job compiles the same Debug app once, through `just uitest-build`
#                 (build-for-testing), rather than twice (#58).
LOCAL_ONLY="verify-hooks fmt build"
# CI_ONLY — recipes CI runs that `just check` deliberately leaves out (the justfile's
# `check` comment: "CI adds uitest, smoke, and test-ios"):
#   uitest-build  compiles the app and the XCUITest runner for a concrete simulator
#                 (`just uitest`'s first half); `just build` already covers a compile
#                 break locally.
#   uitest-run    drives the app on an iOS Simulator through XCUITest (`just uitest`'s
#                 second half); slow.
#   smoke     builds Release and launches it on an iOS Simulator (CI's own `smoke` job,
#             parallel to `app`); slow, and `just build` already covers a compile
#             break locally.
#   test-ios  runs the package tests on an iOS Simulator; `just test` already runs the
#             same suites on the host, so a local `just check` catches everything but
#             iOS-only behavior.
CI_ONLY="uitest-build uitest-run smoke test-ios"
# CI_ONLY_JOBS — whole jobs outside the comparison:
#   bootstrap-smoke  renames a throwaway clone of the template and builds it; it is a
#                    test of scripts/bootstrap.sh, not a gate on this tree, and
#                    bootstrap removes the job from every app cut from the template.
CI_ONLY_JOBS="bootstrap-smoke"

in_list() { # in_list WORD LIST
    case " $2 " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

# recipe_scripts — prints `<recipe> <scripts/….sh>` for every script path in every
# recipe's indented body.
recipe_scripts() {
    awk '
        /^[A-Za-z0-9_-]+([[:space:]]+[^:=]*)?:([^=]|$)/ { r = $0; sub(/[[:space:]:].*$/, "", r); recipe = r; next }
        /^[^[:space:]]/ { recipe = ""; next }
        recipe != "" && /^[[:space:]]+[^[:space:]]/ {
            s = $0
            while (match(s, /scripts\/[A-Za-z0-9_.\/-]+\.sh/)) {
                print recipe, substr(s, RSTART, RLENGTH)
                s = substr(s, RSTART + RLENGTH)
            }
        }
    ' "${CHECK_ROOT}/${JUSTFILE}"
}

# check_gates — prints one recipe per line: `check:`'s dependencies and the
# `just <recipe>` calls in its body.
check_gates() {
    awk '
        function just_calls(s,    n, w, i) {
            gsub(/[;&|()]/, " ", s)
            n = split(s, w, /[[:space:]]+/)
            for (i = 1; i < n; i++) if (w[i] == "just" && w[i + 1] !~ /^-/ && w[i + 1] != "") print w[i + 1]
        }
        /^check([[:space:]]+[^:=]*)?:([^=]|$)/ {
            incheck = 1
            deps = $0; sub(/^[^:]*:/, "", deps); sub(/#.*$/, "", deps)
            n = split(deps, d, /[[:space:]]+/)
            for (i = 1; i <= n; i++) if (d[i] != "") print d[i]
            next
        }
        /^[^[:space:]]/ { incheck = 0 }
        incheck && /^[[:space:]]+[^[:space:]]/ { just_calls($0) }
    ' "${CHECK_ROOT}/${JUSTFILE}"
}

# ci_steps — prints one line per CI `run:` step: `<line>\t<job>\t<run text>`, the
# text of a block step joined with spaces.
ci_steps() {
    awk '
        function indent(s) { match(s, /^ */); return RLENGTH }
        function flush() {
            if (runline != "") printf "%s\t%s\t%s\n", runline, job, text
            runline = ""; text = ""; inblock = 0
        }
        inblock {
            if ($0 ~ /^[[:space:]]*$/) next
            if (indent($0) > key) {
                if ($0 !~ /^[[:space:]]*#/) text = text " " $0
                next
            }
            flush()
        }
        /^[^[:space:]#]/ { flush(); injobs = ($0 ~ /^jobs:/); job = ""; next }
        injobs && /^  [A-Za-z0-9_-]+:/ { flush(); job = $0; sub(/^  /, "", job); sub(/:.*$/, "", job); next }
        injobs && job != "" && /^[[:space:]]*(- )?run:/ {
            flush()
            v = $0; sub(/^[[:space:]]*(- )?run:[[:space:]]*/, "", v)
            if (v ~ /^(#.*)?$/) next # a `defaults: run:` mapping, not a step
            runline = NR
            if (v ~ /^[|>][-+0-9]*[[:space:]]*(#.*)?$/) {
                inblock = 1
                key = indent($0); if ($0 ~ /^[[:space:]]*- /) key += 2
            } else {
                text = v
                flush()
            }
        }
        END { flush() }
    ' "${CHECK_ROOT}/${CI}"
}

# step_recipes TEXT — prints the recipes a step runs, one per line, or
# `script:<path>` for a repository script no recipe calls.
step_recipes() {
    local text="$1" word prev="" path found
    for word in $(printf '%s\n' "${text}" | tr ';&|()' '     '); do
        if [ "${prev}" = "just" ]; then
            case "${word}" in
                -*) ;;
                *) echo "${word}" ;;
            esac
        fi
        prev="${word}"
    done
    { printf '%s\n' "${text}" | grep -oE 'scripts/[A-Za-z0-9_./-]+\.sh' || true; } | while IFS= read -r path; do
        found=$(printf '%s\n' "${RECIPE_SCRIPTS}" | awk -v p="${path}" '$2 == p { print $1 }')
        if [ -n "${found}" ]; then
            printf '%s\n' "${found}"
        else
            echo "script:${path}"
        fi
    done
}

set -f # the word splitting below must not glob
RECIPE_SCRIPTS=$(recipe_scripts)
GATES=$(check_gates | LC_ALL=C sort -u)
STEPS=$(ci_steps)

if [ -z "${GATES}" ]; then
    check_fail ERR_CHECK_JUST_CI_NO_CHECK "${JUSTFILE} has no \`check\` recipe with a gate" \
        "a column-0 \`check: <recipe> …\` line in ${JUSTFILE}" \
        "no \`check:\` line with a dependency or a \`just <recipe>\` in its body" \
        "restore the \`check\` recipe, or update scripts/checks/just-check-matches-ci.sh in the same change"
fi

# Every recipe some non-excepted CI step runs, one per line.
CI_RECIPES=""
while IFS="$(printf '\t')" read -r line job text; do
    [ -n "${line}" ] || continue
    in_list "${job}" "${CI_ONLY_JOBS}" && continue
    ran=$(step_recipes "${text}" | LC_ALL=C sort -u)
    if [ -z "${ran}" ]; then
        check_problem "${CI}:${line}: job \`${job}\` runs a step that calls no \`just\` recipe and no repository script: ${text}"
        continue
    fi
    for recipe in ${ran}; do
        case "${recipe}" in
            script:*)
                check_problem "${CI}:${line}: job \`${job}\` runs ${recipe#script:}, which no ${JUSTFILE} recipe calls"
                continue
                ;;
        esac
        CI_RECIPES="${CI_RECIPES}${recipe}
"
        if ! grep -qxF -- "${recipe}" <<<"${GATES}" && ! in_list "${recipe}" "${CI_ONLY}"; then
            check_problem "${CI}:${line}: job \`${job}\` runs \`just ${recipe}\` (or its script), which \`just check\` does not run"
        fi
    done
done <<EOF
${STEPS}
EOF

for gate in ${GATES}; do
    in_list "${gate}" "${LOCAL_ONLY}" && continue
    if ! grep -qxF -- "${gate}" <<<"${CI_RECIPES}"; then
        check_problem "${JUSTFILE}: \`just check\` runs \`just ${gate}\`, but no ${CI} step runs it or a script its recipe calls"
    fi
done
check_report ERR_CHECK_JUST_CI_DIVERGED "\`just check\` and CI run different gates" \
    "every \`just check\` gate run by a ${CI} step (as \`just <recipe>\` or the scripts/….sh its recipe calls), and every CI step to run only \`just check\` gates, apart from the exceptions in scripts/checks/just-check-matches-ci.sh" \
    "add the gate to the side that lacks it — a CI step calls the same script or \`just <recipe>\`, and a new local gate joins \`check:\` — or, if it genuinely belongs on one side only, add it with its reason to LOCAL_ONLY or CI_ONLY in scripts/checks/just-check-matches-ci.sh"

for recipe in ${LOCAL_ONLY}; do
    if ! grep -qxF -- "${recipe}" <<<"${GATES}"; then
        check_problem "LOCAL_ONLY names \`${recipe}\`, which \`just check\` no longer runs"
    fi
done
for recipe in ${CI_ONLY}; do
    if ! grep -qxF -- "${recipe}" <<<"${CI_RECIPES}"; then
        check_problem "CI_ONLY names \`${recipe}\`, which no ${CI} step runs any more"
    fi
done
check_report ERR_CHECK_JUST_CI_STALE "an exception in scripts/checks/just-check-matches-ci.sh has outlived its reason" \
    "every LOCAL_ONLY recipe to be a \`just check\` gate and every CI_ONLY recipe to be run by a ${CI} step" \
    "remove the stale entry (and its reason) from scripts/checks/just-check-matches-ci.sh"

check_finish "just-check-matches-ci: \`just check\` and ${CI} run the same gates, apart from the listed exceptions."
