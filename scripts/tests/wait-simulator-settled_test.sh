#!/usr/bin/env bash
# Tests for scripts/wait-simulator-settled.sh. xcrun, ps, sleep, date, and sysctl are
# stubbed in every case, so no case boots a simulator, waits in real time, or sees the
# host's own processes:
#   - `xcrun simctl list devices` prints the case's devices file, and `simctl bootstatus`
#     exits with the code in its bootstatus-exit file;
#   - `ps -Ao pid=,comm=` prints the comm file and `ps -o command= -p PID` the argv.PID
#     file: two launchd_sim processes, this device's (pid 100) and another booted
#     simulator's (pid 200), beside host processes;
#   - `ps -Ao pid=,ppid=,time=` prints the next listing from samples/ and moves it aside
#     (the last one stays, so it repeats);
#   - `sleep` advances a fake clock that `date +%s` reads.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT

SCRIPT="${REPO_ROOT}/scripts/wait-simulator-settled.sh"
UDID="1A2B3C4D-2222-3333-4444-5555555555EF"
OTHER_UDID="99999999-8888-7777-6666-555555555555"
RUNTIME="/Library/Developer/CoreSimulator/Volumes/iOS_27A/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime/Contents/Resources/RuntimeRoot"
DEVICES="/Users/dev/Library/Developer/CoreSimulator/Devices"

# setup [STATE] — installs the stubs, with this device in STATE (Shutdown by default).
setup() {
    mkdir "${CASE_DIR}/samples" "${CASE_DIR}/used"
    echo 0 >"${CASE_DIR}/clock"
    echo 0 >"${CASE_DIR}/bootstatus-exit"
    printf '%s\n' "== Devices ==" "-- iOS 27.0 --" \
        "    iPhone 17 (${OTHER_UDID}) (Booted) " \
        "    iPhone 17 Pro (${UDID}) (${1:-Shutdown}) " >"${CASE_DIR}/devices"
    printf '%s\n' \
        "    1 /sbin/launchd" \
        "  200 ${RUNTIME}/sbin/launchd_sim" \
        "  300 /usr/bin/grep" \
        "  100 ${RUNTIME}/sbin/launchd_sim" \
        "  400 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" >"${CASE_DIR}/comm"
    echo "${RUNTIME}/sbin/launchd_sim ${DEVICES}/${OTHER_UDID}/data/var/run/launchd_bootstrap.plist" >"${CASE_DIR}/argv.200"
    echo "${RUNTIME}/sbin/launchd_sim ${DEVICES}/${UDID}/data/var/run/launchd_bootstrap.plist" >"${CASE_DIR}/argv.100"
    # The case's paths are expanded now, inside single quotes; the rest at run time.
    stub_command xcrun "case \"\$*\" in
    'simctl list devices') cat '${CASE_DIR}/devices' ;;
    'simctl bootstatus '*) read -r code <'${CASE_DIR}/bootstatus-exit'; exit \"\${code}\" ;;
    *) exit 64 ;;
