# Enforcement layers

Which layer holds what, and where each leaves a gap. A change that adds, removes, or
narrows a layer updates this file in the same pull request.

| Layer | Fires on | Holds |
|---|---|---|
| `.githooks/pre-commit` (installed by `just install`) | `git commit` | `scripts/lint.sh --staged-tree` on the staged Swift files; the staged guard (`scripts/check-staged.sh`, rules in `scripts/guard/`) on every commit that stages a change — no secret-shaped path or credential-shaped content lands in a commit, and a staged deletion is never inspected |
| `scripts/verify-hooks.sh` (`just install`'s last step, and `just check`'s first) | `just install`, `just check` | git resolves the hooks directory to `.githooks/` and `.githooks/pre-commit` is executable — skips under CI or the `ALLOW_MISSING_GIT_HOOKS` opt-out |
| `scripts/checks/run-all.sh` (`just check-harness`, part of `just check` before `just test`) | `just check-harness`, `just check`, CI `lint` | the harness's claims about itself — the list below |
| `.swiftlint.yml`'s `no_ui_import_in_core` + `ArchitectureBoundaryTests` | the hook, `just lint`, CI `lint`; `just test`, CI `test` | Core's import ban; Core never names `URLSession` or `UserDefaults` (Foundation types no import ban sees); UI and Platform never import each other; no shipped module imports `MyAppTestSupport` |
| `.swiftlint.yml`'s `no_print_in_sources` | the hook, `just lint`, CI `lint` | no `print`/`debugPrint`/`NSLog` in shipped code |
| `scripts/coverage.sh` | `just test`, CI `test` | 80% line / 75% function coverage on `MyAppCore` |
| `AppLogTests` | `just test`, CI `test` | `AppLog.subsystem` equals the bundle identifier in `project.yml` |
| `DeepLinkTests` | `just test`, CI `test` | the scheme Core parses is the one `project.yml` registers |
| `PreferenceKeysTests` | `just test`, CI `test` | stored preference key names and defaults never change silently |
| `LocalizationTests` | `just test`, CI `test` | every `LocalizedStringResource(…)` in Core has a key, a `defaultValue`, and `bundle: .module`; its keys are exactly the catalog's; the catalog's English is what Core renders |
| CI (`.github/workflows/ci.yml`) | push to `main`, every pull request | `lint` (format, lint, shellcheck, actionlint, typos; `scripts/tests/run.sh` — the script tests and the skills' Python suites; the harness checks (`scripts/checks/run-all.sh`)), `test` (package tests + coverage floor), `app` (iOS Simulator build + XCUITest), `smoke` (`Release Smoke Launch (iOS Simulator)`, in parallel with `app`: the Release smoke launch, `just smoke`), `ios-tests` (`Package Tests (iOS Simulator)`: every package test suite on an iOS Simulator, `just test-ios`, no coverage floor), `bootstrap-smoke` (`Template Bootstrap Smoke`: `scripts/bootstrap.sh` renames a clone of the template, which is then linted, tested, and built for the simulator — template-only, so the rename removes it from every app), `changes` (ubuntu: diffs a pull request's files; when none matches the simulator-relevant path list in `ci.yml`, `app`, `smoke`, and `ios-tests` still run and report but skip their steps — a push to `main`, or a failed detection, runs them in full), and the `zizmor` workflow lint (`Workflow Security Lint`) |
| Security workflows (`codeql.yml`, `gitleaks.yml`, `osv-scan.yml`, `dependency-review.yml`, `scorecard.yml`) | every pull request (OSV, dependency review), push to `main` (CodeQL), a pull request that edits `gitleaks.yml`, and weekly schedules (CodeQL, gitleaks, OSV, Scorecard) | CodeQL for the package's Swift, a checksum-verified full-history gitleaks scan, OSV and dependency-review checks of SwiftPM dependencies, OpenSSF Scorecard |
| `.github/workflows/check-pr-title.yml` (job `Validate PR title`) | every pull request (opened, reopened, edited, synchronize) | the PR title is a Conventional Commit whose type is in its `types` list |

## What `just check-harness` holds

Each check under `scripts/checks/` re-asserts one claim; its header states what it reads
and what it cannot see.

- `just-recipes-exist.sh`: every `just <recipe>` `AGENTS.md` names exists, and every
  `Bash(just <recipe>…)` rule in a committed `.claude/settings.json`, if one is added,
  names a recipe the justfile defines.
- `workflow-pins-and-permissions.sh`: every workflow has a top-level `permissions:`,
  and every non-local `uses:` (workflows and composite actions) is pinned to a full SHA
  with a `# v…` comment.
