---
name: writing-repo-scripts
description: >
  Covers writing or editing a shell script under scripts/ (scripts/**/*.sh, including the
  sourced scripts/guard/ and scripts/checks/ libraries), .githooks/pre-commit, or a test
  under scripts/tests/. Use when adding a script or a just recipe that calls one, when a
  script must decide whether to refuse or skip outside a git checkout, when git run from
  a hook writes to the wrong repository (an inherited GIT_DIR or GIT_INDEX_FILE), when
  writing an ERR_<STAGE>_<WHAT> failure message, or when testing a script with
  scripts/tests/lib.sh, stub_command, or a secret-shaped fixture.
---

# Writing Repository Scripts

**Owns:** how a repository script is written and tested — why it is bash, what it may
depend on, how it behaves outside a git checkout, how it reports failure, and how its
test is built. **Does not own:** how a skill is authored or mirrored
(`authoring-skills`); what a gate checks and which gate sees a change (`changing-gates`).

The rules themselves live in one place, `AGENTS.md`'s "Repository scripts" section:
the shebang and shell options, the bash 3.2 subset, the dependency rules, the failure
contract, the git-checkout rule, and the one-test-file-per-script rule. Read it first.
This skill carries the reasoning behind those rules and worked examples from the tree;
it does not restate them, so the two cannot drift apart.

## Why bash, not a compiled language

- A script has to run on a fresh clone, before anything is installed. The only things
  it can assume at that point are `git` and a POSIX shell with its standard utilities.
  A compiled helper, or one written in a language whose runtime the clone does not
  have yet, would need a build or an install step before the very script that installs
  things could run.
- The scripts run on two platforms: macOS for contributors and CI's Xcode jobs, and
  Ubuntu for CI's `lint` job, which runs `scripts/lint.sh`, `scripts/tests/run.sh`, and
  `scripts/checks/run-all.sh`. A POSIX shell is the one runtime both already have. The
  simulator scripts (`scripts/simulator-destination.sh`, `scripts/run-simulator.sh`)
  also need Xcode's `xcrun` and `python3`, which exist only on a Mac; their tests stub
  `xcrun` in every case, because the `lint` job runs those tests on Ubuntu.
