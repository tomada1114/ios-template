#!/usr/bin/env bash
# Run the MyAppKit test suite with code coverage and enforce a line-coverage floor
# and a function-coverage floor on Sources/MyAppCore. The report below is filtered
# to that path, so MyAppUI and MyAppPlatform are outside it rather than measured
# and waived. The floors are
# honest because all logic lives in Core: views render it and MyAppPlatform adapters
# only translate for it, so neither holds a decision a test could catch
# (AGENTS.md > Architecture). MyAppPlatformTests does link MyAppPlatform, but its
# tests are skipped unless RUN_LOCAL_MACHINE_TESTS=1 (`just test-local`) — so they
# contribute nothing here, and measuring Platform would gate the build on whether a
# human opted in.
#
# Swift's llvm-cov has no dependable branch metric, so this gates on LINE
# coverage (uv-template gates on branch coverage; documented divergence), and on
# FUNCTION coverage so a Core function no test calls cannot hide under the line
# floor. llvm-cov counts every compiler-generated closure as a function too — an
# os.Logger message's interpolations and a preconditionFailure message are
# autoclosures no test evaluates — so function coverage stays below 100% with every
# named function tested (19 of 23, 82.6%, when its floor was set), and its floor
# sits below the line floor.
#
# The floors are COVERAGE_FLOOR (lines) and FUNCTION_COVERAGE_FLOOR below and
# nothing else: no environment variable or flag moves either, so every change to
# one is a reviewed diff of this file. They are raised, never lowered (AGENTS.md,
# "Important Reminders").
#
#   scripts/coverage.sh    (what `just test` and CI's test and release jobs run)
#
# Git work tree: not required — it runs from the package directory next to it.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_COVERAGE_OVERRIDE_REMOVED       COVERAGE_MIN is set; it is no longer read,
#                                       and the script stops before running any test
#   ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR  MyAppCore function coverage is below
#                                       FUNCTION_COVERAGE_FLOOR
# A line coverage below COVERAGE_FLOOR predates this contract and exits non-zero
# with a one-line message from the embedded Python instead.
set -euo pipefail

readonly COVERAGE_FLOOR=80
readonly FUNCTION_COVERAGE_FLOOR=75

# The old environment override is rejected rather than silently ignored, so a
# caller who still sets it learns the floor no longer moves that way.
if [ -n "${COVERAGE_MIN+set}" ]; then
    echo "ERR_COVERAGE_OVERRIDE_REMOVED: COVERAGE_MIN is no longer read." >&2
    echo "Expected: the floor comes from COVERAGE_FLOOR in scripts/coverage.sh (currently ${COVERAGE_FLOOR})." >&2
    echo "Actual: COVERAGE_MIN is set in the environment (value: '${COVERAGE_MIN}')." >&2
    echo "Next: unset COVERAGE_MIN and rerun; to raise the floor, edit COVERAGE_FLOOR in a reviewed commit — it is never lowered (AGENTS.md)." >&2
    exit 1
fi

cd "$(dirname "$0")/../Packages/MyAppKit"

swift test --enable-code-coverage
CODECOV_JSON="$(swift test --show-codecov-path)"

python3 - "$CODECOV_JSON" "$COVERAGE_FLOOR" "$FUNCTION_COVERAGE_FLOOR" <<'PY'
import json, sys

data = json.load(open(sys.argv[1]))
line_floor = float(sys.argv[2])
function_floor = float(sys.argv[3])


def percent(summary):
    return 100.0 * summary["covered"] / summary["count"] if summary["count"] else 100.0


lines = {"covered": 0, "count": 0}
functions = {"covered": 0, "count": 0}
for f in data["data"][0]["files"]:
    if "/Sources/MyAppCore/" not in f["filename"]:
        continue
    for total, key in ((lines, "lines"), (functions, "functions")):
        total["covered"] += f["summary"][key]["covered"]
        total["count"] += f["summary"][key]["count"]
    print(
        f'{f["filename"]}: lines {percent(f["summary"]["lines"]):.1f}%, '
        f'functions {percent(f["summary"]["functions"]):.1f}%'
    )
if lines["count"] == 0:
    sys.exit("coverage: no MyAppCore files found — gate misconfigured")
line_pct = percent(lines)
function_pct = percent(functions)
print(f"MyAppCore line coverage: {line_pct:.1f}% (floor {line_floor}%)")
print(
    f"MyAppCore function coverage: {function_pct:.1f}% "
    f'({functions["covered"]} of {functions["count"]} functions; floor {function_floor}%)'
)

# Two decimals in each failure message so a near-miss never rounds up to the
# floor itself (e.g. 79.96% displayed as "80.0% is below the 80% floor"). Both
# floors are checked before exiting, so one run reports every miss.
failed = False
if function_pct < function_floor:
    failed = True
    for message in (
        f"ERR_COVERAGE_FUNCTIONS_BELOW_FLOOR: MyAppCore function coverage "
        f"{function_pct:.2f}% is below the {function_floor}% floor",
        f"Expected: at least {function_floor}% of MyAppCore functions run under "
        "`just test` (FUNCTION_COVERAGE_FLOOR in scripts/coverage.sh)",
        f'Actual: {functions["covered"]} of {functions["count"]} functions ran '
        f"({function_pct:.2f}%)",
        "Next: add a MyAppCore test that calls the uncovered functions in the files "
        "listed above, then rerun `just test`; the floor is never lowered (AGENTS.md).",
    ):
        print(message, file=sys.stderr)
if line_pct < line_floor:
    failed = True
    print(f"coverage {line_pct:.2f}% is below the {line_floor}% floor", file=sys.stderr)
sys.exit(1 if failed else 0)
PY
