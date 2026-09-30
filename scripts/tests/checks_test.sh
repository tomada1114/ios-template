#!/usr/bin/env bash
# Tests for the harness-conformance checks under scripts/checks/ (their sourced
# scripts/checks/lib.sh included) and their runner, scripts/checks/run-all.sh.
# Every case builds its own fixture tree in a temp directory with make_fixture and
# points the check at it with --root, so the real checkout is never read or
# written. Each failure mode gets its own case, and each asserts the specific error
# code and the offending name or line, so a check weakened to always pass (or to
# skip the thing it checks) fails here. just-recipes-exist.sh runs the real `just`
# (a mise tool): run this file through `mise exec --`, or with just on PATH.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

CHECKS="${REPO_ROOT}/scripts/checks"
SHA="9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0"
# A literal backtick, so Markdown code spans can be written in double quotes.
BT='`'
# The template's app-name placeholder, quote-split for the same reason
# scripts/bootstrap.sh and scripts/checks/product-section-filled.sh split theirs:
# this file is tracked too, and the rename must not rewrite the fixture's copy of the
# literal whose absence tells that check the rename has happened.
PH_NAME='My''App'
BOUNDARY_TESTS="Packages/MyAppKit/Tests/MyAppCoreTests/ArchitectureBoundaryTests.swift"

if ! command -v just >/dev/null 2>&1; then
    echo "ERR_TESTS_TOOL_MISSING: 'just' is not on PATH" >&2
    echo "Expected: just (pinned in mise.toml) on PATH for just-recipes-exist.sh's cases" >&2
    echo "Actual: \`command -v just\` found nothing" >&2
    echo "Next: run \`mise exec -- scripts/tests/run.sh\`, or \`just test-scripts\`" >&2
    exit 1
fi

# write_skill ROOT NAME — a well-formed .agents/skills/NAME/SKILL.md.
write_skill() {
    mkdir -p "$1/.agents/skills/$2"
    cat >"$1/.agents/skills/$2/SKILL.md" <<EOF
---
name: $2
description: >
  Covers the $2 fixture skill. Use when testing the harness checks.
---

# $2
EOF
}

# Prints the path of a fixture tree every check passes on. It deliberately holds
# the near misses each check must not flag: a `just --list` and a `just <recipe>`
# placeholder, `just` in prose outside backticks, a local `uses:`, a quoted pin,
# a `### Rules` table after the Skills table, a composite action, a SwiftLint rule
# after no_ui_import_in_core with a group of its own, a quoted module in a comment
# inside forbiddenModules and in a second array, a CI step that reaches a recipe
# through its script, a CI-only recipe run both by name and through its script, a
# CI-only job, a label assigned to a shell
# variable, a quoted label name with a trailing comment, a job-level `defaults: run:`
# mapping, a Dependabot `labels:` list at its key's own indentation, a Dependabot
# entry with no `labels:` key (the implied `dependencies`), a `permissions: {}` whose
# write scope is on the job, a push workflow's per-tag concurrency group without
# `github.workflow` that never cancels, ci.yml's cancel-only-on-pull-requests
# expression, a `run:` block made fail-closed by its own `set -euo pipefail`, a
# step-level and a composite `shell: bash`, a Dependabot prefix without its colon,
# and a Renovate cooldown of `1 week` against Dependabot's 7 days.
make_fixture() {
    local root
    root=$(make_temp_dir)
    cat >"${root}/justfile" <<'EOF'
default:
    @just --list

generate:
    echo generate

verify-hooks:
    scripts/verify-hooks.sh

fmt:
    echo fmt

lint:
    mise exec -- scripts/lint.sh

build:
    echo build

uitest:
    xcodebuild test -destination "$(scripts/simulator-destination.sh)"

check: verify-hooks fmt lint build
    echo check
EOF
    cat >"${root}/AGENTS.md" <<'EOF'
# Project Guide

## Product

TODO: what the fixture app is, and for whom.

**Non-goals** — TODO: everything else.

## Quick Reference

```bash
just generate  # Regenerate
just check     # Everything
```

Run `just --list` to see recipes, then `just generate && just build`. A
`just <recipe>` placeholder names nothing, and this is just prose: just bogus.

## Skills

| Skill | Load it when you are working on |
|---|---|
| `alpha` | the first thing |
| `beta` | the second thing |

### Rules

| Rule | Loads when you touch |
|---|---|
| `.claude/rules/project.md` | `project.yml` |

## Enforcement layers

| Layer | Fires on |
|---|---|
| `gamma` | never |
EOF
    mkdir -p "${root}/.claude"
    cat >"${root}/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(just check)",
      "Bash(just build)",
      "Bash(just generate:*)",
      "Bash(swift test:*)"
    ],
    "deny": [
      "Bash(git push --force:*)"
    ]
  }
}
EOF
    write_skill "${root}" alpha
    write_skill "${root}" beta
    cat >"${root}/project.yml" <<EOF
name: ${PH_NAME}
targets:
  ${PH_NAME}:
    type: application
EOF
    mkdir -p "${root}/.github/workflows" "${root}/.github/actions/setup"
    cat >"${root}/.github/workflows/ci.yml" <<EOF
name: CI

on:
  pull_request:

permissions:
  contents: read

concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: \${{ github.event_name == 'pull_request' }}

defaults:
  run:
    shell: bash

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@${SHA} # v7.0.0
      - uses: ./.github/actions/setup
      - name: Upload
        uses: "github/codeql-action/upload-sarif@${SHA}" # v4.36.3
      - name: Lint
        run: scripts/lint.sh
  app:
    runs-on: macos-26
    defaults:
      run:
        shell: bash
    steps:
      - run: scripts/simulator-destination.sh
      - name: Build and UI test
        run: |
          # just check leaves uitest out
          just build
          just uitest
  bootstrap-smoke:
    runs-on: macos-26
    steps:
      - run: swift test
EOF
    cat >"${root}/.github/workflows/label.yml" <<'EOF'
name: Label
on: pull_request
permissions: {}
concurrency:
  group: label-${{ github.ref }}
  cancel-in-progress: true
jobs:
  label:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - run: |
          # The label this PR's type maps to.
          set -euo pipefail
          case "$TYPE" in
            fix) label=bug ;;
            ci) label="ci" ;;
          esac
          gh label create "$label" || true
          gh pr edit 1 --add-label "$label"
EOF
    cat >"${root}/.github/workflows/release.yml" <<EOF
name: Release
on:
  push:
permissions: {}
concurrency:
  group: release-\${{ github.ref_name }}
  cancel-in-progress: false
jobs:
  build:
    permissions:
      contents: write
    runs-on: ubuntu-latest
    steps:
      - uses: jdx/mise-action@${SHA} # v4.2.0
      - name: Package
        shell: bash
        run: scripts/package_dmg.sh | tee package.log
EOF
    cat >"${root}/.github/workflows/title.yml" <<EOF
name: PR title
on:
  pull_request:
    types: [opened, edited]
permissions:
  pull-requests: read
concurrency:
  group: \${{ github.workflow }}-\${{ github.ref }}
  cancel-in-progress: true
jobs:
  main:
    runs-on: ubuntu-latest
    steps:
      - uses: amannn/action-semantic-pull-request@${SHA} # v6.1.1
        with:
          types: |
            feat
            fix
            ci
            deps
