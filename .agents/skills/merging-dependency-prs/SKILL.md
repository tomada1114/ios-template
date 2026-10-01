---
name: merging-dependency-prs
description: >
  Covers landing already-open Dependabot and Renovate pull requests in this repository:
  Dependabot's SwiftPM (Package.resolved) and GitHub Actions bumps, and Renovate's
  mise.toml and gitleaks bumps. Surveys the bot PRs, runs a security checklist (changelog, new
  workflow permissions, maintainer or repository change), asks the human for one
  approval covering a listed batch of PASSING PRs, then merges them or builds one
  combined branch for conflicting bumps. Use when clearing a backlog of bump PRs, when a
  bot PR fails CI after a SwiftLint or SwiftFormat bump, or when several dependency PRs
  contest the same file.
---

# Merging dependency PRs

**Owns:** landing bot PRs that already exist — survey, security review, the approval
gate, individual merges, the combined branch, and cleanup.
**Does not own:** the pin-bump policy itself — which bot bumps what, the `deps:`/`ci:`
title prefixes, the 7-day cooldown, and the hand-bumped `.xcode-version`. That has one
statement, `.claude/rules/project.md` › Toolchain Pinning; read it, never restate or
override it here. Adding a **new** dependency (not a bump) is out of scope: it needs a
human's sign-off under `.claude/rules/project.md`'s dependency policy and AGENTS.md
"Security and human approval".

All branch names, commits, comments, and PR text are English and Conventional Commits.

## The approval gate

Merging a PR is a remote write, and AGENTS.md "Security and human approval" requires a
human's sign-off for it. This skill is **not** one of that section's Standing
exceptions, so invoking it is not the sign-off. The gate is:

1. Do the whole survey and review first, touching nothing remote.
2. Present the plan: the exact list of PR numbers to merge (the allow-list), which go
   individually and which into a combined branch, which are held and why, and every
   major bump called out by name.
3. Get **one** explicit approval from the human for that listed batch, then execute it
   without asking per merge.

The approval covers only the listed PRs, only for this invocation. A PR opened later,
a PR whose diff changed after approval (beyond a bot rebase), or anything in the stop
list below needs a fresh approval. Never merge before the approval.

## Step 1: Survey (read-only)

```bash
gh pr list --author app/dependabot --state open --json number,title,headRefName,mergeStateStatus,files
gh pr list --author app/renovate   --state open --json number,title,headRefName,mergeStateStatus,files
gh pr checks <number>
gh pr diff <number>
```

If both lists are empty, say so and stop. Expected shapes:

| Bot | Ecosystem | Touches | Title prefix |
|---|---|---|---|
| Dependabot | SwiftPM | `Packages/MyAppKit/Package.resolved` (and `Package.swift` for a range change) | `deps:` |
| Dependabot | GitHub Actions | `.github/workflows/*.yml`, `.github/actions/**` | `ci:` |
| Renovate | mise | `mise.toml` | `deps:` |
| Renovate | regex (gitleaks) | `GITLEAKS_VERSION` in `.github/workflows/gitleaks.yml` | `deps:` |

Minor and patch bumps are expected to arrive grouped, one PR per ecosystem, carrying
several dependencies; majors arrive one per PR. Read a grouped PR's diff in full — its
title is only as precise as the bot made it.

## Step 2: Security checklist (every PR, before the plan)

- **Changelog / release notes:** read them for every major bump and every `0.x` minor
  (treat it as a major). Note removed APIs, a raised Swift tools version or
  `platforms:` minimum, and new SwiftLint rules.
- **Platform floor:** a SwiftPM bump whose package raises its `platforms:` above this
  package's `.iOS(.v27)` or `.macOS(.v27)` (`Packages/MyAppKit/Package.swift`) is not
  mergeable: taking it means raising the deployment floor, an ADR-level decision
  (AGENTS.md "Before changing the architecture"). Hold it with that reason, green or not.
- **gitleaks checksum:** a Renovate gitleaks bump cannot rewrite `GITLEAKS_SHA256`, so
  its `Gitleaks History Scan` run fails until a human updates the hash, as the PR body
  says. Hold it until that run passes; never loosen the checksum step.
- **New permissions:** an Action bump must not widen any workflow's `permissions:`,
  add a `secrets:` input, or switch a `pull_request` trigger to `pull_request_target`.
  Any of these is a gate change — stop and ask, outside the batch (the `changing-gates`
  skill).
- **Pins stay pinned:** every non-local `uses:` stays a full 40-character SHA with a
  `# v…` comment, and the comment matches the new tag.
  `scripts/checks/workflow-pins-and-permissions.sh` (via `just check-harness`) fails CI
  otherwise; a PR that drops the SHA or the comment is held, not fixed by loosening the
  check.
- **Maintainer or source change:** a SwiftPM package whose URL moved to another owner,
  an Action whose repository was transferred, or a mise tool whose backend changed is
  held for the human even when green.
- **No supply-chain relaxation:** a bot PR must not touch `.github/dependabot.yml`'s
  cooldown, `.github/renovate.json`'s `minimumReleaseAge`, or any gate file beyond the
  version it bumps.
