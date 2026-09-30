# shellcheck shell=bash
# Shared helpers for the harness-conformance checks in scripts/checks/. Sourced,
# never executed, so it carries no shebang or `set` line of its own:
#
#   . "$(dirname "$0")/lib.sh"
#   check_parse_args "scripts/checks/x.sh" "$@"     # sets CHECK_ROOT
#   check_require_file "AGENTS.md"
#   check_problem "AGENTS.md:12: ..."               # collect, do not stop
#   check_report ERR_CHECK_X "what failed" "expected" "next"
#   check_finish "x: ok"
#   check_yaml_flatten .github/workflows/ci.yml     # `<line>\t<path>\t<value>` rows
#   rows=$(check_read "ci.yml" some_reader ci.yml)  # a reader failure -> ERR_CHECK_READ_FAILED
#
# Every check reads files under CHECK_ROOT and nothing else. CHECK_ROOT is the
# --root DIR argument when given (tests point it at a fixture tree), otherwise the
# checkout that contains scripts/checks/ — resolved from this file's own location,
# so no git call is needed and the checks also run in a tarball of the template.
#
# Errors raised here (each followed by Expected:/Actual:/Next: lines):
#   ERR_CHECK_USAGE          unknown argument, or a --root DIR that does not exist (exit 1 now)
#   ERR_CHECK_INPUT_MISSING  a file or directory the check reads is absent (exit 1 now)
#   ERR_CHECK_READ_FAILED    a reader run through check_read exited non-zero (exit 1 now)
# A check's own codes are reported through check_report, which lets the check keep
# going; check_finish then exits 1 if anything was reported.

CHECKS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECK_ROOT=""
CHECK_FAILED=0
CHECK_PROBLEMS=""

# check_fail CODE WHAT EXPECTED ACTUAL NEXT — prints one failure block and exits 1.
check_fail() {
    _check_print "$@"
    exit 1
}

# _check_print CODE WHAT EXPECTED ACTUAL NEXT — ACTUAL may span several lines; the
# lines after the first are indented so the block stays readable.
_check_print() {
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    printf 'Actual: %s\n' "$4" | sed '2,$s/^/  /' >&2
    echo "Next: $5" >&2
}

# check_parse_args USAGE_NAME ARGS... — accepts only `--root DIR`.
check_parse_args() {
    local name="$1" usage
    shift
    usage="usage: ${name} [--root DIR]"
    while [ $# -gt 0 ]; do
        case "$1" in
            --root)
                [ $# -ge 2 ] || check_fail ERR_CHECK_USAGE "--root needs a directory" \
                    "--root followed by an existing directory" "no value after --root" "${usage}"
                [ -d "$2" ] || check_fail ERR_CHECK_USAGE "--root directory '$2' does not exist" \
                    "--root followed by an existing directory" "no directory at '$2'" "${usage}"
                CHECK_ROOT=$(cd "$2" && pwd)
                shift
                ;;
            *)
                check_fail ERR_CHECK_USAGE "unknown argument '$1'" \
                    "no arguments, or --root DIR" "argument '$1'" "${usage}"
                ;;
        esac
        shift
    done
    if [ -z "${CHECK_ROOT}" ]; then
        CHECK_ROOT=$(cd "${CHECKS_LIB_DIR}/../.." && pwd)
    fi
}

# check_require_file REL — fails now if CHECK_ROOT/REL does not exist.
check_require_file() {
    [ -e "${CHECK_ROOT}/$1" ] || check_fail ERR_CHECK_INPUT_MISSING "$1 does not exist under ${CHECK_ROOT}" \
        "${CHECK_ROOT}/$1 to exist" "no file or directory at ${CHECK_ROOT}/$1" \
        "run the check from a checkout of this repository, or pass --root DIR"
}

# check_problem TEXT — records one problem for the next check_report.
check_problem() {
    if [ -z "${CHECK_PROBLEMS}" ]; then
        CHECK_PROBLEMS="$1"
    else
        CHECK_PROBLEMS="${CHECK_PROBLEMS}
$1"
    fi
}

# check_report CODE WHAT EXPECTED NEXT — if any problem was recorded since the last
# report, prints one failure block listing all of them (as the Actual: lines),
# marks the check failed, and clears the list. Does not exit.
check_report() {
    [ -n "${CHECK_PROBLEMS}" ] || return 0
    local count
    count=$(printf '%s\n' "${CHECK_PROBLEMS}" | wc -l | tr -d ' ')
    _check_print "$1" "$2 (${count} problem(s))" "$3" "${CHECK_PROBLEMS}" "$4"
    CHECK_FAILED=1
    CHECK_PROBLEMS=""
}

# check_finish OK_MESSAGE — exits 1 if any report was printed, else prints OK_MESSAGE.
check_finish() {
    if [ "${CHECK_FAILED}" = 1 ]; then
        exit 1
    fi
    echo "$1"
}

