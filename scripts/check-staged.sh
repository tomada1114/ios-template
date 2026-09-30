#!/usr/bin/env bash
# Refuse a commit that would put a secret into history, judged from the git index
# alone: a secret-shaped staged path, or credential-shaped staged content.
#
#   scripts/check-staged.sh    (what the pre-commit hook's "Staged guard" section runs)
#
# Two phases per staged path, in this order:
#   1. the path — scripts/guard/paths.sh (`is_blocked_path`);
#   2. only if the path passes, the staged blob — scripts/guard/credentials.sh
#      (`credential_category`), read from the index, not the worktree, so a partially
#      staged file is judged as it will be committed.
# Every finding is collected before failing once, so one run names them all.
#
# The scope is deliberately narrow: only what is mechanically decidable from a path or
# a literal pattern is blocked here. Whether a commit *should* contain what it contains
# is a judgement call and stays in PR review — a hook that blocks legitimate work
# teaches its author to reach for `--no-verify`, which turns this check off too.
#
# Output never contains file content: a finding names the path and the rule's reason
# or category, never the matched text.
#
# The index is read through `git diff --cached`, which honors the GIT_INDEX_FILE git
# hands a hook (`git commit -- <path>` commits from a temporary index). Git work tree:
# required — outside one the script refuses to run (ERR_STAGED_NOT_A_REPO).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1). When paths and
# content are both blocked, every finding line comes first, then one
# Expected:/Actual:/Next: block:
#   ERR_STAGED_NOT_A_REPO          not inside a git work tree
#   ERR_STAGED_READ_FAILED         the staged changes could not be listed, or a staged blob read or scanned
#   ERR_STAGED_BLOCKED_PATH        a staged path matches scripts/guard/paths.sh
#   ERR_STAGED_CREDENTIAL_SHAPED   a staged blob matches scripts/guard/credentials.sh
set -euo pipefail

GUARD_DIR="$(cd "$(dirname "$0")" && pwd)/guard"
# shellcheck source=scripts/guard/paths.sh
. "${GUARD_DIR}/paths.sh"
# shellcheck source=scripts/guard/credentials.sh
. "${GUARD_DIR}/credentials.sh"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]; then
    fail ERR_STAGED_NOT_A_REPO \
        "not inside a git work tree" \
        "to run from inside the repository whose index is being committed" \
        "\`git rev-parse --is-inside-work-tree\` did not print true in $(pwd)" \
        "cd into the repository and re-run scripts/check-staged.sh."
fi

SCRATCH=$(mktemp -d)
trap 'rm -rf "${SCRATCH}"' EXIT
BLOB="${SCRATCH}/blob"
STAGED="${SCRATCH}/staged"

FINDINGS=()
BLOCKED_PATHS=0
CREDENTIAL_PATHS=0

# --raw gives each entry's staged mode and blob id, so the blob is read by id and
# never re-resolved through a path. --no-renames reports a rename as a deletion plus
# an addition, so the new path is always the only path on the line.
#
# Deletions are never inspected (no D in --diff-filter): a staged deletion removes a
# file from the next commit, so it cannot add a secret — and refusing it would block
# the very commit that removes a secret committed earlier. T (a type change, e.g. a
# file replaced by a symlink) is inspected, since it stages new content.
#
# The listing is written to a file first rather than read through a process
# substitution, whose exit status bash discards: a failing `git diff` would otherwise
# look like an empty index and let the commit through unchecked.
if ! git diff --cached --raw -z --no-abbrev --no-renames --diff-filter=ACMRT >"${STAGED}"; then
    fail ERR_STAGED_READ_FAILED \
        "could not list the staged changes" \
        "\`git diff --cached --raw\` to list every staged path" \
        "it exited non-zero" \
        "check \`git status\` and the index, then retry the commit."
fi
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    # meta is ":<old mode> <new mode> <old id> <new id> <status>".
    read -r _ new_mode _ new_id _ <<<"${meta}"

    if is_blocked_path "${path}"; then
        FINDINGS+=("ERR_STAGED_BLOCKED_PATH: ${path} — ${BLOCKED_REASON}")
        BLOCKED_PATHS=$((BLOCKED_PATHS + 1))
        continue
    fi

    # A gitlink (submodule, mode 160000) names a commit in another repository; there
    # is no blob here to scan.
    [ "${new_mode}" != "160000" ] || continue

    if ! git cat-file blob "${new_id}" >"${BLOB}" 2>/dev/null; then
        fail ERR_STAGED_READ_FAILED \
            "could not read the staged content of ${path}" \
            "\`git cat-file blob\` to print the staged blob of every staged path" \
            "it failed for ${path}" \
            "check \`git status\` and the index (\`git ls-files --stage -- ${path}\`), then retry the commit."
    fi
    status=0
    category=$(credential_category "${BLOB}") || status=$?
    case "${status}" in
        0)
            FINDINGS+=("ERR_STAGED_CREDENTIAL_SHAPED: ${path} — content matches the ${category} pattern")
            CREDENTIAL_PATHS=$((CREDENTIAL_PATHS + 1))
            ;;
        1) ;;
        *)
            fail ERR_STAGED_READ_FAILED \
                "could not scan the staged content of ${path}" \
                "grep to read the exported staged blob of every staged path" \
                "grep failed for ${path}" \
                "check that ${SCRATCH} is writable and retry the commit."
            ;;
    esac
done <"${STAGED}"

if [ ${#FINDINGS[@]} -gt 0 ]; then
    printf '%s\n' "${FINDINGS[@]}" >&2
    echo "Expected: no staged path matching scripts/guard/paths.sh and no staged content matching scripts/guard/credentials.sh" >&2
    echo "Actual: ${BLOCKED_PATHS} staged path(s) blocked by name, ${CREDENTIAL_PATHS} by content (the matched text is never printed)" >&2
    echo "Next: unstage each file with \`git restore --staged <path>\`; move the value to the keychain or a CI secret and reference it instead; if the file must be committed, remove the secret from it first." >&2
    exit 1
fi
