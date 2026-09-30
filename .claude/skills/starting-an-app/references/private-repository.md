# Private repository setup

The template's workflows assume a public repository. On a private repository created
from it, three of them fail or mean nothing, and one of the required checks in
`.github/rulesets/main.json` can then never pass, so no pull request can merge. The
fix is documentation, not `if:` guards: a skipped job never reports its check, so a
guarded job would still leave a required context unsatisfied forever.

Do these steps after the bootstrap commit and before `just ruleset`.

## 1. Delete the workflows a private repository cannot run

| File | Why it goes |
|---|---|
| `.github/workflows/scorecard.yml` | OpenSSF Scorecard analyses public repositories only, and its upload to code scanning needs GitHub Advanced Security on a private one |
| `.github/workflows/codeql.yml` | CodeQL code scanning on a private repository needs GitHub Advanced Security (GitHub Code Security) |
| `.github/workflows/dependency-review.yml` | `actions/dependency-review-action` on a private repository needs GitHub Advanced Security |

Keep any of them if the plan includes GitHub Advanced Security for this repository.
`osv-scan.yml` runs without it and stays as the dependency-vulnerability check.
`SECURITY.md`'s "Supply-Chain Posture" names Scorecard and CodeQL, so edit it in the
same change.

## 2. Drop the matching required context before `just ruleset`

In `.github/rulesets/main.json`, remove this entry from `required_status_checks`
when `dependency-review.yml` was deleted:

```json
{ "context": "Dependency Review", "integration_id": 15368 }
```

Neither Scorecard nor CodeQL is a required context, so deleting them needs no ruleset
edit. Keep the remaining contexts — `Lint & Format Check`, `Test & Coverage Gate`,
`App Build & UI Test (iOS Simulator)`, `Package Tests (iOS Simulator)`,
`Workflow Security Lint`, and `Validate PR title`
(`scripts/bootstrap.sh` already removed `Template Bootstrap Smoke`). Mind the commas:
the entry that ends up last in the array takes none. Then run
`scripts/tests/apply-ruleset_test.sh`, and `just ruleset` as a repository admin
(branch rulesets on a private repository need a paid GitHub plan).

## 3. Verify

Run `just lint` and `just check-harness` (actionlint and the workflow checks read the
remaining workflows, and `ruleset-contexts.sh` reads `main.json`), commit, and open a
pull request: every required check it waits for is now one a job in the repository
reports.
