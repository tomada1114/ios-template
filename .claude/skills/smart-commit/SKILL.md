---
name: smart-commit
description: >
  Analyze working tree changes, group them into logical atomic commits with
  Conventional Commits messages, and push. Handles staging, sensitive file
  exclusion, and Package.resolved bundling automatically. Use PROACTIVELY when:
  commit, git commit, save changes, commit and push, stage changes,
  push my changes, commit this work, ship it.
---

# Smart Commit Workflow

All commit messages must be written in English.

## Dynamic Context

Gather this context first (run each command):

```bash
git rev-parse --abbrev-ref HEAD   # current branch
git status --short                # working tree status
git log --oneline -5              # recent commit style
```

## Branch Guard

Check the current branch before staging. The intended `main` ruleset lives at
`.github/rulesets/main.json`, but it only takes effect once an admin runs
`just ruleset` (`scripts/apply-ruleset.sh`) — a manual, admin-only step. Until
then, committing straight to `main` is fine for solo work, and its own early
history is linear on `main`. Once the ruleset is applied, a direct push to
`main` is rejected, so every change goes through a feature branch and the
`create-pr` skill. Use a feature branch instead when either holds:

- The user wants a PR for this change (the `create-pr` skill requires a
  feature branch), or
- The repository has the ruleset applied, or otherwise has a team workflow
  (see CONTRIBUTING.md's fork-and-branch process).

When it is unclear which mode the user wants, ask before staging.

## Step 1: Analyze Changes

Review staged and unstaged changes to understand what was modified.

```bash
git status
git diff          # unstaged changes
git diff --cached # staged changes
```

If changes are already staged, prioritize those — the user has expressed intent
about what to commit. If nothing is staged, treat all modified/untracked files
as candidates.

## Step 2: Sensitive File Check

The mechanical list — secret-shaped paths (`.env*`, `secrets/`, signing material
such as `.p12` or `.p8`, keychains, provisioning profiles, and the rest) and
credential-shaped content (private-key blocks, GitHub tokens, AWS keys, Anthropic,
OpenAI, Slack, Google, and Stripe live keys, JWTs) —
is `AGENTS.md`'s "Never read a secret-shaped file" list. Once the commit-time guard
is ported, it lives in `scripts/guard/paths.sh` and `scripts/guard/credentials.sh`
and the pre-commit hook's "Staged guard" section (`scripts/check-staged.sh`) enforces
it on every commit; until then nothing mechanical stops such a file, so check every
staged path against that list yourself. Do not keep a second copy of the list here.

What stays with you is the judgment no pattern can make:

- A file whose *name* is innocent but whose purpose is secret — a `config.plist`
  or `Settings.swift` holding a real API key, a copied export of the login
  keychain, a signing script with a password inlined.
- A name like `*password*` or `*secret*`: deliberately not a path rule (too many
  legitimate files share the word), so look at what such a file holds.
- Content the guard's literal patterns do not cover: a password, a webhook URL
  with an embedded token, a customer's personal data.
- Something the user plainly did not mean to commit, secret or not.

Also never commit generated artifacts: `MyApp.xcodeproj/`, `.build/`, `build/`
(all gitignored — if one shows up as untracked, something is wrong; investigate
instead of committing it).

If any are detected among the candidates, **exclude them** and warn the user.
If the hook refuses a commit with `ERR_STAGED_BLOCKED_PATH` or
`ERR_STAGED_CREDENTIAL_SHAPED`, unstage the named path (`git restore --staged
<path>`) and tell the user; never work around the guard.
Everything else — config files, source code, docs, test files — should be
committed. Prefer committing work-in-progress over leaving it uncommitted.

## Step 3: Group Changes

Analyze the changes and group them into logical, atomic commits. Each commit
should be independently meaningful. The goal is to tell a clear story of what
happened through the commit history.

**Grouping rules:**

- **Tests** (`Packages/**/Tests/`, `LaunchUITests/`): prefix `test:`
  - New tests → `test: add ...`
  - Fixed tests → `test: fix ...`

- **Documentation** (`.md`, `docs/`): prefix `docs:`

- **Configuration** (`.swiftlint.yml`, `.swiftformat`, `.claude/`, `mise.toml`,
  `typos.toml`, `.editorconfig`): prefix `chore:`

- **Dependencies** (`Package.swift` dependency changes): prefix `deps:`
  - Always include `Package.resolved` in the same commit

- **Build system** (`project.yml`, `justfile`, `scripts/`): prefix `build:`

- **Source code** (`Packages/**/Sources/`, `App/`):
  - New feature → `feat:`
  - Bug fix → `fix:`
  - Refactor → `refactor:`
  - Performance → `perf:`

- **CI/CD** (`.github/`): prefix `ci:`

**Special cases:**
- `Package.resolved` changes must be in the same commit as the `Package.swift`
  dependency change that caused them
- A source file and its corresponding test file MUST go in the same commit —
  this project is TDD-first, and red tests are never committed alone
  (use `feat:` or `fix:` prefix)

If all changes are closely related, a single commit is fine. Don't split
artificially — three related one-line changes are better as one commit than
three separate commits.

## Step 4: Create Commits

For each group, stage the relevant files and commit:

```bash
git add <file1> <file2> ...
git commit -m "$(cat <<'EOF'
<type>(<optional-scope>): <short summary>
EOF
)"
```

**Commit message format:**
- Conventional Commits: `<type>(<optional-scope>): <short summary>`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
  `ci`, `chore`, `revert`, `deps` (the list check-pr-title.yml accepts)
- Summary: imperative mood, lowercase start, no period at end
- Under 72 characters
- Focus on *what* changed, not *how*

**Examples:**

```
feat(core): add persistence for counter state
fix: clamp counter at range bounds instead of overflowing
test: add parameterized tests for boundary values
docs: update architecture guide for new module
chore: bump pinned tool versions in mise.toml
```

Stage specific files by name — avoid `git add .` or `git add -A` which can
accidentally include sensitive files or unrelated changes.

## Step 5: Push (if requested)

Only push if the user explicitly asked to push (e.g., "commit and push",
"ship it"). If the user only said "commit", skip this step — they may want
to make more commits before pushing, or use the `create-pr` skill which
handles push on its own.

```bash
git push
# or if no upstream:
git push -u origin <current-branch>
```

## Step 6: Verify

Show the final state to confirm everything is clean:

```bash
git status
git log --oneline -<number-of-new-commits>
```

Report any remaining uncommitted files and explain why they were excluded
(should only be sensitive files).

## Pre-commit Hook Interaction

The pre-commit hook checks (format, lint, staged guard) and never modifies files;
the skill does not duplicate those checks. When it fails, the commit did not happen:
fix the cause, re-stage, and retry — never `--amend` someone else's commit, never
`--no-verify`. When the hook fails, follow
[references/pre-commit-hook.md](references/pre-commit-hook.md) for the recovery steps
and the fix for each common failure (including when a SwiftLint rule may be disabled).

## Notes

- When in doubt about grouping, fewer larger commits are better than many tiny ones
