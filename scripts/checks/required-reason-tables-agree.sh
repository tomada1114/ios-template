#!/usr/bin/env bash
# The two required-reason API tables name the same categories: REQUIRED_REASON_APIS in
# scripts/build-device.sh (the linked binary's spellings, read by `just build-device`)
# and RequiredReasonAPIScan.categories (the source spellings, read by `just test`). A
# category added to one and not the other is held to the manifest by one gate only,
# while both still pass. Only the categories are compared: the symbols differ by design,
# since a binary spells an API differently from its source.
#
#   scripts/checks/required-reason-tables-agree.sh [--root DIR]
#
# Files (all required):
#   - <root>/scripts/build-device.sh: the lines between `REQUIRED_REASON_APIS="` (alone
#     on its line) and the next line that is only `"`. Each non-blank line's text before
#     its first `|` is a category, prefixed with NSPrivacyAccessedAPICategory. A table
#     built any other way is not seen.
#   - <root>/Packages/MyAppKit/Tests/MyAppCoreTests/RequiredReasonAPIScan.swift: every
#     `name: ident` whose identifier starts lowercase (a `Category(name: …)` argument;
#     `let name: String` is a declaration, not one), each IDENT resolved through a
#     `static let IDENT = "…"` in the same file, or through
#     `static let IDENT = PrivacyManifestTests.OTHER` to a `static let OTHER = "…"` in
#     PrivacyManifestTests.swift beside it. A name given as a literal, or resolved any
#     other way, is reported as unresolved.
#   - <root>/Packages/MyAppKit/Tests/MyAppCoreTests/PrivacyManifestTests.swift.
#   The lists are compared as sets: order and duplicates do not matter.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE                       unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_INPUT_MISSING               one of the files above does not exist
#   ERR_CHECK_REQUIRED_REASON_UNPARSED    a table, or one of its names, could not be read
#   ERR_CHECK_REQUIRED_REASON_DIVERGED    a category is in one table but not the other
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/required-reason-tables-agree.sh" "$@"

SCRIPT="scripts/build-device.sh"
TESTS_DIR="Packages/MyAppKit/Tests/MyAppCoreTests"
SCAN="${TESTS_DIR}/RequiredReasonAPIScan.swift"
MANIFEST_TESTS="${TESTS_DIR}/PrivacyManifestTests.swift"
check_require_file "${SCRIPT}"
check_require_file "${SCAN}"
check_require_file "${MANIFEST_TESTS}"

# One category per line, sorted and de-duplicated.
SCRIPT_CATEGORIES=$(awk '
    intable && /^"$/ { exit }
    intable && NF { split($0, field, "|"); print "NSPrivacyAccessedAPICategory" field[1] }
    /^REQUIRED_REASON_APIS="$/ { intable = 1 }
' "${CHECK_ROOT}/${SCRIPT}" | LC_ALL=C sort -u || true)

# literal_let FILE IDENT — the string a `static let IDENT = "…"` in FILE holds, if any.
literal_let() {
    sed -n "/^[[:space:]]*static let $2 = \"/{s/^[[:space:]]*static let $2 = \"\\([^\"]*\\)\".*/\\1/p;q;}" "$1"
}

SCAN_CATEGORIES=""
NAMES=$(sed -n 's/.*[(,[:space:]]name: \([a-z_][A-Za-z0-9_]*\).*/\1/p' "${CHECK_ROOT}/${SCAN}" | LC_ALL=C sort -u || true)
while IFS= read -r name; do
    [ -n "${name}" ] || continue
    value=$(literal_let "${CHECK_ROOT}/${SCAN}" "${name}")
    if [ -z "${value}" ]; then
        other=$(sed -n "/^[[:space:]]*static let ${name} = PrivacyManifestTests\\./{s/^[[:space:]]*static let ${name} = PrivacyManifestTests\\.\\([A-Za-z_][A-Za-z0-9_]*\\).*/\\1/p;q;}" \
            "${CHECK_ROOT}/${SCAN}")
        [ -z "${other}" ] || value=$(literal_let "${CHECK_ROOT}/${MANIFEST_TESTS}" "${other}")
    fi
    if [ -z "${value}" ]; then
        check_problem "${SCAN}: \`name: ${name}\` resolves to no \`static let ${name} = \"…\"\` (directly, or through PrivacyManifestTests)"
    else
        SCAN_CATEGORIES="${SCAN_CATEGORIES}${value}"$'\n'
    fi
done <<<"${NAMES}"
SCAN_CATEGORIES=$(LC_ALL=C sort -u <<<"${SCAN_CATEGORIES}" | grep -v '^$' || true)

if [ -z "${SCRIPT_CATEGORIES}" ]; then
    check_problem "${SCRIPT}: no CATEGORY|KIND|VALUE line between \`REQUIRED_REASON_APIS=\"\` and a closing \`\"\` line"
fi
if [ -z "${NAMES}" ]; then
    check_problem "${SCAN}: no \`name: IDENT\` argument"
fi
check_report ERR_CHECK_REQUIRED_REASON_UNPARSED "a required-reason API table could not be read" \
    "\`REQUIRED_REASON_APIS=\"\` … \`\"\` in ${SCRIPT}, and \`Category(name: IDENT, …)\` with \`static let IDENT = \"NSPrivacyAccessedAPICategory…\"\` in ${SCAN}" \
    "restore the table in the shape above, or update this check's parser (scripts/checks/required-reason-tables-agree.sh) in the same change"

if [ -n "${SCRIPT_CATEGORIES}" ] && [ -n "${SCAN_CATEGORIES}" ]; then
    while IFS= read -r category; do
        [ -n "${category}" ] || continue
        grep -qxF -- "${category}" <<<"${SCAN_CATEGORIES}" ||
            check_problem "\`${category}\` is in ${SCRIPT}'s REQUIRED_REASON_APIS but not in RequiredReasonAPIScan.categories (${SCAN})"
    done <<<"${SCRIPT_CATEGORIES}"
    while IFS= read -r category; do
        [ -n "${category}" ] || continue
        grep -qxF -- "${category}" <<<"${SCRIPT_CATEGORIES}" ||
            check_problem "\`${category}\` is in RequiredReasonAPIScan.categories (${SCAN}) but not in ${SCRIPT}'s REQUIRED_REASON_APIS"
    done <<<"${SCAN_CATEGORIES}"
fi
check_report ERR_CHECK_REQUIRED_REASON_DIVERGED "the two required-reason API tables name different categories" \
    "${SCRIPT}'s REQUIRED_REASON_APIS and ${SCAN}'s categories to name the same categories" \
    "add the category, with its symbols in that table's spelling, to the other table in the same commit (integrating-system-apis › references/permissions.md); removing one weakens a gate and needs a human's sign-off (AGENTS.md › Security and human approval)"

check_finish "required-reason-tables-agree: scripts/build-device.sh and RequiredReasonAPIScan name the same required-reason categories."
