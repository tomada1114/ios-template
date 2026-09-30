#!/usr/bin/env bash
# Tests for scripts/format-edited-file.sh, the PostToolUse hook: it formats only
# the edited .swift file inside the root, skips everything else, and reports a
# swiftformat failure with exit 2. swiftformat is stubbed; every case uses its own
# temp root, so the real checkout is never touched.
set -euo pipefail

# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SCRIPT="${REPO_ROOT}/scripts/format-edited-file.sh"

payload() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a"}}' "$1"; }

pipe_to_hook() { printf '%s' "$2" | "${SCRIPT}" --root "$1"; }

run_hook() { # run_hook ROOT PAYLOAD
    capture pipe_to_hook "$1" "$2"
}

case_formats_only_the_edited_swift_file() {
    root=$(make_temp_dir)
    mkdir -p "${root}/Sources"
    : >"${root}/Sources/A.swift"
    stub_command swiftformat 'exit 0'
    run_hook "${root}" "$(payload "${root}/Sources/A.swift")"
    assert_exit 0
    [ "$(cat "${STUB_BIN}/swiftformat.log")" = "$(cd "${root}" && pwd -P)/Sources/A.swift" ] ||
        _fail "swiftformat called with: $(cat "${STUB_BIN}/swiftformat.log")"
}

case_unescapes_json_slashes() {
    root=$(make_temp_dir)
    : >"${root}/A.swift"
    stub_command swiftformat 'exit 0'
    run_hook "${root}" "$(payload "${root}/A.swift" | sed 's#/#\\/#g')"
    assert_exit 0
    [ -f "${STUB_BIN}/swiftformat.log" ] || _fail "swiftformat was not called"
}

case_skips_non_swift_paths() {
    root=$(make_temp_dir)
    : >"${root}/README.md"
    stub_command swiftformat 'exit 1'
    run_hook "${root}" "$(payload "${root}/README.md")"
    assert_exit 0
    [ ! -f "${STUB_BIN}/swiftformat.log" ] || _fail "swiftformat ran on a non-Swift path"
}

case_skips_a_payload_without_file_path() {
    root=$(make_temp_dir)
    stub_command swiftformat 'exit 1'
    run_hook "${root}" '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    assert_exit 0
    [ ! -f "${STUB_BIN}/swiftformat.log" ] || _fail "swiftformat ran without a file_path"
}

case_skips_a_file_outside_the_root() {
    root=$(make_temp_dir)
    other=$(make_temp_dir)
    : >"${other}/B.swift"
    stub_command swiftformat 'exit 1'
    run_hook "${root}" "$(payload "${other}/B.swift")"
    assert_exit 0
    [ ! -f "${STUB_BIN}/swiftformat.log" ] || _fail "swiftformat ran outside the root"
}

case_skips_a_missing_file() {
    root=$(make_temp_dir)
    stub_command swiftformat 'exit 1'
    run_hook "${root}" "$(payload "${root}/Gone.swift")"
    assert_exit 0
    [ ! -f "${STUB_BIN}/swiftformat.log" ] || _fail "swiftformat ran on a missing file"
}

case_reports_a_swiftformat_failure() {
    root=$(make_temp_dir)
    : >"${root}/Bad.swift"
    stub_command swiftformat 'echo "error: Unexpected token" >&2; exit 1'
    run_hook "${root}" "$(payload "${root}/Bad.swift")"
    assert_exit 2
    assert_stderr_contains "ERR_FORMAT_FAILED: "
    assert_stderr_contains "Unexpected token"
    assert_stderr_contains "Next: "
}

case_rejects_an_unknown_argument() {
    capture "${SCRIPT}" --bogus
    assert_exit 2
    assert_stderr_contains "ERR_FORMAT_USAGE: "
}

run_case "formats only the edited Swift file" case_formats_only_the_edited_swift_file
run_case "unescapes JSON-escaped slashes" case_unescapes_json_slashes
run_case "skips a non-Swift path" case_skips_non_swift_paths
run_case "skips a payload without file_path" case_skips_a_payload_without_file_path
run_case "skips a file outside the root" case_skips_a_file_outside_the_root
run_case "skips a file that no longer exists" case_skips_a_missing_file
run_case "reports a swiftformat failure with exit 2" case_reports_a_swiftformat_failure
run_case "rejects an unknown argument" case_rejects_an_unknown_argument
finish
