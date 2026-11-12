# CI jobs and workflows

Read from [SKILL.md's `.github/workflows/` section](../SKILL.md#githubworkflows)
before adding, removing, or renaming a job or a workflow.

`ci.yml` splits into `lint` (ubuntu, on push to `main` and every pull request:
`scripts/lint.sh`, `scripts/tests/run.sh`, `scripts/checks/run-all.sh`), `test` (the
required `Test & Coverage Gate`, the one macOS gate job: xcode-27 runs
`scripts/coverage.sh` alone — the package tests on the host with the coverage floors —
within a 20-minute timeout; no xcodebuild runs on a pull request of this tree),
`bootstrap-smoke` (the required `Template Bootstrap Smoke`:
`scripts/bootstrap.sh` renames a clone of the template, then the renamed tree is
linted, its skill descriptions are re-checked (`scripts/checks/skills-descriptions.sh`,
which on every pull request already refuses a description naming a placeholder the
rename would lengthen), tested, and built for the simulator — template-only, so the rename removes it
from every app), `changes` (ubuntu, not required: says `simulator=false` on a push to
`main` and on a draft pull request, otherwise runs `scripts/simulator-relevant.sh
--base … --head …`, a `git diff --name-only` of the pull request against the wider of
the path lists that script holds, beside the per-check lists `just check` reads with
`--check`; `test` and `bootstrap-smoke` need
it, always run under their required names, take an Ubuntu runner and skip their steps
only on its exact output `false`, and a failed `changes` leaves the output empty so
they run in full on macOS; a job skipped outright would report as passing). The UI
test, the iOS Simulator package tests, the Release smoke launch, the Release device
build, and the analyzer rules have no CI job, to keep a pull request's macOS minutes to
one `swift test`: the first two run in local `just check` when the change touches their
paths, and all five in `just check-release` before a release. A pull request
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
