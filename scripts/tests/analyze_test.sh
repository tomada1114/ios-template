#!/usr/bin/env bash
# Tests for scripts/analyze.sh: the two clean builds it asks xcodebuild for, the
# swiftlint analyze call over their combined log, and the named failure for a failed
# build, a Swift file no compile command names (which SwiftLint would skip silently), a
# log with no compile command at all, analyzer violations, and a bad argument.
#
# No real build or analysis is ever run: `xcodebuild`, `xcbeautify`, and `swiftlint` are
# stubbed in every case. Each case copies analyze.sh into a fixture root's scripts/,
# beside a minimal app and package tree, and runs that copy with --root pointing at it.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

PKG="Packages/MyAppKit"

make_fixture_root() {
    local root
    root=$(cd "$(make_temp_dir)" && pwd -P)
    mkdir -p "${root}/scripts" "${root}/App" "${root}/LaunchUITests" \
        "${root}/${PKG}/Sources/MyAppCore" "${root}/${PKG}/Tests/MyAppCoreTests"
    cp "${REPO_ROOT}/scripts/analyze.sh" "${root}/scripts/analyze.sh"
    chmod +x "${root}/scripts/analyze.sh"
    : >"${root}/App/MyAppApp.swift"
    : >"${root}/LaunchUITests/LaunchTests.swift"
    : >"${root}/${PKG}/Package.swift"
    : >"${root}/${PKG}/Sources/MyAppCore/Core.swift"
    : >"${root}/${PKG}/Tests/MyAppCoreTests/CoreTests.swift"
    echo "${root}"
}

# stub_tools MODE [LINT_EXIT] — xcodebuild prints one compile command naming the files
# its build compiles, as absolute physical paths: the app build (run in the root) names
# App/, LaunchUITests/, and the package's sources; the package build (run in the package
# directory, scheme `…-Package`) names the sources and the tests. `missing` leaves the
# test file out, `filelist` names the files through an `@…SwiftFileList` response file
# as xcodebuild does, `empty` prints no compile command, `fail` exits 65. xcbeautify passes
# the log through; swiftlint exits LINT_EXIT (default 0).
stub_tools() {
    export STUB_MODE="$1" STUB_LINT_EXIT="${2:-0}"
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command xcodebuild 'case "$*" in
    *-Package*) base=$(cd ../.. && pwd -P); files="Packages/MyAppKit/Sources/MyAppCore/Core.swift Packages/MyAppKit/Tests/MyAppCoreTests/CoreTests.swift" ;;
    *) base=$(pwd -P); files="App/MyAppApp.swift LaunchUITests/LaunchTests.swift Packages/MyAppKit/Sources/MyAppCore/Core.swift" ;;
esac
if [ "${STUB_MODE}" = fail ]; then echo "error: stubbed compile failure"; exit 65; fi
if [ "${STUB_MODE}" = missing ]; then files="App/MyAppApp.swift LaunchUITests/LaunchTests.swift Packages/MyAppKit/Sources/MyAppCore/Core.swift"; fi
if [ "${STUB_MODE}" = filelist ]; then
    list="${base}/build/$$.SwiftFileList"
    mkdir -p "${base}/build"
    for f in ${files}; do echo "${base}/${f}"; done >"${list}"
    echo "builtin-SwiftDriver -- /usr/bin/swiftc -module-name X @${list}"
elif [ "${STUB_MODE}" != empty ]; then
    line="builtin-SwiftDriver -- /usr/bin/swiftc"
    for f in ${files}; do line="${line} ${base}/${f}"; done
    echo "${line}"
fi
echo "** TEST BUILD SUCCEEDED **"'
    stub_command xcbeautify 'cat >/dev/null'
    # shellcheck disable=SC2016 # expanded when the stub runs, not here
    stub_command swiftlint 'if [ "${STUB_LINT_EXIT}" != 0 ]; then echo "App/MyAppApp.swift:1:1: error: Unused Declaration Violation"; fi
exit "${STUB_LINT_EXIT}"'
}

assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not $1"
}