EOF
    mkdir -p "${root}/.github/rulesets"
    cat >"${root}/.github/rulesets/main.json" <<'EOF'
{
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "required_status_checks": [
          { "context": "lint", "integration_id": 15368 }
        ]
      }
    }
  ]
}
EOF
    cat >"${root}/.github/actions/setup/action.yml" <<EOF
name: Setup
runs:
  using: composite
  steps:
    - uses: actions/cache@${SHA} # v4.2.3
    - shell: bash
      run: echo "cached" | tee -a "\$GITHUB_STEP_SUMMARY"
EOF
    # The next rule's `(print|debugPrint)\b` would join the Core ban list if the
    # no_ui_import_in_core block did not end at it.
    cat >"${root}/.swiftlint.yml" <<'EOF'
strict: true
custom_rules:
  no_ui_import_in_core:
    included: 'Packages/MyAppKit/Sources/MyAppCore/.+\.swift$'
    regex: '^\s*(@[\w()]+\s+)*import\s+((typealias|struct|class)\s+)?(SwiftUI|AppKit|Carbon)\b'
    severity: error

  no_print_in_sources:
    regex: '(print|debugPrint)\b'
EOF
    mkdir -p "$(dirname "${root}/${BOUNDARY_TESTS}")"
    cat >"${root}/${BOUNDARY_TESTS}" <<'EOF'
struct ArchitectureBoundaryTests {
    /// Not "Foundation" — this comment is outside the literal.
    static let forbiddenModules: [String] = [
        "Carbon", "SwiftUI", // "Combine" stays allowed
        "AppKit",
    ]

    static let otherModules = ["Combine"]
}
EOF
    write_labels "${root}" bug enhancement "priority: P1" dependencies ci
    mkdir -p "${root}/.github/ISSUE_TEMPLATE"
    printf 'name: Bug\nlabels: ["bug", "priority: P1"]\nbody: []\n' >"${root}/.github/ISSUE_TEMPLATE/bug.yml"
    printf 'name: Task\nlabels:\n  - enhancement\nbody:\n  - type: markdown\n' >"${root}/.github/ISSUE_TEMPLATE/task.yml"
    printf 'blank_issues_enabled: false\n' >"${root}/.github/ISSUE_TEMPLATE/config.yml"
    cat >"${root}/.github/dependabot.yml" <<'EOF'
version: 2
updates:
  - package-ecosystem: "swift"
    directory: "/"
    groups:
      all:
        patterns: ["*"]
    commit-message:
      prefix: "deps:"
    cooldown:
      default-days: 7
  - package-ecosystem: "github-actions"
    directory: "/"
    labels:
    - "dependencies"
    - ci
    commit-message:
      prefix: ci
    cooldown:
      default-days: 7
EOF
    cat >"${root}/.github/renovate.json" <<'EOF'
{
  "enabledManagers": ["mise"],
  "labels": [
    "dependencies"
  ],
  "commitMessagePrefix": "deps:",
  "minimumReleaseAge": "1 week"
}
EOF
    echo "${root}"
}

# write_labels ROOT NAME... — a .github/labels.yml declaring exactly NAME..., in order.
write_labels() {
    local root="$1" name
    shift
    printf '# Fixture labels.\n' >"${root}/.github/labels.yml"
    for name in "$@"; do
        printf -- '- name: "%s" # a label\n  color: ededed\n  description: "The %s label."\n' "${name}" "${name}" >>"${root}/.github/labels.yml"
    done
}

# first_stderr_is CODE — the failure contract: the first stderr line is `CODE: …`.
first_stderr_is() {
    head -n 1 "${CASE_DIR}/stderr" | grep -q "^$1: " || _fail "first stderr line is not $1"
}

assert_contract() {
    first_stderr_is "$1"
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
}

# --- run-all.sh ---------------------------------------------------------------

case_run_all_passes() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/run-all.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "harness checks: 9 check(s) passed"
}

case_run_all_reports_every_failure() {
    local root
    root=$(make_fixture)
    echo "Then run ${BT}just deploy${BT}." >>"${root}/AGENTS.md"
    sed '/^permissions:/d; /^  contents: read/d' "${root}/.github/workflows/ci.yml" >"${root}/ci.tmp"
    mv "${root}/ci.tmp" "${root}/.github/workflows/ci.yml"
    capture "${BASH}" "${CHECKS}/run-all.sh" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_CHECK_RECIPE_MISSING"
    assert_stderr_contains "ERR_CHECK_WORKFLOW_PERMISSIONS"
    assert_stderr_contains "ERR_CHECKS_FAILED: 2 of 9 harness check(s) failed: just-recipes-exist.sh workflow-pins-and-permissions.sh"
    assert_stderr_not_contains "skills-frontmatter.sh" "a passing check named as failed"
    assert_stderr_not_contains "skills-index-complete.sh" "a passing check named as failed"
    assert_stdout_contains "==> scripts/checks/skills-index-complete.sh"
}

case_run_all_rejects_unknown_argument() {
    capture "${BASH}" "${CHECKS}/run-all.sh" --bogus
    assert_exit 1
    assert_contract ERR_CHECK_USAGE
}

case_check_rejects_missing_root() {
    capture "${BASH}" "${CHECKS}/skills-frontmatter.sh" --root "${CASE_DIR}/nope"
    assert_exit 1
    assert_contract ERR_CHECK_USAGE
}

# --- just-recipes-exist.sh ----------------------------------------------------

case_recipes_pass() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/just-recipes-exist.sh" --root "${root}"
    assert_exit 0
}

case_recipes_bogus_inline() {
    local root
    root=$(make_fixture)
    echo "Then run ${BT}just deploy${BT}." >>"${root}/AGENTS.md"
    capture "${BASH}" "${CHECKS}/just-recipes-exist.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_RECIPE_MISSING
    assert_stderr_contains "AGENTS.md:$(wc -l <"${root}/AGENTS.md" | tr -d ' '): \`just deploy\`"
}

case_recipes_bogus_second_in_chain() {
    local root
    root=$(make_fixture)
    echo "Run ${BT}just build && just deploy-later${BT}." >>"${root}/AGENTS.md"
    capture "${BASH}" "${CHECKS}/just-recipes-exist.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_RECIPE_MISSING
    assert_stderr_contains "no recipe named 'deploy-later'"
    assert_stderr_not_contains "no recipe named 'build'" "an existing recipe reported missing"
}

case_recipes_bogus_in_fenced_block() {
    local root
    root=$(make_fixture)
    printf '\n%sbash\njust release  # Ship it\n%s\n' "${BT}${BT}${BT}" "${BT}${BT}${BT}" >>"${root}/AGENTS.md"
    capture "${BASH}" "${CHECKS}/just-recipes-exist.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_RECIPE_MISSING
    assert_stderr_contains "no recipe named 'release'"
}

case_recipes_bogus_permission_rule() {
    local root
    root=$(make_fixture)
    cat >"${root}/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": [
      "Bash(just check)",
      "Bash(just deploy:*)"
    ]
  }
}
EOF
    capture "${BASH}" "${CHECKS}/just-recipes-exist.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_PERMISSION_RECIPE_MISSING
    assert_stderr_contains ".claude/settings.json:$(grep -n 'just deploy' "${root}/.claude/settings.json" | cut -d: -f1):"
    assert_stderr_contains "no recipe named 'deploy'"
    assert_stderr_not_contains "no recipe named 'check'" "an existing recipe reported missing"
}

