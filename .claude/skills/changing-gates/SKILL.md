---
name: changing-gates
description: >
  Covers editing a file that enforces rather than implements: .swiftlint.yml,
  .swiftformat, Package.swift's strictSettings, mise.toml, .githooks/pre-commit,
  scripts/lint.sh, scripts/coverage.sh, the scripts/guard/ commit-time guard, a
  scripts/checks/ harness check, or a .github/workflows/*.yml workflow. Use when a
  SwiftLint rule is added, disabled, or loosened, a SwiftFormat option changes, a target
  is added to Package.swift, a tool pin is added or bumped, a pre-commit section, a
  harness check, or a CI job or step is proposed, the coverage floor is touched, or the
  question is which gate would have caught a change - including what none of them sees.
---

# Changing Gates

**Owns:** a change to a file that enforces rather than implements — `.swiftlint.yml`,
`.swiftformat`, `Package.swift`'s `strictSettings`, `mise.toml`, `.githooks/pre-commit`,
`scripts/lint.sh`, `scripts/coverage.sh`, the commit-time guard under `scripts/guard/`,
the harness checks under `scripts/checks/`, and `.github/workflows/*.yml` — and which
gate can see a given change at all. **Does not own:** adding a package dependency (the Dependency Policy in `.claude/rules/project.md`);
the content of a repository-specific lint rule; how a script under `scripts/` is written
(`writing-repo-scripts`); the label set in `.github/labels.yml` (`triaging-issues`).

Never weaken a gate to make a check pass: that rule is stated in `AGENTS.md`'s
"Security and human approval" and "Important Reminders" sections, and this skill does
not restate or relax it. A change that lowers, disables, or widens a gate needs a
human's sign-off, and its PR says why the removed protection no longer applies.

## The one rule every gate change shares

A gate file may narrow _what_ a shared script looks at; it never defines a rule of its
own. `scripts/lint.sh` is the single lint script: `just lint`
(`mise exec -- scripts/lint.sh`), the pre-commit hook (`--staged-tree`), and CI's `lint`
job all call it. A new check is therefore added to `scripts/lint.sh`, never inlined as a
command into `justfile`, `.githooks/pre-commit`, or a workflow `run:` step. The same
shape holds elsewhere: CI's `test` job calls `scripts/coverage.sh` (what `just test`
runs), its `lint` job calls `scripts/tests/run.sh` and `scripts/checks/run-all.sh`
(what `just test-scripts` and `just check-harness` run), and the `app` job calls
`just build` and `just uitest`. `scripts/checks/just-check-matches-ci.sh` holds the two
sides to the same set of gates, in both directions, apart from its reasoned exception
list.

A check in `scripts/lint.sh` is three edits, not one:

- the `run …` line, so the check runs and a failure is collected without stopping the
  checks after it;
- the tool in `REQUIRED_TOOLS` for its mode, so a missing tool fails as
  `ERR_LINT_TOOL_MISSING` instead of as a confusing linter error;
- the tool in `mise.toml` and in the `install_args` of ci.yml's `lint` job. That job
  runs on `ubuntu-latest` and installs only the Linux-capable subset, so a macOS-only
  tool cannot join `scripts/lint.sh` at all — it belongs in a macOS job.

`scripts/tests/run.sh` (`just test-scripts`) is a gate on the gates:
`scripts/tests/lint_test.sh` pins `scripts/lint.sh`, one test file pins each hook
section, and `scripts/tests/checks_test.sh` pins every harness check. A change to one of
those files keeps its test green, and a new script gets a test as `AGENTS.md`'s
"Repository scripts" requires.

## `.swiftlint.yml`

`strict: true` makes every warning an error, and `opt_in_rules: [all]` enables every
opt-in rule, so a new SwiftLint release can add rules that fire on a pin bump. Every
entry in `disabled_rules` carries a one-line trailing reason; a new entry without one
is incomplete, and removing a rule needs explicit approval
(`.claude/rules/project.md`). Prefer an inline `// swiftlint:disable:next <rule>` with
a reason when only one site needs the exception — a global disable widens the gate for
every future file; either, used to make a failing check pass, still needs sign-off.
Repository-specific rules live under `custom_rules:`; there are two.

`no_ui_import_in_core` keeps `MyAppCore` from importing a UI, persistence, or
OS-integration framework, and its module list changes together with
`ArchitectureBoundaryTests`' `forbiddenModules` in one commit
(`scripts/checks/core-ban-lists-agree.sh` fails while they differ);
`no_print_in_sources` rejects `print(`, `debugPrint(`, and `NSLog(` in shipped sources.
**REQUIRED:** before editing either rule, read
[references/swiftlint-custom-rules.md](references/swiftlint-custom-rules.md): the
module list and why `os`/`OSLog` stay off it, the boundaries held by the test alone, and
the four load-bearing parts of `no_print_in_sources` a widening edit usually breaks.

`analyzer_rules` is deliberately absent: those run only under `swiftlint analyze` with a
compiler log, which no gate here invokes. `trailing_comma` is set to agree with
SwiftFormat; the two tools must never disagree about one file.

## `.swiftformat`

`just fmt` applies it (`swiftformat .`); `scripts/lint.sh` only checks
(`swiftformat --lint`), so a formatting change surfaces in `just lint`, the hook, and
CI, never as a silent rewrite. Changing an option reformats the whole tree: land the
option and the resulting reformat in the same commit, and check that the output still
passes `swiftlint --strict`. `--swiftversion` follows the package's tools version.

`--decimalgrouping 3,4` is the same agreement as `trailing_comma` in the other
direction: SwiftLint's `number_separator` requires separators from four digits, so
SwiftFormat is set to group by three from four digits up rather than SwiftLint being
relaxed — otherwise `just fmt` strips a separator from a four-digit literal that
`swiftlint --strict` then demands back. `scripts/tests/lint_test.sh`'s number-separator
case (a 4- and a 5-digit literal pass both linters) runs the pinned tools against each
other and fails if they drift, for example on a SwiftLint or SwiftFormat bump.

## `Package.swift`'s `strictSettings`

`strictSettings` holds `.swiftLanguageMode(.v6)` and `.treatAllWarnings(as: .error)`.
It is not inherited: each target passes `swiftSettings: strictSettings` itself, so a new
target — source, test, or a test-support library like `MyAppTestSupport` — must opt in
explicitly, or it compiles without Swift 6 data-race errors and with warnings allowed.
Removing an entry, or adding an `unsafeFlags` or a per-target exception, is weakening a
gate. A new target is also an architecture decision (`AGENTS.md`'s "Before changing the
architecture").

## `mise.toml`

It pins every CLI tool the gates call; scripts call those tools by bare name and the
caller provides PATH. A pin is an exact version, never `latest`, and is not bumped by
hand; `.claude/rules/project.md`'s Toolchain Pinning is the one statement of that
policy, including why `.xcode-version` is the exception that is hand-bumped. No bot
opens pin-bump pull requests here yet; an open issue adds one (`AGENTS.md`'s "Harness
status"). A SwiftLint or SwiftFormat bump is a gate change in its own right: new rules or
formatting may fire, and the fix is to the code or a reasoned `disabled_rules` entry on
that PR, never to skip the bump silently. The Xcode pin lives in `.xcode-version`, which
every macOS job reads through `.github/actions/select-xcode`.

## `scripts/coverage.sh`

It gates on line and function coverage of `Sources/MyAppCore/` only, by filtering
llvm-cov's report to that path. `MyAppUI` and `MyAppPlatform` are outside it because a
view or an adapter holds translation rather than a decision (`AGENTS.md`'s
"Architecture") — not because nothing exercises them: `MyAppPlatformTests` runs under
plain `swift test`, so under `just test` and CI's `test` job, against an in-memory
SwiftData store that needs no device and no permission. The filter is a path, not a
target list, so those tests add nothing to the floor. The floors are `readonly COVERAGE_FLOOR=80` (lines) and
`FUNCTION_COVERAGE_FLOOR=75` in the script and nothing else — no environment variable or
flag moves either, so every change is a reviewed diff of this file, and only ever a
raise. The function floor sits lower because llvm-cov counts compiler-generated closures
(an `os.Logger` interpolation) as functions no test evaluates; the script's header
records the value it was set against. The script rejects the environment override it
used to read with `ERR_COVERAGE_OVERRIDE_REMOVED` before any test runs, rather than
silently ignoring it; `scripts/tests/coverage_test.sh` holds that. Adding a new way to
set the floor from a recipe, workflow, or hook is lowering it by another route.

## `.githooks/pre-commit`

Independent sections — "Swift lint", "Skills mirror", "Staged guard" — each scoped by
the staged paths it cares about, none exiting early, each calling a shared script on the
staged content rather than the worktree. The hook stays lint-only by decision: it never
formats and re-stages, compiles, or runs tests. It only reaches clones that ran
`just install`, a gap `scripts/verify-hooks.sh` narrows but does not close.
**REQUIRED:** before adding or changing a section, read
[references/pre-commit-hook.md](references/pre-commit-hook.md): what each section runs,
the layout and cleanup rules a new section follows, why the hook never builds, and what
`scripts/verify-hooks.sh` does and does not catch.

## `scripts/guard/`

`scripts/check-staged.sh` (the hook's "Staged guard" section) classifies each staged
path with `scripts/guard/paths.sh` first, and only scans the staged blob of a path that
passes with `scripts/guard/credentials.sh`. Staged deletions are never inspected: they
cannot add a secret, and blocking one would block the commit that removes a secret.
Those two files are the list — read them for exactly what is checked.

**REQUIRED:** before adding, removing, or loosening a path or content rule, read
[references/guard-patterns.md](references/guard-patterns.md): what is blocked by path,
what by content, what is deliberately not blocked, and how a new pattern's test fixture
is built.

Removing a pattern or a path rule is weakening a gate. `git commit --no-verify` skips
this guard with every other hook section, and no CI job reruns it: that gap is written
down under `AGENTS.md`'s "Enforcement layers".

## `scripts/checks/`

`scripts/checks/run-all.sh` (`just check-harness`) runs every check in the directory,
each re-asserting one claim the harness makes about itself; `AGENTS.md`'s "Enforcement
layers" row for it is the full list, and each check's header states what it reads and
what it cannot see. A new check takes `--root DIR` through `scripts/checks/lib.sh`, gets
its failure-mode fixtures in `scripts/tests/checks_test.sh`, and extends that row in the
same pull request. Deleting a check, or narrowing what it reads, is weakening a gate; an
exception added to `scripts/checks/just-check-matches-ci.sh` carries its reason.

## `.github/workflows/`

`ci.yml` splits into `lint` (ubuntu: `scripts/lint.sh`, `scripts/tests/run.sh`,
`scripts/checks/run-all.sh`), `test` (macos-26: `scripts/coverage.sh`), `app`
(macos-26: `just build`, then `just uitest` on an iPhone simulator that
`scripts/simulator-destination.sh` chooses, with the `.xcresult` bundles uploaded on
failure), and `zizmor` (ubuntu: the required `Workflow Security Lint`, zizmor's audit of
every workflow, configured by `.github/zizmor.yml`). Beside it run `check-pr-title.yml`
(the required `Validate PR title`) and `pr-label.yml`, which labels a pull request from
its title type with `scripts/label-pr.sh` checked out at the base SHA, and the security
workflows: `codeql.yml` (CodeQL for the package's Swift, on push to `main` and weekly),
`gitleaks.yml` (a checksum-verified full-history gitleaks scan, weekly and on a pull
request that edits it, with `.gitleaksignore` holding the fake fixture's fingerprints),
`osv-scan.yml` (OSV on every pull request and weekly), `dependency-review.yml` (the
required `Dependency Review`, with the license allow-list), and `scorecard.yml` (OpenSSF
Scorecard, weekly). A job added later is added to this paragraph by the change that adds
it.
Which layer holds what is `AGENTS.md`'s "Enforcement layers" table; read it rather than
re-deriving it.

Every workflow follows a set of conventions — remote `uses:` pinned to a full SHA, a
narrow top-level `permissions:`, `persist-credentials: false`, a `pull_request`
`concurrency:` group, and a shell that stops at the first failure. Widening
`permissions:` or adding a workflow that writes needs sign-off. **REQUIRED:** before
editing a workflow, read
[references/workflow-conventions.md](references/workflow-conventions.md) for the full
list and which of it `actionlint`, `zizmor`, and `just check-harness` check.

## What no gate here sees

Nothing launches a Release build: `just build` and `just uitest` build Debug for the
simulator, and no smoke check exists yet. The one XCUITest,
`LaunchUITests/LaunchTests.swift`'s `testAddingAnItemShowsItInTheList` (`just uitest`),
asserts only that the app launches and that one added item appears in the list, on the
one simulator runtime CI's Xcode ships. Any other UI behavior, and every `MyAppUI` code
path, is outside the coverage floor and asserted by no gate. Code under `#if os(iOS)` in
the Swift package compiles only in `just build` and `just uitest` — `swift test`
builds the package for the host Mac — and no test exercises it. Nothing runs the app on the
iOS 18 deployment floor or on a physical device. Info.plist usage-description strings,
entitlements, and signing settings are unchecked. Each is a place a change can be wrong
while every gate passes; a gate proposed to close one is a real gate change and belongs
in the PR as one.
