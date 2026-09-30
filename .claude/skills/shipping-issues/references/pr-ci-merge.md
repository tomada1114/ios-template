# PR, CI, and merge

The detail behind SKILL.md steps 5 to 7. From step 5 to step 7 the run is serial in
both modes: one PR at a time, in the batch's dependency-then-priority order. Finish an
issue's PR -> CI -> merge before opening the next.

## Table of Contents

- [5. Open the PR](#5-open-the-pr)
- [6. CI to green](#6-ci-to-green)
  - [Waiting inside the 600-second cap](#waiting-inside-the-600-second-cap)
  - [Reading the verdict](#reading-the-verdict)
- [7. Merge and confirm the issue closed](#7-merge-and-confirm-the-issue-closed)
  - [Clearing `blocked: dependency`](#clearing-blocked-dependency)
  - [Moving on](#moving-on)

## 5. Open the PR

Commits but nothing pushed -> push from this session (`git -C <workdir> push -u origin
<branch>`). No commits at all -> no branch: record `--event blocked --field issue=<n>`,
report `SKIPPED(<why>)`, and in `all` mode move on.

Open a PR from `<branch>` against `<default_branch>`, titled `<PR-TITLE>`. The body must
carry **`Closes #N`** after the summary (a bare `#N` closes nothing) and target the
**default branch** (auto-close only fires there). Build it from `PR-SUMMARY`,
`Closes #N`, and `TEST-PLAN`, in the shape of `.github/pull_request_template.md` --
Summary, Test Plan, and its Checklist ticked only for what actually ran. Record
`--event pr-created --field issue=<n> --field pr=<url>`, then:

```bash
${CLAUDE_SKILL_DIR}/scripts/link_check.sh <pr> --issue <n> --fix
```

`land_pr.sh` re-checks the link at step 7 too; this earlier call is not redundant,
because it catches `WRONG_BASE` before CI spends its time on the wrong base. `--fix`
appends a missing `Closes #N`; `WRONG_BASE` -> retarget before merging.

## 6. CI to green

Wait for the PR's new head commit to appear among the branch's CI runs before watching
-- the checks API serves the previous commit's results for a minute or two after a
push, and a stale PASS is worse than a stale FAIL
([recovery.md](recovery.md#ci-reports-the-previous-commit)). Then watch the PR once,
output redirected -- raw output carries failing-run log tails that must stay out of this
context -- and read only four lines:

```bash
${CLAUDE_SKILL_DIR}/scripts/ci_watch.sh <pr> --timeout 1800 > <runstate>/ci/<pr>.log
grep -E '^(verdict|mergeable|merge_state|review_decision):' <runstate>/ci/<pr>.log
```

One watch per PR; keep the log's `failed_checks:` for repair. Record `--event ci`.

### Waiting inside the 600-second cap

The Bash tool kills a foreground call after at most 600 seconds, while this repository's
CI (lint, tests with coverage, build, UI test, Release smoke) routinely runs longer. A
`--timeout 1800` watch in the foreground would be killed mid-wait, with no verdict and a
truncated log. So pick one of these, in this order:

1. **Background, then wait for the notification (Claude Code).** Start the command
   above with the Bash tool's `run_in_background`. The host re-invokes this session when
   the command exits; read the four lines then. This is the run's only wait primitive --
   never a hand-rolled `sleep`/poll loop, which burns turns and context. The session may
   do non-GitHub work meanwhile (drain step 8b's queue, draft a follow-up body), but it
   does not open, watch, or merge another PR: the serial rule above still holds.
2. **Foreground, under the cap.** Run it with `--timeout 540` or less. `verdict:
   TIMEOUT` then means only that the watch's own bound ran out, not that CI failed: run
   the same watch again, until 1800 seconds of watching have passed in total.
3. **Codex CLI**, which has no background call with a completion notification: the
   foreground form, with `--timeout` kept below that host's own command timeout, re-run
   on `TIMEOUT` the same way.

After 1800 seconds of `TIMEOUT` in total, treat it like `ERROR`: re-read the PR's
actual CI state before deciding anything.

### Reading the verdict

- `PASS` -> step 7 **in the same turn**. Do not report the green CI and wait: green CI
  is the approval.
- `FAIL` -> [recovery.md](recovery.md#ci-fails) and
  [agents/ci-repair.md](agents/ci-repair.md), at most 3 attempts. The second and third
  attempts go to the same repair agent by `SendMessage` while it is reachable, with what
  the previous attempt tried; once the same failure has survived two attempts, a fresh
  `architect` takes the third.
- `NO_CHECKS`, `ERROR`, `TIMEOUT` ->
  [recovery.md](recovery.md#no_checks-error-timeout-and-other-non-verdicts).

## 7. Merge and confirm the issue closed

```bash
${CLAUDE_SKILL_DIR}/scripts/land_pr.sh <pr> --issue <n>
```

Merge as soon as step 6 reports `verdict: PASS`. Read `result:` and `issue:` -- six
results, one of which must never read as success:
[landing-outcomes.md](landing-outcomes.md). Record `--event merged`. Then:

```bash
git switch <default_branch> && git pull --ff-only
```

after every merge, and again as the run's last act -- a run never ends parked on a
feature branch. In parallel mode the main checkout is already there; pull anyway so it
carries the merge that just landed.

### Clearing `blocked: dependency`

`triaging-issues` defines the rule: the label is not removed automatically when a
blocker closes, and whoever lands the blocking issue clears it from every issue that
named it. This run just landed one, so this run clears them, right after the merge:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/plan.py --mode <same> --refresh --allow-existing-worktrees
```

Its `stale-labels:` line names every open issue still labeled `blocked: dependency`
whose `Depends on` blockers are now all closed, with the exact
`apply_priority_labels.py --clear-dependency` command to run. Run it without asking. Two
cases it leaves alone on purpose: an issue with another blocker still open (the label is
still true), and a label with no `Depends on` line to verify it against (the label rule
in `triaging-issues` requires one; report it at step 10 rather than guess). Do not pass a
`--label` filter to this re-plan: a dependent outside the filter would be missed.

### Moving on

**Serial `all`:** the same re-plan's `select:` line is the next issue; start its step 3
from this up-to-date branch, without pausing. **Parallel `all`:** the batch's remaining
branches are now behind; bring each up to date in its own worktree **before its own
step 5**, rather than after a CI failure, and merge rather than rebase
([how](recovery.md#bringing-the-rest-of-a-parallel-batch-up-to-date)). A conflict
either way means the grouping call was wrong for that pair
([recovery.md](recovery.md#a-merge-conflict)). Only when the whole batch has merged
does the run group the next batch. With no argument or an explicit number, step 8c is
the only thing that extends the run past this merge.
