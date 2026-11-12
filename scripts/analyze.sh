#!/usr/bin/env bash
# Run SwiftLint's analyzer rules (`.swiftlint.yml`'s `analyzer_rules`: unused
# declarations and unused imports) over every Swift file the app and its local packages
# compile. What `just analyze` runs after regenerating the project, and what `just
# check-release` runs through it; no pull request's checks run it.
#
#   scripts/analyze.sh [--root DIR]
#
# Analyzer rules need each file's compiler arguments, which come from the raw log of an
# xcodebuild run that compiled it. So this script makes that log itself, with clean
# builds into derived data of its own (build/analyze-derived-data/), Debug, for the
# generic iOS Simulator destination:
#   - `build-for-testing` of the app scheme: App/, LaunchUITests/, and the packages'
#     library targets as the app links them;
#   - `build-for-testing` of each local package's `<Package>-Package` scheme (every
#     Packages/*/ holding a Package.swift): every target, the test targets and the
#     test-support library included.
# Both kinds are needed: `unused_declaration` counts a reference only from a file it
# analyzes, so an `internal` declaration reached only through `@testable import` needs
# the tests in the same run, and iOS, not the host Mac, is what compiles the code behind
# `#if os(iOS)`. The builds are clean because an incremental one skips the compile
# commands of up-to-date files, and the analyzer would then silently skip those files.
#
# What it cannot see: only this one Debug iOS Simulator compile. A declaration or import
# used only under `#if os(macOS)`, `#if !DEBUG`, or `#if !targetEnvironment(simulator)`
# is inactive here and can be reported unused although another build needs it.
#
# Fail-closed: SwiftLint skips a file it has no compiler arguments for without a word,
# so before analyzing, every Swift file under App/, LaunchUITests/, and each package's
# Sources/ and Tests/ must appear in a compile command SwiftLint reads — a line naming
# `swiftc ` and then ` -module-name ` — or in the `@…SwiftFileList` response file one
# names (ERR_ANALYZE_FILE_NOT_COMPILED); a gate that analyzed nothing would otherwise
# pass. Package.swift is never analyzed: it is a manifest, not a compiled target's source.
#
# A checkout path holding whitespace is refused up front (ERR_ANALYZE_PATH_HAS_SPACE):
# xcodebuild escapes it in the log as `\ `, and SwiftLint splits a compile command on
# spaces, so every file would lose its arguments.
#
# Tools: swiftlint and xcbeautify come from the caller's PATH (`just analyze` runs this
# under `mise exec --`); xcodebuild comes with Xcode.
#
# Git work tree: not required — it builds and analyzes the project under --root, which
# defaults to the checkout containing this script.
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_ANALYZE_USAGE              unknown argument, or a --root DIR that does not exist
#   ERR_ANALYZE_PATH_HAS_SPACE     the checkout's physical path holds whitespace
#   ERR_ANALYZE_BUILD_FAILED       xcodebuild failed one of the builds
#   ERR_ANALYZE_LOG_FAILED         xcodebuild succeeded but keeping its log (tee) or
#                                  formatting it (xcbeautify) failed
#   ERR_ANALYZE_FILE_NOT_COMPILED  a Swift file appears in no compile command of the log
#   ERR_ANALYZE_VIOLATIONS         swiftlint analyze reported a violation (or failed)
set -euo pipefail

APP_NAME="MyApp"
DERIVED_DATA="build/analyze-derived-data"
LOG_DIR="build/analyze"
DESTINATION="generic/platform=iOS Simulator"
USAGE="usage: scripts/analyze.sh [--root DIR]"
CONDITIONAL_NOTE="the analysis compiles Debug for the iOS Simulator only, so a declaration or import used only under \`#if os(macOS)\`, \`#if !DEBUG\`, or \`#if !targetEnvironment(simulator)\` can be reported falsely: do not delete that one; restructure it so this build references it, or report it"

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
case "${ROOT}" in
    *[[:space:]]*) fail ERR_ANALYZE_PATH_HAS_SPACE "the checkout's path holds whitespace, which the analyzer cannot read through" \
        "a checkout path without spaces or other whitespace" "'${ROOT}'" \
        "clone or move the checkout to a path without whitespace (\`git worktree add\` one there works), then rerun \`just analyze\` from it" ;;
esac
cd "${ROOT}"