- `workflow-hygiene.sh`: no workflow grants a `write` scope or a `read-all`/`write-all`
  shorthand at the top level (a write goes on the job that needs it, and no job takes a
  shorthand); every workflow triggered on `pull_request` declares a top-level
  `concurrency:`, and every declared group varies per run, is unique to its workflow
  unless it names `github.workflow`, and never cancels in progress on a `push` except
  through a `github.event_name` expression; every `run:` step (composite actions
  included) resolves to `shell: bash` (`-eo pipefail`) or opens with a `set` carrying
  `-e` and `pipefail`.
- `dependency-bots-agree.sh`: every Dependabot entry's and Renovate's commit prefix is a
  type the PR-title check's `types` accepts, and their release cooldowns are set and
  agree.
- `skills-frontmatter.sh` and `skills-descriptions.sh`: every skill's frontmatter is
  exactly a matching `name` and a `description`; no `SKILL.md` sits below a skill's top
  directory; every `description` is printable ASCII and at most 1,024 characters.
- `ruleset-contexts.sh`: every required status-check context in
  `.github/rulesets/main.json` matches a job `name:` (or id) in a workflow triggered on
  `pull_request`.
- `core-ban-lists-agree.sh`: `.swiftlint.yml`'s `no_ui_import_in_core` regex and
  `ArchitectureBoundaryTests.forbiddenModules` ban the same modules.
- `just-check-matches-ci.sh`: the gates `just check` runs and the `run:` steps of
  `.github/workflows/ci.yml` match in both directions, apart from its reasoned exception
  list.
- `labels-declared.sh`: every label an issue form, a workflow, a dependency bot
  (Dependabot's implied `dependencies`, Renovate's `labels`), or `scripts/label-pr.sh`'s
  type-to-label mapping applies is declared in `.github/labels.yml`, and none twice.
- `product-section-filled.sh`: `AGENTS.md`'s `## Product` section stays a `TODO:`
  skeleton while `project.yml` still names the template's app-name placeholder, and
  holds no `TODO:` marker once `scripts/bootstrap.sh` has renamed this into an app.

## Gaps

`git commit --no-verify` bypasses the hook, and a clone where `just install` never ran
has no hook at all (`scripts/verify-hooks.sh` makes that fail loudly at `just install`
and `just check` time, but a contributor who runs neither still commits without hooks).
CI is the backstop for everything except the staged guard, which no CI job re-runs over
a pull request's diff: a secret committed with `--no-verify` or from a clone without
`just install` reaches the branch unchecked. GitHub push protection and secret scanning
are the server-side layer for secrets, and `.github/workflows/gitleaks.yml` scans the
full git history weekly with a pinned, checksum-verified gitleaks, so a secret that
slipped past both is found after the fact rather than never.

**Whether `main`'s ruleset is actually in force is invisible from the checkout.** The
intended ruleset — PR required, checks green, no force-push or deletion — is defined as
code in `.github/rulesets/main.json`; `just ruleset` (`scripts/apply-ruleset.sh`)
creates or updates it via the GitHub API for whoever runs it as a repository admin.
Nothing in the checkout verifies that it was actually applied to the live repository —
that is visible only via `gh api repos/{owner}/{repo}/rulesets`, never from a git
checkout. "Use this template" does not copy rulesets, so every repository created from
this template still needs its own admin to run `just ruleset` once.

**This repository ships no Claude Code permission list.** There is no committed
`.claude/settings.json`: which commands run without a prompt is each person's own
choice, in their user-level `~/.claude/settings.json` or the gitignored
`.claude/settings.local.json`, and that choice shapes where a human is consulted rather
than what is possible. The same file is where to register `scripts/format-edited-file.sh`
as a `PostToolUse` hook on `Edit|Write|MultiEdit`
(`cd "$CLAUDE_PROJECT_DIR" && mise exec -- scripts/format-edited-file.sh`), which runs
`swiftformat` on the one `.swift` file an edit touched and reports a failure back to the
agent (exit 2) — a convenience on that host, not a gate. Another agent and a
human at a shell are bound by the instructions in `AGENTS.md` and by the gates above.

**No gate runs the app on a device, or on any iOS release but the one the pinned Xcode
ships: CI's simulators run the Xcode-pinned runtime only.**

## What no local gate sees

Every local layer can be skipped, so these reach `main` only if CI or GitHub stops them
(see Gaps above):

- `git commit --no-verify`, a clone where `just install` never ran, or a commit made
  outside this checkout's hooks — the pre-commit hook and staged guard never run.
- An edit made through GitHub's web UI or API, which touches no local hook.
- A secret inside a file whose path and content pattern the guard does not know.
- Any tool other than Claude Code: a Claude Code permission list binds nothing else.
