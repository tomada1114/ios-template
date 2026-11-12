# CI jobs and workflows

Read from [SKILL.md's `.github/workflows/` section](../SKILL.md#githubworkflows)
before adding, removing, or renaming a job or a workflow.

`ci.yml` splits into `lint` (ubuntu, on push to `main` and every pull request:
`scripts/lint.sh`, `scripts/tests/run.sh`, `scripts/checks/run-all.sh`), `test` (the
required `Test & Coverage Gate`, the one macOS gate job: xcode-27 runs
`scripts/coverage.sh`, then `just build` — the Debug app for the generic iOS Simulator
destination — then `just build-device` — the Release app for the generic iOS device
destination with `CODE_SIGNING_ALLOWED=NO`, the one `iphoneos` compile, asserting the
`.app` exists; nothing is signed, archived, or installed — then `just analyze` —
`swiftlint analyze --strict` with `.swiftlint.yml`'s `analyzer_rules`, over the compiler
log of a clean iOS Simulator `build-for-testing` of the app and of the package that
`scripts/analyze.sh` makes itself, since the analyzer needs the test targets' compile
commands too and `just build` compiles neither), `bootstrap-smoke` (the required `Template Bootstrap Smoke`:
`scripts/bootstrap.sh` renames a clone of the template, then the renamed tree is
linted, its skill descriptions are re-checked (`scripts/checks/skills-descriptions.sh`,
which on every pull request already refuses a description naming a placeholder the
rename would lengthen), tested, and built for the simulator — template-only, so the rename removes it
from every app), `changes` (ubuntu, not required: says `simulator=false` on a push to
`main` and on a draft pull request, otherwise runs `scripts/simulator-relevant.sh
--base … --head …`, a `git diff --name-only` of the pull request against the one path
list that script holds and `just check` also reads; `test` and `bootstrap-smoke` need
it, always run under their required names, take an Ubuntu runner and skip their steps
only on its exact output `false`, and a failed `changes` leaves the output empty so
they run in full on macOS; a job skipped outright would report as passing). The UI
test, the Release smoke launch, and the iOS Simulator package tests have no CI job:
they run in local `just check` only, to keep CI's macOS minutes minimal. A pull request
also fires on `ready_for_review`, so marking a draft ready starts the run that does the
macOS work. and `zizmor` (ubuntu: the required `Workflow Security Lint`, zizmor's audit of
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

Dependabot (`.github/dependabot.yml`) bumps the pinned `uses:` SHAs and their `# v…`
comments in `ci:`-prefixed pull requests (Toolchain Pinning's prefix and cooldown, held
by `scripts/checks/dependency-bots-agree.sh`).