# check_yaml_flatten FILE — prints one tab-separated `<line>\t<path>\t<value>` row per
# mapping key and list item of the YAML file FILE, so a check can ask "what is at
# jobs.lint.steps.2.run" with awk instead of re-deriving indentation itself.
#   - path: the keys from the document root joined with `.`, a list item counting as
#     its 0-based index (`jobs.lint.steps.0.uses`, `on.pull_request`, `updates.1`).
#   - value: the inline value, with one pair of surrounding quotes removed or else a
#     trailing ` # comment` dropped; empty for a key whose value is a nested block.
#   - a `|`/`>` block scalar prints its indicator as the value, then one row per
#     non-blank content line at `<path>.|`, leading whitespace stripped.
# It is a line-based reader for the block-style YAML GitHub workflows and bot configs
# use, not a YAML parser: anchors, tags, a flow collection spread over several lines
# (its continuation lines are skipped), and a quoted value holding an escaped quote
# are not understood.
check_yaml_flatten() {
    awk '
        function ind(s) { match(s, /^ */); return RLENGTH }
        function clean(v,    e) {
            sub(/^[[:space:]]+/, "", v)
            if (v ~ /^"/) { e = index(substr(v, 2), "\""); if (e > 0) return substr(v, 2, e - 1) }
            if (v ~ /^\047/) { e = index(substr(v, 2), "\047"); if (e > 0) return substr(v, 2, e - 1) }
            sub(/(^|[[:space:]]+)#.*$/, "", v); sub(/[[:space:]]+$/, "", v)
            return v
        }
        # keylen(s) — the length of the mapping key s starts with (quotes included),
        # or 0 when s is not `key:` followed by a space or the end of the line.
        function keylen(s,    q, e) {
            q = substr(s, 1, 1)
            if (q == "\"" || q == "\047") {
                e = index(substr(s, 2), q)
                if (e == 0) return 0
                e = e + 1
            } else {
                if (!match(s, /^[^[:space:]#][^:]*:/)) return 0
                e = RLENGTH - 1
            }
            if (substr(s, e + 1, 1) != ":") return 0
            if (e + 1 < length(s) && substr(s, e + 2, 1) !~ /[[:space:]]/) return 0
            return e
        }
        function path(    p, i) {
            p = ""
            for (i = 1; i <= sp; i++) p = (i == 1 ? sname[i] : p "." sname[i])
            return p
        }
        BEGIN { sp = 0; inblock = 0; contcol = -1 }
        {
            line = $0
            sub(/\r$/, "", line)
            if (inblock) {
                if (line ~ /^[[:space:]]*$/) next
                if (ind(line) > blockcol) {
                    sub(/^[[:space:]]+/, "", line)
                    print NR "\t" blockpath ".|\t" line
                    next
                }
                inblock = 0
            }
            if (line ~ /^[[:space:]]*(#.*)?$/) next
            if (line ~ /^(---|\.\.\.)([[:space:]]|$)/) next
            c = ind(line)
            rest = substr(line, c + 1)
            # A plain or flow value continued on a deeper line is not structure.
            if (contcol >= 0 && c > contcol) next
            contcol = -1
            while (rest ~ /^-([[:space:]]|$)/) {
                while (sp > 0 && (scol[sp] > c || (scol[sp] == c && sitem[sp]))) sp--
                parent = path()
                sp++; scol[sp] = c; sitem[sp] = 1; sname[sp] = count[parent]++
                rest = substr(rest, 2)
                m = ind(rest)
                c = c + 1 + m
                rest = substr(rest, m + 1)
                if (rest == "") { print NR "\t" path() "\t"; next }
            }
            klen = keylen(rest)
            if (klen > 0) {
                key = substr(rest, 1, klen)
                val = substr(rest, klen + 2)
                if (key ~ /^"/ || key ~ /^\047/) key = substr(key, 2, length(key) - 2)
                while (sp > 0 && scol[sp] >= c) sp--
                sp++; scol[sp] = c; sitem[sp] = 0; sname[sp] = key
                v = clean(val)
                print NR "\t" path() "\t" v
                if (v ~ /^[|>][-+0-9]*$/) { inblock = 1; blockcol = c; blockpath = path() }
                else if (v != "") contcol = c
                next
            }
            # A scalar list item (`- ubuntu-latest`), or a line this reader does not model.
            if (sp > 0 && sitem[sp] && scol[sp] < c) {
                print NR "\t" path() "\t" clean(rest)
                contcol = scol[sp]
            }
        }
    ' "$1"
}

# check_read REL CMD... — runs CMD, a reader of the file REL, and prints its stdout.
# If CMD exits non-zero it fails now with ERR_CHECK_READ_FAILED and CMD's first stderr
# line, so an awk or sed error surfaces under the failure contract instead of as a
# bare message. Call it inside `$(…)`: the failure exits that subshell, and the
# assignment's non-zero status then stops the check under `set -e`.
check_read() {
    local rel="$1" out status=0 message
    shift
    out=$("$@" 2>/dev/null) || status=$?
    if [ "${status}" -ne 0 ]; then
        message=$("$@" 2>&1 >/dev/null | head -n 1) || true
        check_fail ERR_CHECK_READ_FAILED "could not read ${rel}" \
            "the reader of ${rel} to exit 0" \
            "exit ${status}: ${message:-no message}" \
            "check that ${rel} is a readable text file, then re-run the check"
    fi
    printf '%s\n' "${out}"
}
