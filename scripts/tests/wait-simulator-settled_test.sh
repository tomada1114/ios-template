#!/usr/bin/env bash
# Tests for scripts/wait-simulator-settled.sh. ps, sleep, date, and sysctl are stubbed in
# every case: `ps` prints the next listing from the case's samples/ directory and moves
# it aside (the last one stays, so it repeats), and `sleep` advances a fake clock that
# `date +%s` reads, so no case waits in real time or sees the host's own processes.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SCRIPT="${REPO_ROOT}/scripts/wait-simulator-settled.sh"
UDID="11111111-2222-3333-4444-555555555555"
OTHER_UDID="99999999-8888-7777-6666-555555555555"
RUNTIME="/Library/Developer/CoreSimulator/Volumes/iOS_27A/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime/Contents/Resources/RuntimeRoot"
DEVICES="/Users/dev/Library/Developer/CoreSimulator/Devices"

# setup — installs the stubs; each case then writes its listings with add_sample.
setup() {
    mkdir "${CASE_DIR}/samples"
    echo 0 >"${CASE_DIR}/clock"
    mkdir "${CASE_DIR}/used"
    # The case's paths are expanded now, inside single quotes; the rest at run time.
    stub_command ps "set -- '${CASE_DIR}'/samples/*
cat \"\$1\"
if [ \"\$#\" -gt 1 ]; then mv \"\$1\" '${CASE_DIR}/used/'; fi"
    stub_command sleep "read -r now <'${CASE_DIR}/clock'; expr \"\${now}\" + \"\$1\" >'${CASE_DIR}/clock'"
    stub_command date "cat '${CASE_DIR}/clock'"
    stub_command sysctl 'echo "{ 312.50 120.10 40.00 }"'
    unset SIM_SETTLE_INTERVAL SIM_SETTLE_THRESHOLD SIM_SETTLE_SAMPLES SIM_SETTLE_TIMEOUT
    SAMPLE_COUNT=0
}

# add_sample LINE... — the next `ps -Ao pcpu=,command=` listing, one process per line.
add_sample() {
    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    printf '%s\n' "$@" >"${CASE_DIR}/samples/$(printf %03d "${SAMPLE_COUNT}")"
}

busy() { add_sample " 95.0 ${RUNTIME}/System/Library/CoreServices/PosterBoard.app/PosterBoard" " 80.0 ${RUNTIME}/usr/libexec/sociallayerd"; }
quiet() { add_sample "  2.0 ${RUNTIME}/usr/libexec/sociallayerd" "  1.0 ${DEVICES}/${UDID}/data/Containers/Bundle/Application/X/MyApp.app/MyApp"; }

ps_calls() { wc -l <"${STUB_BIN}/ps.log" | tr -d " "; }

case_settles_after_cpu_drops() {
    setup
    busy
    busy
    quiet
    quiet
    quiet
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "wait-simulator-settled: settled after 20 s (simulator CPU 3%)"
    [ "$(ps_calls)" = 5 ] || _fail "expected 5 samples, got $(ps_calls)"
}

case_busy_sample_resets_count() {
    setup
    quiet
    quiet
    busy
    quiet
    quiet
    quiet
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "settled after 25 s"
    [ "$(ps_calls)" = 6 ] || _fail "expected 6 samples, got $(ps_calls)"
}

case_ignores_host_processes() {
    setup
    add_sample \
        "350.0 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building" \
        "120.0 /System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds_stores" \
        "  5.0 ${RUNTIME}/usr/libexec/diagnosticd"
    capture env SIM_SETTLE_SAMPLES=1 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "settled after 0 s (simulator CPU 5%)"
}

case_counts_this_device_and_runtime_only() {
    setup
    # Another device's app is not counted; this device's app and a runtime process are.
    add_sample \
        "500.0 ${DEVICES}/${OTHER_UDID}/data/Containers/Bundle/Application/Y/Other.app/Other" \
        " 60.0 ${DEVICES}/${UDID}/data/Containers/Bundle/Application/X/FitnessWidget.appex/FitnessWidget" \
        " 50.0 ${RUNTIME}/usr/libexec/NewsScoringService"
    capture env SIM_SETTLE_SAMPLES=1 SIM_SETTLE_TIMEOUT=1 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "still busy after 5 s (simulator CPU 110%,"
    # The same listing seen from the other device counts its 500% and not the 60%.
    capture env SIM_SETTLE_SAMPLES=1 SIM_SETTLE_TIMEOUT=1 "${BASH}" "${SCRIPT}" "${OTHER_UDID}"
    assert_stderr_contains "simulator CPU 550%,"
}

case_bound_exits_zero_still_busy() {
    setup
    busy
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "wait-simulator-settled: still busy after 300 s (simulator CPU 175%, load 312.50 120.10 40.00); continuing under load"
    [ "$(wc -l <"${CASE_DIR}/stderr" | tr -d ' ')" = 1 ] || _fail "expected one stderr line"
    [ "$(ps_calls)" = 61 ] || _fail "expected 61 samples at 5 s up to 300 s, got $(ps_calls)"
}

case_env_overrides() {
    setup
    add_sample " 40.0 ${RUNTIME}/usr/libexec/amsengagementd"
    capture env SIM_SETTLE_INTERVAL=2 SIM_SETTLE_THRESHOLD=50 SIM_SETTLE_SAMPLES=2 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "settled after 2 s (simulator CPU 40%)"
    capture env SIM_SETTLE_THRESHOLD=40 SIM_SETTLE_TIMEOUT=7 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "still busy after"
}

case_ps_failure_continues() {
    setup
    stub_command ps 'exit 1'
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "wait-simulator-settled: ps failed; continuing without waiting"
}

case_rejects_missing_udid() {
    setup
    capture "${BASH}" "${SCRIPT}"
    assert_exit 1
    grep -q '^ERR_SETTLE_USAGE: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "first stderr line is not ERR_SETTLE_USAGE"
    assert_stderr_contains "Next: "
    capture "${BASH}" "${SCRIPT}" ""
    assert_exit 1
    capture "${BASH}" "${SCRIPT}" "${UDID}" extra
    assert_exit 1
    capture "${BASH}" "${SCRIPT}" --help
    assert_exit 1
    grep -q '^ERR_SETTLE_USAGE: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "an option is not ERR_SETTLE_USAGE"
}

case_rejects_bad_env() {
    setup
    quiet
    for value in 0 abc 05 -1; do
        capture env SIM_SETTLE_INTERVAL="${value}" "${BASH}" "${SCRIPT}" "${UDID}"
        assert_exit 1
        grep -q '^ERR_SETTLE_BAD_ENV: SIM_SETTLE_INTERVAL ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
            _fail "SIM_SETTLE_INTERVAL=${value} is not ERR_SETTLE_BAD_ENV"
    done
}

run_case "settles once the CPU stays below the threshold for N samples" case_settles_after_cpu_drops
run_case "a busy sample resets the quiet count" case_busy_sample_resets_count
run_case "ignores host processes outside the simulator paths" case_ignores_host_processes
run_case "counts only the given device's apps, and every runtime-root process" case_counts_this_device_and_runtime_only
run_case "at the bound, prints one still-busy line and exits 0" case_bound_exits_zero_still_busy
run_case "the SIM_SETTLE_* variables override the defaults" case_env_overrides
run_case "a failing ps prints one notice and exits 0" case_ps_failure_continues
run_case "rejects a missing udid, extra arguments, and an option" case_rejects_missing_udid
run_case "rejects a SIM_SETTLE_* value that is not a positive integer" case_rejects_bad_env
finish