case_recipes_pass_without_settings() {
    local root
    root=$(make_fixture)
    mv "${root}/.claude" "${CASE_DIR}/claude-dir"
    capture "${BASH}" "${CHECKS}/just-recipes-exist.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "there is no .claude/settings.json to check"
}

case_recipes_just_missing() {
    local root
    root=$(make_fixture)
    if [ -x /usr/bin/just ] || [ -x /bin/just ]; then
        echo "  skip: just is installed under /usr/bin or /bin" >&2
        return 0
    fi
    PATH="/usr/bin:/bin" capture "${BASH}" "${CHECKS}/just-recipes-exist.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_TOOL_MISSING
}

case_recipes_justfile_unreadable() {
    local root
    root=$(make_fixture)
    printf '\ndeploy: no-such-recipe\n    echo deploy\n' >>"${root}/justfile"
    capture "${BASH}" "${CHECKS}/just-recipes-exist.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_JUST_FAILED
    assert_stderr_contains "Actual: error: recipe \`deploy\` has unknown dependency \`no-such-recipe\`"
    assert_stderr_not_contains "justfile:" "more than just's first error line reported"
}

# --- workflow-pins-and-permissions.sh ----------------------------------------

case_workflows_pass() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/workflow-pins-and-permissions.sh" --root "${root}"
    assert_exit 0
}

case_workflows_pass_without_actions_dir() {
    local root
    root=$(make_fixture)
    mv "${root}/.github/actions" "${CASE_DIR}/actions"
    capture "${BASH}" "${CHECKS}/workflow-pins-and-permissions.sh" --root "${root}"
    assert_exit 0
}

case_workflows_missing_permissions() {
    local root
    root=$(make_fixture)
    cat >"${root}/.github/workflows/lint.yml" <<EOF
name: Lint
on: push
jobs:
  lint:
    permissions:
      contents: read
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@${SHA} # v7.0.0
EOF
    capture "${BASH}" "${CHECKS}/workflow-pins-and-permissions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_PERMISSIONS
    assert_stderr_contains ".github/workflows/lint.yml: no top-level"
    assert_stderr_not_contains "ci.yml: no top-level" "a workflow with permissions reported"
}

case_workflows_tag_pin_in_workflow() {
    local root
    root=$(make_fixture)
    echo "      - uses: actions/setup-node@v4" >>"${root}/.github/workflows/ci.yml"
    capture "${BASH}" "${CHECKS}/workflow-pins-and-permissions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_UNPINNED
    assert_stderr_contains ".github/workflows/ci.yml:$(wc -l <"${root}/.github/workflows/ci.yml" | tr -d ' '): actions/setup-node@v4"
}

case_workflows_tag_pin_in_composite_action() {
    local root
    root=$(make_fixture)
    echo "    - uses: actions/setup-python@v5 # v5.0.0" >>"${root}/.github/actions/setup/action.yml"
    capture "${BASH}" "${CHECKS}/workflow-pins-and-permissions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_UNPINNED
    assert_stderr_contains ".github/actions/setup/action.yml:$(wc -l <"${root}/.github/actions/setup/action.yml" | tr -d ' '): actions/setup-python@v5"
}

case_workflows_sha_without_version_comment() {
    local root
    root=$(make_fixture)
    echo "      - uses: actions/setup-go@${SHA}" >>"${root}/.github/workflows/ci.yml"
    capture "${BASH}" "${CHECKS}/workflow-pins-and-permissions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_UNPINNED
    assert_stderr_contains "actions/setup-go@${SHA}"
}

case_workflows_short_sha() {
    local root
    root=$(make_fixture)
    echo "      - uses: actions/setup-go@9c091bb # v5.0.0" >>"${root}/.github/workflows/ci.yml"
    capture "${BASH}" "${CHECKS}/workflow-pins-and-permissions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_UNPINNED
    assert_stderr_contains "actions/setup-go@9c091bb"
}

# --- skills-frontmatter.sh ----------------------------------------------------

case_frontmatter_pass() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/skills-frontmatter.sh" --root "${root}"
    assert_exit 0
}

case_frontmatter_third_key() {
    local root
    root=$(make_fixture)
    { head -n 2 "${root}/.agents/skills/alpha/SKILL.md"; echo 'paths: "**/*.swift"'; tail -n +3 "${root}/.agents/skills/alpha/SKILL.md"; } >"${CASE_DIR}/x"
    mv "${CASE_DIR}/x" "${root}/.agents/skills/alpha/SKILL.md"
    capture "${BASH}" "${CHECKS}/skills-frontmatter.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_FRONTMATTER
    assert_stderr_contains ".agents/skills/alpha: unexpected key \`paths\`"
    assert_stderr_not_contains ".agents/skills/beta:" "a well-formed skill reported"
}

case_frontmatter_name_mismatch() {
    local root
    root=$(make_fixture)
    sed 's/^name: beta$/name: gamma/' "${root}/.agents/skills/beta/SKILL.md" >"${CASE_DIR}/x"
    mv "${CASE_DIR}/x" "${root}/.agents/skills/beta/SKILL.md"
    capture "${BASH}" "${CHECKS}/skills-frontmatter.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_FRONTMATTER
    assert_stderr_contains ".agents/skills/beta: \`name\` is \`gamma\`, but the directory is \`beta\`"
}

case_frontmatter_empty_description() {
    local root
    root=$(make_fixture)
    printf -- '---\nname: alpha\ndescription: >\n---\n\n# alpha\n' >"${root}/.agents/skills/alpha/SKILL.md"
    capture "${BASH}" "${CHECKS}/skills-frontmatter.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_FRONTMATTER
    assert_stderr_contains ".agents/skills/alpha: \`description\` is empty"
}

case_frontmatter_missing_block() {
    local root
    root=$(make_fixture)
    printf '# alpha\n\nname: alpha\n' >"${root}/.agents/skills/alpha/SKILL.md"
    capture "${BASH}" "${CHECKS}/skills-frontmatter.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_FRONTMATTER
    assert_stderr_contains ".agents/skills/alpha: does not start with a \`---\` frontmatter line"
}

case_frontmatter_unclosed_block() {
    local root
    root=$(make_fixture)
    printf -- '---\nname: alpha\ndescription: A skill.\n' >"${root}/.agents/skills/alpha/SKILL.md"
    capture "${BASH}" "${CHECKS}/skills-frontmatter.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_FRONTMATTER
    assert_stderr_contains ".agents/skills/alpha: frontmatter block is never closed"
}

case_frontmatter_missing_skill_file() {
    local root
    root=$(make_fixture)
    mkdir "${root}/.agents/skills/gamma"
    capture "${BASH}" "${CHECKS}/skills-frontmatter.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_FRONTMATTER
    assert_stderr_contains ".agents/skills/gamma: no SKILL.md"
}

# --- skills-descriptions.sh ---------------------------------------------------

# write_frontmatter ROOT NAME DESCRIPTION_LINES — replaces NAME's SKILL.md with a
# frontmatter whose description is the given line(s), verbatim after `description:`.
write_frontmatter() {
    printf -- '---\nname: %s\ndescription:%s\n---\n\n# %s\n' "$2" "$3" "$2" >"$1/.agents/skills/$2/SKILL.md"
}

case_descriptions_pass() {
    local root
    root=$(make_fixture)
    # Near misses: a quoted value with `: ` and ` #`, and a folded block holding both.
    write_frontmatter "${root}" alpha " \"Covers alpha: the fixture #1. Use when testing.\""
    write_frontmatter "${root}" beta " >
  Covers beta: the fixture #2.
  - Use when testing."
    mkdir -p "${root}/.agents/skills/beta/references"
    echo "# notes" >"${root}/.agents/skills/beta/references/failure-modes.md"
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 0
}

