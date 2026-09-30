---
name: authoring-skills
description: >
  Covers how a skill in this repository is authored under .agents/skills/, mirrored into
  .claude/skills/ by scripts/sync-agents.sh, and checked so a malformed SKILL.md does
  not silently fail to load. Use when adding, editing, or reviewing a SKILL.md, running
  just agents-sync or just agents-check, deciding whether new material belongs in
  AGENTS.md or a new skill, or investigating why a skill never fires in Claude Code or
  Codex CLI.
---

# Authoring Skills

**Owns:** how a skill in this repository is authored, mirrored, and kept from silently
failing to load. **Does not own:** how a script under `scripts/` is written
(`writing-repo-scripts`); a change to the gate files that run the mirror check
(`changing-gates`); which documentation surface a change lands on (`updating-docs`); the
content of any individual skill.

## The single source of truth

- Author every skill once, under `.agents/skills/<name>/` — the path Codex CLI discovers
  project skills from. `scripts/sync-agents.sh` mirrors that tree into
  `.claude/skills/`, the only path Claude Code reads.
- Both copies are real, committed files. A symlink would work from this checkout but not
  from a fresh clone on every platform, and Codex follows a linked directory into its
  own subdirectories, registering a nested `SKILL.md` as a second, nameless skill.
- Loop: edit the `.agents/` copy, run `just agents-sync`, commit both sides. Never
  hand-edit anything under `.claude/skills/` — the next sync overwrites it silently
  (`rsync -a --delete`), and a hand edit there drifts from the source it should mirror.
