#!/usr/bin/env bash
# Every label an issue form, a workflow, a dependency bot, or scripts/label-pr.sh
# applies is declared in .github/labels.yml, and no label is declared there twice — so `just labels` creates
# every label something in the repository expects to exist, and never with two
# conflicting colors or descriptions.
#
#   scripts/checks/labels-declared.sh [--root DIR]
#
# Files: <root>/.github/labels.yml (required), and whichever of these exist:
#   - declared: every `- name: <label>` item in labels.yml (quotes stripped, a trailing
#     ` # …` comment dropped). GitHub treats label names case-insensitively, so two
#     names differing only in case count as a duplicate.
#   - .github/ISSUE_TEMPLATE/*.yml|*.yaml: the column-0 `labels:` key — a flow list
#     (`labels: ["bug"]`), a comma-separated string (`labels: bug, chore`), or a block
#     list of `- <label>` items directly under it.
#   - .github/workflows/*.yml|*.yaml: a literal label after `--add-label` or `--label`
#     (`gh pr edit --add-label ci`, comma-separated values split), and a literal assigned
#     to a shell variable named `label` or `labels`, any case (`feat) label=enhancement
#     ;;`, pr-label.yml's mapping). A value starting with `$` is a variable, not a
#     label, and is skipped; a label computed any other way is not seen.
#   - .github/dependabot.yml: each `updates:` entry (a two-space-indented `  - ` item)
#     with a `labels:` key contributes its flow list, or the `- <label>` items directly
#     under the key (indented at least as deep as it). An entry with no `labels:` key gets
#     Dependabot's default instead, `dependencies` plus an ecosystem label
#     (`github_actions`, `swift`); the check requires `dependencies` to be declared for
#     such an entry, and not the ecosystem label, which Dependabot creates itself and
#     labels.yml deliberately leaves repository-local. `labels: []` applies none.
#   - renovate.json and .github/renovate.json: every string in a `"labels"` or
#     `"addLabels"` array (one line or several, no nested arrays). Renovate applies no
#     label by default.
#   - scripts/label-pr.sh: its type-to-label mapping, read with the workflow parser
#     above (`feat) label=enhancement ;;`), so every label a PR title can map to is
#     declared before the script ever reports ERR_LABELPR_UNDECLARED on a live PR.
#   Matching is exact (case included). The parsing is line-based, not YAML- or
#   JSON-aware; .github/release.yml, which reads labels rather than applying them, is
#   not compared.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE              unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING      .github/labels.yml does not exist
#   ERR_CHECK_LABEL_DUPLICATE    a label is declared more than once in labels.yml
#   ERR_CHECK_LABEL_UNDECLARED   a label something applies is not declared in labels.yml
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/labels-declared.sh" "$@"

LABELS=".github/labels.yml"
check_require_file "${LABELS}"

