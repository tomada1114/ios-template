---
paths:
  - "scripts/**"
  - ".githooks/**"
  - ".claude/skills/**/scripts/*.sh"
---

# Repository scripts

Every script under `scripts/` and `.githooks/pre-commit` follows these rules, whoever
writes it. A shell script bundled in a skill (`.claude/skills/<name>/scripts/`) follows
the same language and failure rules; its tests are the skill's own `scripts/tests/`
suite, which `just test-scripts` runs. What a gate checks, and which gate sees a change, is the `changing-gates`
skill.

## Shell and dependencies

- `#!/usr/bin/env bash` and `set -euo pipefail`. The sourced libraries
  (`scripts/tests/lib.sh`, `scripts/checks/lib.sh`, `scripts/guard/*.sh`) carry no
  shebang or `set` line of their own.
- Bash, because a script must run on a fresh clone before anything is installed, on
  macOS for contributors and CI's Xcode jobs and on Ubuntu for CI's `lint` job; a POSIX
  shell is the one runtime both have. Beyond it, assume only `git` and POSIX utilities,
  with no GNU- or BSD-only flag (`sed -i`, `readlink -f`, `mktemp -t`). The simulator
  scripts also need Xcode's `xcrun` and `python3`, as their headers say.
- Bash 3.2, because that is macOS `/bin/bash`: no associative arrays, no
  `mapfile`/`readarray`, no `${var,,}`, and no `"${arr[@]}"` on a possibly empty array
  under `set -u` (use `${arr[@]+"${arr[@]}"}`).
