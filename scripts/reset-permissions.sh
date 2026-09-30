#!/usr/bin/env bash
# Make the booted iOS Simulator forget every privacy decision recorded for this app, so
# the next request prompts again. What `just reset-permissions` runs.
#
#   scripts/reset-permissions.sh [--root DIR]
#
# `simctl privacy booted reset all <bundle id>` drops the app's grants on the booted
# simulator, so the identifier is never a free-form argument: it is read from
# project.yml (scripts/bundle-id.sh), the manifest that is the source of truth for the
# app target, which is also what keeps this working after scripts/bootstrap.sh renames
# the app. `--root DIR` follows the manifest under DIR — it exists for the tests, and
# `just reset-permissions` never passes it. Only a booted simulator is touched; a
# physical device's grants change only in its Settings app.
#
# `xcrun` comes with Xcode and is not a mise tool, so — like `git` — it is taken from
# PATH rather than routed through `mise exec --`.
#
# Git work tree: not required — the manifest is read under --root, which defaults to
# the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_RESETPERM_USAGE             unknown argument, or a --root DIR that does not exist
#   ERR_RESETPERM_BUNDLE_ID         scripts/bundle-id.sh could not read the identifier
#   ERR_RESETPERM_NO_BOOTED_DEVICE  `xcrun simctl list devices booted` lists no booted device
#   ERR_RESETPERM_SIMCTL_FAILED     `xcrun simctl privacy booted reset all` exited non-zero
set -euo pipefail

USAGE="usage: scripts/reset-permissions.sh [--root DIR]"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 1
}

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] && [ -d "$2" ] || fail ERR_RESETPERM_USAGE "--root needs an existing directory" \
                "--root followed by an existing directory" "'${2:-}'" "${USAGE}"
            ROOT=$(cd "$2" && pwd)
            shift
            ;;
        *) fail ERR_RESETPERM_USAGE "unknown argument '$1'" "no arguments, or --root DIR" "argument '$1'" "${USAGE}" ;;
    esac
    shift
done
[ -n "${ROOT}" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

# bundle-id.sh prints its own ERR_BUNDLEID_* block; it is captured so this script's
# code stays the first stderr line, and its first line becomes the Actual: line.
if ! BUNDLE_ID=$("${SCRIPTS}/bundle-id.sh" --root "${ROOT}" 2>&1); then
    fail ERR_RESETPERM_BUNDLE_ID "could not read the app's bundle identifier from ${ROOT}/project.yml" \
        "scripts/bundle-id.sh to print the app target's PRODUCT_BUNDLE_IDENTIFIER" \
        "$(head -n 1 <<<"${BUNDLE_ID}")" \
        "run \`scripts/bundle-id.sh\` and fix what it reports, then rerun \`just reset-permissions\`"
fi

BOOTED=$(xcrun simctl list devices booted 2>&1) || true
if ! grep -q '(Booted)' <<<"${BOOTED}"; then
    fail ERR_RESETPERM_NO_BOOTED_DEVICE "no iOS Simulator is booted" \
        "a device marked (Booted) in \`xcrun simctl list devices booted\`" \
        "none listed" \
        "run \`just run\` (it boots one), then rerun \`just reset-permissions\`"
fi

echo "==> Resetting every privacy permission for ${BUNDLE_ID} on the booted simulator"
if ! RESET_OUTPUT=$(xcrun simctl privacy booted reset all "${BUNDLE_ID}" 2>&1); then
    fail ERR_RESETPERM_SIMCTL_FAILED "\`xcrun simctl privacy booted reset all ${BUNDLE_ID}\` exited non-zero" \
        "simctl to drop every recorded privacy decision for ${BUNDLE_ID}" \
        "${RESET_OUTPUT}" \
        "run \`xcrun simctl privacy booted reset all ${BUNDLE_ID}\` and read its error, then retry"
fi

echo "reset-permissions: ${BUNDLE_ID} will be asked for permission again on its next request"
