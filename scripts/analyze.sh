#!/usr/bin/env bash
# Run SwiftLint's analyzer rules (`.swiftlint.yml`'s `analyzer_rules`: unused
# declarations and unused imports) over every Swift file the app and the package
# compile. What `just analyze` runs after regenerating the project, and what CI's
# `Test & Coverage Gate` runs through it.
#
#   scripts/analyze.sh [--root DIR]
#
# Analyzer rules need each file's compiler arguments, which come from the raw log of an
# xcodebuild run that compiled it. So this script makes that log itself, with two clean
# builds into derived data of its own (build/analyze-derived-data/), for the generic iOS
# Simulator destination:
#   - `build-for-testing` of the app scheme: App/, LaunchUITests/, and the package's
#     library targets as the app links them;
#   - `build-for-testing` of the package's `<Package>-Package` scheme: every package
#     target, the test targets and the test-support library included.
# Both are needed: `unused_declaration` counts a reference only from a file it analyzes,
# so an `internal` declaration reached only through `@testable import` needs the tests
# in the same run, and iOS, not the host Mac, is what compiles the code behind
# `#if os(iOS)`. The builds are clean because an incremental one skips the compile
# commands of up-to-date files, and the analyzer would then silently skip those files.
#
# Fail-closed: SwiftLint skips a file it has no compiler arguments for without a word,
# so before analyzing, every Swift file under App/, LaunchUITests/, and each package's
# Sources/ and Tests/ must appear in a compile command of the log, or in the
# `@…SwiftFileList` response file one names
# (ERR_ANALYZE_FILE_NOT_COMPILED); a gate that analyzed nothing would otherwise pass.
# Package.swift is never analyzed: it is a manifest, not a compiled target's source.
#
# Tools: swiftlint and xcbeautify come from the caller's PATH (`just analyze` runs this
# under `mise exec --`); xcodebuild comes with Xcode.
#
# Git work tree: not required — it builds and analyzes the project under --root, which
# defaults to the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_ANALYZE_USAGE              unknown argument, or a --root DIR that does not exist
#   ERR_ANALYZE_BUILD_FAILED       one of the two builds failed
#   ERR_ANALYZE_FILE_NOT_COMPILED  a Swift file appears in no compile command of the log
#   ERR_ANALYZE_VIOLATIONS         swiftlint analyze reported a violation (or failed)
set -euo pipefail

APP_NAME="MyApp"
DERIVED_DATA="build/analyze-derived-data"
LOG_DIR="build/analyze"
DESTINATION="generic/platform=iOS Simulator"
USAGE="usage: scripts/analyze.sh [--root DIR]"

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
            [ $# -ge 2 ] && [ -d "$2" ] || fail ERR_ANALYZE_USAGE "--root needs an existing directory" \
                "--root followed by an existing directory" "'${2:-}'" "${USAGE}"
            ROOT=$(cd "$2" && pwd -P)
            shift
            ;;
        *) fail ERR_ANALYZE_USAGE "unknown argument '$1'" "no arguments, or --root DIR" "argument '$1'" "${USAGE}" ;;
    esac
    shift
done
# Physical path: xcodebuild writes resolved paths into its compile commands, and the
# coverage check below compares against them.
[ -n "${ROOT}" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
cd "${ROOT}"

PACKAGE_DIR=""
for dir in Packages/*/; do
    [ -f "${dir}Package.swift" ] && PACKAGE_DIR="${dir%/}" && break
done
PACKAGE_NAME="${PACKAGE_DIR##*/}"

mkdir -p "${LOG_DIR}"
COMPILER_LOG="${LOG_DIR}/compiler.log"
: >"${COMPILER_LOG}"

# The job cap scripts/run-throttled.sh exports (`just analyze`), when there is one.
JOBS_ARGS=()
if [ -n "${THROTTLE_JOBS:-}" ]; then JOBS_ARGS=(-jobs "${THROTTLE_JOBS}"); fi