case_descriptions_too_long() {
    local root long
    root=$(make_fixture)
    long=$(printf 'x%.0s' $(seq 1 1025))
    write_frontmatter "${root}" alpha " >
  ${long}"
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_DESCRIPTION
    assert_stderr_contains ".agents/skills/alpha: \`description\` is 1025 characters, over the 1024-character limit"
    assert_stderr_not_contains ".agents/skills/beta:" "a well-formed skill reported"
}

case_descriptions_at_limit_passes() {
    local root long
    root=$(make_fixture)
    long=$(printf 'x%.0s' $(seq 1 1024))
    write_frontmatter "${root}" alpha " >
  ${long}"
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 0
}

case_descriptions_non_ascii() {
    local root
    root=$(make_fixture)
    write_frontmatter "${root}" alpha " >
  Covers alpha $(printf '\342\200\224') the fixture skill."
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_DESCRIPTION
    assert_stderr_contains ".agents/skills/alpha: \`description\` contains a non-ASCII"
}

case_descriptions_unquoted_colon() {
    local root
    root=$(make_fixture)
    write_frontmatter "${root}" alpha " Covers alpha: the fixture skill."
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_DESCRIPTION
    assert_stderr_contains ".agents/skills/alpha: line 3 (\`description\`) is an unquoted value containing \`: \`"
}

case_descriptions_plain_continuation_colon() {
    local root
    root=$(make_fixture)
    write_frontmatter "${root}" alpha " Covers alpha.
  Use when: testing."
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_DESCRIPTION
    assert_stderr_contains ".agents/skills/alpha: line 4 (\`description\`) is an unquoted value containing \`: \`"
}

case_descriptions_unquoted_comment() {
    local root
    root=$(make_fixture)
    write_frontmatter "${root}" alpha " Covers alpha #1 fixture."
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_DESCRIPTION
    assert_stderr_contains ".agents/skills/alpha: line 3 (\`description\`) is an unquoted value containing \` #\`"
}

case_descriptions_indicator_start() {
    local root
    root=$(make_fixture)
    write_frontmatter "${root}" alpha " *alpha covers the fixture."
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_DESCRIPTION
    assert_stderr_contains ".agents/skills/alpha: line 3 (\`description\`) starts with a YAML indicator character"
}

case_descriptions_nested_skill_file() {
    local root
    root=$(make_fixture)
    mkdir -p "${root}/.agents/skills/alpha/references"
    cp "${root}/.agents/skills/alpha/SKILL.md" "${root}/.agents/skills/alpha/references/SKILL.md"
    capture "${BASH}" "${CHECKS}/skills-descriptions.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_NESTED
    assert_stderr_contains ".agents/skills/alpha/references/SKILL.md"
    assert_stderr_not_contains "ERR_CHECK_SKILL_DESCRIPTION" "a well-formed description reported"
}

# --- skills-index-complete.sh -------------------------------------------------

case_index_pass_ignores_rules_table() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/skills-index-complete.sh" --root "${root}"
    assert_exit 0
    assert_stderr_not_contains ".claude/rules/project.md" "the ### Rules table read as skills"
}

case_index_directory_without_row() {
    local root
    root=$(make_fixture)
    write_skill "${root}" delta
    capture "${BASH}" "${CHECKS}/skills-index-complete.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_INDEX
    assert_stderr_contains ".agents/skills/delta/: no row for \`delta\`"
}

case_index_row_without_directory() {
    local root
    root=$(make_fixture)
    mv "${root}/.agents/skills/beta" "${CASE_DIR}/beta"
    capture "${BASH}" "${CHECKS}/skills-index-complete.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_INDEX
    assert_stderr_contains "AGENTS.md:$(grep -n "^| ${BT}beta${BT}" "${root}/AGENTS.md" | cut -d: -f1): \`beta\` has a Skills table row but no .agents/skills/beta/ directory"
    assert_stderr_not_contains "\`alpha\`" "an indexed skill with a directory reported"
}

case_index_no_skills_table() {
    local root
    root=$(make_fixture)
    sed 's/^## Skills$/## Capabilities/' "${root}/AGENTS.md" >"${CASE_DIR}/x"
    mv "${CASE_DIR}/x" "${root}/AGENTS.md"
    capture "${BASH}" "${CHECKS}/skills-index-complete.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_SKILL_INDEX
    assert_stderr_contains "no table under a \`## Skills\` heading"
}

# --- core-ban-lists-agree.sh --------------------------------------------------

# replace_in ROOT REL FROM TO — the first match of the basic regex FROM on each line
# of ROOT/REL becomes TO (neither may contain a `#`).
replace_in() {
    sed "s#$3#$4#" "$1/$2" >"${CASE_DIR}/replaced"
    mv "${CASE_DIR}/replaced" "$1/$2"
}

case_ban_pass() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/core-ban-lists-agree.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "core-ban-lists-agree: .swiftlint.yml and ArchitectureBoundaryTests ban the same modules."
}

case_ban_pass_single_line_literal() {
    local root
    root=$(make_fixture)
    printf 'enum T {\n    static let forbiddenModules = ["AppKit", "SwiftUI", "Carbon", "AppKit"]\n}\n' >"${root}/${BOUNDARY_TESTS}"
    capture "${BASH}" "${CHECKS}/core-ban-lists-agree.sh" --root "${root}"
    assert_exit 0
}

case_ban_lint_has_extra() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .swiftlint.yml "|Carbon)" "|Carbon|UIKit)"
    capture "${BASH}" "${CHECKS}/core-ban-lists-agree.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_CORE_BAN_DIVERGED
    assert_stderr_contains "\`UIKit\` is banned by .swiftlint.yml's no_ui_import_in_core but missing from forbiddenModules"
    assert_stderr_not_contains "\`Carbon\`" "a module in both lists reported"
}

case_ban_tests_have_extra() {
    local root
    root=$(make_fixture)
    replace_in "${root}" "${BOUNDARY_TESTS}" '"AppKit",' '"AppKit", "ServiceManagement",'
    capture "${BASH}" "${CHECKS}/core-ban-lists-agree.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_CORE_BAN_DIVERGED
    assert_stderr_contains "\`ServiceManagement\` is in forbiddenModules in ${BOUNDARY_TESTS} but missing from .swiftlint.yml's no_ui_import_in_core regex"
    assert_stderr_not_contains "\`Combine\`" "a module outside forbiddenModules read as banned"
}

case_ban_lint_list_unparsed() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .swiftlint.yml "no_ui_import_in_core:" "no_ui_import:"
    capture "${BASH}" "${CHECKS}/core-ban-lists-agree.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_CORE_BAN_UNPARSED
    assert_stderr_contains ".swiftlint.yml: no module alternation"
    assert_stderr_not_contains "ERR_CHECK_CORE_BAN_DIVERGED" "an unreadable list compared as empty"
}

case_ban_tests_list_unparsed() {
    local root
    root=$(make_fixture)
    replace_in "${root}" "${BOUNDARY_TESTS}" "forbiddenModules" "bannedModules"
    capture "${BASH}" "${CHECKS}/core-ban-lists-agree.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_CORE_BAN_UNPARSED
    assert_stderr_contains "${BOUNDARY_TESTS}: no string literal"
}