- Bash 3.2 specifically, because that is macOS `/bin/bash` — the shell a contributor
  gets when nothing else is installed. `scripts/tests/run.sh` runs each test file with
  the same bash that runs it, so `/bin/bash scripts/tests/run.sh` exercises the whole
  suite under 3.2 — worth running by hand, because 3.2 can fail a file *silently*: it
  scans `$(…)` for the closing `)` without understanding a heredoc inside it, so
  `"$(cat <<'EOF' … case "$1" in a) … EOF)"` ends at that `a)` and the file dies with a
  syntax error while still exiting 0, which no exit code can catch. `run.sh` parses
  every file with `bash -n` before starting it for exactly this reason, and counts a
  file that does not parse as that file failing. Write a multi-line stub body as one
  single-quoted literal instead (`scripts/tests/run-simulator_test.sh`'s `xcrun` stub).
- `pipefail` turns a reader that stops early into an intermittent failure of the whole
  pipeline. In `printf '%s\n' "${list}" | grep -qxF -- "${name}"`, `grep -q` exits at
  its first match, the writer can then hit a closed pipe (`printf: write error: Broken
  pipe`), and the pipeline reports failure for a line that *was* there — which is how
  `labels-declared.sh` once failed CI on an unchanged tree in the template this harness
  was ported from. Feed a variable to a reader with a here-string instead,
  `grep -qxF -- "${name}" <<<"${list}"`, which has no writer to kill; the same goes for
  `head`, `grep -m`, or any reader that exits before its input ends. The tests follow
  the same rule when they check a first stderr line:
  `grep -q '^ERR_…: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")"`.
- Pinned tools (`swiftlint`, `shellcheck`, `just`, …) arrive through the caller's PATH:
  `mise exec -- …` in a `just` recipe and the pre-commit hook, `jdx/mise-action` in CI.
  A script never calls `mise exec` itself, because CI's `lint` job installs only a
  subset of `mise.toml` (its `install_args`), and a script that asked mise for a tool
  the job did not install would start a download in the middle of a lint run instead
  of failing on the missing tool. A script that needs a tool checks for it and fails
  with a named code — `scripts/lint.sh`'s `ERR_LINT_TOOL_MISSING`,
  `scripts/sync-agents.sh`'s `ERR_AGENTS_TOOL_MISSING`.

## Running outside a git checkout

Every script's header comment says what it does when it is not inside a git work
tree. Pick by asking whether the script is meaningful there at all.

- **Refuse**, when the script's job is defined over tracked files. `scripts/lint.sh`
  finds the shell scripts to check with `git ls-files`, so in whole-repository mode it
  checks `git rev-parse --is-inside-work-tree` first and exits with
  `ERR_LINT_NOT_A_REPO`, whose `Next:` line names the way out (lint exported files with
  `--staged-tree DIR`). Without that guard a tarball would silently skip every shell
  script. `scripts/check-staged.sh` refuses the same way (`ERR_STAGED_NOT_A_REPO`):
  there is no index to judge.
- **Skip with a one-line notice**, when the question the script answers does not exist
  outside a checkout. `scripts/verify-hooks.sh` checks that git runs this repository's
  hooks; outside a work tree there are no hooks to check, so it prints
  `verify-hooks: not inside a git work tree; not checking the pre-commit hook.` and
  exits 0.
- **Need git only for a default.** `scripts/sync-agents.sh` uses the work tree only to
  find its root: with `--root DIR` it never calls git, without it it refuses
  (`ERR_AGENTS_NOT_A_REPO`). The `scripts/checks/` checks take the same `--root` flag,
  which is what lets their tests point them at a fixture tree.
- **Need no checkout at all.** `scripts/bundle-id.sh` and `scripts/run-simulator.sh`
  read files under a `--root` that defaults to the checkout containing the script, and
  `scripts/simulator-destination.sh` reads nothing from the tree; each header says so.

### Git run from inside a hook

Git exports `GIT_DIR` to every hook, and `git commit -- <path>` also exports a temporary
`GIT_INDEX_FILE`. An inherited `GIT_DIR` outranks both the current directory and
`git -C`, so a `git` call meant for another repository — a test's throwaway repo —
writes into the outer one instead. `scripts/tests/lib.sh` therefore unsets every
exported `GIT_*` variable as it is sourced (`unset_git_env`), not a fixed list, since
`GIT_CONFIG_*` or `GIT_CEILING_DIRECTORIES` would still reshape a fixture repository.
The deliberate opposite is `scripts/check-staged.sh`: it **is** the hook's check and
must judge the index the hook was handed, so it reads through `git diff --cached` with
the inherited variables intact.

## The stderr contract

A failure from a repository script is usually read by an agent, not by a person
watching a terminal, and an agent acts on exactly what the message says. So the message
names what failed, what was expected against what was found, and the next command that
is safe to run — and it never echoes a secret or the matched content (check-staged
names a path and a category, never the text). The format and the code naming are in
`AGENTS.md`'s "Repository scripts"; a script lists its codes in its header comment.

Worked example: `scripts/verify-hooks.sh` in a clone where `just install` never ran
(the checkout's absolute path shortened to `<repo>`):

```
ERR_HOOKS_NOT_INSTALLED: git does not resolve the hooks directory to <repo>/.githooks
Expected: git runs hooks from <repo>/.githooks (core.hooksPath .githooks)
Actual: `git rev-parse --git-path hooks` resolves to <repo>/.git/hooks
Next: run `just install`, or `git config core.hooksPath .githooks`. Or, if this environment cannot have git hooks, set ALLOW_MISSING_GIT_HOOKS=1.
```

The `Next:` line offers the fix first and the documented opt-out second, so the reader
is never left with only "turn the check off". Every one of its failures ends with the
same opt-out sentence, built once in the script (`OPT_OUT_SENTENCE`) so the wording
cannot diverge between them.

Two departures are listed in `AGENTS.md`'s "Repository scripts", each for a reason:
`scripts/coverage.sh`'s below-the-line-floor failure predates the contract and is a
bare one-line message from its embedded Python (its override rejection and
function-floor failure, `ERR_COVERAGE_OVERRIDE_REMOVED` and
`ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR`, already follow it) — do not copy its shape into a
new script; and `scripts/format-edited-file.sh` follows the message format but exits 2,
because Claude Code feeds a `PostToolUse` hook's stderr back to the agent only on
exit 2.

## Testing a script

Each test file sources `scripts/tests/lib.sh` and is picked up by `scripts/tests/run.sh`
(`just test-scripts`) because of its `_test.sh` name. The shape, from `lib.sh`'s header:

```bash
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT
case_rejects_bad_flag() {
    capture "${REPO_ROOT}/scripts/x.sh" --bad
    assert_exit 1
    assert_stderr_contains "ERR_X_USAGE"
}
run_case "rejects a bad flag" case_rejects_bad_flag
finish
```

- **A throwaway repository per case.** `make_temp_repo` returns a fresh repository with
  a local identity and commit signing disabled, under a temp root that `cleanup_temp`
  removes. `scripts/tests/verify-hooks_test.sh` builds one per case and runs a copy of
  the script from inside it; the real checkout is never read or written. A check that
  takes `--root` gets a fixture tree instead (`scripts/tests/checks_test.sh`).
- **Each case is a subshell.** `run_case` gives it its own `CASE_DIR` and `STUB_BIN`, so
  a `cd`, a PATH change, or a stub cannot leak into the next case.
- **The files run concurrently**, which is why the independence above is a rule and not
  just good manners: `run.sh` starts every file at once and `wait`s for each pid in glob
  order, printing that file's captured log whole, so the output reads exactly like a
  sequential run while the wall time is the slowest file rather than the sum. A file
  that reached for a fixed shared path, or wrote into the checkout, would race.
  On INT or TERM it kills the files it started — a non-interactive shell starts a
  background job with SIGINT ignored, so Ctrl-C reaches the runner alone and would
  otherwise leave them writing into a log directory it has already removed — and prints
  every log it had not reported yet, marked `(interrupted)`.
  `scripts/tests/run_test.sh` covers the runner itself, including a case whose three
  fixture files each wait for the other two — it can only pass if they really do run at
  the same time.
- **Fake every external command.** `stub_command gh '…'` writes an executable `gh` into
  the case's stub directory, prepends it to PATH, and logs each call's arguments to
  `${STUB_BIN}/gh.log`, so a test asserts on what would have been sent to GitHub
  without a network call. `scripts/tests/label-pr_test.sh` stubs `gh`;
  `scripts/tests/coverage_test.sh` stubs `swift`;
  `scripts/tests/simulator-destination_test.sh` and
  `scripts/tests/run-simulator_test.sh` stub `xcrun`.
- **Assert on the first stderr line**, not just a substring, when the point is the
  contract: `grep -q '^ERR_…: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")"`, a here-string
  for the `pipefail` reason above.
- **Secret-shaped fixtures are assembled at runtime.** A test of the staged guard needs a
  value that looks like a credential, but a whole literal in the test file would be
  blocked by the very guard it tests, and by GitHub push protection. Split the prefix
  across two quoted strings so no single token matches, as
  `scripts/tests/check-staged_test.sh` and `scripts/tests/guard-credentials_test.sh` do
  (`TOKEN="gh""p_…"`), and say so in the file's header comment.

Which script gets which kind of test file, and the known exceptions, are listed in
`AGENTS.md`'s "Repository scripts"; `AGENTS.md`'s "Validating a change" names the check
to run after editing one.

## Adding a script

A new script usually lands with more than its own file:

- its `scripts/tests/<name>_test.sh`;
- a `justfile` recipe if people run it by hand (`mise exec -- scripts/<name>.sh` when it
  needs a pinned tool), and the recipe in `AGENTS.md`'s Quick Reference —
  `scripts/checks/just-recipes-exist.sh` fails if `AGENTS.md` names a recipe the
  `justfile` does not define, or a `Bash(just <recipe>…)` rule in
  `.claude/settings.json` names one;
- a row in `AGENTS.md`'s "Validating a change" when no existing row covers it, and an
  Enforcement layers row when it enforces something (**REQUIRED:** `changing-gates`).

`shellcheck` needs no wiring: `scripts/lint.sh` checks every tracked `*.sh`
(except the generated `.claude/skills/` mirror).
