#!/usr/bin/env bash
# Every skill's SKILL.md opens with a frontmatter block both hosts can load: a
# SKILL.md with a stray key, a `name` that disagrees with its directory, or an
# empty description mirrors cleanly and then silently never loads.
#
#   scripts/checks/skills-frontmatter.sh [--root DIR]
#
# For each directory <root>/.agents/skills/<dir>/:
#   - <dir>/SKILL.md exists and its first line is exactly `---`, and a later line
#     that is exactly `---` closes the block;
#   - the block's top-level keys (a key at column 0) are exactly `name` and
#     `description`, each once — any other key, a duplicate, or a missing one fails;
#   - `name` (quotes stripped) equals <dir>;
#   - `description` is non-empty: an inline value, or a block (`>`, `|`, …) or plain
#     multi-line scalar with at least one non-blank indented line.
# Indented lines continue the key above them, and blank lines and `#` comments are
# ignored; any other line in the block fails as unparsable. The check is
# line-based, not a full YAML parser. Only .agents/skills/ is read: .claude/skills/
# is its byte-identical mirror (scripts/sync-agents.sh --check).
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE              unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING      <root>/.agents/skills/ does not exist
#   ERR_CHECK_SKILL_FRONTMATTER  a SKILL.md frontmatter breaks one of the rules above
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/skills-frontmatter.sh" "$@"
check_require_file ".agents/skills"

# Prints one problem per line for the SKILL.md given, whose directory is `dir`.
frontmatter_problems() { # frontmatter_problems <dir name> <SKILL.md path>
    awk -v dir="$1" -v q="'" '
        function unquote(v) {
            sub(/[ \t]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ ("^" q ".*" q "$")) v = substr(v, 2, length(v) - 2)
            return v
        }
        NR == 1 {
            if ($0 != "---") { print "does not start with a `---` frontmatter line"; bad = 1; exit }
            next
        }
        $0 == "---" { closed = 1; exit }
        /^[ \t]*$/ || /^#/ { next }
        /^[ \t]/ {
            if (current == "description" && $0 ~ /[^ \t]/) desc_ok = 1
            next
        }
        /^[A-Za-z0-9_-]+:/ {
            key = $0; sub(/:.*/, "", key)
            value = $0; sub(/^[^:]*:[ \t]*/, "", value)
            count[key]++
            if (count[key] == 1) order[++nkeys] = key
            current = key
            if (key == "name") name = unquote(value)
            if (key == "description" && value != "" && value !~ /^[>|][-+0-9]*[ \t]*$/) desc_ok = 1
            next
        }
        { print "line " NR " is not a `key: value` line: " $0 }
        END {
            if (bad) exit
            if (NR == 0) { print "SKILL.md is empty"; exit }
            if (!closed) { print "frontmatter block is never closed with a `---` line"; exit }
            for (i = 1; i <= nkeys; i++) {
                k = order[i]
                if (k != "name" && k != "description") print "unexpected key `" k "` (only `name` and `description` are allowed)"
                else if (count[k] > 1) print "key `" k "` appears " count[k] " times"
            }
            if (!("name" in count)) print "no `name` key"
            else if (name != dir) print "`name` is `" name "`, but the directory is `" dir "`"
            if (!("description" in count)) print "no `description` key"
            else if (!desc_ok) print "`description` is empty"
        }
    ' "$2"
}

for skill_dir in "${CHECK_ROOT}"/.agents/skills/*/; do
    [ -d "${skill_dir}" ] || continue
    dir=$(basename "${skill_dir}")
    skill_file="${skill_dir}SKILL.md"
    if [ ! -f "${skill_file}" ]; then
        check_problem ".agents/skills/${dir}: no SKILL.md"
        continue
    fi
    while IFS= read -r problem; do
        [ -n "${problem}" ] || continue
        check_problem ".agents/skills/${dir}: ${problem}"
    done <<EOF
$(frontmatter_problems "${dir}" "${skill_file}")
EOF
done

check_report ERR_CHECK_SKILL_FRONTMATTER "a SKILL.md frontmatter would not load as a skill" \
    "each .agents/skills/<dir>/SKILL.md to open with a --- block holding exactly \`name: <dir>\` and a non-empty \`description\`" \
    "fix the frontmatter in .agents/skills/ (see the authoring-skills skill), then run \`just agents-sync\`"
check_finish "skills-frontmatter: every SKILL.md has exactly a matching name and a description."
