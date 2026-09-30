#!/usr/bin/env bash
# Format the one Swift file a Claude Code Edit/Write/MultiEdit just touched.
# Registered as .claude/settings.json's PostToolUse hook:
#
#   <hook JSON on stdin> | scripts/format-edited-file.sh [--root DIR]
#
# Reads tool_input.file_path out of the hook's JSON payload and runs
# `swiftformat <that file>` from the root, so .swiftformat applies. Nothing else in
# the tree is touched. It exits 0 without running anything when the payload names
# no file_path, the path does not end in .swift, the file no longer exists, or the
# file lies outside the root. The JSON is read with sed, not jq (not a pinned tool):
# a file_path containing an escaped quote is not recognised and is skipped.
#
# swiftformat is called by bare name; the caller provides PATH (`mise exec --`).
#
# Exit codes: 0 formatted or nothing to do; 2 on failure, because Claude Code feeds
# a PostToolUse hook's stderr back to the agent only on exit 2 — the failure is
# reported to whoever made the edit instead of being silenced.
#
# Git work tree: not required — paths are compared against --root, which defaults
# to the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 2):
#   ERR_FORMAT_USAGE   unknown argument, or a --root DIR that does not exist
#   ERR_FORMAT_FAILED  swiftformat exited non-zero on the edited file
set -euo pipefail

USAGE="usage: scripts/format-edited-file.sh [--root DIR] < hook-payload.json"

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    echo "Actual: $4" >&2
    echo "Next: $5" >&2
    exit 2
}

ROOT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || fail ERR_FORMAT_USAGE "--root needs a directory" "${USAGE}" "--root with no value" "pass --root DIR"
            ROOT="$2"
            shift 2
            ;;
        *)
            fail ERR_FORMAT_USAGE "unknown argument" "${USAGE}" "$1" "run scripts/format-edited-file.sh < payload.json"
            ;;
    esac
done
if [ -z "${ROOT}" ]; then
    ROOT="$(dirname "$0")/.."
fi
[ -d "${ROOT}" ] || fail ERR_FORMAT_USAGE "--root is not a directory" "an existing directory" "${ROOT}" "pass an existing --root DIR"
ROOT=$(cd "${ROOT}" && pwd -P)

payload=$(cat)
file=$(printf '%s\n' "${payload}" | tr -d '\n' |
    sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"\\]*\(\\\/[^"\\]*\)*\)".*/\1/p' |
    sed 's#\\/#/#g')

case "${file}" in
    *.swift) ;;
    *) exit 0 ;;
esac
[ -f "${file}" ] || exit 0

# Resolve symlinks and relative segments before the inside-the-root comparison.
dir=$(cd "$(dirname "${file}")" && pwd -P)
resolved="${dir}/$(basename "${file}")"
case "${resolved}" in
    "${ROOT}"/*) ;;
    *) exit 0 ;;
esac

if ! output=$(cd "${ROOT}" && swiftformat "${resolved}" 2>&1); then
    fail ERR_FORMAT_FAILED "swiftformat could not format the edited file" \
        "swiftformat exits 0 on ${resolved#"${ROOT}"/}" \
        "$(printf '%s' "${output}" | tail -n 5 | tr '\n' ' ')" \
        "fix the syntax error, then run: mise exec -- swiftformat ${resolved#"${ROOT}"/}"
fi
exit 0
