---
name: triaging-issues
description: >
  Covers this repository's issue vocabulary: the type, priority, and blocked label
  taxonomy declared in .github/labels.yml and synced by `just labels`, what
  `blocked: design`, `blocked: dependency`, `blocked: external`, `on hold` and
  `tracking` mean, and what an issue body must contain (a `path:line`, an observable
  close condition, a `Depends on #N` line). Use when filing a GitHub issue, triaging
  or re-prioritizing the backlog, picking a `priority: P0`-`P3` label, choosing
  between `bug`/`enhancement`/`documentation`/`chore`, marking a tracking issue,
  editing .github/labels.yml or an issue form, running `just labels`, or routing a
  friction or idea that came up while using the app.
---

# Triaging Issues

**Owns:** this repository's issue vocabulary — the label taxonomy, what a priority
means, and what an issue body must contain. **Does not own:** implementing an issue; a
change to a gate file (`changing-gates`); any workflow beyond the tracker.

Labels carry the triage decision, so it is made once and read back rather than
re-derived every time the backlog is looked at. An issue is filed with a type label and
left untiered; triage adds the priority, and a `blocked:` label where one applies.

## Priority labels

| Label | When to apply it |
|---|---|
| `priority: P0` | Reserve for a real blocking chain — another open issue names it as the blocker — or active damage (red `main`, a live vulnerability). Don't tier by how urgent an issue feels; tier by whether something is actually blocked or broken. |
| `priority: P1` | Foundational work — CI, schema, shared types, config — future issues will build on, even before any open issue names it as a dependency. Once one does, the resulting blocking chain likely makes it P0 instead of P1. |
| `priority: P2` | The default tier, used absent a specific reason to move up or down. Before leaving something here, check whether it actually blocks an open issue (P0) or is groundwork later issues will need (P1) — P2 is not a place to park work you haven't evaluated. |
| `priority: P3` | Defer only when impact is genuinely low — nobody is waiting on it and no future issue depends on it. Not a stand-in for "I don't want to do this"; an issue that matters but is unappealing to implement belongs at its real tier. |
| `blocked: design` | Applies when the approach has real, unresolved alternatives a human must choose between — not simply that no one has looked at it yet. It still gets a priority tier (see below); readiness and priority are independent judgments. |
| `blocked: dependency` | Applies only alongside a `Depends on #N` line in the body (see Ordering constraints below) — the label without a named blocker can't be verified or cleared. |
| `blocked: external` | Applies when the next step is one only a person can take: a signing identity or an App Store Connect credential, an Apple Developer account step, a purchase or accepting terms, a physical device or a permission prompt only a person can answer. Not for anything an agent can do with its own tools. `shipping-issues` never picks such an issue. |
| `on hold` | Applies to work parked on purpose, with the reason in a comment: real work nobody should pick up yet. It keeps its priority tier. `shipping-issues` never picks it. Not for a tracking issue — that is `tracking`. |

Priority ranks impact on the rest of the backlog, not how interesting the work is. Do
not tier an issue by how appealing it is to implement.

Tier and design-readiness are independent: an issue carrying `blocked: design` still
gets a tier, so it ranks correctly the moment the block clears. Never leave a
`blocked: design` issue untiered on the assumption that the tier can wait — it cannot be
re-derived later without redoing the judgment.

A label that turns out to be wrong gets corrected, not worked around. Ranking around a
stale label in your head leaves the next reader to make the same mistake — fix the label
instead of mentally overriding it.

## Type labels

`bug`, `enhancement`, `documentation`, and `chore` are the issue types. The forms under
`.github/ISSUE_TEMPLATE/` apply one at filing time: `bug_report.yml` applies `bug`,
`feature_request.yml` applies `enhancement`, and `task.yml` applies `chore`.
`documentation` has no form of its own (`config.yml` disables blank issues), so triage
applies it by hand to a documentation-only issue.

`ci` and `dependencies` are PR-only and never used for issue triage:
`.github/workflows/pr-label.yml` runs `scripts/label-pr.sh`, which labels a pull
request from its Conventional Commits title type, `!` or not (`feat` → `enhancement`,
`fix` → `bug`, `docs` → `documentation`, `ci` → `ci`, `deps` → `dependencies`, every
other accepted type → `chore`), drops a type label a retitle left stale, and never
creates a label. Dependabot also applies `dependencies` to its own pull requests, so
the script never removes that one.

