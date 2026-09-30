# Pre-commit hook interaction

The detail behind `smart-commit`'s "Pre-commit Hook Interaction" section.

This project's pre-commit hook (`.githooks/pre-commit`) runs
`swiftformat --lint` and `swiftlint lint --strict` on the staged Swift files, and
the skills-mirror check when a staged path is under `.agents/skills/` or
`.claude/skills/`, and the staged guard (`scripts/check-staged.sh`) on every commit
that stages a change.
It checks but never modifies files. The skill does NOT duplicate these checks —
the hook handles code quality, while the skill handles commit workflow.

**When the hook fails:**

1. The commit did NOT happen — staged files remain staged but uncommitted
2. Run `just fmt` to fix formatting, or fix the reported SwiftLint violation
   in the source
3. Re-stage the fixed files: `git add <fixed-files>`
4. Retry the commit (same message is fine) — never `--amend` someone else's commit
5. Never use `--no-verify` to skip hooks — fix the underlying issue instead

**Common hook failures and fixes:**
- `swiftformat`: run `just fmt` and re-stage
- `swiftlint`: fix the violation in the code. Disabling a rule in
  `.swiftlint.yml` requires explicit user approval (see `AGENTS.md` › Security
  and human approval), is limited to subjective style rules with a
  reason comment, and NEVER applies to safety rules
