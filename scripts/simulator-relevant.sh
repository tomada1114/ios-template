#!/usr/bin/env bash
# Prints `true` or `false`: whether a change set touches a path a macOS check exercises.
# This file holds the only copy of the path lists.
#
#   scripts/simulator-relevant.sh --check NAME [--base REF]   (`just check`, per check)
#   scripts/simulator-relevant.sh --base REF --head REF       (CI: git diff BASE...HEAD)
#   scripts/simulator-relevant.sh [--base REF]                (local, the CI list)
#
# --check NAME answers for one simulator check `just check` runs before a pull request:
#   uitest    (uitest-build, uitest-run) what the launch UI test renders and drives:
#             App/, MyAppUI, LaunchUITests/, Config/, project.yml, .xcode-version, a
#             Package.resolved, and the script that picks its simulator.
#   test-ios  what the package tests exercise on iOS and not on the host: MyAppPlatform,
#             its tests, the test-support fakes, Package.swift, a Package.resolved,
#             .xcode-version, and the script that picks its simulator. MyAppCore holds no `#if os(iOS)` code, so
#             `just test` on the host already runs everything a Core change can break.
# Both lists also hold what runs either check: the justfile, mise.toml (the pinned
# tools), and scripts/run-throttled.sh.
# A change that matches neither list runs no simulator check before the pull request;
# `just check-release` runs all of them, with smoke, build-device, and analyze, on the
# commit a release is cut from.
#
# Without --check the answer is for CI's `changes` job, which decides whether the macOS
# jobs (`test`, `bootstrap-smoke`) have work (#54): the wider RELEVANT list below.
#
# Locally, the change set is everything since `git merge-base HEAD <base>` (base
# defaults to origin/main, then main): committed, staged, and unstaged changes, plus
# untracked files that are not ignored.
#
# Fail-safe: running too much is safe, skipping is not. So it prints `true` when
# CHECK_ALL=1 and, with a one-line notice on stderr, when any git command fails (outside
# a git checkout included). An empty change set prints `true` without --check (CI) and
# `false` with it: a tree that equals the base has no change for a simulator check to
# judge — a fresh branch's baseline `just check` stays on the host — and
# `just check-release` is what runs them on main. Exit 0 in every case
# but bad arguments. With --head it lists the changed files on stderr; a `false`
# adds one stderr line saying how to run the check anyway.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_RELEVANT_USAGE  unknown argument, a flag without its value, --head without
#                       --base, --check with --head, or an unknown --check NAME
set -euo pipefail

# The paths CI's macOS jobs exercise, as one extended regex.
RELEVANT='^(App/|Packages/|LaunchUITests/|Config/|scripts/|\.github/actions/|project\.yml$|justfile$|mise\.toml$|\.xcode-version$|\.swiftlint\.yml$|\.github/workflows/ci\.yml$)'
# The per-check lists `just check` asks for with --check.
RELEVANT_UITEST='^(App/|justfile$|mise\.toml$|scripts/run-throttled\.sh$|(.*/)?Package\.resolved$|LaunchUITests/|Packages/MyAppKit/Sources/MyAppUI/|Config/|project\.yml$|\.xcode-version$|scripts/simulator-destination\.sh$)'
RELEVANT_TEST_IOS='^(justfile$|mise\.toml$|scripts/run-throttled\.sh$|(.*/)?Package\.resolved$|Packages/MyAppKit/Sources/MyAppPlatform/|Packages/MyAppKit/Tests/MyAppPlatformTests/|Packages/MyAppKit/Tests/MyAppTestSupport/|Packages/MyAppKit/Package\.swift$|\.xcode-version$|scripts/simulator-destination\.sh$)'

usage_fail() {
    {
        echo "ERR_RELEVANT_USAGE: $1"
        echo "Expected: \`scripts/simulator-relevant.sh [--check uitest|test-ios] [--base REF [--head REF]]\`"
        echo "Actual: $2"
        echo "Next: fix the call (the usage is in the header of scripts/simulator-relevant.sh)"
    } >&2
    exit 1
}

BASE=""
HEAD=""
CHECK=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --base | --head | --check)
            [ "$#" -ge 2 ] && [ -n "$2" ] || usage_fail "$1 needs a value" "arguments end at $1"
            case "$1" in
                --base) BASE="$2" ;;
                --head) HEAD="$2" ;;
                *) CHECK="$2" ;;
            esac
            shift 2
            ;;
        *) usage_fail "unknown argument: $1" "arguments: $*" ;;
    esac
done
[ -z "${HEAD}" ] || [ -n "${BASE}" ] || usage_fail "--head needs --base" "--head ${HEAD} without --base"
[ -z "${HEAD}" ] || [ -z "${CHECK}" ] || usage_fail "--check answers for the local change set, not --head" "--check ${CHECK} with --head ${HEAD}"
case "${CHECK}" in
    "") WHAT="the macOS checks" ;;
    uitest) RELEVANT="${RELEVANT_UITEST}" WHAT="uitest-build and uitest-run" ;;
    test-ios) RELEVANT="${RELEVANT_TEST_IOS}" WHAT="test-ios" ;;
    *) usage_fail "unknown --check name: ${CHECK}" "--check ${CHECK}" ;;
esac

if [ "${CHECK_ALL:-}" = 1 ]; then
    echo true
    exit 0
fi

git_failed() {
    echo "simulator-relevant: $1, so ${WHAT} run" >&2
    echo true
    exit 0
}

if [ -n "${HEAD}" ]; then
    FILES=$(git diff --name-only "${BASE}...${HEAD}" 2>/dev/null) ||
        git_failed "\`git diff ${BASE}...${HEAD}\` failed"
    printf 'Changed files:\n%s\n' "${FILES}" >&2
else
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || git_failed "this is not a git checkout"
    if [ -z "${BASE}" ]; then
        if git rev-parse --verify --quiet "origin/main^{commit}" >/dev/null 2>&1; then
            BASE="origin/main"
        else
            BASE="main"
        fi
    fi
    MERGE_BASE=$(git merge-base HEAD "${BASE}" 2>/dev/null) ||
        git_failed "no merge base between HEAD and ${BASE}"
    TRACKED=$(git diff --name-only "${MERGE_BASE}" 2>/dev/null) ||
        git_failed "\`git diff ${MERGE_BASE}\` failed"
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null) ||
        git_failed "\`git ls-files --others\` failed"
    FILES=$(printf '%s\n%s\n' "${TRACKED}" "${UNTRACKED}" | sed '/^$/d')
fi

if [ -z "${FILES}" ] && [ -n "${CHECK}" ]; then
    echo "simulator-relevant: nothing changed since ${BASE}, so ${WHAT} are skipped; CHECK_ALL=1 runs them anyway" >&2
    echo false
elif [ -n "${FILES}" ] && ! grep -qE -- "${RELEVANT}" <<<"${FILES}"; then
    echo "simulator-relevant: nothing ${WHAT} exercise changed since ${BASE}, so they are skipped; CHECK_ALL=1 runs them anyway" >&2
    echo false
else
    echo true
fi
