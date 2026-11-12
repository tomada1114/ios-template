#!/usr/bin/env bash
# Prints `true` or `false`: whether a change set touches any path the simulator checks
# (uitest-build, uitest-run, smoke, build-device, analyze, test-ios) exercise. `just check` runs
# those checks only on `true`; CI's `changes` job uses the answer to decide whether its
# macOS jobs (`test`, `bootstrap-smoke`) have work (#54).
# This file holds the only copy of the path list.
#
#   scripts/simulator-relevant.sh --base REF --head REF   (CI: git diff BASE...HEAD)
#   scripts/simulator-relevant.sh [--base REF]            (local)
#
# Locally, the change set is everything since `git merge-base HEAD <base>` (base
# defaults to origin/main, then main): committed, staged, and unstaged changes, plus
# untracked files that are not ignored.
#
# Fail-safe: running too much is safe, skipping is not. So it prints `true` when
# CHECK_ALL=1, when the change set is empty, and, with a one-line notice on stderr,
# when any git command fails (outside a git checkout included). Exit 0 in every case
# but bad arguments. With --head it lists the changed files on stderr; a `false`
# adds one stderr line saying how to run the checks anyway.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_RELEVANT_USAGE  unknown argument, a flag without its value, or --head without
#                       --base
set -euo pipefail

# The paths the simulator checks exercise, as one extended regex: anything matching
# sends them through in full. `.swiftlint.yml` is here for `analyze`: its analyzer_rules
# are read by that check alone.
RELEVANT='^(App/|Packages/|LaunchUITests/|Config/|scripts/|\.github/actions/|project\.yml$|justfile$|mise\.toml$|\.xcode-version$|\.swiftlint\.yml$|\.github/workflows/ci\.yml$)'

usage_fail() {
    {
        echo "ERR_RELEVANT_USAGE: $1"
        echo "Expected: \`scripts/simulator-relevant.sh [--base REF [--head REF]]\`"
        echo "Actual: $2"
        echo "Next: fix the call (the usage is in the header of scripts/simulator-relevant.sh)"
    } >&2
    exit 1
}

BASE=""
HEAD=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --base | --head)
            [ "$#" -ge 2 ] && [ -n "$2" ] || usage_fail "$1 needs a value" "arguments end at $1"
            if [ "$1" = --base ]; then BASE="$2"; else HEAD="$2"; fi
            shift 2
            ;;
        *) usage_fail "unknown argument: $1" "arguments: $*" ;;
    esac
done
[ -z "${HEAD}" ] || [ -n "${BASE}" ] || usage_fail "--head needs --base" "--head ${HEAD} without --base"

if [ "${CHECK_ALL:-}" = 1 ]; then
    echo true
    exit 0
fi

git_failed() {
    echo "simulator-relevant: $1, so the simulator checks run" >&2
    echo true
    exit 0
}

if [ -n "${HEAD}" ]; then
    FILES=$(git diff --name-only "${BASE}...${HEAD}" 2>/dev/null) ||
        git_failed "\`git diff ${BASE}...${HEAD}\` failed"
    printf 'Changed files:\n%s\n' "${FILES}" >&2
else
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || git_failed "this is not a git checkout"
    if [ -z "${BASE}" ]; then
        if git rev-parse --verify --quiet "origin/main^{commit}" >/dev/null 2>&1; then
            BASE="origin/main"
        else
            BASE="main"
        fi
    fi
    MERGE_BASE=$(git merge-base HEAD "${BASE}" 2>/dev/null) ||
        git_failed "no merge base between HEAD and ${BASE}"
    TRACKED=$(git diff --name-only "${MERGE_BASE}" 2>/dev/null) ||
        git_failed "\`git diff ${MERGE_BASE}\` failed"
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null) ||
        git_failed "\`git ls-files --others\` failed"
    FILES=$(printf '%s\n%s\n' "${TRACKED}" "${UNTRACKED}" | sed '/^$/d')
fi

if [ -n "${FILES}" ] && ! grep -qE -- "${RELEVANT}" <<<"${FILES}"; then
    echo "simulator-relevant: nothing under the simulator paths changed since ${BASE}, so uitest-build, uitest-run, smoke, build-device, analyze, and test-ios are skipped; CHECK_ALL=1 runs them anyway" >&2
    echo false
else
    echo true
fi
