#!/usr/bin/env bash
# Creates or updates this repository's GitHub labels from a label manifest,
# the single declarative source for the label taxonomy (.github/labels.yml).
#
#   scripts/sync-labels.sh                    sync .github/labels.yml (`just labels`)
#   scripts/sync-labels.sh --manifest PATH    sync a different manifest (tests use this)
#
# Parses the whole manifest first — a missing field or a bad color fails before
# any `gh` call. Then, per entry in file order, runs `gh label create --force`,
# which creates the label if it is absent or updates its color and description
# if it already exists. Never calls `gh label delete`: a label the manifest
# does not mention (e.g. a repository-local `duplicate`) is left alone.
#
# `gh` is not a mise-pinned tool (see mise.toml): it comes from the caller's
# own PATH and must already be authenticated against this repository. `awk` is
# assumed, like every other POSIX utility this repository's scripts rely on.
#
# Git work tree: not required. The manifest is read from an explicit or
# default file path, and `gh` resolves the target repository itself (from the
# current directory's git remote, or `gh repo set-default`).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_LABELS_USAGE                   unknown argument, --manifest with no PATH,
#                                       or the manifest file does not exist
#   ERR_LABELS_MANIFEST_MISSING_FIELD  an entry has no name, color, or description
#   ERR_LABELS_MANIFEST_BAD_COLOR      a color is not six lowercase hex digits
#   ERR_LABELS_GH_FAILED               a `gh label create` call failed
set -euo pipefail

USAGE='usage: scripts/sync-labels.sh [--manifest PATH]'

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

usage_error() { # usage_error <what failed> <what was found>
    fail ERR_LABELS_USAGE "$1" "no arguments, or --manifest followed by an existing file" "$2" "${USAGE}"
}

cd "$(dirname "$0")/.."

MANIFEST=".github/labels.yml"
ORIGINAL_ARGS="$*"
while [ $# -gt 0 ]; do
    case "$1" in
        --manifest)
            [ $# -ge 2 ] || usage_error "--manifest needs a file path" "arguments: ${ORIGINAL_ARGS}"
            MANIFEST="$2"
            shift
            ;;
        *) usage_error "unknown argument '$1'" "arguments: ${ORIGINAL_ARGS}" ;;
    esac
    shift
done

[ -f "${MANIFEST}" ] || usage_error "manifest '${MANIFEST}' does not exist" "no file at '${MANIFEST}'"

for tool in gh awk; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        fail ERR_LABELS_USAGE "'${tool}' is not on PATH" \
            "'${tool}' on the caller's PATH" \
            "\`command -v ${tool}\` found nothing" \
            "install ${tool} (the GitHub CLI is not a mise tool) and authenticate it with \`gh auth login\`"
    fi
done

# Six lines per manifest entry: have_name, name, have_color, color,
# have_description, description — one field per line, never combined onto one
# tab-separated line, because an empty field between two tabs is exactly the
# case `read -r` needs to see (an absent color), and bash's word-splitting
# treats a run of tabs as a single delimiter, silently dropping it. "have_*"
# is 1 only when that key was present in the entry at all (an empty value
# still counts as present), so a bad but present color is reported as
# ERR_LABELS_MANIFEST_BAD_COLOR, never as a missing field. A quoted scalar
# ("priority: P0") has its quotes stripped.
parse_manifest() {
    awk '
        function unquote(v,    n) {
            n = length(v)
            if (n >= 2 && substr(v, 1, 1) == "\"" && substr(v, n, 1) == "\"") {
                return substr(v, 2, n - 2)
            }
            return v
        }
        function flush() {
            if (started) {
                printf "%d\n%s\n%d\n%s\n%d\n%s\n", have_name, name, have_color, color, have_description, description
            }
        }
        /^- name:/ {
            flush()
            started = 1
            have_name = 1
            have_color = 0
            have_description = 0
            color = ""
            description = ""
            val = $0
            sub(/^- name:[ \t]*/, "", val)
            name = unquote(val)
            next
        }
        started && /^  color:/ {
            val = $0
            sub(/^  color:[ \t]*/, "", val)
            color = unquote(val)
            have_color = 1
            next
        }
        started && /^  description:/ {
            val = $0
            sub(/^  description:[ \t]*/, "", val)
            description = unquote(val)
            have_description = 1
            next
        }
        END { flush() }
    ' "$1"
}

NAMES=()
COLORS=()
DESCRIPTIONS=()
INDEX=0
while IFS= read -r have_name && IFS= read -r name && IFS= read -r have_color &&
    IFS= read -r color && IFS= read -r have_description && IFS= read -r description; do
    INDEX=$((INDEX + 1))
    if [ "${have_name}" != "1" ] || [ "${have_color}" != "1" ] || [ "${have_description}" != "1" ]; then
        missing=""
        [ "${have_name}" = "1" ] || missing="name"
        [ "${have_color}" = "1" ] || missing="${missing:+${missing}, }color"
        [ "${have_description}" = "1" ] || missing="${missing:+${missing}, }description"
        fail ERR_LABELS_MANIFEST_MISSING_FIELD "entry ${INDEX} in '${MANIFEST}' is missing ${missing}" \
            "a name, a color, and a description on every entry" \
            "entry ${INDEX} (name=\"${name}\") has no ${missing}" \
            "fix ${MANIFEST}"
    fi
    if ! [[ "${color}" =~ ^[0-9a-f]{6}$ ]]; then
        fail ERR_LABELS_MANIFEST_BAD_COLOR "\"${name}\" in '${MANIFEST}' has an invalid color" \
            "six lowercase hex digits, no leading '#' (e.g. d73a4a)" \
            "\"${color}\"" \
            "fix ${MANIFEST}"
    fi
    NAMES+=("${name}")
    COLORS+=("${color}")
    DESCRIPTIONS+=("${description}")
done < <(parse_manifest "${MANIFEST}")

if [ ${#NAMES[@]} -eq 0 ]; then
    echo "labels: ${MANIFEST} declares no entries; nothing to sync."
    exit 0
fi

for ((i = 0; i < ${#NAMES[@]}; i++)); do
    name="${NAMES[$i]}"
    color="${COLORS[$i]}"
    description="${DESCRIPTIONS[$i]}"
    if gh label create "${name}" --color "${color}" --description "${description}" --force; then
        echo "labels: applied ${name}"
    else
        fail ERR_LABELS_GH_FAILED "\`gh label create\` failed for \"${name}\"" \
            "\`gh label create ${name} --color ${color} --description ... --force\` to exit 0" \
            "the command exited non-zero for \"${name}\"" \
            "run \`gh auth status\` and confirm this checkout has write access to the repository"
    fi
done

echo "labels: applied ${#NAMES[@]} label(s) from ${MANIFEST}."
