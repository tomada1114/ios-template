#!/usr/bin/env bash
# Tests for scripts/bundle-id.sh: which value it reads out of a project.yml, and
# the named failure for each way the manifest can fail to name one. Every case
# points --root at a fixture manifest, so the real checkout is never read.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

BUNDLE_ID_SH="${REPO_ROOT}/scripts/bundle-id.sh"

# write_manifest ROOT SETTINGS_BODY — a project.yml shaped like the real one.
write_manifest() {
    cat >"$1/project.yml" <<EOF
name: MyApp
targets:
  MyApp:
    type: application
    settings:
      base:
$2
EOF
}

case_reads_the_identifier() {
    root=$(make_temp_dir)
    write_manifest "${root}" '        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyApp'
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 0
    assert_stdout_contains "com.example.MyApp"
}

case_reads_a_renamed_identifier() {
    # What `just run` and `just logs` depend on after scripts/bootstrap.sh: a
    # second manifest, a second answer, with nothing hard-coded on this side.
    # It asserts only on this fixture's own value — scripts/bootstrap.sh rewrites
    # the template's placeholder prefix inside this file too, so an assertion
    # about that prefix would be rewritten into one about the new app's.
    root=$(make_temp_dir)
    write_manifest "${root}" '        PRODUCT_BUNDLE_IDENTIFIER: dev.acme.Notes'
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 0
    assert_stdout_contains "dev.acme.Notes"
}

case_strips_quotes_and_trailing_space() {
    root=$(make_temp_dir)
    write_manifest "${root}" '        PRODUCT_BUNDLE_IDENTIFIER: "com.example.MyApp"   '
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 0
    assert_stdout_contains "com.example.MyApp"
    assert_stdout_not_contains '"' "the surrounding quotes"
}

case_strips_a_trailing_comment() {
    # XcodeGen accepts a YAML comment after the value, so this script must too.
    root=$(make_temp_dir)
    write_manifest "${root}" '        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyApp # the app id'
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 0
    assert_stdout_contains "com.example.MyApp"
    assert_stdout_not_contains "#" "the comment"
    assert_stdout_not_contains "the app id" "the comment text"
}

case_strips_a_trailing_comment_after_quotes() {
    root=$(make_temp_dir)
    write_manifest "${root}" '        PRODUCT_BUNDLE_IDENTIFIER: "com.example.MyApp"   # the app id'
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 0
    assert_stdout_contains "com.example.MyApp"
    assert_stdout_not_contains '"' "the surrounding quotes"
    assert_stdout_not_contains "#" "the comment"
}

case_comment_only_value() {
    root=$(make_temp_dir)
    write_manifest "${root}" '        PRODUCT_BUNDLE_IDENTIFIER: # to be filled in'
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_BUNDLEID_NOT_FOUND"
}

case_takes_the_first_target() {
    root=$(make_temp_dir)
    write_manifest "${root}" '        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyApp'
    cat >>"${root}/project.yml" <<'EOF'
  MyAppLaunchUITests:
    type: bundle.ui-testing
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyAppLaunchUITests
EOF
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 0
    assert_stdout_contains "com.example.MyApp"
    assert_stdout_not_contains "LaunchUITests" "the test bundle's identifier"
}

case_missing_manifest() {
    root=$(make_temp_dir)
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_BUNDLEID_MANIFEST_MISSING"
    assert_stderr_contains "Next: "
    grep -q '^ERR_BUNDLEID_MANIFEST_MISSING: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
        _fail "the first stderr line is not the failure code"
}

case_no_identifier_declared() {
    root=$(make_temp_dir)
    write_manifest "${root}" '        GENERATE_INFOPLIST_FILE: YES'
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_BUNDLEID_NOT_FOUND"
}

case_malformed_identifier() {
    root=$(make_temp_dir)
    write_manifest "${root}" '        PRODUCT_BUNDLE_IDENTIFIER: com.example My App'
    capture "${BUNDLE_ID_SH}" --root "${root}"
    assert_exit 1
    assert_stderr_contains "ERR_BUNDLEID_MALFORMED"
}

case_unknown_argument() {
    capture "${BUNDLE_ID_SH}" --nope
    assert_exit 1
    assert_stderr_contains "ERR_BUNDLEID_USAGE"
}

case_missing_root_directory() {
    capture "${BUNDLE_ID_SH}" --root "${TEST_TMP_ROOT}/does-not-exist"
    assert_exit 1
    assert_stderr_contains "ERR_BUNDLEID_USAGE"
}

run_case "prints the identifier the manifest declares" case_reads_the_identifier
run_case "follows a renamed identifier (post-bootstrap)" case_reads_a_renamed_identifier
run_case "strips surrounding quotes and trailing space" case_strips_quotes_and_trailing_space
run_case "strips a YAML comment after the value" case_strips_a_trailing_comment
run_case "strips a YAML comment after a quoted value" case_strips_a_trailing_comment_after_quotes
run_case "names a line whose value is only a comment" case_comment_only_value
run_case "takes the app target's identifier, not a later target's" case_takes_the_first_target
run_case "names a missing project.yml" case_missing_manifest
run_case "names a manifest with no identifier" case_no_identifier_declared
run_case "rejects a value that is not a bundle identifier" case_malformed_identifier
run_case "rejects an unknown argument" case_unknown_argument
run_case "rejects a --root that does not exist" case_missing_root_directory
finish