# build <label> <log> <directory> <derived data> <xcodebuild arguments…> — a clean
# build-for-testing in <directory>, its raw output kept in <log> and appended to the
# compiler log. Each build has derived data of its own, so one's clean cannot touch the
# other's products.
build() {
    local label="$1" log="$2" dir="$3" derived="$4" status=0
    shift 4
    echo "==> Building ${label} for testing (Debug, iOS Simulator, clean) for the analyzer"
    (cd "${dir}" && xcodebuild ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} "$@" \
        -destination "${DESTINATION}" \
        -derivedDataPath "${ROOT}/${derived}" \
        clean build-for-testing) 2>&1 | tee "${log}" | xcbeautify --quiet || status=$?
    [ "${status}" = 0 ] || fail ERR_ANALYZE_BUILD_FAILED "the ${label} build the analyzer needs failed" \
        "\`xcodebuild clean build-for-testing\` of ${label} for '${DESTINATION}' to succeed" \
        "the build exited ${status} (xcbeautify's errors are above; the raw log is ${log})" \
        "fix the first error above (\`just build\` or \`just uitest-build\` shows the same compile), then rerun \`just analyze\`"
    cat "${log}" >>"${COMPILER_LOG}"
}

build "${APP_NAME}" "${LOG_DIR}/app.log" "${ROOT}" "${DERIVED_DATA}/app" -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}"
if [ -n "${PACKAGE_DIR}" ]; then
    build "${PACKAGE_NAME}" "${LOG_DIR}/package.log" "${ROOT}/${PACKAGE_DIR}" "${DERIVED_DATA}/package" -scheme "${PACKAGE_NAME}-Package"
fi

# Every Swift file the analyzer is pointed at, and the compile commands of the log.
PATHS=()
for path in App LaunchUITests Packages/*/Sources Packages/*/Tests; do
    [ -d "${path}" ] && PATHS+=("${path}")
done
FILES=$(find ${PATHS[@]+"${PATHS[@]}"} -name '*.swift' -not -path '*/.build/*' | LC_ALL=C sort)
COMMANDS=$(grep -F 'swiftc' "${COMPILER_LOG}" || true)
# xcodebuild passes a target's sources as a response file (`@…/<Target>.SwiftFileList`,
# one path per line), which SwiftLint expands, so its paths count as named too.
RESPONSE_FILES=$({ grep -oE '@/[^[:space:]]+' <<<"${COMMANDS}" || true; } | LC_ALL=C sort -u)
while IFS= read -r response; do
    [ -n "${response}" ] && [ -f "${response#@}" ] || continue
    COMMANDS="${COMMANDS}
$(cat "${response#@}")"
done <<<"${RESPONSE_FILES}"
MISSING=""
while IFS= read -r file; do
    [ -n "${file}" ] || continue
    grep -qF -- "${ROOT}/${file}" <<<"${COMMANDS}" || MISSING="${MISSING} ${file}"
done <<<"${FILES}"
COUNT=$(grep -c . <<<"${FILES}" || true)
[ -z "${MISSING}" ] && [ "${COUNT}" -gt 0 ] || fail ERR_ANALYZE_FILE_NOT_COMPILED \
    "a Swift file the analyzer would silently skip appears in no compile command of ${COMPILER_LOG}" \
    "every Swift file under App/, LaunchUITests/, and Packages/*/Sources and Tests/ compiled by the app or the package build" \
    "not compiled:${MISSING:- (no Swift files found at all)}" \
    "add the file to a target in project.yml or Package.swift, or move it out of those directories; a file no target compiles is dead code"

echo "==> swiftlint analyze --strict (${COUNT} files)"
LINT_STATUS=0
swiftlint analyze --strict --quiet --compiler-log-path "${COMPILER_LOG}" "${PATHS[@]}" || LINT_STATUS=$?
[ "${LINT_STATUS}" = 0 ] || fail ERR_ANALYZE_VIOLATIONS "swiftlint analyze reported violations" \
    "no unused_declaration or unused_import violation (.swiftlint.yml's analyzer_rules)" \
    "swiftlint analyze exited ${LINT_STATUS}; the violations are listed above" \
    "remove the unused declaration or import it names, by hand (an import can be needed on macOS, which this iOS Simulator analysis does not see: \`just test\` builds it), then rerun \`just analyze\`"

echo "ANALYZE OK: ${COUNT} files"
