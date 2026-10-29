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
- How the app is built and why lives in the skill that owns the subject, never in a
  document here: a design change rewrites that skill (the `updating-docs` skill)
- User-facing changes get a CHANGELOG entry under `[Unreleased]` in the same PR