- Drift between the two trees fails `scripts/sync-agents.sh --check`, which compares the
  trees byte for byte with `diff -r`, not just a spot-check of `name`. It runs as
  `just agents-check`, inside `scripts/lint.sh` (so `just lint` and CI's `lint` job), and
  in the pre-commit hook's "Skills mirror" section, which checks the staged versions of
  both trees whenever a commit stages a path under either one.

## Layout

- Exactly one directory level under `.agents/skills/`: `.agents/skills/<name>/SKILL.md`
  plus optional reference, script, or asset subdirectories beneath that same skill
  directory. No category subfolders — both hosts and the mirror assume one path segment
  between the skills root and the skill's own files.
- No file below a skill root may itself be named `SKILL.md`. A nested one registers as a
  second, nameless skill in both hosts. Name reference files for their content instead
  (`failure-modes.md`, not another `SKILL.md`). `scripts/checks/skills-descriptions.sh`
  refuses one (`ERR_CHECK_SKILL_NESTED`).
- No symlinks anywhere under either tree. `scripts/sync-agents.sh` refuses a symlink in
  the source tree, and a `.claude/skills` that is itself a symlink, with
  `ERR_AGENTS_SYMLINK`.

## Frontmatter

Exactly two keys, `name` and `description`, with `description` written as a folded
block scalar (`description: >`) as the skills here do. Do not add any third key — no
`paths`, no `globs`, no host-specific extension. Claude Code's own `paths` field would
gate auto-invocation on a glob, but Codex CLI has no such field: it ignores an unknown
key and matches only on `description`. The same skill would then auto-fire on different
terms per host, so a portable skill keeps `description` as its one trigger surface.
(`.claude/rules/*.md` do use `paths:` — they are Claude Code-only and are not skills.)

- `name` is byte-identical to the directory name: lowercase letters, digits, and
  hyphens.
- English only, per `AGENTS.md`'s "Important Reminders".
- The description is a retrieval string describing the situation that should load the
  skill (file globs, command names, error strings, decisions), never a summary of the
  skill's internal workflow. Both hosts select a skill on the description's _meaning_,
  so a trigger keyword mirrored into another language buys nothing.
- Keep the description well under the 1,024-character limit of the Agent Skills format;
  a longer one is not a better trigger. Write it in printable ASCII: a hyphen, not an
  em dash, and straight quotes.

Enforced by: `scripts/checks/skills-frontmatter.sh` (exactly `name` and `description`,
`name` equal to the directory, a non-empty `description`) and
`scripts/checks/skills-descriptions.sh` (a printable-ASCII `description` of at most
1,024 characters, and no unquoted plain value Codex CLI's strict YAML parser would
reject, such as one containing `: ` or ` #`). The description's wording, and whether
ASCII text is actually English, are not checked — see "Why this needs its own test"
below.

## When a new skill is warranted

Add a skill only for work that recurs and needs a workflow, local references, or policy
loaded on demand — not for a fact stated once. Extend an existing skill instead of
creating a near-duplicate when the new material is a variant of what that skill already
covers.

One home per rule: a rule stated in both `AGENTS.md` and a skill costs context twice and
the two copies drift apart. The one exception is a prohibition an agent needs even while
its own declared task is something else entirely (for example, never lower the coverage
floor or weaken a gate to make a run pass) — that stays in `AGENTS.md`, where every agent
reads it regardless of task, and a task-specific skill holds only the reasoning an agent
doing that task needs. `changing-gates` shows the pattern: it points at `AGENTS.md`'s
"Security and human approval" for the prohibition rather than restating it.

Every new skill opens with an ownership block (`**Owns:**` / `**Does not own:**`) naming
what it decides and which sibling decides the adjacent question. `create-pr`,
`smart-commit`, and `tdd` predate the convention. Cross-reference a sibling skill by its
name in backticks, never by path, and an `AGENTS.md` rule by its section name in quotes
(`AGENTS.md`'s "Repository scripts"), never by line number — line numbers go stale the
first time the file above them changes.

Do not write down what a config already enforces. Name the gate in one line
(`Enforced by: <file> "<setting>".`) and spend the skill's words on the judgment the
config cannot express — the same principle `AGENTS.md` states for itself.

A skill added, renamed, or deleted gets its row in `AGENTS.md`'s Skills table updated in
the same commit, and widening a skill's subject means widening its row. Enforced by:
`scripts/checks/skills-index-complete.sh` (the row set, not its wording).

## Conventions

- **Cross-reference markers.** A pointer that sends the reader to a sibling skill (by
  name) or to this skill's own `references/` file (by relative path) as a step of the
  task carries one of two markers and no other: `**REQUIRED:**` when the task cannot be
  finished correctly without it, `**BACKGROUND:**` when it only explains why. A mention
  that only names an owner — the ownership block, a scope note, an attribution such as
  "(`changing-gates`)" — stays bare, with no marker and no "see".
- **Deletable illustrations.** Example code in a skill is an illustration no build or
  test depends on, and a reader may delete it or replace it with their own; the
  template's worked example a skill points to (the to-do list) is replaced by an app,
  too. State the rule in its own sentence and the example in the next, so the rule still
  reads once the example is gone.
- **Platform skills.** A skill about an iOS or Apple API surface holds only what this
  repository decided there and why. It links Apple's documentation by URL instead of
  restating it, and a version, availability, or policy it must state carries its URL and
  a checked date (**BACKGROUND:** `recording-architecture-decisions` › "Fact
  discipline").

## Where a skill lives

A skill lives in `.agents/skills/` (mirrored to `.claude/skills/`), and the template
commits no plugin marketplace. Codex CLI cannot read Claude Code plugins;
`just agents-check`, the frontmatter and description checks, and CI never see a plugin
skill; a plugin update changes behavior without a pull request unless pinned; and a
public template cannot ask its users to trust a personal marketplace. A shared plugin
pinned by ref is an option only for a stack-agnostic skill copied across repositories
that demonstrably drifts.

## Size and structure

- Target 150 body lines per `SKILL.md`, never exceed 200; past that, move detail into
  `references/`. No check enforces this, and a skill that runs past it today is not the
  norm to copy.
- A `references/*.md` file stays under 400 lines and is linked with a relative path one
  level deep, never with `@` and never as an absolute path.

## Spell-check and formatting

`just lint` spell-checks `.agents/skills/` with `typos` (`typos.toml` sets
`ignore-hidden = false`, so dot-directories are scanned, and excludes the
`.claude/skills` mirror, so a typo is reported once). Fix it in `.agents/skills/` and
run `just agents-sync`. When a technical term has to be allowed, add it to
`typos.toml`'s `default.extend-words` rather than working around the checker.

Markdown has no auto-formatter here: `just fmt` runs SwiftFormat on Swift files only, so
a `SKILL.md` is formatted by hand and reviewed by eye. Wrap prose at the width the
neighboring skills use.

## Scripts bundled inside a skill

A script shipped under `.agents/skills/<name>/scripts/` follows `AGENTS.md`'s
"Repository scripts" section exactly like one under `scripts/`: `#!/usr/bin/env bash`
with `set -euo pipefail`, bash 3.2-compatible, `shellcheck`-clean (`scripts/lint.sh`
checks every tracked `*.sh` at any depth but the `.claude/skills/` mirror), the
`ERR_<STAGE>_<WHAT>` failure contract, and a test — a `scripts/tests/<name>_test.sh`
built on `scripts/tests/lib.sh`, which `scripts/tests/run.sh` (`just test-scripts`)
runs, or the skill's own Python suite described below. Keep it a thin dispatcher; anything with real
branching logic belongs in `scripts/`, where it is easier to find and test.

The one skill that ships scripts today is `shipping-issues`: Python helpers
(`plan.py`, `issue_digest.py`, `run_record.py`, …) and bash wrappers (`ci_watch.sh`,
`land_pr.sh`, …) under `.agents/skills/shipping-issues/scripts/`, with a Python
`unittest` suite beside them in `scripts/tests/test_*.py` that covers the wrappers too.
That suite is not built on `scripts/tests/lib.sh`; `scripts/tests/skill-scripts_test.sh`
runs every `.agents/skills/*/scripts/tests/` suite with `python3 -m unittest discover`
under `PYTHONDONTWRITEBYTECODE=1`, fails on any failing test or a `__pycache__` left in
the authored tree, and is itself run by `just test-scripts` and CI's `lint` job. A new
skill's Python tests land in the same place and are picked up without a runner change.
`python3` is assumed on PATH like `git`, not pinned in `mise.toml`.

## Why this needs its own test

`scripts/sync-agents.sh --check` only proves the two trees are byte-identical; it says
nothing about whether the source tree is well-formed. A `SKILL.md` whose frontmatter
fails to parse, whose `name` disagrees with its directory, or whose frontmatter carries
a stray key passes that check, mirrors cleanly, and simply never loads in either host.
Three harness checks cover that, all run by `just check-harness` (part of `just check`)
and CI's `lint` job through `scripts/checks/run-all.sh`:

- `scripts/checks/skills-frontmatter.sh` — every `.agents/skills/<dir>/SKILL.md` opens
  with a `---` block holding exactly `name` and `description`, `name` equals `<dir>`,
  and `description` is non-empty (`ERR_CHECK_SKILL_FRONTMATTER`).
- `scripts/checks/skills-descriptions.sh` — no `SKILL.md` below a skill's top directory
  (`ERR_CHECK_SKILL_NESTED`); every `description` is printable ASCII and at most 1,024
  characters, and every unquoted frontmatter value is Codex-YAML-safe
  (`ERR_CHECK_SKILL_DESCRIPTION`).
- `scripts/checks/skills-index-complete.sh` — the first table under `AGENTS.md`'s
  `## Skills` heading and the directories under `.agents/skills/` name the same skills,
  in both directions (`ERR_CHECK_SKILL_INDEX`).

None of them sees the description's wording or the size limits above — read those
yourself. Before committing a new or changed skill run:

```bash
just agents-sync
just agents-check
just check-harness
```
