#!/usr/bin/env bash
# AGENTS.md's Skills table and the skills under .agents/skills/ name the same set,
# in both directions: a skill with no row is never discovered by an agent reading
# the index, and a row with no skill points at nothing.
#
#   scripts/checks/skills-index-complete.sh [--root DIR]
#
# The index is the first Markdown table (a run of lines starting with `|`) after
# the `## Skills` heading of <root>/AGENTS.md and before the next heading of any
# level — so the `.claude/rules/` table under its own `### Rules` subheading is
# never read. Its header row and `|---|` separator row are skipped; each other row's
# first cell, with backticks and surrounding spaces stripped, is a skill name. The
# directories are the entries directly under <root>/.agents/skills/.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE          unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING  <root>/AGENTS.md or <root>/.agents/skills/ does not exist
#   ERR_CHECK_SKILL_INDEX    no Skills table was found, a name appears twice in it,
#                            or the table and the directories disagree
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/skills-index-complete.sh" "$@"
check_require_file "AGENTS.md"
check_require_file ".agents/skills"

# Prints `<line>\t<name>` for each data row of the first table under `## Skills`,
# or the single line `NO_TABLE` when there is no such table.
ROWS=$(awk '
    /^## Skills[ \t]*$/ { in_section = 1; next }
    in_section && /^#/ { exit }
    in_section && /^[|]/ {
        in_table = 1
        rows++
        if (rows == 1 || $0 ~ /^[|][ \t:|-]*$/) next
        cell = $0
        sub(/^[|]/, "", cell); sub(/[|].*/, "", cell)
        gsub(/`/, "", cell); sub(/^[ \t]+/, "", cell); sub(/[ \t]+$/, "", cell)
        print NR "\t" cell
        next
    }
    in_table { exit }
    END { if (!in_table) print "NO_TABLE" }
' "${CHECK_ROOT}/AGENTS.md")

if [ "${ROWS}" = "NO_TABLE" ]; then
    check_problem "AGENTS.md: no table under a \`## Skills\` heading"
    ROWS=""
fi

INDEXED=" "
while IFS="$(printf '\t')" read -r line name; do
    [ -n "${line}" ] || continue
    if [ -z "${name}" ]; then
        check_problem "AGENTS.md:${line}: a Skills table row has an empty first cell"
        continue
    fi
    case "${INDEXED}" in
        *" ${name} "*) check_problem "AGENTS.md:${line}: \`${name}\` has a second row in the Skills table" ;;
    esac
    INDEXED="${INDEXED}${name} "
    if [ ! -d "${CHECK_ROOT}/.agents/skills/${name}" ]; then
        check_problem "AGENTS.md:${line}: \`${name}\` has a Skills table row but no .agents/skills/${name}/ directory"
    fi
done <<EOF
${ROWS}
EOF

for skill_dir in "${CHECK_ROOT}"/.agents/skills/*/; do
    [ -d "${skill_dir}" ] || continue
    name=$(basename "${skill_dir}")
    case "${INDEXED}" in
        *" ${name} "*) ;;
        *) check_problem ".agents/skills/${name}/: no row for \`${name}\` in AGENTS.md's Skills table" ;;
    esac
done

check_report ERR_CHECK_SKILL_INDEX "AGENTS.md's Skills table and .agents/skills/ disagree" \
    "one Skills table row per directory under .agents/skills/, and no other rows" \
    "add, rename, or remove the row in AGENTS.md's Skills table (or the skill directory) in the same commit"
check_finish "skills-index-complete: AGENTS.md's Skills table matches .agents/skills/."
