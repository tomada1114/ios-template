#!/usr/bin/env bash
# Every `just <recipe>` that AGENTS.md names, and every `Bash(just <recipe>…)`
# permission rule in .claude/settings.json, must be a recipe the justfile defines, so
# a renamed or removed recipe cannot leave the agent guide pointing at nothing or the
# Claude Code permission list holding a rule that can never match.
#
#   scripts/checks/just-recipes-exist.sh [--root DIR]
#
# Tokens, read from <root>/AGENTS.md:
#   - inside an inline code span (text between single backticks), every
#     `just <name>` — so `just generate && just build` yields both recipes and
#     `just lint`, then `just test-scripts` yields each one;
#   - inside a fenced code block, the same, on every line (the Quick Reference);
#   - <name> starts with a letter or `_` and continues with letters, digits, `_`,
#     or `-` (just's own recipe-name rule), so `just --list` or a placeholder like
#     `just <recipe>` names no recipe, and `just` must not be the tail of a longer
#     word (`adjust x` is not a token). Prose outside backticks is never read.
# Tokens, read from <root>/.claude/settings.json (Claude Code's permission rules):
#   - every permission rule of the form `Bash(just <name>…)`, wherever it appears in
#     the file, so the `allow`, `ask`, and `deny` lists are all covered. The literal
#     `Bash(` prefix is required, so a `just` call written into a hook's `"command"`
#     string is not a token and is not checked;
#   - <name> follows the same rule-name shape as above, so `Bash(just test-fast:*)`
#     yields `test-fast` and `Bash(just check)` yields `check`.
#   The file is optional: a checkout without it has no permission rule to check, and
#   the AGENTS.md half of this check still runs.
# The recipes are the names `just --summary --justfile <root>/justfile` prints
# (public recipes; `[private]` and `_`-prefixed ones are not listed). A rule or a
# reference naming a private recipe is therefore reported as missing, which is the
# intended answer for AGENTS.md and means a private recipe cannot be permitted by
# name — make the recipe public, or drop the rule. Only AGENTS.md and
# .claude/settings.json are read — CONTRIBUTING.md, README.md, and
# .claude/settings.local.json are not covered.
#
# Requires `just` on PATH (a mise tool: `mise exec -- …` locally, jdx/mise-action
# in CI). Git work tree: not required — the check reads files under --root, which
# defaults to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE           unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING   <root>/AGENTS.md or <root>/justfile does not exist
#   ERR_CHECK_TOOL_MISSING    `just` is not on PATH
#   ERR_CHECK_JUST_FAILED     `just --summary` could not read the justfile
#   ERR_CHECK_RECIPE_MISSING  AGENTS.md names a recipe the justfile does not define
#   ERR_CHECK_PERMISSION_RECIPE_MISSING
#                             .claude/settings.json holds a `Bash(just <recipe>…)`
#                             rule for a recipe the justfile does not define
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/just-recipes-exist.sh" "$@"
check_require_file "AGENTS.md"
check_require_file "justfile"

if ! command -v just >/dev/null 2>&1; then
    check_fail ERR_CHECK_TOOL_MISSING "'just' is not on PATH" \
        "just (pinned in mise.toml) on PATH" "\`command -v just\` found nothing" \
        "run it through mise — \`mise exec -- scripts/checks/just-recipes-exist.sh\` or \`just check-harness\`"
fi

if ! SUMMARY=$(just --summary --justfile "${CHECK_ROOT}/justfile" 2>&1); then
    check_fail ERR_CHECK_JUST_FAILED "\`just --summary\` could not read ${CHECK_ROOT}/justfile" \
        "\`just --summary --justfile ${CHECK_ROOT}/justfile\` to list the recipes" \
        "$(printf '%s\n' "${SUMMARY}" | head -n 1)" \
        "run \`just --summary --justfile ${CHECK_ROOT}/justfile\` and fix the justfile"
fi
RECIPES=" $(printf '%s' "${SUMMARY}" | tr '\n\t' '  ') "

# Prints one `<line>\t<recipe>` per token, in file order.
TOKENS=$(awk '
    function scan(text,    s, tok) {
        s = " " text
        while (match(s, /[^A-Za-z0-9_-]just[ \t]+[A-Za-z_][A-Za-z0-9_-]*/)) {
            tok = substr(s, RSTART + 1, RLENGTH - 1)
            sub(/^just[ \t]+/, "", tok)
            print NR "\t" tok
            s = substr(s, RSTART + RLENGTH)
        }
    }
    /^[ \t]*```/ { fenced = !fenced; next }
    fenced { scan($0); next }
    {
        n = split($0, parts, "`")
        for (i = 2; i <= n; i += 2) scan(parts[i])
    }
' "${CHECK_ROOT}/AGENTS.md")

while IFS="$(printf '\t')" read -r line recipe; do
    [ -n "${recipe}" ] || continue
    case "${RECIPES}" in
        *" ${recipe} "*) ;;
        *) check_problem "AGENTS.md:${line}: \`just ${recipe}\` — no recipe named '${recipe}'" ;;
    esac
done <<EOF
${TOKENS}
EOF

check_report ERR_CHECK_RECIPE_MISSING "AGENTS.md names a just recipe the justfile does not define" \
    "every \`just <recipe>\` in AGENTS.md to be listed by \`just --summary\`" \
    "rename the reference in AGENTS.md to an existing recipe, or add the recipe to the justfile"

SETTINGS=".claude/settings.json"
SETTINGS_SCOPE="there is no ${SETTINGS} to check"
if [ -f "${CHECK_ROOT}/${SETTINGS}" ]; then
    SETTINGS_SCOPE="so does every recipe ${SETTINGS} permits"
    # Prints one `<line>\t<recipe>` per `Bash(just <recipe>` rule, in file order.
    RULE_TOKENS=$(awk '
        {
            s = $0
            while (match(s, /Bash\(just[ \t]+[A-Za-z_][A-Za-z0-9_-]*/)) {
                tok = substr(s, RSTART, RLENGTH)
                sub(/^Bash\(just[ \t]+/, "", tok)
                print NR "\t" tok
                s = substr(s, RSTART + RLENGTH)
            }
        }
    ' "${CHECK_ROOT}/${SETTINGS}")

    while IFS="$(printf '\t')" read -r line recipe; do
        [ -n "${recipe}" ] || continue
        case "${RECIPES}" in
            *" ${recipe} "*) ;;
            *) check_problem "${SETTINGS}:${line}: \`Bash(just ${recipe}…)\` — no recipe named '${recipe}'" ;;
        esac
    done <<EOF
${RULE_TOKENS}
EOF

    check_report ERR_CHECK_PERMISSION_RECIPE_MISSING \
        "${SETTINGS} permits a just recipe the justfile does not define" \
        "every \`Bash(just <recipe>…)\` rule in ${SETTINGS} to name a recipe \`just --summary\` lists" \
        "drop the dead permission rule, rename it to an existing recipe, or add the recipe to the justfile"
fi

check_finish "just-recipes-exist: every just recipe AGENTS.md names exists; ${SETTINGS_SCOPE}."
