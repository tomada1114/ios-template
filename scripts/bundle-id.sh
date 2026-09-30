#!/usr/bin/env bash
# Print this app's bundle identifier, read from project.yml — the XcodeGen
# manifest that is the source of truth for the app target.
#
#   scripts/bundle-id.sh [--root DIR]
#
# Reading the identifier here, instead of hard-coding it, is what keeps the
# recipes that need it (`just run`, `just logs`) working after
# scripts/bootstrap.sh renames the app and rewrites the bundle-id prefix: the
# manifest is rewritten by that rename, so this answer follows it.
#
# Prints the value of the first PRODUCT_BUNDLE_IDENTIFIER in the manifest — the
# app target's, which project.yml declares first — so a target added later (a
# widget extension, say) never shadows it. A YAML trailing comment (whitespace, then `#`,
# to the end of the line) and a surrounding pair of single or double quotes are
# stripped; the value is otherwise taken literally.
#
# Git work tree: not required — the manifest is read under --root, which
# defaults to the checkout containing this script, so a tarball works too.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_BUNDLEID_USAGE             unknown argument, or a --root DIR that does not exist
#   ERR_BUNDLEID_MANIFEST_MISSING  there is no project.yml under the root
#   ERR_BUNDLEID_NOT_FOUND         project.yml declares no PRODUCT_BUNDLE_IDENTIFIER
#   ERR_BUNDLEID_MALFORMED         the declared value is not a bundle identifier
set -euo pipefail

USAGE="usage: scripts/bundle-id.sh [--root DIR]"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || fail ERR_BUNDLEID_USAGE "--root needs a directory" \
                "--root followed by an existing directory" "no value after --root" "${USAGE}"
            [ -d "$2" ] || fail ERR_BUNDLEID_USAGE "--root directory '$2' does not exist" \
                "--root followed by an existing directory" "no directory at '$2'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *)
            fail ERR_BUNDLEID_USAGE "unknown argument '$1'" \
                "no arguments, or --root DIR" "argument '$1'" "${USAGE}"
            ;;
    esac
    shift
done
[ -n "${ROOT}" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd)

MANIFEST="${ROOT}/project.yml"
[ -f "${MANIFEST}" ] || fail ERR_BUNDLEID_MANIFEST_MISSING "there is no project.yml under ${ROOT}" \
    "${MANIFEST} to exist" "no file at ${MANIFEST}" \
    "run this from a checkout of this repository, or pass --root DIR"

VALUE=$(sed -n 's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER:[[:space:]]*//p' "${MANIFEST}" | head -n 1)
# A trailing carriage return (a CRLF manifest), a YAML comment, and trailing
# spaces are not part of the value; strip them before the quotes, which would
# otherwise not be last. A comment needs whitespace in front of its `#` to be
# one (YAML's own rule), and a bundle identifier can hold no `#` of its own.
VALUE=$(printf '%s' "${VALUE}" | tr -d '\r' | sed -e 's/[[:space:]]#.*//' -e 's/[[:space:]]*$//')
# A line whose value is only a comment declares no identifier at all.
case "${VALUE}" in
    \#*) VALUE="" ;;
esac
case "${VALUE}" in
    \"*\") VALUE=${VALUE#\"}; VALUE=${VALUE%\"} ;;
    \'*\') VALUE=${VALUE#\'}; VALUE=${VALUE%\'} ;;
esac

[ -n "${VALUE}" ] || fail ERR_BUNDLEID_NOT_FOUND "project.yml declares no PRODUCT_BUNDLE_IDENTIFIER" \
    "a \`PRODUCT_BUNDLE_IDENTIFIER: <id>\` line in ${MANIFEST}" \
    "no such line, or an empty value" \
    "add the setting to the app target in ${MANIFEST}, then run \`just generate\`"

# Bundle identifiers are alphanumerics, hyphens, and periods (Apple's rule), and
# the recipes that consume this embed it in a log predicate and compare it to a
# running app's CFBundleIdentifier — so anything else is a manifest bug, not a
# string to pass on.
case "${VALUE}" in
    *[!A-Za-z0-9.-]* | "" | .* | *.)
        fail ERR_BUNDLEID_MALFORMED "PRODUCT_BUNDLE_IDENTIFIER is not a bundle identifier" \
            "alphanumerics, hyphens, and periods, not starting or ending with a period" \
            "'${VALUE}' in ${MANIFEST}" \
            "fix the value in ${MANIFEST} (e.g. com.example.MyApp), then run \`just generate\`"
        ;;
esac

echo "${VALUE}"
