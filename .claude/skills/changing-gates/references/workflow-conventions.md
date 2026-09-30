# Conventions every workflow follows

The detail behind `changing-gates`' `.github/workflows/` section.

Conventions every workflow here follows, which `actionlint` (in `scripts/lint.sh`) and
`just check-harness` partly check and review holds for the rest:

- every `uses:` of a remote action is pinned to a full commit SHA with a trailing
  `# vX.Y.Z` comment; a local `./.github/actions/…` action is exempt;
- a top-level `permissions:` as narrow as the work allows, and every job has a
  `timeout-minutes`; a `write` scope goes on the job that needs it, never the top
  level, and neither level uses `read-all`/`write-all`;
- a workflow triggered on `pull_request` declares a top-level `concurrency:` whose group
  varies per run and names `github.workflow` (or is otherwise unique to the file) — a
  pull-request-only key such as `github.head_ref` is empty on any other trigger, so a
  workflow with one keys on `github.ref`, `github.sha`, or a `|| github.run_id`
  fallback — and a workflow triggered on `push` never cancels a push run in progress —
  ci.yml's `cancel-in-progress: ${{ github.event_name == 'pull_request' }}` is the
  pattern;
- every `run:` step runs under `shell: bash`, which GitHub runs with `-eo pipefail`,
  or opens with `set -euo pipefail`; an unnamed shell is `bash -e {0}`, which misses a
  failure before a `|`. Name it with a top-level `defaults:` block written in block
  style — `defaults:`, then `  run:`, then `    shell: bash`, one key per line, since
  the harness check does not read a flow mapping — and a composite action's step
  names `shell: bash` itself;
- `actions/checkout` runs with `persist-credentials: false`;
- a new check goes into an existing job unless it needs a different runner, trigger, or
  permission footprint. Widening `permissions:` or adding a workflow that writes is a
  security-relevant change that needs sign-off, not a routine CI edit.

`just check-harness` holds the mechanical part of this list:
`scripts/checks/workflow-pins-and-permissions.sh` the pins and the presence of a
top-level `permissions:`, `scripts/checks/workflow-hygiene.sh` the write-scope,
concurrency, and shell rules, and `scripts/checks/just-check-matches-ci.sh` that
ci.yml's `run:` steps and `just check` run the same gates. `timeout-minutes` and
`persist-credentials: false` are review's to hold.