esac"
    stub_command ps "case \"\$*\" in
    '-Ao pid=,comm=') cat '${CASE_DIR}/comm' ;;
    '-o command= -p '*) cat '${CASE_DIR}/argv.'\"\$4\" ;;
    '-Ao pid=,ppid=,time=')
        set -- '${CASE_DIR}'/samples/*
        cat \"\$1\"
        if [ \"\$#\" -gt 1 ]; then mv \"\$1\" '${CASE_DIR}/used/'; fi
        ;;
    *) exit 64 ;;
esac"
    stub_command sleep "read -r now <'${CASE_DIR}/clock'; expr \"\${now}\" + \"\$1\" >'${CASE_DIR}/clock'"
    stub_command date "cat '${CASE_DIR}/clock'"
    stub_command sysctl 'echo "{ 312.50 120.10 40.00 }"'
    unset SIM_SETTLE_INTERVAL SIM_SETTLE_THRESHOLD SIM_SETTLE_SAMPLES SIM_SETTLE_TIMEOUT
    SAMPLE_COUNT=0
    # Cumulative CPU seconds of each process the samples list.
    T101=0 T102=0 T103=0 T201=0 T400=0
}

# cputime SECONDS — the M:SS.ss form macOS `ps -o time=` prints.
cputime() { printf '%d:%02d.00' "$(($1 / 60))" "$(($1 % 60))"; }

# add_sample [LINE...] — the next `ps -Ao pid=,ppid=,time=` listing: the host launchd,
# both launchd_sim processes, this device's tree 100 > 101 > 102 > 103, the other
# simulator's daemon 201, the host's xcodebuild 400 and grep 300 (whose arguments name
# this device's path), at the T* totals, plus any extra LINE.
add_sample() {
    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    printf '%s\n' \
        "    1     0 $(cputime 9000)" \
        "  100     1 $(cputime 1)" \
        "  101   100 $(cputime "${T101}")" \
        "  102   101 $(cputime "${T102}")" \
        "  103   102 $(cputime "${T103}")" \
        "  200     1 $(cputime 1)" \
        "  201   200 $(cputime "${T201}")" \
        "  300     1 $(cputime 0)" \
        "  400     1 $(cputime "${T400}")" \
        "$@" >"${CASE_DIR}/samples/$(printf %03d "${SAMPLE_COUNT}")"
}

# busy — 10 CPU seconds in this device's tree since the last sample: 200% over 5 s.
busy() {
    T101=$((T101 + 4)) T102=$((T102 + 6))
    add_sample
}
# quiet — 0.0 s in this device's tree since the last sample.
quiet() { add_sample; }

samples_taken() {
    grep -c -- '-Ao pid=,ppid=,time=' "${STUB_BIN}/ps.log" || true
}

case_settles_after_cpu_drops() {
    setup
    quiet # the baseline
    busy
    busy
    quiet
    quiet
    quiet
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "wait-simulator-settled: settled after 25 s (simulator CPU 0%)"
    [ "$(samples_taken)" = 6 ] || _fail "expected 6 samples, got $(samples_taken)"
}

case_busy_sample_resets_count() {
    setup
    quiet
    quiet
    quiet
    busy
    quiet
    quiet
    quiet
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "settled after 30 s"
    [ "$(samples_taken)" = 7 ] || _fail "expected 7 samples, got $(samples_taken)"
}

case_ignores_other_simulator_and_host() {
    setup
    quiet
    # Another booted simulator's daemon, the host's xcodebuild, and the grep whose
    # arguments name this device's path all burn CPU; this device's tree does not.
    T201=500 T400=900
    add_sample "  300     1 $(cputime 50)"
    capture env SIM_SETTLE_SAMPLES=1 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "settled after 5 s (simulator CPU 0%)"
    # The same listing seen from the other simulator counts its own daemon: 500 s in 5 s.
    printf '%s\n' "    iPhone 17 (${OTHER_UDID}) (Shutdown) " >"${CASE_DIR}/devices"
    mv "${CASE_DIR}"/used/* "${CASE_DIR}/samples/"
    capture env SIM_SETTLE_SAMPLES=1 SIM_SETTLE_TIMEOUT=1 "${BASH}" "${SCRIPT}" "${OTHER_UDID}"
    assert_stderr_contains "still busy after 5 s (simulator CPU 10000%,"
}

case_counts_deep_descendants() {
    setup
    quiet
    T103=6 # three levels below launchd_sim: 6 s in 5 s is 120%
    add_sample
    capture env SIM_SETTLE_SAMPLES=1 SIM_SETTLE_TIMEOUT=1 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "still busy after 5 s (simulator CPU 120%,"
}

case_new_pid_from_zero_vanished_dropped() {
    setup
    T102=100
    add_sample
    # 102 exits (its 100 s must not count, nor go negative); 104 appears under 101
    # with 3 s, all of it in this interval: 60%.
    printf '%s\n' "    1     0 $(cputime 9000)" "  100     1 $(cputime 1)" "  101   100 $(cputime 0)" \
        "  104   101 $(cputime 3)" >"${CASE_DIR}/samples/002"
    capture env SIM_SETTLE_SAMPLES=1 SIM_SETTLE_TIMEOUT=1 SIM_SETTLE_THRESHOLD=50 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "still busy after 5 s (simulator CPU 60%,"
}

case_bound_exits_zero_still_busy() {
    setup
    quiet
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 \
        31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
        busy
    done
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "wait-simulator-settled: still busy after 300 s (simulator CPU 200%, load 312.50 120.10 40.00); continuing under load"
    [ "$(wc -l <"${CASE_DIR}/stderr" | tr -d ' ')" = 1 ] || _fail "expected one stderr line"
    [ "$(samples_taken)" = 61 ] || _fail "expected 61 samples at 5 s up to 300 s, got $(samples_taken)"
}

case_warm_boot_skips() {
    setup Booted
    quiet
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "wait-simulator-settled: ${UDID} was already booted; not waiting"
    grep -qxF "simctl bootstatus ${UDID} -b" "${STUB_BIN}/xcrun.log" || _fail "bootstatus was not called"
    [ ! -e "${STUB_BIN}/ps.log" ] || _fail "a warm boot sampled ps"
    [ "$(cat "${CASE_DIR}/clock")" = 0 ] || _fail "a warm boot slept"
}

case_cold_boot_waits_lowercase_udid() {
    setup
    quiet
    quiet
    capture env SIM_SETTLE_SAMPLES=1 "${BASH}" "${SCRIPT}" "$(printf '%s' "${UDID}" | tr '[:upper:]' '[:lower:]')"
    assert_exit 0
    assert_stdout_contains "settled after 5 s"
    grep -qxF "simctl bootstatus ${UDID} -b" "${STUB_BIN}/xcrun.log" || _fail "bootstatus did not get the uppercase udid"
}

case_env_overrides() {
    setup
    quiet
    T101=2 # 2 s in 2 s: 100%
    add_sample
    capture env SIM_SETTLE_INTERVAL=2 SIM_SETTLE_THRESHOLD=101 SIM_SETTLE_SAMPLES=1 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stdout_contains "settled after 2 s (simulator CPU 100%)"
}

case_boot_failure() {
    setup
    echo 3 >"${CASE_DIR}/bootstatus-exit"
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 1
    grep -q '^ERR_SETTLE_BOOT_FAILED: ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" || _fail "first stderr line is not ERR_SETTLE_BOOT_FAILED"
}

case_ps_failure_continues() {
    setup
    quiet
    stub_command ps 'exit 1'
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "wait-simulator-settled: ps failed; continuing without waiting"
}

case_no_launchd_sim_says_so() {
    setup
    quiet
    # No launchd_sim names this device: that is said, not reported as a ps failure.
    : >"${CASE_DIR}/argv.100"
    capture "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "wait-simulator-settled: no launchd_sim for ${UDID} among the host's processes; continuing without waiting"
    assert_stderr_not_contains "ps failed"
}

case_list_failure_counts_as_cold() {
    setup Booted
    quiet
    quiet
    stub_command xcrun "case \"\$*\" in 'simctl list devices') exit 1 ;; *) exit 0 ;; esac"
    capture env SIM_SETTLE_SAMPLES=1 "${BASH}" "${SCRIPT}" "${UDID}"
    assert_exit 0
    assert_stderr_contains "\`xcrun simctl list devices\` failed; treating the boot as cold"
    assert_stdout_contains "settled after 5 s"
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
    [ ! -e "${STUB_BIN}/xcrun.log" ] || _fail "a usage error reached xcrun"
}

case_rejects_bad_env() {
    setup
    for value in 0 abc 05 -1; do
        capture env SIM_SETTLE_INTERVAL="${value}" "${BASH}" "${SCRIPT}" "${UDID}"
        assert_exit 1
        grep -q '^ERR_SETTLE_BAD_ENV: SIM_SETTLE_INTERVAL ' <<<"$(head -n 1 "${CASE_DIR}/stderr")" ||
            _fail "SIM_SETTLE_INTERVAL=${value} is not ERR_SETTLE_BAD_ENV"
    done
}

run_case "settles once the CPU stays below the threshold for N samples" case_settles_after_cpu_drops
run_case "a busy sample resets the quiet count" case_busy_sample_resets_count
run_case "ignores another simulator's processes and the host's" case_ignores_other_simulator_and_host
run_case "counts descendants several levels below launchd_sim" case_counts_deep_descendants
run_case "a new pid counts from 0 and a vanished one drops out" case_new_pid_from_zero_vanished_dropped
run_case "at the bound, prints one still-busy line and exits 0" case_bound_exits_zero_still_busy
run_case "a device already booted is not waited for" case_warm_boot_skips
run_case "a cold boot waits, with a lowercase udid uppercased" case_cold_boot_waits_lowercase_udid
run_case "the SIM_SETTLE_* variables override the defaults" case_env_overrides
run_case "a failed boot is ERR_SETTLE_BOOT_FAILED" case_boot_failure
run_case "a failing ps prints one notice and exits 0" case_ps_failure_continues
run_case "no launchd_sim for the device names that, and exits 0" case_no_launchd_sim_says_so
run_case "a failing simctl list counts as a cold boot" case_list_failure_counts_as_cold
run_case "rejects a missing udid, extra arguments, and an option" case_rejects_missing_udid
run_case "rejects a SIM_SETTLE_* value that is not a positive integer" case_rejects_bad_env
finish
