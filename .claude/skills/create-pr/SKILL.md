---
name: create-pr
description: >
  Create or update pull requests following project conventions. Runs pre-checks
  (just check), generates Conventional Commits title, fills PR template with
  summary/test plan/checklist, and verifies all checklist items pass before
  creating via gh CLI. Use PROACTIVELY when: PR creation, pull request,
  create PR, open PR, submit PR, PR update, review request.
---

# PR Creation Workflow

All PR titles, bodies, and commit messages MUST be written in English.

## Dynamic Context

Gather this context first (run each command):

```bash
cat .github/PULL_REQUEST_TEMPLATE.md   # PR template
git log main..HEAD --oneline           # commits in this PR
git diff --stat main..HEAD             # changed files
```

## Step 1: Pre-flight Checks

Check working tree status and whether a PR already exists for this branch.

```bash
git status --short
gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number,title,url
```

- If uncommitted changes exist, **abort** and prompt to commit first
  (running `just check` on uncommitted code can cause inconsistencies)
- If a PR already exists, switch to **update mode** (`gh pr edit`) instead of creating a new one
- If on `main` branch, **abort** — PRs must come from feature branches

## Step 2: Quality Gate

Run the full quality check suite. This is the prerequisite for PR creation.

```bash
just check
```

`just check` runs `verify-hooks -> fmt -> lint -> test-scripts -> check-harness -> test -> build`
sequentially (the justfile's `check` recipe is the source of truth).
**If any step fails, abort PR creation** and report the failure.

On success, the "All checks pass (`just check`)" checklist item is verified:
formatting, SwiftLint strict, tests with the 80% coverage floor on MyAppCore,
and a Debug build.

## Step 3: Additional Verification

Analyze `git diff main..HEAD` to determine:

**Logic placement and coverage:**
- New/changed logic must live in `Packages/MyAppKit/Sources/MyAppCore` with
  matching tests in `Tests/MyAppCoreTests`
- If logic was added to `MyAppUI` or `App/`: mark the "New logic lives in
  MyAppCore" checklist item unchecked and warn

**Public API changes:**
- Check if `public` declarations in `Packages/MyAppKit/Sources/` were added,
  removed, or changed
- If changes found: verify docs/ or README was updated where relevant
  - If not updated: mark "Documentation updated" as unchecked and warn

**Breaking changes:**
- Detect deleted public types/functions, changed signatures, changed behavior
- If found: note them explicitly in the PR Summary section

**Changelog:**
- User-facing change without a `CHANGELOG.md` entry under `[Unreleased]`:
  mark the CHANGELOG checklist item unchecked and warn

## Step 4: Generate PR Title

Generate a title in Conventional Commits format:

```
<type>(<optional-scope>): <short summary>
```

**Rules:**
- Analyze commits to select the most appropriate type
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
  `ci`, `chore`, `revert`, `deps` (dependency bumps only) — the list
  check-pr-title.yml accepts, shared with smart-commit
- If multiple types are mixed: use the type of the most significant change
- Keep under 70 characters
- Scope is optional (e.g., `core`, `ui`, `app`)

**Examples:**
- `feat(core): add counter persistence`
- `fix(ui): disable increment button at upper bound`
- `chore: bump pinned tool versions in mise.toml`

## Step 5: Generate PR Body

Follow the PR template from dynamic context. Write everything in English.

### Summary

Analyze commits and diff to describe the purpose and content in **1-3 lines**.
Focus on "why this change is needed" rather than "what was changed."

- Include `Closes #N` if a related issue number is known
- Explicitly note any breaking changes

### Test Plan

- If tests were added/modified: summarize what is being tested
- If no test changes: `Existing tests cover this change.` or similar

### Checklist

Fill each item based on verification results from Steps 2-3:

| Item | Criteria |
|------|----------|
| All checks pass | `just check` passed (every step of the justfile's `check` recipe) |
| New logic lives in MyAppCore and is covered | Verified in Step 3; no-logic changes = checked |
| Behavior only the running app shows: evidence in the Test Plan | Required only when the change is visible only in the running app (a view's wiring, an OS integration) — `just uitest` output or a simulator screenshot from `just run`. No such change = checked |
| Documentation updated | Required only when public API or behavior changed. No change = checked |
| No breaking changes | No breaking changes, or documented in Summary = checked |
| PR title follows Conventional Commits | Guaranteed by Step 4 |
| CHANGELOG updated | Required only for user-facing changes. Not user-facing = checked |

**If any item is unchecked, abort PR creation** and report the issue.

## Step 6: Create or Update PR

```bash
# Push if not yet pushed
git push -u origin <current-branch>

# Create PR (new)
gh pr create --base main --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"

# Or update PR (existing)
gh pr edit <number> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

- Use HEREDOC to pass the body (preserves newlines and markdown)
- Display the PR URL after creation/update

## Notes

- This skill does NOT create commits — use the `smart-commit` skill for that
- Abort if attempting to create a PR from the `main` branch
- When a PR already exists for the current branch, update it with `gh pr edit`
