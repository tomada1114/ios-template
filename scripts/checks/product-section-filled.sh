#!/usr/bin/env bash
# AGENTS.md's `## Product` section is the one part of that file about the application
# rather than the harness: what the app is, who it is for, and above all what it
# deliberately is not. In the template it is a skeleton of `TODO:` markers; in a
# repository the rename has already turned into an app, a surviving marker means the
# agent instructions still carry no product context, so "is this in scope?" has no
# in-repo answer and a non-goal is whatever the implementer assumes.
#
#   scripts/checks/product-section-filled.sh [--root DIR]
#
# The section is the lines of <root>/AGENTS.md after a line that is exactly
# `## Product`, up to (not including) the next `## ` heading. Which repository this is
# comes from <root>/project.yml: while it still names the template's app-name
# placeholder, the rename has not run and this is the template itself. Both directions
# are checked, as one invariant:
#   - the `## Product` section exists and names its `**Non-goals**` — in either
#     repository;
#   - template (project.yml still holds the placeholder): at least one `TODO:` marker,
#     so filling the skeleton in *here* cannot quietly make the rule below vacuous for
#     every app cut from the template afterwards;
#   - app (the placeholder is gone): no `TODO:` marker at all.
# Nothing here can judge prose: the marker is the whole signal, and whether what
# replaced it is true stays with the human who wrote it.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE            unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING    <root>/AGENTS.md or <root>/project.yml does not exist
#   ERR_CHECK_PRODUCT_SECTION  the section is absent, does not name its non-goals, or
#                              its `TODO:` markers disagree with which repository this is
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/product-section-filled.sh" "$@"
check_require_file "AGENTS.md"
check_require_file "project.yml"

# Quote-split exactly as scripts/bootstrap.sh splits its own PH_* literals: this
# script is a tracked text file too, and the rename must not rewrite the very literal
# whose absence tells the check that the rename has happened.
PLACEHOLDER_NAME='My''App'
# The colon is part of the marker: a bare `TODO` would also reject an app whose
# product genuinely mentions a to-do list or points at a `docs/TODO.md`.
MARKER='TODO:'

# `<line>\t<text>` per line of the section, or the single line `NO_SECTION`.
SECTION=$(awk '
    /^## Product[ \t]*$/ { found = 1; in_section = 1; next }
    in_section && /^## / { exit }
    in_section { print NR "\t" $0 }
    END { if (!found) print "NO_SECTION" }
' "${CHECK_ROOT}/AGENTS.md")

HAVE_SECTION=1
if [ "${SECTION}" = "NO_SECTION" ]; then
    HAVE_SECTION=0
    SECTION=""
    check_problem "AGENTS.md: no \`## Product\` section (the heading must be exactly \`## Product\`)"
fi

MODE="an app"
if grep -qF -- "${PLACEHOLDER_NAME}" "${CHECK_ROOT}/project.yml"; then
    MODE="the template"
fi

if [ "${HAVE_SECTION}" = 1 ]; then
    if ! grep -qF -- "Non-goals" <<<"${SECTION}"; then
        check_problem "AGENTS.md: the \`## Product\` section does not name its \`**Non-goals**\`"
    fi

    MARKER_LINES=$(printf '%s\n' "${SECTION}" | grep -F -- "${MARKER}" || true)
    if [ "${MODE}" = "the template" ]; then
        if [ -z "${MARKER_LINES}" ]; then
            check_problem "AGENTS.md: the \`## Product\` section holds no \`${MARKER}\` marker, but project.yml still names the template's app-name placeholder — in the template the section stays a skeleton"
        fi
    else
        while IFS="$(printf '\t')" read -r line text; do
            [ -n "${line}" ] || continue
            check_problem "AGENTS.md:${line}: a \`${MARKER}\` marker survived the rename: ${text}"
        done <<EOF
${MARKER_LINES}
EOF
    fi
fi

check_report ERR_CHECK_PRODUCT_SECTION "AGENTS.md's \`## Product\` section does not match this repository (${MODE})" \
    "a \`## Product\` section naming its \`**Non-goals**\`, left as a \`${MARKER}\` skeleton in the template and holding no \`${MARKER}\` once scripts/bootstrap.sh has renamed it into an app" \
    "write AGENTS.md's \`## Product\` section for this app — what it is and who for, the core interaction, its non-goals, and where those decisions are recorded — and delete every \`${MARKER}\` marker (README.md's \"Using This Template\", step 3)"
check_finish "product-section-filled: AGENTS.md's Product section matches ${MODE}."
