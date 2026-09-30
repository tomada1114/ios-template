#!/usr/bin/env bash
# Every skill's frontmatter must load in both hosts, not merely have the right keys
# (skills-frontmatter.sh): a description that is too long, one that is not plain
# ASCII, a value Codex CLI's strict YAML parser rejects, or a second SKILL.md below a
# skill's top directory each makes a skill silently fail to load or load twice.
#
#   scripts/checks/skills-descriptions.sh [--root DIR]
#
# Checked, reading only <root>/.agents/skills/ (.claude/skills/ is its byte-identical
# mirror, checked by scripts/sync-agents.sh --check):
#   - no file named SKILL.md exists below <root>/.agents/skills/<dir>/ at any depth
#     other than <dir>/SKILL.md itself (e.g. <dir>/references/SKILL.md);
#   - in each <dir>/SKILL.md frontmatter (the lines between the opening `---` and the
#     next `---`), every top-level `key: value` whose value is a plain (unquoted)
#     scalar is Codex-YAML-safe. A value is exempt when it is empty, a block scalar
#     header (`>` or `|`, optionally followed by chomping/indent indicators), or
#     starts with `"` or `'` (a quoted scalar). A plain value fails when:
#       * it contains `: ` or ends with `:` (read as a nested mapping);
#       * it contains ` #` (the rest is silently dropped as a comment);
#       * its first character is one of  [ ] { } , # & * ! | > % @ `  or it starts
#         with `-`, `?`, or `:` followed by a space or the end of the value;
#     and each indented continuation line of a plain value fails on the same `: `,
#     trailing `:`, and ` #` rules. Block scalar content is not inspected for YAML.
#   - `description` contains only printable ASCII (bytes 0x20-0x7E, and tab): no
#     em-dash, curly quote, or other non-English character;
#   - `description` is at most 1024 characters (the Agent Skills format's maximum),
#     measured on its text with each line trimmed and lines joined by one space —
#     the folded value both hosts see, to within a trailing newline.
# The check is line-based, not a full YAML parser; the frontmatter's shape (keys,
# name, non-empty description) is skills-frontmatter.sh's job.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE              unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING      <root>/.agents/skills/ does not exist
#   ERR_CHECK_SKILL_NESTED       a SKILL.md sits below a skill's top directory
#   ERR_CHECK_SKILL_DESCRIPTION  a frontmatter value or description breaks a rule above
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/skills-descriptions.sh" "$@"
check_require_file ".agents/skills"

MAX_DESCRIPTION=1024

while IFS= read -r nested; do
    [ -n "${nested}" ] || continue
    check_problem "${nested#"${CHECK_ROOT}"/}"
done <<EOF
$(find "${CHECK_ROOT}/.agents/skills" -mindepth 3 -name SKILL.md | LC_ALL=C sort)
EOF
check_report ERR_CHECK_SKILL_NESTED "a SKILL.md sits below a skill's top directory" \
    "SKILL.md only at .agents/skills/<dir>/SKILL.md; reference files named for their content" \
    "rename the nested file (e.g. references/failure-modes.md), then run \`just agents-sync\`"

# Prints one problem per line for the SKILL.md given.
description_problems() { # description_problems <SKILL.md path>
    LC_ALL=C awk -v max="${MAX_DESCRIPTION}" -v q="'" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function plain_bad(s, where) {
            if (s ~ /: / || s ~ /:$/) print where " is an unquoted value containing `: ` or ending in `:`; quote it or use `>`"
            if (s ~ / #/) print where " is an unquoted value containing ` #`; quote it or use `>`"
        }
        NR == 1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        /^[ \t]*$/ || /^#/ { next }
        /^[ \t]/ {
            if (style == "plain") plain_bad(trim($0), "line " NR " (`" key "`)")
            if (key == "description") desc = desc (desc == "" ? "" : " ") trim($0)
            next
        }
        /^[A-Za-z0-9_-]+:/ {
            key = $0; sub(/:.*/, "", key)
            value = $0; sub(/^[^:]*:[ \t]*/, "", value); value = trim(value)
            if (value == "" || value ~ /^[>|][-+0-9]*$/) style = "block"
            else if (value ~ /^"/ || value ~ ("^" q)) style = "quoted"
            else style = "plain"
            if (style == "plain") {
                plain_bad(value, "line " NR " (`" key "`)")
                if (value ~ /^[][{},#&*!|>%@`]/ || value ~ /^[-?:]( |$)/)
                    print "line " NR " (`" key "`) starts with a YAML indicator character; quote it or use `>`"
            }
            if (key == "description") {
                desc = ""
                if (style == "quoted") desc = substr(value, 2, length(value) - 2)
                else if (style == "plain") desc = value
            }
            next
        }
        END {
            if (desc ~ /[^\t -~]/) print "`description` contains a non-ASCII or non-printable character (e.g. an em-dash or curly quote)"
            if (length(desc) > max) print "`description` is " length(desc) " characters, over the " max "-character limit"
        }
    ' "$1"
}

for skill_file in "${CHECK_ROOT}"/.agents/skills/*/SKILL.md; do
    [ -f "${skill_file}" ] || continue
    dir=$(basename "$(dirname "${skill_file}")")
    while IFS= read -r problem; do
        [ -n "${problem}" ] || continue
        check_problem ".agents/skills/${dir}: ${problem}"
    done <<EOF
$(description_problems "${skill_file}")
EOF
done

check_report ERR_CHECK_SKILL_DESCRIPTION "a SKILL.md frontmatter would not load in both hosts" \
    "Codex-YAML-safe values and a printable-ASCII description of at most ${MAX_DESCRIPTION} characters" \
    "fix the frontmatter in .agents/skills/ (see the authoring-skills skill), then run \`just agents-sync\`"
check_finish "skills-descriptions: no nested SKILL.md; every description is ASCII, within ${MAX_DESCRIPTION} characters, and Codex-YAML-safe."