case_ban_missing_tests_file() {
    local root
    root=$(make_fixture)
    mv "${root}/${BOUNDARY_TESTS}" "${CASE_DIR}/moved.swift"
    capture "${BASH}" "${CHECKS}/core-ban-lists-agree.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_INPUT_MISSING
}

# --- just-check-matches-ci.sh -------------------------------------------------

# append_ci_step ROOT RUN — appends a `run:` step to the fixture ci.yml's lint job.
append_ci_step() {
    awk -v run="$2" '{ print } /^        run: scripts\/lint.sh$/ { print "      - run: " run }' \
        "$1/.github/workflows/ci.yml" >"${CASE_DIR}/ci.yml"
    mv "${CASE_DIR}/ci.yml" "$1/.github/workflows/ci.yml"
}

case_ci_pass() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "just-check-matches-ci: "
}

case_ci_gate_missing_from_ci() {
    local root
    root=$(make_fixture)
    printf '\ntest:\n    scripts/coverage.sh\n' >>"${root}/justfile"
    replace_in "${root}" justfile "^check: verify-hooks fmt lint build" "check: verify-hooks fmt lint test build"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_JUST_CI_DIVERGED
    assert_stderr_contains "\`just check\` runs \`just test\`, but no .github/workflows/ci.yml step runs it"
    assert_stderr_not_contains "\`just lint\`" "a gate CI reaches through its script reported"
}

case_ci_recipe_missing_from_check() {
    local root
    root=$(make_fixture)
    append_ci_step "${root}" "just generate"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_JUST_CI_DIVERGED
    assert_stderr_contains ".github/workflows/ci.yml:$(grep -n 'run: just generate' "${root}/.github/workflows/ci.yml" | cut -d: -f1): job \`lint\` runs \`just generate\`"
    assert_stderr_not_contains "\`just uitest\`" "a CI_ONLY recipe reported"
}

case_ci_script_no_recipe_calls() {
    local root
    root=$(make_fixture)
    append_ci_step "${root}" "scripts/other.sh --flag"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_JUST_CI_DIVERGED
    assert_stderr_contains "runs scripts/other.sh, which no justfile recipe calls"
}

case_ci_step_runs_nothing_shared() {
    local root
    root=$(make_fixture)
    append_ci_step "${root}" "swift build"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_JUST_CI_DIVERGED
    assert_stderr_contains "job \`lint\` runs a step that calls no \`just\` recipe and no repository script: swift build"
    assert_stderr_not_contains "swift test" "a step in a CI_ONLY_JOBS job reported"
}

case_ci_stale_local_only() {
    local root
    root=$(make_fixture)
    replace_in "${root}" justfile "^check: verify-hooks fmt lint build" "check: verify-hooks lint build"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_JUST_CI_STALE
    assert_stderr_contains "LOCAL_ONLY names \`fmt\`, which \`just check\` no longer runs"
}

case_ci_stale_ci_only() {
    local root
    root=$(make_fixture)
    sed '/^          just uitest$/d; /^      - run: scripts\/simulator-destination.sh$/d' \
        "${root}/.github/workflows/ci.yml" >"${CASE_DIR}/ci.yml"
    mv "${CASE_DIR}/ci.yml" "${root}/.github/workflows/ci.yml"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_JUST_CI_STALE
    assert_stderr_contains "CI_ONLY names \`uitest\`, which no .github/workflows/ci.yml step runs any more"
}

# The shape of ios-template's app job: a step that calls only the script the uitest
# recipe calls still counts as running uitest.
case_ci_only_reached_through_its_script() {
    local root
    root=$(make_fixture)
    sed '/^          just uitest$/d' "${root}/.github/workflows/ci.yml" >"${CASE_DIR}/ci.yml"
    mv "${CASE_DIR}/ci.yml" "${root}/.github/workflows/ci.yml"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "just-check-matches-ci: "
}

case_ci_no_check_recipe() {
    local root
    root=$(make_fixture)
    replace_in "${root}" justfile "^check: verify-hooks fmt lint build" "all: verify-hooks fmt lint build"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_JUST_CI_NO_CHECK
}

case_ci_missing_workflow() {
    local root
    root=$(make_fixture)
    mv "${root}/.github/workflows/ci.yml" "${CASE_DIR}/ci.yml"
    capture "${BASH}" "${CHECKS}/just-check-matches-ci.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_INPUT_MISSING
}

# --- labels-declared.sh -------------------------------------------------------

case_labels_pass() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "labels-declared: every applied label is declared once"
}

case_labels_label_pr_real_mapping() {
    local root
    root=$(make_fixture)
    mkdir -p "${root}/scripts"
    cp "${REPO_ROOT}/scripts/label-pr.sh" "${root}/scripts/label-pr.sh"
    cp "${REPO_ROOT}/.github/labels.yml" "${root}/.github/labels.yml"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "labels-declared: every applied label is declared once"
}

case_labels_label_pr_undeclared() {
    local root
    root=$(make_fixture)
    mkdir -p "${root}/scripts"
    cp "${REPO_ROOT}/scripts/label-pr.sh" "${root}/scripts/label-pr.sh"
    cp "${REPO_ROOT}/.github/labels.yml" "${root}/.github/labels.yml"
    replace_in "${root}" scripts/label-pr.sh "feat) label=enhancement ;;" "feat) label=feature ;;"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    assert_stderr_contains "scripts/label-pr.sh:$(grep -n 'label=feature' "${root}/scripts/label-pr.sh" | cut -d: -f1): applies \`feature\`"
    assert_stderr_not_contains "\`bug\`" "a declared mapping reported"
}

case_labels_duplicate() {
    local root
    root=$(make_fixture)
    write_labels "${root}" bug enhancement "priority: P1" dependencies ci bug
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_DUPLICATE
    assert_stderr_contains ".github/labels.yml:17: \`bug\` is already declared at line 2"
    assert_stderr_not_contains "ERR_CHECK_LABEL_UNDECLARED" "a declared label reported as undeclared"
}

case_labels_duplicate_differs_in_case() {
    local root
    root=$(make_fixture)
    write_labels "${root}" bug enhancement "priority: P1" dependencies ci "Priority: p1"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_DUPLICATE
    assert_stderr_contains "\`Priority: p1\` is already declared at line 8"
}

case_labels_issue_form_flow() {
    local root
    root=$(make_fixture)
    printf 'name: Bug\nlabels: [bug, "needs triage"]\n' >"${root}/.github/ISSUE_TEMPLATE/bug.yml"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    assert_stderr_contains ".github/ISSUE_TEMPLATE/bug.yml:2: applies \`needs triage\`"
    assert_stderr_not_contains "\`bug\`" "a declared label reported"
}

case_labels_issue_form_block_list() {
    local root
    root=$(make_fixture)
    printf 'name: Task\nlabels:\n  - enhancement\n  - "question"\nbody: []\n' >"${root}/.github/ISSUE_TEMPLATE/task.yml"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    assert_stderr_contains ".github/ISSUE_TEMPLATE/task.yml:4: applies \`question\`"
}

case_labels_issue_form_comma_string() {
    local root
    root=$(make_fixture)
    printf 'name: Task\nlabels: enhancement, wontfix\n' >"${root}/.github/ISSUE_TEMPLATE/task.yml"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    assert_stderr_contains ".github/ISSUE_TEMPLATE/task.yml:2: applies \`wontfix\`"
}