There is no `security` label. A vulnerability is never filed as a public issue: it goes
through `SECURITY.md`'s private reporting route (GitHub Security Advisories), which the
issue chooser's `config.yml` also links to.

`tracking` marks a tracking issue: a checklist of sub-issues (`- [ ] #N`) whose own
body is never implemented. It takes a type label (usually `chore`) and no priority
tier, because it ranks nothing; each sub-issue carries its own tier and says
`Part of #N`. `shipping-issues` drops a `tracking` issue from ranking, selection, and
priority backfill, so it never has to be judged again on each run.

`chore`, `ci`, `tracking`, and the `priority:`/`blocked:` labels are not GitHub defaults, and GitHub
silently drops a label a form applies when the repository does not have it. `just labels`
(`scripts/sync-labels.sh`) creates or updates every label in `.github/labels.yml` on the
live repository and never deletes one; running it is a remote write that needs a human's
sign-off (`AGENTS.md`'s "Security and human approval").

`.github/labels.yml` is the source for the label set itself — name, color, and
description; this skill holds only what each one _means_ for triage. A label is added
or renamed there first, then here. If the file and this skill disagree about a label,
fix the mismatch rather than choosing one.

## What an issue body must contain

Two things belong in the body because nothing else can recover them later:

- **What is wrong today**, with a `path:line`. A description of a symptom without a
  location forces whoever picks up the issue to re-find what the filer already knew.
- **What observable result closes it**, named as a test or a command (`just test`,
  `just lint`, a `grep` that must print nothing) — not as a feeling of doneness ("works
  correctly", "is cleaned up"). A closing condition that cannot be checked mechanically
  cannot be verified by anyone but the filer.

## Ordering constraints

Write an ordering constraint as `Depends on #12`, one per line under a
`## Dependencies` heading, with `Blocks #N` for the reverse edge. This is the spelling
automation parses; prose like "after the guard work lands" is not machine-readable and
will not be picked up.

An issue carrying a `Depends on` line also carries `blocked: dependency` while the
blocker is open. The label is **not** removed automatically when the blocker closes:
whoever lands the blocking issue clears `blocked: dependency` by hand from every issue
that named it. Do not assume the label update is someone else's automated job — it is
a manual step in the same PR or a prompt follow-up that closes the blocker.

## Requests from daily use

A friction or an idea that comes up while using the app is routed the moment it is
raised, so it is never lost in a chat log and never shipped unreviewed. Decide one of
three outcomes:

1. **File it now** when it stays inside the existing design (a default, a key binding,
   copy, a small change to how an existing screen behaves) and is in scope under
   `AGENTS.md`'s `## Product`. The request authorizes creating the issue and nothing
   more: file it with a type label and a tier (`priority: P2` by default, per the table
   above) and a body that meets "What an issue body must contain". Several requests in
   one message get one issue each, unless they are one pull request's worth. Report
   the numbers and stop; implementing waits for someone to pick the issue.
2. **Park it** as `on hold` when it is worth keeping but not worth doing yet: it needs
   more use to judge, it leans on a `## Product` non-goal, or it would need a design or
   architecture decision first. File it the same way, add `on hold`, and give the
   reason and what would change the call in a comment. It keeps its tier, and
   `shipping-issues` skips it until the label comes off.
3. **Drop it** without an issue when it contradicts a `## Product` non-goal or
   duplicates an open issue (comment on that one instead). Say so in the reply, with
   the reason, so the decision is visible rather than silent.

A parked issue leaves the lane only by a decision, never by age:

- **Promote** it by removing `on hold` once its reason no longer holds — the use it
  was waiting on has happened, or the decision it needed was made. Re-check its tier;
  it may now warrant `blocked: design` instead, if a real choice remains.
- **Close** it as not planned when its reason became permanent — the app moved away
  from it, or a later issue superseded it (link that one).

Moving a request out of `## Product`'s non-goals is a human's call, not the triager's:
parking or dropping it records that line rather than crossing it.
