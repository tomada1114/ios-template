#!/usr/bin/env bash
# Mirrors .agents/skills/ into .claude/skills/, byte for byte.
#
#   scripts/sync-agents.sh [--root DIR]            regenerate the mirror (`just agents-sync`)
#   scripts/sync-agents.sh --check [--root DIR]    report drift, write nothing (`just agents-check`)
#
# Skills are authored once, under .agents/skills/ — the path Codex CLI reads. Claude
# Code reads only .claude/skills/, so the same tree has to exist there too. It is a
# real, committed copy, never a symlink: Codex follows a linked directory into its
# subdirectories and registers a nested references/SKILL.md as a skill of its own.
#
# Sync runs `rsync -a --delete` from the source into the mirror and never writes or
# deletes outside <root>/.claude/skills/. --check runs `diff -r -q` and names every
# path that is missing from the mirror, extra in it, or different. Both ignore
# .DS_Store, which Finder drops into any directory it has shown (gitignored, but on
# disk). rsync and diff are used because they ship with macOS (openrsync since
# macOS 15) and the ubuntu-latest image, so no tool is added to mise.toml.
#
# Every path is relative to --root, which defaults to `git rev-parse
# --show-toplevel`. Git work tree: needed only for that default — without --root
# the script refuses to run outside one (ERR_AGENTS_NOT_A_REPO); with --root it
# never calls git.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_AGENTS_USAGE           unknown argument, or a --root DIR that does not exist
#   ERR_AGENTS_NOT_A_REPO      no --root given and not inside a git work tree
#   ERR_AGENTS_SOURCE_MISSING  <root>/.agents/skills/ does not exist
#   ERR_AGENTS_SYMLINK         the mirror directory, or an entry in the source, is a symlink
#   ERR_AGENTS_TOOL_MISSING    rsync (sync) or diff (--check) is not on PATH
#   ERR_AGENTS_DRIFT           --check found the mirror differs from the source
#   ERR_AGENTS_DIFF_FAILED     --check: diff could not compare the trees
set -euo pipefail

USAGE='usage: scripts/sync-agents.sh [--check] [--root DIR]'
SOURCE_REL=".agents/skills"
MIRROR_REL=".claude/skills"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

usage_error() { # usage_error <what failed> <what was found>
    fail ERR_AGENTS_USAGE "$1" "--check and/or --root followed by an existing directory" "$2" "${USAGE}"
}

CHECK=0
ROOT=""
ORIGINAL_ARGS="$*"
while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --root)
            [ $# -ge 2 ] || usage_error "--root needs a directory" "arguments: ${ORIGINAL_ARGS}"
            [ -d "$2" ] || usage_error "--root directory '$2' does not exist" "no directory at '$2'"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *) usage_error "unknown argument '$1'" "arguments: ${ORIGINAL_ARGS}" ;;
    esac
    shift
done

if [ -z "${ROOT}" ]; then
    if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
        fail ERR_AGENTS_NOT_A_REPO "no --root given and not inside a git work tree" \
            "run inside the repository, or pass --root DIR" \
            "\`git rev-parse --show-toplevel\` failed in $(pwd)" \
            "cd into the repository and run \`just agents-sync\`, or pass --root DIR"
    fi
fi

SOURCE="${ROOT}/${SOURCE_REL}"
MIRROR="${ROOT}/${MIRROR_REL}"

if [ ! -d "${SOURCE}" ]; then
    fail ERR_AGENTS_SOURCE_MISSING "${SOURCE_REL}/ does not exist under ${ROOT}" \
        "skills authored under ${SOURCE_REL}/" \
        "no directory at ${SOURCE}" \
        "author the skills under ${SOURCE_REL}/ (move them there with \`git mv\`), then run \`just agents-sync\`"
fi

if [ -L "${MIRROR}" ]; then
    fail ERR_AGENTS_SYMLINK "${MIRROR_REL} is a symlink" \
        "${MIRROR_REL}/ to be a real directory holding a copy of ${SOURCE_REL}/" \
        "${MIRROR} -> $(readlink "${MIRROR}")" \
        "replace the symlink with a real directory (\`git rm ${MIRROR_REL}\`), then run \`just agents-sync\`"