case_labels_workflow_add_label() {
    local root
    root=$(make_fixture)
    echo '          gh issue edit 2 --add-label "stale,ci" --label=triaged' >>"${root}/.github/workflows/label.yml"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    local last
    last=$(wc -l <"${root}/.github/workflows/label.yml" | tr -d ' ')
    assert_stderr_contains ".github/workflows/label.yml:${last}: applies \`stale\`"
    assert_stderr_contains ".github/workflows/label.yml:${last}: applies \`triaged\`"
    assert_stderr_not_contains "\`ci\`" "a declared label in a comma list reported"
    assert_stderr_not_contains "\`\$label\`" "a variable read as a label"
}

case_labels_workflow_assignment() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/label.yml 'label="ci"' "LABEL='infra'"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    assert_stderr_contains ".github/workflows/label.yml:$(grep -n "LABEL='infra'" "${root}/.github/workflows/label.yml" | cut -d: -f1): applies \`infra\`"
}

case_labels_dependabot_explicit() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/dependabot.yml "^    - ci$" "    - github-actions"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    assert_stderr_contains ".github/dependabot.yml:$(grep -n -- '- github-actions' "${root}/.github/dependabot.yml" | cut -d: -f1): applies \`github-actions\`"
    assert_stderr_not_contains "Dependabot default" "an entry with a labels: key given the default"
}

case_labels_dependabot_default() {
    local root
    root=$(make_fixture)
    write_labels "${root}" bug enhancement "priority: P1" ci
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    assert_stderr_contains ".github/dependabot.yml:3: applies \`dependencies\` (Dependabot default, no labels: key)"
    assert_stderr_contains ".github/renovate.json:4: applies \`dependencies\`"
    assert_stderr_not_contains "\`swift\`" "the ecosystem label Dependabot creates itself required"
}

case_labels_dependabot_empty_list() {
    local root
    root=$(make_fixture)
    write_labels "${root}" bug enhancement "priority: P1" ci
    printf 'version: 2\nupdates:\n  - package-ecosystem: "swift"\n    labels: []\n' >"${root}/.github/dependabot.yml"
    mv "${root}/.github/renovate.json" "${CASE_DIR}/renovate.json"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 0
}

case_labels_renovate() {
    local root
    root=$(make_fixture)
    printf '{\n  "packageRules": [{ "addLabels": ["tooling"] }]\n}\n' >"${root}/renovate.json"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_LABEL_UNDECLARED
    assert_stderr_contains "renovate.json:2: applies \`tooling\`"
}

case_labels_missing_file() {
    local root
    root=$(make_fixture)
    mv "${root}/.github/labels.yml" "${CASE_DIR}/labels.yml"
    capture "${BASH}" "${CHECKS}/labels-declared.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_INPUT_MISSING
}

# --- workflow-hygiene.sh ------------------------------------------------------

# line_of ROOT REL TEXT — the line number of the first line of ROOT/REL containing TEXT.
line_of() {
    grep -nF -- "$3" "$1/$2" | head -n 1 | cut -d: -f1
}

case_hygiene_pass() {
    local root
    root=$(make_fixture)
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "workflow-hygiene: "
}

case_hygiene_top_level_write() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/label.yml "^permissions: {}$" "permissions:\\
  pull-requests: write"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_PERMISSION_SCOPE
    assert_stderr_contains ".github/workflows/label.yml:4: top-level \`pull-requests: write\` is granted to every job"
    assert_stderr_not_contains "release.yml" "a job-level write reported"
}

case_hygiene_top_level_shorthand() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "^permissions: {}$" "permissions: read-all"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_PERMISSION_SCOPE
    assert_stderr_contains ".github/workflows/release.yml:4: top-level \`permissions: read-all\` grants every scope to every job"
}

case_hygiene_top_level_flow_write() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "^permissions: {}$" "permissions: { contents: write }"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_PERMISSION_SCOPE
    assert_stderr_contains ".github/workflows/release.yml:4: top-level \`permissions: { contents: write }\` grants a write scope"
}

case_hygiene_job_shorthand() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "^    permissions:$" "    permissions: write-all"
    replace_in "${root}" .github/workflows/release.yml "^      contents: write$" "    env: {}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_PERMISSION_SCOPE
    assert_stderr_contains "job \`build\` uses \`permissions: write-all\`, which grants every scope"
}

