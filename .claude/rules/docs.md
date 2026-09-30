---
paths:
  - "docs/**/*.md"
  - "README.md"
  - "CONTRIBUTING.md"
  - "CHANGELOG.md"
---

- Document non-obvious behavior, architecture decisions, and trade-offs
- Do NOT document what is obvious from the code or already expressed by the type system
- Code examples in docs must be valid Swift or shell that works with the current project
- Command examples must match the `justfile` recipes and CONTRIBUTING.md equivalents
- Keep README's Design Philosophy in sync when a documented decision changes
- User-facing changes get a CHANGELOG entry under `[Unreleased]` in the same PR