fi
LINKS=$(find "${SOURCE}" -type l)
if [ -n "${LINKS}" ]; then
    fail ERR_AGENTS_SYMLINK "${SOURCE_REL}/ contains a symlink" \
        "only regular files and directories under ${SOURCE_REL}/" \
        "symlink(s): $(echo "${LINKS}" | tr '\n' ' ')" \
        "replace each symlink with the file it points to, then run \`just agents-sync\`"
fi

TOOL="rsync"
[ "${CHECK}" = 0 ] || TOOL="diff"
if ! command -v "${TOOL}" >/dev/null 2>&1; then
    fail ERR_AGENTS_TOOL_MISSING "'${TOOL}' is not on PATH" \
        "'${TOOL}' on PATH (it ships with macOS and the ubuntu-latest image)" \
        "\`command -v ${TOOL}\` found nothing" \
        "install ${TOOL} with the system package manager, then rerun \`scripts/sync-agents.sh${ORIGINAL_ARGS:+ ${ORIGINAL_ARGS}}\`"
fi

if [ "${CHECK}" = 0 ]; then
    mkdir -p "${MIRROR}"
    rsync -a --delete --exclude .DS_Store "${SOURCE}/" "${MIRROR}/"
    echo "agents:sync: ${MIRROR_REL}/ regenerated from ${SOURCE_REL}/."
    exit 0
fi

if [ ! -d "${MIRROR}" ]; then
    fail ERR_AGENTS_DRIFT "${MIRROR_REL}/ does not exist" \
        "${MIRROR_REL}/ byte-identical to ${SOURCE_REL}/" \
        "no directory at ${MIRROR}" \
        "run \`just agents-sync\` and commit both trees"
fi

DIFF_STATUS=0
# Through env, not a bare LC_ALL=C prefix: Homebrew bash re-inits its locale for a
# prefixed command in the forked child, which can SIGSEGV on macOS (exit 139).
DIFF_OUTPUT=$(env LC_ALL=C diff -r -q -x .DS_Store "${SOURCE}" "${MIRROR}" 2>&1) || DIFF_STATUS=$?

if [ "${DIFF_STATUS}" = 0 ]; then
    echo "agents:check: ${MIRROR_REL}/ is in sync."
    exit 0
fi
if [ "${DIFF_STATUS}" != 1 ]; then
    fail ERR_AGENTS_DIFF_FAILED "diff could not compare ${SOURCE_REL}/ and ${MIRROR_REL}/" \
        "diff to exit 0 (in sync) or 1 (drift)" \
        "diff exited ${DIFF_STATUS}: $(echo "${DIFF_OUTPUT}" | tr '\n' ' ')" \
        "fix what diff reports, then run \`just agents-sync\`"
fi

# Turns one `diff -r -q` line into a drift report with root-relative paths. GNU and
# BSD diff agree on these three shapes under LC_ALL=C; anything else is shown as is.
COUNT=0
while IFS= read -r line; do
    [ -n "${line}" ] || continue
    COUNT=$((COUNT + 1))
    case "${line}" in
        "Only in ${SOURCE}"*)
            rest=${line#"Only in ${SOURCE}"}
            dir=${rest%%": "*}
            name=${rest#*": "}
            report="missing from the mirror: ${MIRROR_REL}${dir}/${name}"
            ;;
        "Only in ${MIRROR}"*)
            rest=${line#"Only in ${MIRROR}"}
            dir=${rest%%": "*}
            name=${rest#*": "}
            report="extra in the mirror: ${MIRROR_REL}${dir}/${name}"
            ;;
        "Files ${SOURCE}/"*" differ")
            rest=${line#"Files ${SOURCE}/"}
            report="differs: ${MIRROR_REL}/${rest%%" and ${MIRROR}/"*}"
            ;;
        *) report="${line}" ;;
    esac
    echo "ERR_AGENTS_DRIFT: ${report}" >&2
done <<EOF
${DIFF_OUTPUT}
EOF
echo "Expected: ${MIRROR_REL}/ byte-identical to ${SOURCE_REL}/ (ignoring .DS_Store)" >&2
echo "Actual: ${COUNT} difference(s), listed above" >&2
echo "Next: run \`just agents-sync\` and commit both trees" >&2
exit 1