case_hygiene_pr_without_concurrency() {
    local root
    root=$(make_fixture)
    sed '/^concurrency:/,/^  cancel-in-progress:/d' "${root}/.github/workflows/ci.yml" >"${CASE_DIR}/ci.yml"
    mv "${CASE_DIR}/ci.yml" "${root}/.github/workflows/ci.yml"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/ci.yml: runs on pull requests but has no top-level \`concurrency:\`"
    assert_stderr_not_contains "release.yml" "a push-only workflow required to declare concurrency"
}

case_hygiene_flow_trigger_without_concurrency() {
    local root
    root=$(make_fixture)
    cat >"${root}/.github/workflows/docs.yml" <<'EOF'
name: Docs
on: [push, "pull_request"]
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: set -euo pipefail; echo docs
EOF
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/docs.yml: runs on pull requests"
    assert_stderr_not_contains "ERR_CHECK_WORKFLOW_SHELL" "a one-line run: starting with set -euo pipefail reported"
}

case_hygiene_constant_group() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/label.yml "^  group: .*$" "  group: label"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/label.yml:5: group \`label\` is the same for every run"
}

case_hygiene_no_group() {
    local root
    root=$(make_fixture)
    sed '/^  group: /d' "${root}/.github/workflows/label.yml" >"${CASE_DIR}/label.yml"
    mv "${CASE_DIR}/label.yml" "${root}/.github/workflows/label.yml"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/label.yml:4: \`concurrency:\` has no \`group:\`"
}

case_hygiene_push_cancels() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "cancel-in-progress: false" "cancel-in-progress: true"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/release.yml:7: \`cancel-in-progress: true\` on a push-triggered workflow"
    assert_stderr_not_contains "label.yml" "a pull-request-only workflow's cancel reported"
}

case_hygiene_push_cancel_expression() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "cancel-in-progress: false" "cancel-in-progress: \${{ github.ref != 'refs/heads/main' }}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/release.yml:7: \`cancel-in-progress: \${{ github.ref != 'refs/heads/main' }}\` on a push-triggered workflow is not limited to pull request runs"
}

case_hygiene_shared_group() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/title.yml "^  group: .*$" "  group: label-\${{ github.ref }}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/title.yml:$(line_of "${root}" .github/workflows/title.yml "  group:"): group \`label-\${{ github.ref }}\` is also used by .github/workflows/label.yml:5"
}

case_hygiene_run_without_shell() {
    local root
    root=$(make_fixture)
    sed '/^defaults:/,/^    shell: bash/d' "${root}/.github/workflows/ci.yml" >"${CASE_DIR}/ci.yml"
    mv "${CASE_DIR}/ci.yml" "${root}/.github/workflows/ci.yml"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_SHELL
    assert_stderr_contains ".github/workflows/ci.yml:$(line_of "${root}" .github/workflows/ci.yml "run: scripts/lint.sh"): a \`run:\` step in job \`lint\` names no shell"
    assert_stderr_contains "in job \`bootstrap-smoke\` names no shell"
    assert_stderr_not_contains "in job \`app\`" "a job with defaults.run.shell: bash reported"
    assert_stderr_contains "block-style \`defaults:\`"
    assert_stderr_not_contains "{ run:" "flow-style advice this check cannot read"
}

case_hygiene_set_line_not_first() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/label.yml "^          .*The label this PR.*$" '          echo "labelling"'
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_SHELL
    assert_stderr_contains ".github/workflows/label.yml:$(line_of "${root}" .github/workflows/label.yml "- run: |"): a \`run:\` step in job \`label\` names no shell"
}

case_hygiene_shell_not_fail_closed() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/ci.yml "^        shell: bash$" "        shell: sh"
    replace_in "${root}" .github/workflows/release.yml "^        shell: bash$" "        shell: bash -e {0}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_SHELL
    assert_stderr_contains ".github/workflows/ci.yml:$(line_of "${root}" .github/workflows/ci.yml "shell: sh"): \`shell: sh\` does not stop"
    assert_stderr_contains ".github/workflows/release.yml:$(line_of "${root}" .github/workflows/release.yml "shell: bash -e"): \`shell: bash -e {0}\` does not stop"
}

case_hygiene_custom_fail_closed_shell_passes() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "^        shell: bash$" "        shell: bash --noprofile --norc -euo pipefail {0}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 0
}

case_hygiene_composite_shell() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/actions/setup/action.yml "^    - shell: bash$" "    - shell: sh"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_SHELL
    assert_stderr_contains ".github/actions/setup/action.yml:$(line_of "${root}" .github/actions/setup/action.yml "shell: sh"): \`shell: sh\` does not stop"
}

case_hygiene_reports_every_rule() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "^permissions: {}$" "permissions: write-all"
    replace_in "${root}" .github/workflows/release.yml "cancel-in-progress: false" "cancel-in-progress: true"
    replace_in "${root}" .github/workflows/release.yml "^        shell: bash$" "        shell: sh"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    first_stderr_is ERR_CHECK_WORKFLOW_PERMISSION_SCOPE
    assert_stderr_contains "ERR_CHECK_WORKFLOW_CONCURRENCY: "
    assert_stderr_contains "ERR_CHECK_WORKFLOW_SHELL: "
}

# write_mixed_workflow ROOT GROUP [CANCEL] — .github/workflows/mixed.yml, triggered on
# push and pull_request, with the given concurrency group and cancel-in-progress.
write_mixed_workflow() {
    cat >"$1/.github/workflows/mixed.yml" <<EOF
name: Mixed
on:
  push:
  pull_request:
permissions: {}
concurrency:
  group: $2
  cancel-in-progress: ${3:-false}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: set -o pipefail; make | tee build.log
EOF
}

case_hygiene_pr_key_on_mixed_triggers() {
    local root
    root=$(make_fixture)
    write_mixed_workflow "${root}" "\${{ github.workflow }}-\${{ github.head_ref }}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/mixed.yml:7: group \`\${{ github.workflow }}-\${{ github.head_ref }}\` is keyed by the pull request"
    assert_stderr_not_contains "title.yml" "a pull-request-only workflow's PR key reported"
}

case_hygiene_pr_key_with_run_id_fallback_passes() {
    local root
    root=$(make_fixture)
    write_mixed_workflow "${root}" "\${{ github.workflow }}-\${{ github.head_ref || github.run_id }}"
    replace_in "${root}" .github/workflows/title.yml "^  group: .*$" "  group: \${{ github.workflow }}-\${{ github.event.pull_request.number }}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 0
}

case_hygiene_ref_type_is_not_ref() {
    local root
    root=$(make_fixture)
    write_mixed_workflow "${root}" "\${{ github.workflow }}-\${{ github.ref_type }}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/mixed.yml:7: group \`\${{ github.workflow }}-\${{ github.ref_type }}\` is the same for every run"
}

case_hygiene_flow_mapping_trigger() {
    local root
    root=$(make_fixture)
    cat >"${root}/.github/workflows/docs.yml" <<'EOF'
name: Docs
on: {push: {branches: [main]}, pull_request: {types: [opened, edited]}}
permissions: {}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
EOF
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/docs.yml: runs on pull requests"
}

case_hygiene_push_cancel_on_push_event() {
    local root
    root=$(make_fixture)
    write_mixed_workflow "${root}" "\${{ github.workflow }}-\${{ github.ref }}" "\${{ github.event_name == 'push' }}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_CONCURRENCY
    assert_stderr_contains ".github/workflows/mixed.yml:8: \`cancel-in-progress: \${{ github.event_name == 'push' }}\` on a push-triggered workflow is not limited to pull request runs"
}

case_hygiene_push_cancel_not_push_passes() {
    local root
    root=$(make_fixture)
    write_mixed_workflow "${root}" "\${{ github.workflow }}-\${{ github.ref }}" "\${{ github.event_name != 'push' }}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 0
}

case_hygiene_set_errexit_off_fails() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/label.yml "^          set -euo pipefail$" "          set +e -o pipefail"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 1
    assert_contract ERR_CHECK_WORKFLOW_SHELL
    assert_stderr_contains "a \`run:\` step in job \`label\` names no shell"
}

case_hygiene_long_option_shell_passes() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "^        shell: bash$" "        shell: /usr/bin/bash -o errexit -o pipefail {0}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 0
}

case_hygiene_other_interpreters_pass() {
    local root
    root=$(make_fixture)
    replace_in "${root}" .github/workflows/release.yml "^        shell: bash$" "        shell: pwsh"
    replace_in "${root}" .github/actions/setup/action.yml "^    - shell: bash$" "    - shell: python {0}"
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    assert_exit 0
}

case_hygiene_unreadable_file() {
    local root
    root=$(make_fixture)
    chmod 000 "${root}/.github/workflows/label.yml"
    if [ -r "${root}/.github/workflows/label.yml" ]; then
        echo "  skip: running as a user who can read a mode-000 file" >&2
        return 0
    fi
    capture "${BASH}" "${CHECKS}/workflow-hygiene.sh" --root "${root}"
    chmod 644 "${root}/.github/workflows/label.yml"
    assert_exit 1
    assert_contract ERR_CHECK_READ_FAILED
    assert_stderr_contains "could not read .github/workflows/label.yml"
}

run_case "run-all: passes on a conforming tree" case_run_all_passes
run_case "run-all: two broken checks are both reported" case_run_all_reports_every_failure
run_case "run-all: rejects an unknown argument" case_run_all_rejects_unknown_argument
run_case "lib: rejects a --root that does not exist" case_check_rejects_missing_root
run_case "recipes: passes on a conforming tree" case_recipes_pass
run_case "recipes: a bogus inline recipe fails" case_recipes_bogus_inline
run_case "recipes: a bogus second recipe in a chain fails" case_recipes_bogus_second_in_chain
run_case "recipes: a bogus recipe in a fenced block fails" case_recipes_bogus_in_fenced_block
run_case "recipes: a permission rule for a bogus recipe fails" case_recipes_bogus_permission_rule
run_case "recipes: passes with no .claude/settings.json" case_recipes_pass_without_settings
run_case "recipes: just missing from PATH fails" case_recipes_just_missing
run_case "recipes: a justfile just cannot read fails" case_recipes_justfile_unreadable
run_case "workflows: passes on a conforming tree" case_workflows_pass
run_case "workflows: passes with no .github/actions/" case_workflows_pass_without_actions_dir
run_case "workflows: no top-level permissions fails" case_workflows_missing_permissions
run_case "workflows: a tag pin in a workflow fails" case_workflows_tag_pin_in_workflow
run_case "workflows: a tag pin in a composite action fails" case_workflows_tag_pin_in_composite_action
run_case "workflows: a SHA without a version comment fails" case_workflows_sha_without_version_comment
run_case "workflows: a short SHA fails" case_workflows_short_sha
run_case "frontmatter: passes on a conforming tree" case_frontmatter_pass
run_case "frontmatter: a third key fails" case_frontmatter_third_key
run_case "frontmatter: a name differing from the directory fails" case_frontmatter_name_mismatch
run_case "frontmatter: an empty description fails" case_frontmatter_empty_description
run_case "frontmatter: no frontmatter block fails" case_frontmatter_missing_block
run_case "frontmatter: an unclosed block fails" case_frontmatter_unclosed_block
run_case "frontmatter: a skill directory without SKILL.md fails" case_frontmatter_missing_skill_file
run_case "descriptions: passes, including quoted and block-scalar near misses" case_descriptions_pass
run_case "descriptions: a description over 1024 characters fails" case_descriptions_too_long
run_case "descriptions: a description of exactly 1024 characters passes" case_descriptions_at_limit_passes
run_case "descriptions: a non-ASCII description fails" case_descriptions_non_ascii
run_case "descriptions: an unquoted value containing a colon-space fails" case_descriptions_unquoted_colon
run_case "descriptions: a plain continuation line containing a colon-space fails" case_descriptions_plain_continuation_colon
run_case "descriptions: an unquoted value containing space-hash fails" case_descriptions_unquoted_comment
run_case "descriptions: a value starting with a YAML indicator fails" case_descriptions_indicator_start
run_case "descriptions: a nested SKILL.md fails" case_descriptions_nested_skill_file
run_case "index: passes, and ignores the ### Rules table" case_index_pass_ignores_rules_table
run_case "index: a skill directory without a row fails" case_index_directory_without_row
run_case "index: a row without a directory fails" case_index_row_without_directory
run_case "index: no Skills table fails" case_index_no_skills_table
run_case "ban: passes, ignoring a later rule's group and quoted modules in comments" case_ban_pass
run_case "ban: passes on a one-line literal with a repeated module" case_ban_pass_single_line_literal
run_case "ban: a module only in the lint rule fails" case_ban_lint_has_extra
run_case "ban: a module only in forbiddenModules fails" case_ban_tests_have_extra
run_case "ban: an unreadable lint list fails" case_ban_lint_list_unparsed
run_case "ban: an unreadable forbiddenModules fails" case_ban_tests_list_unparsed
run_case "ban: a missing ArchitectureBoundaryTests.swift fails" case_ban_missing_tests_file
run_case "ci: passes, with scripts, a block step, and the exceptions" case_ci_pass
run_case "ci: a just check gate no CI step runs fails" case_ci_gate_missing_from_ci
run_case "ci: a CI recipe just check does not run fails" case_ci_recipe_missing_from_check
run_case "ci: a CI script no recipe calls fails" case_ci_script_no_recipe_calls
run_case "ci: a CI step running no recipe or script fails" case_ci_step_runs_nothing_shared
run_case "ci: a stale LOCAL_ONLY exception fails" case_ci_stale_local_only
run_case "ci: a stale CI_ONLY exception fails" case_ci_stale_ci_only
run_case "ci: a CI_ONLY recipe reached only through its script is not stale" case_ci_only_reached_through_its_script
run_case "ci: no check recipe fails" case_ci_no_check_recipe
run_case "ci: a missing ci.yml fails" case_ci_missing_workflow
run_case "labels: passes on a conforming tree" case_labels_pass
run_case "labels: the real label-pr.sh mapping passes" case_labels_label_pr_real_mapping
run_case "labels: a label-pr.sh mapping to an undeclared label fails" case_labels_label_pr_undeclared
run_case "labels: a label declared twice fails" case_labels_duplicate
run_case "labels: two names differing only in case fail" case_labels_duplicate_differs_in_case
run_case "labels: an undeclared label in an issue form flow list fails" case_labels_issue_form_flow
run_case "labels: an undeclared label in an issue form block list fails" case_labels_issue_form_block_list
run_case "labels: an undeclared label in an issue form comma string fails" case_labels_issue_form_comma_string
run_case "labels: an undeclared --add-label/--label value fails" case_labels_workflow_add_label
run_case "labels: an undeclared label assigned in a workflow fails" case_labels_workflow_assignment
run_case "labels: an undeclared Dependabot label fails" case_labels_dependabot_explicit
run_case "labels: Dependabot's implied dependencies label must be declared" case_labels_dependabot_default
run_case "labels: an empty Dependabot labels list implies nothing" case_labels_dependabot_empty_list
run_case "labels: an undeclared Renovate addLabels value fails" case_labels_renovate
run_case "labels: a missing labels.yml fails" case_labels_missing_file
run_case "hygiene: passes on a conforming tree" case_hygiene_pass
run_case "hygiene: a top-level write scope fails" case_hygiene_top_level_write
run_case "hygiene: a top-level read-all fails" case_hygiene_top_level_shorthand
run_case "hygiene: a top-level flow mapping with a write fails" case_hygiene_top_level_flow_write
run_case "hygiene: a job-level write-all fails" case_hygiene_job_shorthand
run_case "hygiene: a pull request workflow without concurrency fails" case_hygiene_pr_without_concurrency
run_case "hygiene: a flow-list pull_request trigger without concurrency fails" case_hygiene_flow_trigger_without_concurrency
run_case "hygiene: a constant concurrency group fails" case_hygiene_constant_group
run_case "hygiene: a concurrency block without a group fails" case_hygiene_no_group
run_case "hygiene: cancel-in-progress true on a push workflow fails" case_hygiene_push_cancels
run_case "hygiene: a push workflow's cancel expression not on event_name fails" case_hygiene_push_cancel_expression
run_case "hygiene: two workflows sharing a group fail" case_hygiene_shared_group
run_case "hygiene: a run step with no shell fails" case_hygiene_run_without_shell
run_case "hygiene: a set -euo pipefail after the first command does not count" case_hygiene_set_line_not_first
run_case "hygiene: a shell that is not fail-closed fails" case_hygiene_shell_not_fail_closed
run_case "hygiene: a custom bash template with -e and pipefail passes" case_hygiene_custom_fail_closed_shell_passes
run_case "hygiene: a composite step's non-bash shell fails" case_hygiene_composite_shell
run_case "hygiene: all three rules report in one run" case_hygiene_reports_every_rule
run_case "hygiene: a pull request key on a workflow with other triggers fails" case_hygiene_pr_key_on_mixed_triggers
run_case "hygiene: a pull request key with a run_id fallback passes" case_hygiene_pr_key_with_run_id_fallback_passes
run_case "hygiene: github.ref_type is not a per-run key" case_hygiene_ref_type_is_not_ref
run_case "hygiene: a one-line flow mapping on: is read" case_hygiene_flow_mapping_trigger
run_case "hygiene: cancelling on the push event fails" case_hygiene_push_cancel_on_push_event
run_case "hygiene: cancelling unless the event is push passes" case_hygiene_push_cancel_not_push_passes
run_case "hygiene: a set that turns errexit off fails" case_hygiene_set_errexit_off_fails
run_case "hygiene: a bash template with -o errexit -o pipefail passes" case_hygiene_long_option_shell_passes
run_case "hygiene: pwsh and python shells are outside the rule" case_hygiene_other_interpreters_pass
run_case "hygiene: an unreadable workflow fails under the contract" case_hygiene_unreadable_file
finish
