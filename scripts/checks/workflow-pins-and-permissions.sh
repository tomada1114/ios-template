#!/usr/bin/env bash
# Every GitHub Actions workflow declares its token permissions, and every action it
# (or a composite action in this repository) pulls in is pinned to a full commit SHA
# with a readable version comment.
#
#   scripts/checks/workflow-pins-and-permissions.sh [--root DIR]
#
# Files: <root>/.github/workflows/*.yml|*.yaml, and for the pin rule also
# <root>/.github/actions/*/action.yml|action.yaml (either directory may be absent).
#   - permissions: each workflow has a top-level `permissions:` key (column 0) —
#     a block, `read-all`, or `{}` all count.
#   - pins: each `uses:` line (`uses:` or `- uses:` as the first thing on the line)
#     whose value is not local (`./…`) must read
#     `owner/repo[/path]@<40 lowercase hex> # v<digit>…` — the format Dependabot
#     keeps when it bumps a pin. A tag or branch ref, a short SHA, a missing
#     version comment, and a `docker://` ref all fail. This is stricter than
#     zizmor's default `unpinned-uses` policy, which accepts tag pins for some
#     owners, and it also covers composite actions.
# The check is grep-based, not YAML-aware: a `uses:` whose value sits on the next
# line is not seen.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE                unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_WORKFLOW_PERMISSIONS a workflow has no top-level `permissions:` key
#   ERR_CHECK_WORKFLOW_UNPINNED    a non-local `uses:` is not pinned to a SHA with a `# v…` comment
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/workflow-pins-and-permissions.sh" "$@"

USES_LINE='^[[:space:]]*(-[[:space:]]+)?uses:'
QUOTE="[\"']?"
PINNED="${USES_LINE}[[:space:]]+${QUOTE}[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[^@[:space:]\"']+)?@[0-9a-f]{40}${QUOTE}[[:space:]]+#[[:space:]]*v[0-9]"
LOCAL="${USES_LINE}[[:space:]]+${QUOTE}\\./"

WORKFLOWS=()
ACTIONS=()
for file in "${CHECK_ROOT}"/.github/workflows/*.yml "${CHECK_ROOT}"/.github/workflows/*.yaml; do
    if [ -f "${file}" ]; then WORKFLOWS+=("${file}"); fi
done
for file in "${CHECK_ROOT}"/.github/actions/*/action.yml "${CHECK_ROOT}"/.github/actions/*/action.yaml; do
    if [ -f "${file}" ]; then ACTIONS+=("${file}"); fi
done

for file in ${WORKFLOWS[@]+"${WORKFLOWS[@]}"}; do
    if ! grep -qE '^permissions:' "${file}"; then
        check_problem "${file#"${CHECK_ROOT}"/}: no top-level \`permissions:\` key"
    fi
done
check_report ERR_CHECK_WORKFLOW_PERMISSIONS "a workflow does not declare its token permissions" \
    "a top-level \`permissions:\` key (column 0) in every .github/workflows/*.yml" \
    "add a least-privilege top-level \`permissions:\` block (e.g. \`contents: read\`) to each workflow named above"

for file in ${WORKFLOWS[@]+"${WORKFLOWS[@]}"} ${ACTIONS[@]+"${ACTIONS[@]}"}; do
    while IFS= read -r hit; do
        [ -n "${hit}" ] || continue
        line="${hit%%:*}"
        text="${hit#*:}"
        if grep -qE "${LOCAL}" <<<"${text}"; then
            continue
        fi
        if ! grep -qE "${PINNED}" <<<"${text}"; then
            ref=$(printf '%s\n' "${text}" | sed -E 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//')
            check_problem "${file#"${CHECK_ROOT}"/}:${line}: ${ref}"
        fi
    done <<EOF
$(grep -nE "${USES_LINE}" "${file}" || true)
EOF
done
check_report ERR_CHECK_WORKFLOW_UNPINNED "an action reference is not pinned to a full commit SHA" \
    "every non-local \`uses:\` to read \`owner/repo[/path]@<40-hex SHA> # vX.Y.Z\`" \
    "replace the ref with the release's full commit SHA and a trailing \`# vX.Y.Z\` comment"

check_finish "workflow-pins-and-permissions: every workflow declares permissions and every action is SHA-pinned."
