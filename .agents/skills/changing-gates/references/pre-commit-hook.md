# `.githooks/pre-commit` in detail

The detail behind `changing-gates`' `.githooks/pre-commit` section.

## Sections

Independent sections, each scoped by the staged paths it cares about, none exiting
early — a commit that skips one section must still reach every other. Each section
calls a shared script:

- "Swift lint" exports the staged Swift blobs with `git checkout-index --prefix=` and
  runs `scripts/lint.sh --staged-tree` on them (`scripts/tests/pre-commit-swift_test.sh`);
- "Skills mirror" exports both skill trees from the index and runs
  `scripts/sync-agents.sh --check --root` on the export
  (`scripts/tests/pre-commit-skills_test.sh`);
- "Staged guard" runs `scripts/check-staged.sh` on every commit that stages any change
  (`scripts/tests/check-staged_test.sh`; the rules live in `scripts/guard/`).

All three check the staged content, not the worktree, so a partially staged file is
judged as it will be committed. A new section is appended below the layout-rule comment,
and one that needs a scratch directory takes it from `new_temp_dir`, which registers it
in `CLEANUP_DIRS` for the one shared `EXIT` trap — a second `trap … EXIT` would replace
the first and leak its directory.

## Why the hook never builds

The hook stays lint-only by decision: it never formats and re-stages, compiles, or runs
related tests. A SwiftPM build takes tens of seconds and builds the worktree rather than
the staged blobs, so it would check something other than the commit; and a slow or
noisy hook teaches `--no-verify`, which also skips the staged secret guard. CI runs the
build and tests. Do not reopen this without a new reason those costs miss.

## Whether the hook runs at all

The hook only reaches clones that ran `just install` (`core.hooksPath`).
`scripts/verify-hooks.sh` (`just install`'s last step, and `just check`'s first) fails
loudly when that config did not stick or `.githooks/pre-commit` lost its executable bit,
narrowing — not closing — that gap: a contributor who runs neither still commits
without the hook, so CI stays the backstop. It skips under CI or the named
`ALLOW_MISSING_GIT_HOOKS` opt-out, for an environment that genuinely cannot have git
hooks.
