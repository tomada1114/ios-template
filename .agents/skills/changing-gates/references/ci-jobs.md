# CI jobs and workflows

Read from [SKILL.md's `.github/workflows/` section](../SKILL.md#githubworkflows)
before adding, removing, or renaming a job or a workflow.

`ci.yml` splits into `lint` (ubuntu: `scripts/lint.sh`, `scripts/tests/run.sh`,
`scripts/checks/run-all.sh`), `test` (macos-26: `scripts/coverage.sh`), `app`
(macos-26: `just build`, then `just uitest` on an iPhone simulator that
`scripts/simulator-destination.sh` chooses, then the "Smoke launch (Release)" step,
`just smoke` — `scripts/smoke_launch.sh` builds Release and asserts the app stays alive
on that simulator for ten seconds — with the `.xcresult` bundles uploaded on failure),
`ios-tests` (macos-26, the required `Package Tests (iOS Simulator)`: `just test-ios` runs
every package test suite on that simulator, with no coverage floor, uploading its
`.xcresult` on failure), `bootstrap-smoke` (macos-26, the required
`Template Bootstrap Smoke`: `scripts/bootstrap.sh` renames a clone of the template, then
the renamed tree is linted, tested, and built for the simulator — template-only, so the
rename removes it from every app), and `zizmor` (ubuntu: the required `Workflow Security Lint`, zizmor's audit of
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
