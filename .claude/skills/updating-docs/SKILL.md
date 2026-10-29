---
name: updating-docs
description: >
  Decides whether a change owes a documentation update and which surface it lands on:
  README.md, AGENTS.md, CHANGELOG.md, a guide under docs/, the skill that owns the
  design of what changed, or a /// doc comment in Packages/*/Sources. Use when
  triaging whether a pull request needs a document changed or a CHANGELOG entry, when a
  rule, a just recipe, or an architecture boundary moved and it is unclear which file
  owns it, when tempted to write an architecture overview, decision record, or roadmap,
  when the quick start or setup steps drifted, or when deciding that an internal
  refactor needs no documentation change.
---

# Updating Documentation

**Owns:** whether a change owes a documentation update, and which surface it lands on.
**Does not own:** what a `///` comment for a given symbol says (`.claude/rules/swift.md`);
how a skill is authored and mirrored (`authoring-skills`); a design change's description
(`AGENTS.md`'s "Before changing the architecture"); the wording rules for files under
`docs/` and the top-level Markdown (`.claude/rules/docs.md`).

## Decide on observability, not location

Documentation impact is decided by what a **reader can observe**, not by which directory
the edit began in. An internal refactor and a test-only change need no documentation
change — say so explicitly. Deciding that nothing is needed is a legitimate outcome of
this skill, not a shortcut to be double-checked away.

A reader of this template can observe: what the app does when launched, the `just`
recipes and what they run, the setup steps and pinned toolchain, what a gate accepts or
rejects, and how the template is turned into a new app (README's "Using This
Template"). A change to any of those owes a document; a change behind them does not.

- `README.md` changes when the first ten minutes with a checkout change — the
  Quickstart commands, the layout it tours, or what "Using This Template" asks you to
  do.
- It does not change for a refactor, a test, a gate or rule that `AGENTS.md` owns, or an
  edit to a skill.

## Design lives in the skills

How the app is built and why — its layers, view models, navigation, storage, ports,
screens, and the template's own choices — is written once, in the skill that owns the
subject, so a code change owes at most that skill (and `AGENTS.md`'s Architecture
section for a layer rule or a contract). There is no architecture overview, decision
record, design-philosophy page, or roadmap to keep in step: never create one, and never
copy a skill's design into another surface. Direction is `AGENTS.md`'s Product section
and the open issues (`triaging-issues`).

The design is stated as it stands now, never as a log of decisions: a design change
rewrites the owning skill in place, in the present tense, and git history holds what it
used to say. Numbered records with statuses would make every feature change cost a new
record, and two homes for one fact drift apart, so there are none.

## Purpose per file

Each surface has one job; do not blur them, and do not let one grow a second copy of
another's content. An issue that creates a new document adds its line here.

- `README.md` — the tour: what the app is, the Quickstart, how it is laid out (a short
  paragraph pointing at `AGENTS.md`'s Architecture section and the skills), "Using This
  Template" (turning it into a new app), the everyday-recipe Development table, and the
  Documentation list. It links to `AGENTS.md` and `CONTRIBUTING.md` instead of repeating
  them, and holds no design reasoning of its own.
- `CONTRIBUTING.md` — for a human contributor: the prerequisites, every `just` recipe in
  `justfile` order with the commands it runs without Just, the pull request process,
  code standards, commit messages, and the changelog policy. The full recipe list lives
  here and in `AGENTS.md`'s Quick Reference only; a renamed or added recipe updates both.
- `docs/getting-started.md` — the first run: setup, everyday commands, the simulator
  and your own iPhone, removing the example code (every to-do file and wiring point,
  what to keep, and an order that stays green), opening the project in Xcode, and the
  app icon. A file the example adds, moves, or wires in updates its removal list.
- `AGENTS.md` — the agent-facing guide: the Quick Reference command index, "Validating a
  change", the Architecture (the layer rules, the app's shape, and "What is contract
  and what is private"), "Before changing the architecture", the Skills and Rules
  tables, "Security and human approval", "Repository scripts", "Enforcement
  layers", and the Review Checklist. A changed boundary, gate, `just`
  recipe, or script rule lands here.
- `CHANGELOG.md` — the canonical, human-curated record of user-facing changes, in the
  Keep a Changelog format its header links. A user-facing change gets an entry under
  `[Unreleased]` in the same pull request that makes it; GitHub's generated release
  notes are supplementary, never a substitute.
- `docs/design-system.md` — the research record behind the design lock: the brief, the
  reviewed references, the decision ledger, and the sources. The lock itself is
  `designing-ui`'s; a lock change that new research supports updates both.
- `docs/running-on-device.md` — the device-run guide: the one-time setup and everyday
  use of `just run-device`.
- `.agents/skills/<name>/SKILL.md` and its `references/` — the conventions of one kind
  of change, loaded on demand, and the design of the subject it owns ("Design lives in
  the skills"). `authoring-skills` owns how one is written, mirrored, and checked.
- `///` doc comments in `Packages/*/Sources/**` — a symbol's contract: the "why",
  not what the signature already says (`.claude/rules/swift.md`). Public API carries one
  (`AGENTS.md`'s "Review Checklist"); this skill owns only whether one is owed.

This repository has both a `CHANGELOG.md` and a `docs/` tree, and both are maintained
surfaces, not leftovers — keep them current rather than folding them into a pull request
description. `.claude/rules/docs.md` holds the mechanical rules that load whenever one of
them or `README.md` is touched: the `[Unreleased]` entry, and commands that match the
`justfile`.

## A skill is documentation; editing one is usually not a doc change

Both halves are true and the tension is worth holding. A `SKILL.md` is documentation —
for an agent rather than for a person — so it is held to the same prose rules as the
files above. But maintaining one is not itself user-observable, and it obliges no
README or `AGENTS.md` edit.

The one exception is the skill set changing shape: a skill added, renamed, or deleted
has to be recorded in `AGENTS.md`'s Skills table, and widening a skill's subject means
widening its row. `scripts/checks/skills-index-complete.sh` (`just check-harness`)
fails when the table's skill names and the directories under `.agents/skills/` differ,
but not when a row's wording no longer matches what the skill covers.

## The checklist owns the mechanical items

`AGENTS.md`'s "Review Checklist" already carries the items that fire most often — `///`
comments on new public API and a `CHANGELOG.md` entry for a user-facing change — and
`.github/PULL_REQUEST_TEMPLATE.md`'s Checklist asks the author to tick the CHANGELOG and
documentation items. Work from those; this skill does not restate their items and
neither should anything else.

## What belongs in prose

Document non-obvious behavior, architecture decisions, and trade-offs. Do not restate
what the code or the type system already says — the same principle `///` comments follow
in `Packages/*/Sources/**`. If a reader could get the fact from the signature or
from running the code, it does not need a sentence here.

## Nothing verifies a fenced example

`.claude/rules/docs.md` asks that code examples be valid Swift or shell and that command
examples match the `justfile`, but no gate in this repository compiles or runs a code
block in a document. The one command check is `scripts/checks/just-recipes-exist.sh`
(`just check-harness`), which fails when `AGENTS.md` names a `just <recipe>` the
`justfile` does not define; nothing checks any other command in any other document. Do
not claim more — a document that promises a gate it does not have is worse than one that
stays silent.

That leaves a discipline instead. Keep a fenced example to something a reader can check
by eye — a command, a path, a short snippet. When the example has to be runnable, put the
runnable thing where a test already calls it — `Sources/MyAppCore/`
under `just test`, or a script under `scripts/` with its `scripts/tests/` file — and have
the document point at it rather than copy it.

## Generated trees are off-limits

`.claude/skills/` is a generated mirror of `.agents/skills/` (`scripts/sync-agents.sh`,
run as `just agents-sync`) — never hand-edit it, and never include it in a documentation
sweep. Edit the authored file and re-run the sync; `authoring-skills` owns the rest.
`MyApp.xcodeproj` is generated from `project.yml` the same way and is never documented
as if it were a source file.