PACKAGE_DIRS=()
for dir in Packages/*/; do
    [ -f "${dir}Package.swift" ] && PACKAGE_DIRS+=("${dir%/}")
done

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
    local label="$1" log="$2" dir="$3" derived="$4" statuses
    shift 4
    echo "==> Building ${label} for testing (Debug, iOS Simulator, clean) for the analyzer"
    set +e
    (cd "${dir}" && xcodebuild ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} "$@" \
        -destination "${DESTINATION}" \
        -derivedDataPath "${ROOT}/${derived}" \
        clean build-for-testing) 2>&1 | tee "${log}" | xcbeautify --quiet
    statuses="${PIPESTATUS[*]}"
    set -e
    # shellcheck disable=SC2086 # split the three exit statuses on purpose
    set -- ${statuses}
    [ "$1" = 0 ] || fail ERR_ANALYZE_BUILD_FAILED "the ${label} build the analyzer needs failed" \
        "\`xcodebuild clean build-for-testing\` of ${label} for '${DESTINATION}' to succeed" \
        "xcodebuild exited $1 (xcbeautify's errors are above; the raw log is ${log})" \
        "fix the first error above (\`just uitest-build\` shows the same compile), then rerun \`just analyze\`"
    [ "$2" = 0 ] && [ "$3" = 0 ] || fail ERR_ANALYZE_LOG_FAILED "the ${label} build succeeded, but its log was not kept whole" \
        "tee to write ${log} and xcbeautify to read it, both exiting 0" \
        "tee exited $2, xcbeautify exited $3" \
        "check that ${LOG_DIR}/ is writable and that \`xcbeautify --version\` runs (\`just install\` installs it), then rerun \`just analyze\`"
    cat "${log}" >>"${COMPILER_LOG}"
}

build "${APP_NAME}" "${LOG_DIR}/app.log" "${ROOT}" "${DERIVED_DATA}/app" -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}"
for dir in ${PACKAGE_DIRS[@]+"${PACKAGE_DIRS[@]}"}; do
    name="${dir##*/}"
    build "${name}" "${LOG_DIR}/package-${name}.log" "${ROOT}/${dir}" "${DERIVED_DATA}/package-${name}" -scheme "${name}-Package"
done

# Every Swift file the analyzer is pointed at: the app's directories, and the Sources/
# and Tests/ of each package built above.
PATHS=()
for path in App LaunchUITests; do
    [ -d "${path}" ] && PATHS+=("${path}")
done
for dir in ${PACKAGE_DIRS[@]+"${PACKAGE_DIRS[@]}"}; do
    for path in "${dir}/Sources" "${dir}/Tests"; do
        [ -d "${path}" ] && PATHS+=("${path}")
    done
done
FILES=$(find ${PATHS[@]+"${PATHS[@]}"} -name '*.swift' -not -path '*/.build/*' | LC_ALL=C sort)
COUNT=$(grep -c . <<<"${FILES}" || true)

# The compile commands as SwiftLint reads them, and the response files they name:
# xcodebuild passes a target's sources as `@…/<Target>.SwiftFileList`, one path per line,
# which SwiftLint expands.
COMMANDS=$(grep -E 'swiftc( | .* )-module-name ' "${COMPILER_LOG}" || true)
RESPONSE_FILES=$({ grep -oE '@/[^[:space:]]+' <<<"${COMMANDS}" || true; } | sed 's/^@//' | LC_ALL=C sort -u)
while IFS= read -r response; do
    [ -n "${response}" ] && [ -f "${response}" ] || continue
    COMMANDS="${COMMANDS}
$(cat "${response}")"
done <<<"${RESPONSE_FILES}"

# One pass: the expected absolute paths as fixed patterns, matched once over the
# commands, then compared with the list.
EXPECTED="${LOG_DIR}/expected-files.txt"
awk -v r="${ROOT}/" 'NF { print r $0 }' <<<"${FILES}" >"${EXPECTED}"
FOUND=$({ grep -oF -f "${EXPECTED}" <<<"${COMMANDS}" || true; } | LC_ALL=C sort -u)
MISSING=$(LC_ALL=C comm -23 "${EXPECTED}" - <<<"${FOUND}" | awk -v r="${ROOT}/" '{ printf "%s ", substr($0, length(r) + 1) }')
[ -z "${MISSING}" ] && [ "${COUNT}" -gt 0 ] || fail ERR_ANALYZE_FILE_NOT_COMPILED \
    "a Swift file the analyzer would silently skip appears in no compile command of ${COMPILER_LOG}" \
    "every Swift file under App/, LaunchUITests/, and each built package's Sources/ and Tests/ named by a \`swiftc … -module-name …\` line of the app or a package build, or by its SwiftFileList" \
    "not compiled: ${MISSING:-(no Swift files found at all)}" \
    "add the file to a target in project.yml or Package.swift, or move it out of those directories; a file no target compiles is dead code. If every file is listed, the compile-command format changed: update this check, never skip it"

echo "==> swiftlint analyze --strict (${COUNT} files)"
LINT_STATUS=0
swiftlint analyze --strict --quiet --compiler-log-path "${COMPILER_LOG}" "${PATHS[@]}" || LINT_STATUS=$?
[ "${LINT_STATUS}" = 0 ] || fail ERR_ANALYZE_VIOLATIONS "swiftlint analyze reported violations" \
    "no unused_declaration or unused_import violation (.swiftlint.yml's analyzer_rules)" \
    "swiftlint analyze exited ${LINT_STATUS}; the violations are listed above" \
    "remove the unused declaration or import it names, by hand, then rerun \`just test\` (an import can be needed on macOS) and \`just analyze\`. But ${CONDITIONAL_NOTE}"

echo "ANALYZE OK: ${COUNT} files"