- **Nothing new:** a `Package.resolved` gaining a package that was not there before is
  a new (transitive) dependency — call it out in the plan by name.

## Step 3: Classify and choose the landing mode

A PR is on the allow-list only if **all** hold: `gh pr checks` shows every check
`pass` (a `skipping` check counts as passing; `fail`, `pending`, `cancel`, or anything
unrecognised does not), its merge state is `CLEAN`, and the checklist found nothing.
An unknown CI state holds a PR; it is never waved through.

A SwiftPM PR's checks include the `Package Tests (iOS Simulator)` job (`just test-ios`)
and the `App Build & UI Test (iOS Simulator)` job (`just uitest`): a package bump can
behave differently on the iOS runtime than in the host `swift test`, so a SwiftPM PR
with either job missing or not yet `pass` is not eligible.

**Merge individually** when the eligible PRs share no file. In practice this is the
Actions PRs and a lone SwiftPM or mise PR.

**Build one combined branch** when two eligible PRs touch the same file (two SwiftPM
PRs both rewrite `Package.resolved`; two Renovate PRs both edit `mise.toml`), or when
more than three are eligible and sequential rebase-and-wait cycles would dominate.

Mixed outcomes are fine; the plan says which PR goes which way.

## Step 4a: Individual merges

In ascending PR number, one at a time. After each merge the rest go `BEHIND`: ask the
bot to rebase (`@dependabot rebase`, or tick Renovate's rebase checkbox) and re-run
`gh pr checks <n>` **after** the rebase. Never merge on a check result older than the
PR's last push.

```bash
gh pr checks <number>
gh pr merge <number> --squash --delete-branch
```

## Step 4b: The combined branch

```bash
git switch -c deps/combined-<yyyy-mm-dd> origin/main
```

Apply each PR's version change by hand, not by merging bot branches:

- **SwiftPM:** edit `Package.swift` only if a PR changed a range, then
  `swift package resolve --package-path Packages/MyAppKit` to regenerate
  `Package.resolved`. Commit `Package.resolved` with the change (the `smart-commit`
  skill bundles it).
- **mise:** edit `mise.toml`, then `mise install` so the pinned version actually exists.
- **Actions:** copy the new SHA and its `# v…` comment exactly.

Then verify: `just check`, then — when the branch carries a SwiftPM bump — `just test-ios`
(a package bump can behave differently on the iOS runtime) and `just uitest`. A SwiftLint or SwiftFormat bump may fire new rules or reformat
code: fix the code on this branch (`just fix`, then hand edits), never disable or relax
a rule to get green — that is weakening a gate. Open the PR (**REQUIRED:** `create-pr`),
title `deps: combine dependency bumps (#a, #b, …)`, listing each superseded PR. Once its
CI is green and it is merged, close each superseded PR with a comment naming the
combined PR. Opening and merging the combined PR are inside the approved batch only if
the plan named it.

## Stop and ask (outside any batch approval)

- A workflow `permissions:` widening, a new secret, or a trigger change in an Action bump.
- A maintainer, owner, or source change on any bumped dependency.
- A new package appearing in `Package.resolved`, or a bump that needs a new dependency.
- A SwiftPM bump that raises a package's `platforms:` above `.iOS(.v27)` or
  `.macOS(.v27)`: raising the floor needs an ADR first (`recording-architecture-decisions`).
- A bump that only goes green by disabling a lint rule, lowering the coverage floor, or
  editing another gate file.
- A bump of `.xcode-version`: bots never open one; it is hand-bumped per Toolchain Pinning.

## Failure modes

| Symptom | Usual cause | Response |
|---|---|---|
| `lint` fails on a SwiftLint/SwiftFormat PR | New rule or formatting default | Fix code on that PR or the combined branch; never skip the bump |
| `check-harness` fails on an Actions PR | SHA or `# v…` comment dropped or mismatched | Hold; restore the pin format in the combined branch |
| `test` fails after a SwiftPM bump | Real API change in the package | Read the release notes; fix on the branch or hold with a reason |
| `ios-tests` or `app` fails while `test` passes | The package behaves differently on the iOS runtime | Reproduce with `just test-ios` or `just uitest`; fix on the branch or hold with a reason |
| `Gitleaks History Scan` fails on a gitleaks PR | `GITLEAKS_SHA256` still names the old release | The human copies the new linux_x64 hash into it; merge only once the run passes |
| `swift package resolve` changes unrelated pins | A range in `Package.swift` was loose | Revert unrelated pin moves; resolve only what the PRs bumped |
| mise PR green but `mise install` fails locally | Version not yet published for this platform | Hold until it is |
| `check-pr-title` fails | Bot prefix drifted from Toolchain Pinning's list | Change the bot config and `check-pr-title.yml` together, per that section |
| PR goes `DIRTY` after a sibling merged | Contested file | Move it into the combined branch |

## Report

End with: merged PRs, the combined PR (if any) and what it superseded, held PRs with
the reason each, and any follow-up the human needs to decide.
