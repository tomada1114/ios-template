#!/usr/bin/env bash
# Tests for scripts/targets-ipad.sh: whether a project.yml builds an iOS target for
# iPad, which decides whether the iPad launch UI test in `just check-release`
# (scripts/uitest-ipad.sh) runs, and the named failure for each way the manifest can
# fail to answer. Every case but one points --root at a fixture manifest; that one
# reads the real checkout, read-only.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

TARGETS_IPAD_SH="${REPO_ROOT}/scripts/targets-ipad.sh"

# write_manifest ROOT APP_FAMILY TESTS_FAMILY [EXTRA_TARGETS] — a project.yml shaped
# like the real one: an app and a UI-test target, each with its own family line (an
# empty family leaves the key out), then any extra target text.
write_manifest() {
    local app_line="" tests_line=""
    [ -z "$2" ] || app_line="        TARGETED_DEVICE_FAMILY: \"$2\""
    [ -z "$3" ] || tests_line="        TARGETED_DEVICE_FAMILY: \"$3\""
    cat >"$1/project.yml" <<EOF
name: MyApp
options:
  deploymentTarget:
    iOS: "27.0"
targets:
  MyApp:
    type: application
    platform: iOS
    settings:
      base:
        # iPhone and iPad. Dropping iPad is an app's decision (TARGETED_DEVICE_FAMILY: "1").
${app_line}
        CODE_SIGN_STYLE: Automatic
  MyAppLaunchUITests:
    type: bundle.ui-testing
    platform: iOS
    settings:
      base:
${tests_line}
${4:-}
schemes:
  MyApp:
    build:
      targets: { MyApp: all }
EOF
}

WATCH_TARGET='  MyAppWatch:
    type: application
    platform: watchOS
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "4"'

# rewrite_family ROOT FROM TO — replaces every `TARGETED_DEVICE_FAMILY: FROM` line's value.
rewrite_family() {
    sed "s/TARGETED_DEVICE_FAMILY: $2\$/TARGETED_DEVICE_FAMILY: $3/" "$1/project.yml" >"${CASE_DIR}/project.yml"
    mv "${CASE_DIR}/project.yml" "$1/project.yml"
}

# assert_answer WANT — the run exited 0 and printed exactly WANT.
assert_answer() {
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "$1" ] || _fail "stdout is not exactly $1"
}

# assert_first_stderr_line CODE — the failure contract's first line.
assert_first_stderr_line() {
    grep -q "^$1: " <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "the first stderr line is not $1"
}

case_shipped_both_families() {
    root=$(make_temp_dir)
    write_manifest "${root}" "1,2" "1,2"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer true
}

case_iphone_only() {
    root=$(make_temp_dir)
    write_manifest "${root}" "1" "1"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer false
}

# One iOS target keeping iPad is enough: the rule is "any iOS target names 2".
case_mixed_ios_families() {
    root=$(make_temp_dir)
    write_manifest "${root}" "1" "1,2"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer true
}

# A watchOS target's family 4 neither keeps nor drops iPad.
case_watchos_target_is_ignored() {
    root=$(make_temp_dir)
    write_manifest "${root}" "1" "1" "${WATCH_TARGET}"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer false

    write_manifest "${root}" "1,2" "1,2" "${WATCH_TARGET}"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer true
}

# No key means XcodeGen's iOS default, "1,2".
case_missing_key_means_ipad() {
    root=$(make_temp_dir)
    write_manifest "${root}" "" ""
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer true

    write_manifest "${root}" "1" ""
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer true
}

case_trailing_comment_and_quotes() {
    root=$(make_temp_dir)
    write_manifest "${root}" "1" "1"
    rewrite_family "${root}" '"1"' "'1, 2' # both"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer true

    write_manifest "${root}" "1" "1"
    rewrite_family "${root}" '"1"' '"1" # iPad later: "1,2"'
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer false
}

# iOS named in a list, flow or block, still counts as an iOS target.
case_ios_in_a_platform_list() {
    root=$(make_temp_dir)
    printf '%s\n' \
        'targets:' \
        '  Flow:' \
        '    type: framework' \
        '    platform: [macOS, iOS]' \
        '    settings:' \
        '      base:' \
        '        TARGETED_DEVICE_FAMILY: "1,2"' >"${root}/project.yml"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer true

    printf '%s\n' \
        'targets:' \
        '  Block:' \
        '    type: application' \
        '    supportedDestinations:' \
        '      - iOS' \
        '      - macOS' \
        '    settings:' \
        '      base:' \
        '        TARGETED_DEVICE_FAMILY: "1,2"' >"${root}/project.yml"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer true

    printf '%s\n' \
        'targets:' \
        '  Mac:' \
        '    type: application' \
        '    supportedDestinations:' \
        '      - macOS' \
        '    settings:' \
        '      base:' \
        '        TARGETED_DEVICE_FAMILY: "1,2"' >"${root}/project.yml"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_answer false
}

# The real manifest, read-only: the template ships iPhone and iPad on both targets.
case_reads_the_checkout_by_default() {
    capture "${BASH}" "${TARGETS_IPAD_SH}"
    assert_exit 0
    grep -qxE 'true|false' "${CASE_DIR}/stdout" || _fail "stdout is not true or false"
}

case_unknown_argument() {
    capture "${BASH}" "${TARGETS_IPAD_SH}" --bogus
    assert_exit 1
    assert_first_stderr_line ERR_IPAD_USAGE
    assert_stderr_contains "unknown argument '--bogus'"
    assert_stderr_contains "Next: usage: scripts/targets-ipad.sh [--root DIR]"
}

case_root_missing() {
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${CASE_DIR}/nowhere"
    assert_exit 1
    assert_first_stderr_line ERR_IPAD_USAGE
    assert_stderr_contains "does not exist"
}

case_manifest_missing() {
    root=$(make_temp_dir)
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_IPAD_MANIFEST_MISSING
    assert_stderr_contains "Expected:"
    assert_stderr_contains "Actual:"
    assert_stderr_contains "Next:"
}

case_no_targets() {
    root=$(make_temp_dir)
    printf '%s\n' 'name: MyApp' 'options:' '  bundleIdPrefix: com.example' >"${root}/project.yml"
    capture "${BASH}" "${TARGETS_IPAD_SH}" --root "${root}"
    assert_exit 1
    assert_first_stderr_line ERR_IPAD_NO_TARGETS
    [ ! -s "${CASE_DIR}/stdout" ] || _fail "stdout is not empty on a failure"
}

run_case "the shipped \"1,2\" on both targets prints true" case_shipped_both_families
run_case "\"1\" on every iOS target prints false" case_iphone_only
run_case "one iOS target with 2 prints true" case_mixed_ios_families
run_case "a watchOS target's family 4 is ignored" case_watchos_target_is_ignored
run_case "an iOS target with no family key prints true" case_missing_key_means_ipad
run_case "a trailing comment and quotes are stripped" case_trailing_comment_and_quotes
run_case "iOS in a platform or supportedDestinations list counts" case_ios_in_a_platform_list
run_case "with no --root, it reads the checkout's project.yml" case_reads_the_checkout_by_default
run_case "an unknown argument fails ERR_IPAD_USAGE" case_unknown_argument
run_case "a --root that does not exist fails ERR_IPAD_USAGE" case_root_missing
run_case "no project.yml fails ERR_IPAD_MANIFEST_MISSING" case_manifest_missing
run_case "a project.yml with no target fails ERR_IPAD_NO_TARGETS" case_no_targets
finish
