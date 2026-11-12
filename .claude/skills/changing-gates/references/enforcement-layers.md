# Enforcement layers

Which layer holds what, and where each leaves a gap. A change that adds, removes, or
narrows a layer updates this file in the same pull request.

| Layer | Fires on | Holds |
|---|---|---|
| `.githooks/pre-commit` (installed by `just install`) | `git commit` | `scripts/lint.sh --staged-tree` on the staged Swift files; the staged guard (`scripts/check-staged.sh`, rules in `scripts/guard/`) on every commit that stages a change — no secret-shaped path or credential-shaped content lands in a commit, and a staged deletion is never inspected |
| `scripts/verify-hooks.sh` (`just install`'s last step, and `just check`'s first) | `just install`, `just check` | git resolves the hooks directory to `.githooks/` and `.githooks/pre-commit` is executable — skips under CI or the `ALLOW_MISSING_GIT_HOOKS` opt-out |
| `scripts/checks/run-all.sh` (`just check-harness`, part of `just check` before `just test`) | `just check-harness`, `just check`, CI `lint` | the harness's claims about itself — the list below |
| `scripts/simulator-relevant.sh` + `scripts/run-throttled.sh` | `just check` | the simulator checks (`uitest-build`, `uitest-run`, `smoke`, `build-device`, `analyze`, `test-ios`) run when the change since `origin/main` touches a path they exercise, or `CHECK_ALL=1` — a git failure counts as relevant; every xcodebuild/simulator recipe holds one per-user lock under `~/.cache/run-throttled`, at a lower QoS and half the cores (`CHECK_JOBS`, `CHECK_QOS`), and runs unthrottled under CI |
| `.swiftlint.yml`'s `no_ui_import_in_core` + `ArchitectureBoundaryTests` | the hook, `just lint`, CI `lint`; `just test`, CI `test` | Core's import ban; Core never names `URLSession` or `UserDefaults` (Foundation types no import ban sees); UI and Platform never import each other; no shipped module imports `MyAppTestSupport` |
| `.swiftlint.yml`'s `no_print_in_sources` | the hook, `just lint`, CI `lint` | no `print`/`debugPrint`/`NSLog` in shipped code |
| `.swiftlint.yml`'s `analyzer_rules` (`unused_declaration`, `unused_import`) via `scripts/analyze.sh` | `just analyze` (in `just check`'s simulator-relevant tail), CI `test` — never the hook or `just lint`, which run `swiftlint lint` | no unused `internal` or `private` declaration and no unused import in any Swift file under `App/`, `LaunchUITests/`, or a package's `Sources/` or `Tests/`, judged on a clean Debug iOS Simulator `build-for-testing` of the app and of every local package; a file in no `swiftc … -module-name` compile command fails the run instead of being skipped, and a checkout path with a space is refused. `public` declarations are not checked; an import only the macOS build needs is invisible to it (`just test` compiles that), and a declaration or import used only under `#if os(macOS)`, `#if !DEBUG`, or `#if !targetEnvironment(simulator)` can be flagged falsely — restructure it or report it, never delete it |
| `scripts/coverage.sh` | `just test`, CI `test` | 80% line / 75% function coverage on `MyAppCore` |
| `AppLogTests` | `just test`, CI `test` | `AppLog.subsystem` equals the bundle identifier in `project.yml` |
| `DeepLinkTests` | `just test`, CI `test` | the scheme Core parses is the one `project.yml` registers |
| `PreferenceKeysTests` | `just test`, CI `test` | stored preference key names and defaults never change silently |
| `LocalizationTests` | `just test`, CI `test` | every `LocalizedStringResource(…)` in Core has a key, a `defaultValue`, and `bundle: .module`; its keys are exactly the catalog's; the catalog's English is what Core renders |
| CI (`.github/workflows/ci.yml`) | push to `main` and every pull request (`lint`, `zizmor`); a non-draft pull request whose diff `scripts/simulator-relevant.sh` calls relevant (macOS work in `test`, `bootstrap-smoke`) | `lint` (format, lint, shellcheck, actionlint, typos; `scripts/tests/run.sh` — the script tests and the skills' Python suites; the harness checks (`scripts/checks/run-all.sh`)), `test` (`Test & Coverage Gate`: package tests + coverage floor, then `just build-device`, the unsigned Release device-SDK compile, and `just analyze`, the analyzer rules over a clean Debug iOS Simulator compile — the one `just build` makes, which CI therefore does not run), `bootstrap-smoke` (`Template Bootstrap Smoke`: `scripts/bootstrap.sh` renames a clone of the template, which is then linted, tested, and built for the simulator — template-only, so the rename removes it from every app), `changes` (ubuntu: says false on a push to `main` or a draft, else diffs a pull request's files against `scripts/simulator-relevant.sh`; on false `test` and `bootstrap-smoke` still run and report on Ubuntu but skip their steps — a failed detection runs them in full), and the `zizmor` workflow lint (`Workflow Security Lint`). The UI test, Release smoke launch, and iOS Simulator package tests run in no CI job |
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
  directory; every `description` is printable ASCII, at most 1,024 characters, and names
  no placeholder `scripts/bootstrap.sh` rewrites, so a rename cannot lengthen it.
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
ships: the local simulators run the Xcode-pinned runtime only.** `just build-device`
(in `just check` and CI's `test` job) compiles and links Release for the device SDK,
unsigned; nothing signs, installs, or launches that build, so a signing, entitlement,
or on-device runtime failure still reaches `main` unseen.

**The simulator checks are local only.** `just uitest`, `just smoke`, and `just
test-ios` (and so every `#if os(iOS)` test) run in `just check` on the author's Mac and
in no CI job; CI records coverage, the Debug simulator compile, the unsigned Release device compile, and the analyzer rules alone, so a pull request whose
author skipped `just check` carries no simulator evidence. Nothing re-verifies `main` on
macOS after a merge, and a draft pull request runs no macOS work until it is marked
ready, so two pull requests that pass separately can break `main` together.

## What no local gate sees

Every local layer can be skipped, so these reach `main` only if CI or GitHub stops them
(see Gaps above):

- `git commit --no-verify`, a clone where `just install` never ran, or a commit made
  outside this checkout's hooks — the pre-commit hook and staged guard never run.
- An edit made through GitHub's web UI or API, which touches no local hook.
- A secret inside a file whose path and content pattern the guard does not know.
- Any tool other than Claude Code: a Claude Code permission list binds nothing else.
