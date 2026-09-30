#!/usr/bin/env bash
# Creates or updates this repository's "main" branch ruleset — the committed,
# reviewable definition of branch protection — from .github/rulesets/main.json,
# the JSON body `POST /repos/{owner}/{repo}/rulesets` (and `PUT .../rulesets/{id}`)
# accept.
#
#   scripts/apply-ruleset.sh
#
# This is a human-run, admin-only step: applying a ruleset needs repository admin
# permissions, so it is never called from CI or a git hook, and running it against
# the live repository needs sign-off first, the same as any other remote write
# (see AGENTS.md's "Security and human approval"). "Use this template" does not
# copy rulesets, so every repository created from this template needs its own
# admin to run this once.
#
# Idempotent: resolves the repository with `gh repo view`, lists its own rulesets,
# and updates a ruleset already named "main" in place (PUT) instead of creating a
# duplicate; otherwise it creates one (POST).
#
# `gh` is not a mise-pinned tool (see mise.toml), like scripts/sync-labels.sh: it
# comes from the caller's own PATH and must already be authenticated against this
# repository.
#
# Git work tree: not required — `gh` resolves the target repository itself (from
# the current directory's git remote, or `gh repo set-default`).
#
# Rulesets on a private repository need a paid GitHub plan (GitHub Free supports
# them on public repositories only); that failure is mapped to
# ERR_RULESET_PLAN_UNSUPPORTED instead of surfacing a raw 403/404.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_RULESET_FILE_MISSING      .github/rulesets/main.json does not exist
#   ERR_RULESET_GH_MISSING        `gh` is not on PATH
#   ERR_RULESET_PLAN_UNSUPPORTED  the API refused because rulesets need a paid plan
#   ERR_RULESET_FORBIDDEN         the API refused for any other reason (403, 404, auth, ...)
set -euo pipefail

cd "$(dirname "$0")/.."

RULESET_FILE=".github/rulesets/main.json"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

[ -f "${RULESET_FILE}" ] || fail ERR_RULESET_FILE_MISSING \
    "${RULESET_FILE} does not exist" \
    "a committed ruleset definition at ${RULESET_FILE}" \
    "no file at ${RULESET_FILE}" \
    "restore ${RULESET_FILE} from version control"

command -v gh >/dev/null 2>&1 || fail ERR_RULESET_GH_MISSING \
    "'gh' is not on PATH" \
    "the GitHub CLI ('gh') on the caller's PATH, authenticated against this repository" \
    "\`command -v gh\` found nothing" \
    "install the GitHub CLI and run \`gh auth login\`"

GH_STDERR=$(mktemp)
trap 'rm -f "${GH_STDERR}"' EXIT

# classify_failure ACTION — reads the last failed call's stderr from GH_STDERR and
# exits with the matching ERR_ code. GitHub's message for a plan-gated ruleset call
# mentions upgrading the plan; anything else (auth, missing repo, no admin
# permission, a plain 404) is reported as an unclassified forbidden.
classify_failure() {
    local action="$1" message
    message=$(cat "${GH_STDERR}")
    if grep -qi 'upgrade' <<<"${message}"; then
        fail ERR_RULESET_PLAN_UNSUPPORTED \
            "${action} was refused: rulesets need a paid GitHub plan on a private repository" \
            "GitHub Free supports rulesets on public repositories only" \
            "${message}" \
            "make the repository public, or use a paid GitHub plan"
    fi
    fail ERR_RULESET_FORBIDDEN \
        "${action} was refused" \
        "the GitHub API to accept the request from a repository admin" \
        "${message}" \
        "run \`gh auth status\` and confirm this account is an admin of the repository"
}

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>"${GH_STDERR}") ||
    classify_failure "resolving the repository (\`gh repo view\`)"

# includes_parents=false: the listing otherwise also returns organization-level
# rulesets, whose ids the repository-scoped PUT below cannot address. --paginate:
# the listing is paged (30 per page), so a "main" past the first page is still found.
EXISTING_ID=$(gh api --paginate "repos/${REPO}/rulesets?includes_parents=false" \
    --jq '.[] | select(.name == "main" and .source_type == "Repository") | .id' 2>"${GH_STDERR}") ||
    classify_failure "listing rulesets (\`gh api repos/${REPO}/rulesets\`)"
EXISTING_ID=$(head -n 1 <<<"${EXISTING_ID}")

if [ -z "${EXISTING_ID}" ]; then
    echo "apply-ruleset: no ruleset named \"main\" in ${REPO}; creating it from ${RULESET_FILE}."
    gh api "repos/${REPO}/rulesets" --method POST --input "${RULESET_FILE}" >/dev/null 2>"${GH_STDERR}" ||
        classify_failure "creating the ruleset (\`gh api repos/${REPO}/rulesets\`)"
    echo "apply-ruleset: created the \"main\" ruleset in ${REPO}."
else
    echo "apply-ruleset: ruleset \"main\" (id ${EXISTING_ID}) already exists in ${REPO}; updating it from ${RULESET_FILE}."
    gh api "repos/${REPO}/rulesets/${EXISTING_ID}" --method PUT --input "${RULESET_FILE}" >/dev/null 2>"${GH_STDERR}" ||
        classify_failure "updating the ruleset (\`gh api repos/${REPO}/rulesets/${EXISTING_ID}\`)"
    echo "apply-ruleset: updated the \"main\" ruleset in ${REPO}."
fi