- 3.2 can fail a file silently: it scans `$(…)` for the closing `)` without
  understanding a heredoc inside it, so a `case` pattern like `a)` in a heredoc within
  `$(…)` ends the substitution and the file dies with a syntax error while exiting 0.
  Write a multi-line stub body as one single-quoted literal instead
  (`scripts/tests/run-simulator_test.sh`'s `xcrun` stub). `scripts/tests/run.sh` parses
  every file with `bash -n` first and counts one that does not parse as failed; run
  `/bin/bash scripts/tests/run.sh` by hand to exercise the suite under 3.2.
- Under `pipefail`, never pipe into a reader that exits early (`grep -q`, `head`,
  `grep -m`): the writer can hit a closed pipe and fail the pipeline for a line that was
  there, which once failed CI on an unchanged tree. Feed it a here-string instead,
  `grep -qxF -- "${x}" <<<"${list}"`.
- Pinned tools (`swiftlint`, `shellcheck`, `just`, …) are called by bare name; the
  caller provides PATH (`mise exec -- …` in a `just` recipe and the hook,
  `jdx/mise-action` in CI). A script never calls `mise exec` itself: CI's `lint` job
  installs only a subset of `mise.toml`, and a script asking mise for a missing tool
  would start a download mid-run instead of failing. It checks for the tool and fails
  with a named code (`scripts/lint.sh`'s `ERR_LINT_TOOL_MISSING`).
- `scripts/lint.sh` runs `shellcheck` on every tracked `*.sh`, the scripts a skill ships
  under `.claude/skills/` included; nothing needs wiring.

## Outside a git checkout

Never assume the checkout is the only repository on the machine. Each script's header
states which of these it does:

- **Refuse**, when its job is defined over tracked files: `scripts/lint.sh` lists shell
  scripts with `git ls-files`, so it checks `git rev-parse --is-inside-work-tree` and
  exits `ERR_LINT_NOT_A_REPO`, whose `Next:` names the way out (`--staged-tree DIR`).
  Without the guard a tarball would silently skip every script. `scripts/check-staged.sh`
  refuses the same way: there is no index to judge.
- **Skip with a one-line notice**, when the question does not exist outside a checkout:
  `scripts/verify-hooks.sh` has no hooks to check, prints one line, and exits 0.
- **Need no checkout**: `scripts/bundle-id.sh`, `scripts/run-simulator.sh`, and the
  `scripts/checks/` checks read files under a `--root` that defaults to the checkout
  holding the script (the flag is what lets tests point them at a fixture tree);
  `scripts/simulator-destination.sh`, `scripts/run-throttled.sh`, and
  `scripts/wait-simulator-settled.sh` read nothing from the tree. `scripts/simulator-relevant.sh` is the fail-safe case: outside a checkout, or on
  any git failure, it prints `true` with a one-line notice, because running the
  simulator checks needlessly is safe and skipping them is not.

Git exports `GIT_DIR` to every hook, and `git commit -- <path>` also exports a temporary
`GIT_INDEX_FILE`. An inherited `GIT_DIR` outranks the current directory and `git -C`,
so a `git` call meant for a test's throwaway repository writes into the outer one.
`scripts/tests/lib.sh` therefore unsets every exported `GIT_*` variable as it is sourced
(not a fixed list: `GIT_CONFIG_*` or `GIT_CEILING_DIRECTORIES` would still reshape a
fixture). The deliberate opposite is `scripts/check-staged.sh`: it is the hook's check
and must judge the index the hook was handed.

## Failure contract

A failure is usually read by an agent, which acts on exactly what it says. So the first
stderr line is `ERR_<STAGE>_<WHAT>: <what failed>`, then `Expected:`, `Actual:`, and
`Next:` lines, and the script exits 1. `Next:` names the next safe command, the fix
first and any documented opt-out second, so the reader is never left with only "turn
the check off". A script lists its codes in its header comment and never prints a
secret or the matched content (check-staged names a path and a category, never the
text). `scripts/verify-hooks.sh` in a clone where `just install` never ran:

```
ERR_HOOKS_NOT_INSTALLED: git does not resolve the hooks directory to <repo>/.githooks
Expected: git runs hooks from <repo>/.githooks (core.hooksPath .githooks)
Actual: `git rev-parse --git-path hooks` resolves to <repo>/.git/hooks
Next: run `just install`, or `git config core.hooksPath .githooks`. Or, if this environment cannot have git hooks, set ALLOW_MISSING_GIT_HOOKS=1.
```

A sentence repeated across a script's failures is built once (`OPT_OUT_SENTENCE`) so its
wording cannot diverge. Two known departures:

- `scripts/format-edited-file.sh` follows the format but exits 2, because Claude Code
  feeds a `PostToolUse` hook's stderr back to the agent only on exit 2.
- `scripts/coverage.sh`'s below-the-line-floor failure predates the contract and is a
  bare line from its embedded Python; its other failures
  (`ERR_COVERAGE_OVERRIDE_REMOVED`, `ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR`) follow it. Do
  not copy that shape into a new script.

## Tests

- Every script directly under `scripts/` has `scripts/tests/<script-name>_test.sh`,
  built on `scripts/tests/lib.sh`. A sourced library under `scripts/guard/` gets its own,
  `scripts/tests/guard-<library>_test.sh`. The harness checks under `scripts/checks/`,
  their runner, and their `lib.sh` share `scripts/tests/checks_test.sh`, which builds a
  fixture tree per failure mode and points each check at it with `--root`.
  `scripts/tests/run_test.sh` covers the runner.
- Known exceptions: `bootstrap.sh` has no test file, because CI's `bootstrap-smoke` job
  renames a clone of the template with it end to end; `coverage_test.sh` stubs `swift`
  to cover the removed-override rejection and the floor comparisons, but not a real
  coverage run, which is CI's `test` job.
- The shape, from `lib.sh`'s header: source it, `trap cleanup_temp EXIT`, one function
  per case using `capture`, `assert_exit`, and `assert_stderr_contains`, each run with
  `run_case "<name>" <function>`, then `finish`.
- `scripts/tests/run.sh` (`just test-scripts`, part of `just check` and CI's `lint`)
  starts every file at once and prints each file's log whole in glob order. Files
  therefore share nothing: each works in its own throwaway repository
  (`make_temp_repo`: local identity, signing off) or temp directory, never the real
  checkout, and touches the checkout read-only at most. `run_case` runs each case in a
  subshell with its own `CASE_DIR` and `STUB_BIN`, so a `cd`, PATH change, or stub
  cannot leak.
- Fake every external command with `stub_command`, which logs each call's arguments to
  `${STUB_BIN}/<name>.log`. A simulator test stubs `xcrun` in every case, since CI's
  `lint` job runs on Ubuntu.
- Assert the first stderr line when the contract is the point:
  `grep -q '^ERR_…: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")"`.
- A secret-shaped fixture is assembled at runtime, split across two quoted strings
  (`TOKEN="gh""p_…"`), because a whole literal would be blocked by the guard it tests and
  by GitHub push protection; the file's header comment says so.

## Adding a script

It lands with its test file; a `justfile` recipe if people run it by hand
(`mise exec -- scripts/<name>.sh` when it needs a pinned tool) and that recipe in
`AGENTS.md`'s Quick Reference (`just check-harness` fails on a recipe `AGENTS.md` names
but the `justfile` lacks); and, when it enforces something, the `changing-gates` steps.

## Verifying

`just lint` (shellcheck), then `just test-scripts`. Also `just verify-hooks` after
editing `scripts/verify-hooks.sh`, `just check-harness` after a harness check, and, for
`scripts/run-device.sh`, `just run-device` on a connected phone (owner-run).
