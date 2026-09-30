#!/usr/bin/env bash
# The two enforcements of the Core import ban name the same modules: the module
# alternation in .swiftlint.yml's `no_ui_import_in_core` regex and
# `ArchitectureBoundaryTests.forbiddenModules`. Adding a framework to one list and
# not the other leaves the boundary enforced once while both still pass
# (AGENTS.md › Architecture: "their module lists change together").
#
#   scripts/checks/core-ban-lists-agree.sh [--root DIR]
#
# Files (both required):
#   - <root>/.swiftlint.yml: the first `regex:` line inside the `no_ui_import_in_core:`
#     block (the key at any indentation; the block ends at the next line indented no
#     deeper than the key). The module list is the last parenthesized group made only
#     of identifier characters and `|` that is directly followed by `\b` — in today's
#     regex `(SwiftUI|AppKit|…|ServiceManagement)\b`. A regex split across lines, or
#     one whose module group is not followed by `\b`, is not seen.
#   - <root>/Packages/MyAppKit/Tests/MyAppCoreTests/ArchitectureBoundaryTests.swift:
#     the array literal assigned to `forbiddenModules` — from the `[` after
#     `forbiddenModules … =` to the first `]`, on one line or several. Every
#     double-quoted string literal in that span is a module; a `// …` comment is
#     dropped first. A list built any other way (concatenation, a computed property,
#     an escaped quote inside a literal) is not seen.
#   The lists are compared as sets: order and duplicates do not matter. The rule's
#   `message:` and the prose copies of the list (AGENTS.md, the changing-gates skill)
#   are not compared.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE              unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING      one of the two files above does not exist
#   ERR_CHECK_CORE_BAN_UNPARSED  a module list could not be found in its file
#   ERR_CHECK_CORE_BAN_DIVERGED  a module is in one list but not the other
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/core-ban-lists-agree.sh" "$@"

LINT=".swiftlint.yml"
TESTS="Packages/MyAppKit/Tests/MyAppCoreTests/ArchitectureBoundaryTests.swift"
check_require_file "${LINT}"
check_require_file "${TESTS}"

# One module per line, sorted and de-duplicated.
LINT_MODULES=$(awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    !inblock && /^[[:space:]]*no_ui_import_in_core:[[:space:]]*(#.*)?$/ { inblock = 1; key = indent($0); next }
    inblock && /^[[:space:]]*(#.*)?$/ { next }
    inblock && indent($0) <= key { exit }
    inblock && /^[[:space:]]*regex:/ { print; exit }
' "${CHECK_ROOT}/${LINT}" |
    sed -n 's/.*(\([A-Za-z0-9_][A-Za-z0-9_|]*\))\\b.*/\1/p' | tr '|' '\n' | grep -v '^$' | LC_ALL=C sort -u || true)

TEST_MODULES=$(awk '
    function emit(s) {
        while (match(s, /"[^"]*"/)) {
            print substr(s, RSTART + 1, RLENGTH - 2)
            s = substr(s, RSTART + RLENGTH)
        }
    }
    {
        line = $0
        sub(/\/\/.*$/, "", line)
    }
    !inlist {
        if (line !~ /forbiddenModules[^=]*=[[:space:]]*\[/) next
        inlist = 1
        sub(/^[^=]*=[[:space:]]*\[/, "", line)
    }
    {
        end = index(line, "]")
        if (end > 0) line = substr(line, 1, end - 1)
        emit(line)
        if (end > 0) exit
    }
' "${CHECK_ROOT}/${TESTS}" | grep -v '^$' | LC_ALL=C sort -u || true)

if [ -z "${LINT_MODULES}" ]; then
    check_problem "${LINT}: no module alternation \`(A|B|…)\\b\` on a \`regex:\` line inside \`no_ui_import_in_core:\`"
fi
if [ -z "${TEST_MODULES}" ]; then
    check_problem "${TESTS}: no string literal in a \`forbiddenModules = [ … ]\` array literal"
fi
check_report ERR_CHECK_CORE_BAN_UNPARSED "a Core import ban list could not be read" \
    "a \`regex:\` line in ${LINT}'s no_ui_import_in_core ending in \`(Module|Module|…)\\b\`, and \`static let forbiddenModules = [\"Module\", …]\` in ${TESTS}" \
    "restore the list in the shape above, or update this check's parser (scripts/checks/core-ban-lists-agree.sh) in the same change"

if [ -n "${LINT_MODULES}" ] && [ -n "${TEST_MODULES}" ]; then
    while IFS= read -r module; do
        [ -n "${module}" ] || continue
        if ! grep -qxF -- "${module}" <<<"${TEST_MODULES}"; then
            check_problem "\`${module}\` is banned by ${LINT}'s no_ui_import_in_core but missing from forbiddenModules in ${TESTS}"
        fi
    done <<EOF
${LINT_MODULES}
EOF
    while IFS= read -r module; do
        [ -n "${module}" ] || continue
        if ! grep -qxF -- "${module}" <<<"${LINT_MODULES}"; then
            check_problem "\`${module}\` is in forbiddenModules in ${TESTS} but missing from ${LINT}'s no_ui_import_in_core regex"
        fi
    done <<EOF
${TEST_MODULES}
EOF
fi
check_report ERR_CHECK_CORE_BAN_DIVERGED "the two Core import ban lists name different modules" \
    "${LINT}'s no_ui_import_in_core regex and ${TESTS}'s forbiddenModules to name the same modules" \
    "add the missing module to the other list in the same commit (adding strengthens the gate; removing one weakens it and needs a human's sign-off, AGENTS.md › Security and human approval)"

check_finish "core-ban-lists-agree: .swiftlint.yml and ArchitectureBoundaryTests ban the same modules."
