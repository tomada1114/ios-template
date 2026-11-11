---
paths:
  - "docs/**/*.md"
  - "README.md"
  - "CONTRIBUTING.md"
  - "CHANGELOG.md"
---

- Document non-obvious behavior and trade-offs
- Do NOT document what is obvious from the code or already expressed by the type system
- Code examples in docs must be valid Swift or shell that works with the current project
- Command examples must match the `justfile` recipes and CONTRIBUTING.md equivalents
- How the app is built and why lives in the skill that owns the subject (and `AGENTS.md`'s
  Architecture section for a layer rule or a contract), never in a document here: a
  design change rewrites that skill in place, in the present tense, and git history holds
  what it used to say. There is no architecture overview, decision record,
  design-philosophy page, or roadmap; never create one or copy a skill's design into
  another surface. Direction is `AGENTS.md`'s Product section and the open issues
- `docs/` holds guides only: `getting-started.md` (removing the worked example),
  `running-on-device.md` (`just run-device`), and `design-system.md`, the research record
  behind `designing-ui`'s design lock, never a second copy of the lock
- User-facing changes get a CHANGELOG entry under `[Unreleased]` in the same PR
