#!/usr/bin/env bash
# Runs every harness-conformance check in scripts/checks/ (every *.sh except this
# file and the sourced lib.sh), each in its own bash process, and keeps going after
# one fails so a single run reports every broken invariant.
#
#   scripts/checks/run-all.sh [--root DIR]    (what `just check-harness` and CI's lint job run)
#
# --root DIR is passed through to every check (tests point it at a fixture tree);
# without it each check reads the checkout containing scripts/checks/. The checks
# need `just` on PATH (just-recipes-exist.sh): run this through `mise exec --`
# locally; CI's jdx/mise-action installs it.
#
# Git work tree: not required — no check calls git.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE    unknown argument, or a --root DIR that does not exist
#   ERR_CHECKS_NONE    no check script was found next to this one
#   ERR_CHECKS_FAILED  at least one check exited non-zero; every failing one is named
set -euo pipefail

CHECKS_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/checks/lib.sh
. "${CHECKS_DIR}/lib.sh"
# Validates the arguments once, up front, with the same rules every check applies.
check_parse_args "scripts/checks/run-all.sh" "$@"

TOTAL=0
FAILED_COUNT=0
FAILED_CHECKS=""
for check in "${CHECKS_DIR}"/*.sh; do
    [ -f "${check}" ] || continue
    name=$(basename "${check}")
    case "${name}" in
        run-all.sh | lib.sh) continue ;;
    esac
    TOTAL=$((TOTAL + 1))
    echo "==> scripts/checks/${name}"
    if ! "${BASH}" "${check}" "$@"; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_CHECKS="${FAILED_CHECKS} ${name}"
    fi
done

if [ "${TOTAL}" = 0 ]; then
    check_fail ERR_CHECKS_NONE "no harness check to run" \
        "at least one scripts/checks/*.sh besides run-all.sh and lib.sh" \
        "the glob matched nothing in ${CHECKS_DIR}" \
        "restore the check scripts under scripts/checks/"
fi

if [ "${FAILED_COUNT}" -gt 0 ]; then
    check_fail ERR_CHECKS_FAILED "${FAILED_COUNT} of ${TOTAL} harness check(s) failed:${FAILED_CHECKS}" \
        "every scripts/checks/*.sh to exit 0" \
        "failed:${FAILED_CHECKS}" \
        "read each failing check's ERR_ block above, fix it, and re-run \`just check-harness\`"
fi
echo "harness checks: ${TOTAL} check(s) passed"
