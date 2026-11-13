# Enforcement layers

Which layer holds what, and where each leaves a gap. A change that adds, removes, or
narrows a layer updates this file in the same pull request.

| Layer | Fires on | Holds |
|---|---|---|
| `.githooks/pre-commit` (installed by `just install`) | `git commit` | `scripts/lint.sh --staged-tree` on the staged Swift files; the staged guard (`scripts/check-staged.sh`, rules in `scripts/guard/`) on every commit that stages a change — no secret-shaped path or credential-shaped content lands in a commit, and a staged deletion is never inspected |
| `scripts/verify-hooks.sh` (`just install`'s last step, and `just check`'s first) | `just install`, `just check` | git resolves the hooks directory to `.githooks/` and `.githooks/pre-commit` is executable — skips under CI or the `ALLOW_MISSING_GIT_HOOKS` opt-out |
| `scripts/checks/run-all.sh` (`just check-harness`, part of `just check` before `just test`) | `just check-harness`, `just check`, CI `lint` | the harness's claims about itself — the list below |
| `scripts/simulator-relevant.sh` + `scripts/run-throttled.sh` | `just check`, `just check-release` | each simulator check `just check` holds runs when the change since `origin/main` touches a path it exercises (`--check uitest`: `uitest-build` and `uitest-run`, for the UI and app paths; `--check test-ios`: `test-ios`, for the platform-adapter paths), or under `CHECK_ALL=1` — a git failure counts as relevant, an empty change set as not; `uitest-ipad` (the launch UI test on an iPad `scripts/simulator-destination.sh --family ipad` resolves, shut down after; skipped with a one-line notice when `scripts/targets-ipad.sh` finds no iOS target built for iPad), `smoke`, `build-device`, and `analyze` run only in `just check-release`, after `CHECK_ALL=1 just check`; every xcodebuild/simulator recipe holds one per-user lock under `~/.cache/run-throttled`, at a lower QoS and half the cores (`CHECK_JOBS`, `CHECK_QOS`), and runs unthrottled under CI |
| `.swiftlint.yml`'s `no_ui_import_in_core` + `ArchitectureBoundaryTests` | the hook, `just lint`, CI `lint`; `just test`, CI `test` | Core's import ban; Core never names `URLSession` or `UserDefaults` (Foundation types no import ban sees); UI and Platform never import each other; no shipped module imports `MyAppTestSupport` |
| `.swiftlint.yml`'s `no_print_in_sources` | the hook, `just lint`, CI `lint` | no `print`/`debugPrint`/`NSLog` in shipped code |
| `.swiftlint.yml`'s `analyzer_rules` (`unused_declaration`, `unused_import`) via `scripts/analyze.sh` | `just analyze` (in `just check-release`) — never the hook, `just lint`, `just check`, or CI, which run `swiftlint lint` at most | no unused `internal` or `private` declaration and no unused import in any Swift file under `App/`, `LaunchUITests/`, or a package's `Sources/` or `Tests/`, judged on a clean Debug iOS Simulator `build-for-testing` of the app and of every local package; a file in no `swiftc … -module-name` compile command fails the run instead of being skipped, and a checkout path with a space is refused. `public` declarations are not checked; an import only the macOS build needs is invisible to it (`just test` compiles that), and a declaration or import used only under `#if os(macOS)`, `#if !DEBUG`, or `#if !targetEnvironment(simulator)` can be flagged falsely — restructure it or report it, never delete it |
| `scripts/coverage.sh` | `just test`, CI `test` | 80% line / 75% function coverage on `MyAppCore` |
| `AppLogTests` | `just test`, CI `test` | `AppLog.subsystem` equals the bundle identifier in `project.yml` |
| `DeepLinkTests` | `just test`, CI `test` | the scheme Core parses is the one `project.yml` registers |
| `PrivacyManifestTests` + `RequiredReasonAPITests` | `just test`, CI `test` | `App/PrivacyInfo.xcprivacy` keeps `UserDefaults`/`CA92.1`, no tracking and no collected data; every required-reason API category whose Apple-listed symbol appears in the code (comments and one-line strings stripped) of a `.swift`, `.c`, `.h`, `.m`, or `.mm` file under `Packages/MyAppKit/Sources/` or `App/` has an entry with at least one reason (a textual scan, the fast signal: no binary dependency, no alias, no judgment of the reason; the linked binary is `scripts/build-device.sh`'s) |
| `scripts/build-device.sh`'s bundle check | `just build-device` (in `just check-release`) | the Release device build links `MyApp.app/MyApp` and bundles `PrivacyInfo.xcprivacy` at its root, passing `plutil -lint` and equal to `App/PrivacyInfo.xcprivacy` (`ERR_BUILD_DEVICE_NO_APP`, `ERR_BUILD_DEVICE_NO_PRIVACY_MANIFEST`, `ERR_BUILD_DEVICE_PRIVACY_MANIFEST_INVALID`, `ERR_BUILD_DEVICE_PRIVACY_MANIFEST_MISMATCH`), from a bundle removed before the build; every required-reason API category the linked executable uses — its imported symbols (`xcrun nm -u`) and sent Objective-C selectors (`xcrun otool`), through the script's `REQUIRED_REASON_APIS` table — has an entry with at least one reason in the bundled manifest, and every app extension's executable (`PlugIns/*.appex`) the same against the `PrivacyInfo.xcprivacy` in its own bundle (`ERR_BUILD_DEVICE_UNDECLARED_REQUIRED_REASON_API`; an executable `nm` or `otool` cannot read — otool's section header and at least one selector line are required — or an extension naming none, `ERR_BUILD_DEVICE_SYMBOLS_UNREADABLE`) |
| `PreferenceKeysTests` | `just test`, CI `test` | stored preference key names and defaults never change silently |
| `LocalizationTests` | `just test`, CI `test` | every `LocalizedStringResource(…)` in Core has a key, a `defaultValue`, and `bundle: .module`; its keys are exactly the catalog's; the catalog's English is what Core renders |
| CI (`.github/workflows/ci.yml`) | push to `main` and every pull request (`lint`, `zizmor`); a non-draft pull request whose diff `scripts/simulator-relevant.sh` calls relevant (macOS work in `test`, `bootstrap-smoke`) | `lint` (format, lint, shellcheck, actionlint, typos; `scripts/tests/run.sh` — the script tests and the skills' Python suites; the harness checks (`scripts/checks/run-all.sh`)), `test` (`Test & Coverage Gate`: package tests + coverage floor on the host, and nothing else), `bootstrap-smoke` (`Template Bootstrap Smoke`: `scripts/bootstrap.sh` renames a clone of the template, which is then linted, tested, and built for the simulator — template-only, so the rename removes it from every app), `changes` (ubuntu: says false on a push to `main` or a draft, else diffs a pull request's files against `scripts/simulator-relevant.sh`; on false `test` and `bootstrap-smoke` still run and report on Ubuntu but skip their steps — a failed detection runs them in full), and the `zizmor` workflow lint (`Workflow Security Lint`). The UI test, iOS Simulator package tests, Release smoke launch, Release device build, and analyzer rules run in no CI job |
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
- `required-reason-tables-agree.sh`: `scripts/build-device.sh`'s `REQUIRED_REASON_APIS`
  and `RequiredReasonAPIScan.categories` name the same required-reason categories (the
  categories only: the symbols differ by design, a binary's spelling against a
  source's).
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
(in `just check-release`) compiles and links Release for the device SDK,
unsigned, and checks that the privacy manifest is in the bundle and declares every
required-reason API the executable uses; nothing signs, installs, or launches that build, so a signing, entitlement,
or on-device runtime failure still reaches `main` unseen.

**The privacy manifest is held to the code twice, and the binary check is the one that
counts.** `RequiredReasonAPITests` scans the shipped sources' text in `just test`, on
every pull request, in seconds; `scripts/build-device.sh` reads the linked Release
executable in `just build-device`, which only `just check-release` runs. Both stay: the
binary is what App Store Connect judges and the only place a call reached through a
package, an alias, or generated code shows, but it waits for a release check, so
without the scan a new `systemUptime` call with no manifest entry would merge and
surface only then. `required-reason-tables-agree.sh` (`just check-harness`) keeps the
two tables on the same categories; within a category, each table's symbols are its own. The scan's misses (anything outside the source text) and its false
reports (a domain identifier named like a listed symbol) are why it is not the
authority; when the two disagree, the binary's answer stands. The binary check reads
the app's executable and each app extension's, each against the manifest in its own
bundle. Neither reads a framework
embedded under `MyApp.app/Frameworks/`, a symbol looked up with `dlsym`, or a selector
built at run time, and neither judges whether a declared reason is the right one —
that stays the author's and the reviewer's. The binary check's own blind spots: a
`selector` row matches any selector of that name in the binary, so the app's own
`@objc` member called `systemUptime` reads as Apple's API (the error's `Next:` says to
rename the member), and an `import-part` row (`So14NSUserDefaultsC`) matches the
literal mangled spelling only, so a Swift symbol whose mangling abbreviates it with a
word substitution is not seen. The binary table's spellings were read from
a probe built against one SDK (the script's comment names it): a later SDK that links
an API under another name leaves its row unmatched, silently.

**The simulator checks are local only.** `just uitest` and `just test-ios` (and so
every `#if os(iOS)` test) run in `just check` on the author's Mac only when the change
touches their paths, and in no CI job; CI records the host package tests and coverage
alone, so a pull request whose author skipped `just check` carries no simulator
evidence. **Nothing on a pull request's path runs `just analyze`, `just build-device`,
or `just smoke`**, nor `just uitest` or `just test-ios` unless the diff touches their
paths, nor the launch UI test on an iPad at all: an unused declaration or import, a
device-SDK-only compile break, a Release launch crash, an iOS-only test failure, or a
launch-test failure only an iPad layout shows merges unseen and is found at `just
check-release`, run on `main` before a release tag and after a batch of merges. That
delay is the accepted trade: those failures are rare and cheap to fix later, while
their checks are several clean builds plus about ten minutes of `swiftlint analyze`,
which on every pull request made one `just check` take 20-30 minutes under a lock every
worktree waits on; running them in CI instead costs macOS minutes, which are paid once a
repository cut from the template is private. Nothing re-verifies `main` on macOS after
a merge until `just check-release` runs there, and a draft pull request runs no macOS
work until it is marked ready, so two pull requests that pass separately can break
`main` together.

## What no local gate sees

Every local layer can be skipped, so these reach `main` only if CI or GitHub stops them
(see Gaps above):

- `git commit --no-verify`, a clone where `just install` never ran, or a commit made
  outside this checkout's hooks — the pre-commit hook and staged guard never run.
- An edit made through GitHub's web UI or API, which touches no local hook.
- A secret inside a file whose path and content pattern the guard does not know.
- Any tool other than Claude Code: a Claude Code permission list binds nothing else.