# The awk helpers every parser below shares: clean(v) strips a trailing comment,
# surrounding whitespace, and one pair of matching quotes; flow(v, where) prints each
# item of a `[a, "b"]` list or a comma-separated string.
AWK_LIB='
    function clean(v) {
        sub(/[[:space:]]+#.*$/, "", v)
        sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
        if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
        return v
    }
    function flow(v, where,    n, parts, i, item) {
        sub(/[[:space:]]+#.*$/, "", v)
        sub(/^[[:space:]]*\[/, "", v); sub(/\][[:space:]]*$/, "", v)
        n = split(v, parts, ",")
        for (i = 1; i <= n; i++) { item = clean(parts[i]); if (item != "") print where "\t" item }
    }
'

# declared_labels — prints `<line>\t<name>` for every `- name:` item.
declared_labels() {
    awk "${AWK_LIB}"'
        /^[[:space:]]*-[[:space:]]+name:/ { v = $0; sub(/^[[:space:]]*-[[:space:]]+name:/, "", v); print NR "\t" clean(v) }
    ' "${CHECK_ROOT}/${LABELS}"
}

# form_labels REL — prints `<REL:line>\t<label>` for an issue form's `labels:`.
form_labels() {
    awk -v f="$1" "${AWK_LIB}"'
        inlist && /^[[:space:]]*-[[:space:]]*/ { v = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", v); v = clean(v); if (v != "") print f ":" NR "\t" v; next }
        inlist && /^[[:space:]]*(#.*)?$/ { next }
        { inlist = 0 }
        /^labels:/ {
            v = $0; sub(/^labels:[[:space:]]*/, "", v)
            if (v ~ /^(#.*)?$/) inlist = 1
            else flow(v, f ":" NR)
        }
    ' "${CHECK_ROOT}/$1"
}

# workflow_labels REL — prints `<REL:line>\t<label>` for literal labels a workflow
# passes to `--add-label`/`--label` or assigns to a `label`/`labels` variable.
workflow_labels() {
    awk -v f="$1" "${AWK_LIB}"'
        function value(s,    v) {
            if (s ~ /^"/) { v = substr(s, 2); sub(/".*$/, "", v) }
            else if (s ~ /^\047/) { v = substr(s, 2); sub(/\047.*$/, "", v) }
            else { v = s; sub(/[[:space:];)|&].*$/, "", v) }
            return v
        }
        function emit(v,    n, parts, i, item) {
            if (v == "" || v ~ /^\$/) return
            n = split(v, parts, ",")
            for (i = 1; i <= n; i++) { item = clean(parts[i]); if (item != "" && item !~ /^\$/) print f ":" NR "\t" item }
        }
        {
            s = $0
            while (match(s, /--(add-)?label([[:space:]]+|=)/)) {
                s = substr(s, RSTART + RLENGTH)
                emit(value(s))
            }
            s = $0
            while (match(s, /(^|[^A-Za-z0-9_$])[Ll][Aa][Bb][Ee][Ll][Ss]?=/)) {
                s = substr(s, RSTART + RLENGTH)
                emit(value(s))
            }
        }
    ' "${CHECK_ROOT}/$1"
}

# dependabot_labels REL — prints `<REL:line>\t<label>` for each updates entry's
# labels, or the implied `dependencies` for an entry without a `labels:` key.
dependabot_labels() {
    awk -v f="$1" "${AWK_LIB}"'
        function indent(s) { match(s, /^ */); return RLENGTH }
        function close_entry() { if (entry && !haslabels) print f ":" entry "\tdependencies\t(Dependabot default, no labels: key)"; entry = 0; haslabels = 0; inlist = 0 }
        /^[^[:space:]#]/ { close_entry(); inupdates = ($0 ~ /^updates:/); next }
        !inupdates { next }
        /^  -[[:space:]]/ { close_entry(); entry = NR; next }
        inlist && indent($0) >= lkey && /^[[:space:]]+-[[:space:]]*/ { v = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", v); v = clean(v); if (v != "") print f ":" NR "\t" v; next }
        inlist && /^[[:space:]]*(#.*)?$/ { next }
        { inlist = 0 }
        entry && /^[[:space:]]+labels:/ {
            haslabels = 1
            lkey = indent($0)
            v = $0; sub(/^[[:space:]]+labels:[[:space:]]*/, "", v)
            if (v ~ /^(#.*)?$/) inlist = 1
            else flow(v, f ":" NR)
        }
        END { close_entry() }
    ' "${CHECK_ROOT}/$1"
}

# renovate_labels REL — prints `<REL:line>\t<label>` for every string in a
# `"labels"`/`"addLabels"` array.
renovate_labels() {
    awk -v f="$1" '
        function strings(s) {
            while (match(s, /"[^"]*"/)) {
                print f ":" NR "\t" substr(s, RSTART + 1, RLENGTH - 2)
                s = substr(s, RSTART + RLENGTH)
            }
        }
        {
            s = $0
            if (!inarr) {
                if (!match(s, /"(labels|addLabels)"[[:space:]]*:[[:space:]]*\[/)) next
                inarr = 1
                s = substr(s, RSTART + RLENGTH)
            }
            end = index(s, "]")
            if (end > 0) s = substr(s, 1, end - 1)
            strings(s)
            if (end > 0) inarr = 0
        }
    ' "${CHECK_ROOT}/$1"
}

DECLARED=$(declared_labels)

# Duplicates, case-insensitively.
DUPES=$(printf '%s\n' "${DECLARED}" | awk -F '\t' '
    $2 == "" { next }
    { k = tolower($2); if (k in first) print first[k] "\t" $1 "\t" $2; else first[k] = $1 }
')
while IFS="$(printf '\t')" read -r first line name; do
    [ -n "${line}" ] || continue
    check_problem "${LABELS}:${line}: \`${name}\` is already declared at line ${first}"
done <<EOF
${DUPES}
EOF
check_report ERR_CHECK_LABEL_DUPLICATE "a label is declared more than once" \
    "each label name to appear in exactly one \`- name:\` item of ${LABELS} (GitHub compares names case-insensitively)" \
    "merge the duplicate items into one, keeping the color and description you mean"

APPLIED=""
add_applied() {
    [ -n "$1" ] || return 0
    APPLIED="${APPLIED}$1
"
}
for file in "${CHECK_ROOT}"/.github/ISSUE_TEMPLATE/*.yml "${CHECK_ROOT}"/.github/ISSUE_TEMPLATE/*.yaml; do
    [ -f "${file}" ] || continue
    add_applied "$(form_labels "${file#"${CHECK_ROOT}"/}")"
done
for file in "${CHECK_ROOT}"/.github/workflows/*.yml "${CHECK_ROOT}"/.github/workflows/*.yaml; do
    [ -f "${file}" ] || continue
    add_applied "$(workflow_labels "${file#"${CHECK_ROOT}"/}")"
done
if [ -f "${CHECK_ROOT}/.github/dependabot.yml" ]; then
    add_applied "$(dependabot_labels .github/dependabot.yml)"
fi
if [ -f "${CHECK_ROOT}/scripts/label-pr.sh" ]; then
    add_applied "$(workflow_labels scripts/label-pr.sh)"
fi
for rel in renovate.json .github/renovate.json; do
    if [ -f "${CHECK_ROOT}/${rel}" ]; then
        add_applied "$(renovate_labels "${rel}")"
    fi
done

DECLARED_NAMES=$(printf '%s\n' "${DECLARED}" | cut -f 2)
while IFS="$(printf '\t')" read -r where label note; do
    [ -n "${label}" ] || continue
    if ! grep -qxF -- "${label}" <<<"${DECLARED_NAMES}"; then
        check_problem "${where}: applies \`${label}\`${note:+ ${note}}, which ${LABELS} does not declare"
    fi
done <<EOF
${APPLIED}
EOF
check_report ERR_CHECK_LABEL_UNDECLARED "a label is applied but not declared" \
    "every label an issue form, workflow, dependency bot, or scripts/label-pr.sh applies to be a \`- name:\` in ${LABELS}" \
    "declare the label in ${LABELS} (name, color, description), or change the file that applies it to a declared label; then \`just labels\` creates it"

check_finish "labels-declared: every applied label is declared once in ${LABELS}."