case_happy_path() {
    local root builds app package lint want
    root=$(make_fixture_root)
    stub_tools ok
    capture "${BASH}" "${root}/scripts/analyze.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "ANALYZE OK: 4 files"
    builds=$(cat "${STUB_BIN}/xcodebuild.log")
    [ "$(grep -c . <<<"${builds}")" = 2 ] || _fail "expected two xcodebuild calls: ${builds}"
    app=$(sed -n 1p <<<"${builds}")
    package=$(sed -n 2p <<<"${builds}")
    for want in "-project MyApp.xcodeproj -scheme MyApp " "-derivedDataPath ${root}/build/analyze-derived-data/app"; do
        grep -qF -- "${want}" <<<"${app}" || _fail "the app build lacks '${want}': ${app}"
    done
    for want in "-scheme MyAppKit-Package " "-derivedDataPath ${root}/build/analyze-derived-data/package"; do
        grep -qF -- "${want}" <<<"${package}" || _fail "the package build lacks '${want}': ${package}"
    done
    for want in "-destination generic/platform=iOS Simulator" "clean build-for-testing"; do
        grep -qF -- "${want}" <<<"${app}" || _fail "the app build lacks '${want}': ${app}"
        grep -qF -- "${want}" <<<"${package}" || _fail "the package build lacks '${want}': ${package}"
    done
    lint=$(cat "${STUB_BIN}/swiftlint.log")
    want="analyze --strict --quiet --compiler-log-path build/analyze/compiler.log App LaunchUITests ${PKG}/Sources ${PKG}/Tests"
    [ "${lint}" = "${want}" ] || _fail "swiftlint was called as '${lint}', not '${want}'"
    [ "$(grep -c 'swiftc' "${root}/build/analyze/compiler.log")" = 2 ] ||
        _fail "the compiler log does not hold both builds' compile commands"
}

case_throttle_jobs() {
    local root
    root=$(make_fixture_root)
    stub_tools ok
    THROTTLE_JOBS=3 capture "${BASH}" "${root}/scripts/analyze.sh" --root "${root}"
    assert_exit 0
    [ "$(grep -cF -- "-jobs 3" "${STUB_BIN}/xcodebuild.log")" = 2 ] ||
        _fail "THROTTLE_JOBS was not passed to both builds as -jobs"
}

case_response_file() {
    local root
    root=$(make_fixture_root)
    stub_tools filelist
    capture "${BASH}" "${root}/scripts/analyze.sh" --root "${root}"
    assert_exit 0
    assert_stdout_contains "ANALYZE OK: 4 files"
}

case_build_failure() {
    local root
    root=$(make_fixture_root)
    stub_tools fail
    capture "${BASH}" "${root}/scripts/analyze.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_ANALYZE_BUILD_FAILED
    assert_stderr_contains "the build exited 65"
    [ ! -e "${STUB_BIN}/swiftlint.log" ] || _fail "swiftlint ran after a failed build"
}

case_file_not_compiled() {
    local root
    root=$(make_fixture_root)
    stub_tools missing
    capture "${BASH}" "${root}/scripts/analyze.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_ANALYZE_FILE_NOT_COMPILED
    assert_stderr_contains "not compiled: ${PKG}/Tests/MyAppCoreTests/CoreTests.swift"
    assert_stderr_not_contains "Core.swift " "a compiled file listed as not compiled"
    [ ! -e "${STUB_BIN}/swiftlint.log" ] || _fail "swiftlint ran over a log that skips a file"
}

case_no_compile_commands() {
    local root
    root=$(make_fixture_root)
    stub_tools empty
    capture "${BASH}" "${root}/scripts/analyze.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_ANALYZE_FILE_NOT_COMPILED
    assert_stderr_contains "App/MyAppApp.swift"
    [ ! -e "${STUB_BIN}/swiftlint.log" ] || _fail "swiftlint ran over a log with no compile command"
}

case_violations() {
    local root
    root=$(make_fixture_root)
    stub_tools ok 2
    capture "${BASH}" "${root}/scripts/analyze.sh" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_ANALYZE_VIOLATIONS
    assert_stderr_contains "swiftlint analyze exited 2"
    assert_stdout_contains "Unused Declaration Violation"
    assert_stdout_not_contains "ANALYZE OK"
}

case_unknown_argument() {
    local root
    root=$(make_fixture_root)
    stub_tools ok
    capture "${BASH}" "${root}/scripts/analyze.sh" --bogus
    assert_exit 1
    assert_first_stderr_line ERR_ANALYZE_USAGE
    assert_stderr_contains "unknown argument '--bogus'"
    [ ! -e "${STUB_BIN}/xcodebuild.log" ] || _fail "xcodebuild ran before the arguments were checked"
}

run_case "builds the app and the package clean for testing, then analyzes their log" case_happy_path
run_case "passes THROTTLE_JOBS to both builds as -jobs" case_throttle_jobs
run_case "files named through an @…SwiftFileList response file count as compiled" case_response_file
run_case "a failed build fails ERR_ANALYZE_BUILD_FAILED" case_build_failure
run_case "a file no compile command names fails ERR_ANALYZE_FILE_NOT_COMPILED" case_file_not_compiled
run_case "a log with no compile command fails ERR_ANALYZE_FILE_NOT_COMPILED" case_no_compile_commands
run_case "an analyzer violation fails ERR_ANALYZE_VIOLATIONS" case_violations
run_case "an unknown argument fails ERR_ANALYZE_USAGE" case_unknown_argument
finish
