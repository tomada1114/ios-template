#!/usr/bin/env bash
# Labels a pull request from the Conventional Commits type in its title, and drops
# a type label a retitle left stale. Run by .github/workflows/pr-label.yml from a
# checkout of the PR's base SHA, so a PR cannot change the script that labels it.
#
#   scripts/label-pr.sh PR_NUMBER TITLE
#   scripts/label-pr.sh --manifest PATH PR_NUMBER TITLE   (tests use this)
#
# Every type .github/workflows/check-pr-title.yml accepts maps to one label, with
# or without a scope and a `!`: feat → enhancement, fix → bug, docs → documentation,
# ci → ci, deps → dependencies, and style/refactor/perf/test/build/chore/revert →
# chore. Any other type labels nothing and exits 0 (the title check reports it).
#
# The label must already be declared in .github/labels.yml (`just labels` creates
# it); this script never creates a label. Every other type label the PR carries is
# removed — except `dependencies`, which Dependabot applies to its own `ci:` PRs.
# A rejected `gh pr edit` (a fork PR's read-only token) is a notice, not a failure.
#
# `gh` comes from the caller's PATH, authenticated, with GH_REPO or a git remote
# naming the repository. Git work tree: not required.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_LABELPR_USAGE        wrong arguments, or the manifest does not exist
#   ERR_LABELPR_UNDECLARED   the mapped label is not declared in the manifest
#   ERR_LABELPR_GH_FAILED    reading the PR's current labels failed
set -euo pipefail

USAGE='usage: scripts/label-pr.sh [--manifest PATH] PR_NUMBER TITLE'

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

cd "$(dirname "$0")/.."

MANIFEST=".github/labels.yml"
if [ "${1:-}" = "--manifest" ]; then
    [ $# -ge 2 ] || fail ERR_LABELPR_USAGE "--manifest needs a file path" "--manifest PATH" "no path" "${USAGE}"
    MANIFEST="$2"
    shift 2
fi
[ $# -eq 2 ] || fail ERR_LABELPR_USAGE "expected a PR number and a title" "2 arguments" "$# argument(s)" "${USAGE}"
PR_NUMBER="$1"
TITLE="$2"
case "${PR_NUMBER}" in
    '' | *[!0-9]*) fail ERR_LABELPR_USAGE "PR number is not a number" "digits only" "'${PR_NUMBER}'" "${USAGE}" ;;
esac
[ -f "${MANIFEST}" ] || fail ERR_LABELPR_USAGE "manifest '${MANIFEST}' does not exist" "an existing labels.yml" "no file at '${MANIFEST}'" "${USAGE}"

TYPE_LABELS="enhancement bug documentation chore ci dependencies"

type_re='^([a-z]+)(\([^)]*\))?!?: '
if [[ ! "${TITLE}" =~ ${type_re} ]]; then
    echo "No Conventional Commits type in the title; no label applied."
    exit 0
fi
type="${BASH_REMATCH[1]}"
case "${type}" in
    feat) label=enhancement ;;
    fix) label=bug ;;
    docs) label=documentation ;;
    ci) label=ci ;;
    deps) label=dependencies ;;
    style | refactor | perf | test | build | chore | revert) label=chore ;;
    *)
        echo "No label mapping for type: ${type}"
        exit 0
        ;;
esac

if ! grep -Eq "^- name: \"?${label}\"?[[:space:]]*(#.*)?$" "${MANIFEST}"; then
    fail ERR_LABELPR_UNDECLARED "label '${label}' is not declared in ${MANIFEST}" \
        "every label this script applies declared in ${MANIFEST}" "no '- name: ${label}' entry" \
        "add '${label}' to ${MANIFEST}, then run: just labels"
fi

current=$(gh pr view "${PR_NUMBER}" --json labels --jq '.labels[].name') ||
    fail ERR_LABELPR_GH_FAILED "could not read the labels of PR #${PR_NUMBER}" \
        "gh pr view to succeed" "gh exited non-zero" "gh auth status, and check GH_REPO"

args=(--add-label "${label}")
for existing in ${TYPE_LABELS}; do
    [ "${existing}" != "${label}" ] || continue
    [ "${existing}" != dependencies ] || continue
    if grep -qxF -- "${existing}" <<<"${current}"; then
        args+=(--remove-label "${existing}")
    fi
done

if gh pr edit "${PR_NUMBER}" "${args[@]}"; then
    echo "Labeled PR #${PR_NUMBER}: ${label}"
else
    echo "::notice::Could not apply label '${label}' (fork PRs have a read-only token)."
fi
