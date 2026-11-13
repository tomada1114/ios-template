#!/usr/bin/env bash
# Print `true` or `false`: whether project.yml builds any iOS target for iPad, which
# decides whether the iPad launch UI test (scripts/uitest-ipad.sh, in
# `just check-release`) has work.
#
#   scripts/targets-ipad.sh [--root DIR]
#
# The rule: `true` when at least one target under `targets:` that builds for iOS
# (`platform: iOS`, or iOS in a `platform:` or `supportedDestinations:` list) is built
# for iPad — one of its TARGETED_DEVICE_FAMILY values names 2, or it declares none,
# since XcodeGen's iOS default is "1,2". `false` when every iOS target names only
# other families, or there is no iOS target. A non-iOS target (a watchOS target's
# family 4, say) never counts either way. So an app bootstrapped to iPhone only
# (`"1"` on the app and the UI-test target; starting-an-app's device-family choice)
# prints `false`, and an app keeping iPad on any iOS target prints `true`.
#
# A YAML trailing comment (whitespace, then `#`) and quotes are stripped. The parsing
# is line-based, not YAML-aware: a target is a two-space-indented key under a column-0
# `targets:`, and its keys are read at any deeper indent; a family set through
# `settingGroups:`, a target template, or the project-level `settings:` is not seen.
#
# Git work tree: not required — the manifest is read under --root, which defaults to
# the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_IPAD_USAGE             unknown argument, or a --root DIR that does not exist
#   ERR_IPAD_MANIFEST_MISSING  there is no project.yml under the root
#   ERR_IPAD_NO_TARGETS        project.yml has no column-0 `targets:` with a target
set -euo pipefail

USAGE="usage: scripts/targets-ipad.sh [--root DIR]"

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
            [ $# -ge 2 ] || fail ERR_IPAD_USAGE "--root needs a directory" \
                "--root followed by an existing directory" "no value after --root" "${USAGE}"
            [ -d "$2" ] || fail ERR_IPAD_USAGE "--root directory '$2' does not exist" \
                "--root followed by an existing directory" "no directory at '$2'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *)
            fail ERR_IPAD_USAGE "unknown argument '$1'" \
                "no arguments, or --root DIR" "argument '$1'" "${USAGE}"
            ;;
    esac
    shift
done
[ -n "${ROOT}" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd)

MANIFEST="${ROOT}/project.yml"
[ -f "${MANIFEST}" ] || fail ERR_IPAD_MANIFEST_MISSING "there is no project.yml under ${ROOT}" \
    "${MANIFEST} to exist" "no file at ${MANIFEST}" \
    "run this from a checkout of the app, or pass --root DIR naming the directory that holds project.yml"

# Prints one line per target: `<name> <ios|other> <families>`, the families joined
# with `;` (empty when the target declares none).
TARGETS=$(awk -v sq="'" '
    function strip(s) {
        sub(/[[:space:]]#.*$/, "", s)
        gsub(/["[:space:]]/, "", s)
        gsub(sq, "", s)
        return s
    }
    function flush() {
        if (name != "") print name, (ios ? "ios" : "other"), families
        name = ""; ios = 0; families = ""; listkey = 0
    }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { flush(); intargets = ($0 ~ /^targets:[[:space:]]*(#.*)?$/); next }
    !intargets { next }
    /^  [^[:space:]]/ { flush(); name = $0; sub(/^  /, "", name); sub(/:.*$/, "", name); next }
    name == "" { next }
    {
        line = $0
        if (listkey && line ~ /^[[:space:]]+-[[:space:]]/) {
            if (strip(line) ~ /^-iOS$/) ios = 1
            next
        }
        listkey = 0
        if (line ~ /^    (platform|supportedDestinations):/) {
            value = line; sub(/^[^:]*:/, "", value); value = strip(value)
            if (value == "") { listkey = 1; next }
            gsub(/\[|\]/, ",", value)
            if (("," value ",") ~ /,iOS,/) ios = 1
            next
        }
        if (line ~ /^[[:space:]]+TARGETED_DEVICE_FAMILY:/) {
            value = line; sub(/^[^:]*:/, "", value)
            families = families (families == "" ? "" : ";") strip(value)
        }
    }
    END { flush() }
' "${MANIFEST}")

[ -n "${TARGETS}" ] || fail ERR_IPAD_NO_TARGETS "project.yml declares no target" \
    "a column-0 \`targets:\` in ${MANIFEST} with at least one two-space-indented target" \
    "no target found" \
    "check project.yml's \`targets:\` section (the format is in this script's header)"

ANSWER=false
while read -r _name kind families; do
    [ "${kind}" = "ios" ] || continue
    if [ -z "${families}" ]; then
        ANSWER=true
        continue
    fi
    case ",${families//;/,}," in
        *,2,*) ANSWER=true ;;
    esac
done <<<"${TARGETS}"
echo "${ANSWER}"
