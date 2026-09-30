#!/usr/bin/env bash
# The two dependency bots open pull requests the PR-title check accepts, and wait the
# same number of days after a release before opening one — so neither bot's PRs fail
# `Validate PR title` and neither pulls a release the other still holds back
# (.claude/rules/project.md, Toolchain Pinning).
#
#   scripts/checks/dependency-bots-agree.sh [--root DIR]
#
# Files, each optional: <root>/.github/dependabot.yml; the JSON Renovate configs
# <root>/renovate.json, .github/renovate.json, .gitlab/renovate.json, .renovaterc, and
# .renovaterc.json (RENOVATE_JSON below); and <root>/.github/workflows/*.yml|*.yaml.
# A JSON5 Renovate config (renovate.json5, .github/renovate.json5,
# .gitlab/renovate.json5, .renovaterc.json5) is not read — the check prints a notice
# naming it — and neither is a `renovate` key in package.json.
#   - the title check: every workflow step that `uses:`
#     amannn/action-semantic-pull-request. Its accepted types are its `with.types`
#     input (split on newlines, spaces, and commas), or the action's default list when
#     the input is absent (DEFAULT_TYPES below). With no such step there is nothing to
#     compare prefixes against, and the prefix rule is skipped with a notice.
#   - prefixes: each Dependabot `updates` entry states `commit-message.prefix` (and
#     `prefix-development`, when present, is checked the same way; a one-level flow
#     mapping, `commit-message: { prefix: "deps:" }`, is read too); Renovate states
#     `commitMessagePrefix` (every `commitMessagePrefix` and `semanticCommitType`
#     string is checked). A prefix's type is its leading run of letters, digits, `_`,
#     and `-` (`deps:` -> deps, `chore(deps)` -> chore), and every title check must
#     list it; a prefix that starts with anything else (`[deps]`) has no type and
#     fails. A missing prefix fails too: the bot then titles its PRs `Bump …` or
#     guesses a type from the history.
#   - cooldowns: each Dependabot entry states `cooldown.default-days` (block style or a
#     one-level flow mapping), and Renovate
#     states `minimumReleaseAge` (or the deprecated `stabilityDays`); a Renovate age is
#     read as `N day(s)`, `N week(s)`, or a whole number of days in `N hour(s)`. Every
#     stated value must be the same number of days — a Renovate age inside
#     `packageRules` included, since the JSON is read line by line. Dependabot's
#     per-update-type `semver-*-days` are not read.
#   The YAML is read through check_yaml_flatten (scripts/checks/lib.sh) and the JSON
#   line by line, so a value spread over several lines is not seen.
#
# Git work tree: not required — the check reads files under --root, which defaults
# to the checkout containing this script (scripts/checks/lib.sh).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_CHECK_USAGE          unknown argument, or a --root DIR that does not exist
#   ERR_CHECK_BOT_PREFIX     a bot states no commit prefix, or one whose type a title check does not accept
#   ERR_CHECK_BOT_COOLDOWN   a bot states no cooldown, one that cannot be read, or the cooldowns disagree
set -euo pipefail

# shellcheck source=scripts/checks/lib.sh
. "$(dirname "$0")/lib.sh"
check_parse_args "scripts/checks/dependency-bots-agree.sh" "$@"

# amannn/action-semantic-pull-request's types when its `types` input is unset
# (conventional-commit-types, as of v6).
DEFAULT_TYPES="feat fix docs style refactor perf test build ci chore revert"
DEPENDABOT=".github/dependabot.yml"
TAB=$(printf '\t')

RENOVATE_JSON="renovate.json .github/renovate.json .gitlab/renovate.json .renovaterc .renovaterc.json"
RENOVATE_JSON5="renovate.json5 .github/renovate.json5 .gitlab/renovate.json5 .renovaterc.json5"

RENOVATES=()
for rel in ${RENOVATE_JSON}; do
    if [ -f "${CHECK_ROOT}/${rel}" ]; then RENOVATES+=("${rel}"); fi
done
for rel in ${RENOVATE_JSON5}; do
    if [ -f "${CHECK_ROOT}/${rel}" ]; then
        echo "dependency-bots-agree: notice: ${rel} is JSON5, which this check does not read; its prefix and cooldown are not compared."
    fi
done
if [ ! -f "${CHECK_ROOT}/${DEPENDABOT}" ] && [ ${#RENOVATES[@]} -eq 0 ]; then
    check_finish "dependency-bots-agree: no ${DEPENDABOT} or JSON Renovate config; nothing to compare."
    exit 0
fi

# title_types FILE REL — prints `<REL:line>\t<types>` for every title-check step.
title_types() {
    check_yaml_flatten "$1" | awk -F '\t' -v f="$2" -v d="${DEFAULT_TYPES}" '
        function step(p) { sub(/\.(uses|with\.types|with\.types\.\|)$/, "", p); return p }
        $2 ~ /^jobs\.[^.]+\.steps\.[0-9]+\.uses$/ && $3 ~ /^amannn\/action-semantic-pull-request@/ {
            k = step($2); line[k] = $1; n++; order[n] = k
        }
        $2 ~ /^jobs\.[^.]+\.steps\.[0-9]+\.with\.types$/ { k = step($2); has[k] = 1; if ($3 !~ /^[|>]/) types[k] = types[k] " " $3 }
        $2 ~ /^jobs\.[^.]+\.steps\.[0-9]+\.with\.types\.\|$/ { k = step($2); types[k] = types[k] " " $3 }
        END {
            for (i = 1; i <= n; i++) {
                k = order[i]
                t = (k in has) ? types[k] : d
                gsub(/,/, " ", t)
                print f ":" line[k] "\t" t
            }
        }
    '
}

# dependabot_settings FILE REL — prints the settings rows below for each updates entry.
dependabot_settings() {
    check_yaml_flatten "$1" | awk -F '\t' -v f="$2" '
        # flow(n, key, v, line) — the pairs of a one-level `{ a: b, c: d }` mapping.
        function flow(n, key, v, line,    parts, i, k, val, m) {
            sub(/^[[:space:]]*\{/, "", v); sub(/\}[[:space:]]*$/, "", v)
            m = split(v, parts, ",")
            for (i = 1; i <= m; i++) {
                k = parts[i]; sub(/:.*$/, "", k); gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
                val = parts[i]; if (!sub(/^[^:]*:/, "", val)) continue
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); gsub(/^"|"$/, "", val); gsub(/^\047|\047$/, "", val)
                set(n, key "." k, val, line)
            }
        }
        function set(n, key, v, line) {
            if (key == "commit-message.prefix") { prefix[n] = v; pline[n] = line }
            else if (key == "commit-message.prefix-development") { pdev[n] = v; pdline[n] = line }
            else if (key == "cooldown.default-days") { days[n] = v; dline[n] = line }
        }
        {
            if ($2 !~ /^updates\.[0-9]+(\.|$)/) next
            split($2, parts, ".")
            n = parts[2]
            if (!(n in start)) { start[n] = $1; count++; order[count] = n }
            key = $2; sub(/^updates\.[0-9]+\.?/, "", key)
        }
        key == "package-ecosystem" { eco[n] = $3 }
        (key == "commit-message" || key == "cooldown") && $3 ~ /^\{/ { flow(n, key, $3, $1) }
        { set(n, key, $3, $1) }
        END {
            for (i = 1; i <= count; i++) {
                n = order[i]
                who = "Dependabot `" (eco[n] == "" ? "updates[" n "]" : eco[n]) "`"
                print "PREFIX\t" f ":" ((n in pline) ? pline[n] : start[n]) "\t" who " commit-message.prefix\t" prefix[n]
                if (n in pdev) print "PREFIX\t" f ":" pdline[n] "\t" who " commit-message.prefix-development\t" pdev[n]
                if (n in days) print "COOLDOWN\t" f ":" dline[n] "\t" who " cooldown.default-days\t" days[n] " days"
                else print "COOLDOWN\t" f ":" start[n] "\t" who " cooldown.default-days\t"
            }
        }
    '
}

# renovate_settings FILE REL — prints the settings rows below for one JSON config.
renovate_settings() {
    awk -v f="$2" '
        {
            s = $0
            while (match(s, /"(commitMessagePrefix|semanticCommitType|minimumReleaseAge)"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
                m = substr(s, RSTART, RLENGTH)
                s = substr(s, RSTART + RLENGTH)
                key = m; sub(/^"/, "", key); sub(/".*$/, "", key)
                val = m; sub(/"[[:space:]]*$/, "", val); sub(/^.*"/, "", val)
                if (key == "minimumReleaseAge") { print "COOLDOWN\t" f ":" NR "\tRenovate " key "\t" val; cool = 1 }
                else { print "PREFIX\t" f ":" NR "\tRenovate " key "\t" val; if (key == "commitMessagePrefix") prefix = 1 }
            }
            s = $0
            if (match(s, /"stabilityDays"[[:space:]]*:[[:space:]]*[0-9]+/)) {
                m = substr(s, RSTART, RLENGTH); sub(/^.*:[[:space:]]*/, "", m)
                print "COOLDOWN\t" f ":" NR "\tRenovate stabilityDays\t" m " days"; cool = 1
            }
        }
        END {
            if (!prefix) print "PREFIX\t" f "\tRenovate commitMessagePrefix\t"
            if (!cool) print "COOLDOWN\t" f "\tRenovate minimumReleaseAge\t"
        }
    ' "$1"
}

# `<where>\t<types>` for every title-check step.
TITLE_CHECKS=""
for file in "${CHECK_ROOT}"/.github/workflows/*.yml "${CHECK_ROOT}"/.github/workflows/*.yaml; do
    [ -f "${file}" ] || continue
    rows=$(check_read "${file#"${CHECK_ROOT}"/}" title_types "${file}" "${file#"${CHECK_ROOT}"/}")
    if [ -n "${rows}" ]; then
        TITLE_CHECKS="${TITLE_CHECKS}${rows}
"
    fi
done

# `<PREFIX|COOLDOWN>\t<where>\t<which bot setting>\t<value, empty when unstated>`.
SETTINGS=""
if [ -f "${CHECK_ROOT}/${DEPENDABOT}" ]; then
    SETTINGS=$(check_read "${DEPENDABOT}" dependabot_settings "${CHECK_ROOT}/${DEPENDABOT}" "${DEPENDABOT}")
    SETTINGS="${SETTINGS}
"
fi
for rel in ${RENOVATES[@]+"${RENOVATES[@]}"}; do
    rows=$(check_read "${rel}" renovate_settings "${CHECK_ROOT}/${rel}" "${rel}")
    SETTINGS="${SETTINGS}${rows}
"
done

# --- prefixes ---------------------------------------------------------------------
if [ -z "${TITLE_CHECKS}" ]; then
    echo "dependency-bots-agree: no workflow uses amannn/action-semantic-pull-request; not comparing commit prefixes."
else
    while IFS="${TAB}" read -r kind where which value; do
        [ "${kind}" = PREFIX ] || continue
        if [ -z "${value}" ]; then
            check_problem "${where}: ${which} is not set"
            continue
        fi
        type=$(printf '%s\n' "${value}" | sed -E 's/^[[:space:]]*([A-Za-z0-9_-]*).*$/\1/')
        if [ -z "${type}" ]; then
            check_problem "${where}: ${which} \`${value}\` has no type: it does not start with a letter, digit, \`_\`, or \`-\`"
            continue
        fi
        while IFS="${TAB}" read -r title types; do
            [ -n "${title}" ] || continue
            case " ${types} " in
                *[[:space:]]"${type}"[[:space:]]*) ;;
                *) check_problem "${where}: ${which} \`${value}\` has type \`${type}\`, which the title check at ${title} does not accept" ;;
            esac
        done <<EOF
${TITLE_CHECKS}
EOF
    done <<EOF
${SETTINGS}
EOF
fi
check_report ERR_CHECK_BOT_PREFIX "a dependency bot's commit prefix is missing or not a PR-title type" \
    "every Dependabot entry's commit-message.prefix and Renovate's commitMessagePrefix set, with a type the title check's \`types\` input lists" \
    "set the prefix (e.g. \`deps:\`), and add its type to the \`types\` of the workflow step named above in the same change — or change the prefix to a type it already lists"

# --- cooldowns --------------------------------------------------------------------
DAYS_SEEN=""
while IFS="${TAB}" read -r kind where which value; do
    [ "${kind}" = COOLDOWN ] || continue
    if [ -z "${value}" ]; then
        check_problem "${where}: ${which} is not set, so this bot opens a PR the day a release ships"
        continue
    fi
    days=$(printf '%s\n' "${value}" | awk '
        {
            v = tolower($0); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            if (!match(v, /^[0-9]+/)) exit
            n = substr(v, 1, RLENGTH) + 0
            unit = substr(v, RLENGTH + 1); sub(/^[[:space:]]+/, "", unit)
            if (unit ~ /^(d|days?)$/) print n
            else if (unit ~ /^(w|weeks?)$/) print n * 7
            else if (unit ~ /^(h|hours?)$/ && n % 24 == 0) print n / 24
        }
    ')
    if [ -z "${days}" ]; then
        check_problem "${where}: ${which} \`${value}\` is not a whole number of days, weeks, or 24-hour multiples"
        continue
    fi
    DAYS_SEEN="${DAYS_SEEN}${days}${TAB}${where}: ${which} is ${days} day(s)
"
done <<EOF
${SETTINGS}
EOF
if [ "$(printf '%s' "${DAYS_SEEN}" | cut -f 1 | sort -u | grep -c . || true)" -gt 1 ]; then
    while IFS="${TAB}" read -r days text; do
        if [ -n "${text}" ]; then check_problem "${text}"; fi
    done <<EOF
${DAYS_SEEN}
EOF
fi
check_report ERR_CHECK_BOT_COOLDOWN "the dependency bots' release cooldowns are missing or disagree" \
    "every Dependabot entry's cooldown.default-days and Renovate's minimumReleaseAge set to the same number of days (.claude/rules/project.md, Toolchain Pinning)" \
    "set each value named above to the one cooldown the policy states (\`default-days: 7\`, \`\"minimumReleaseAge\": \"7 days\"\`)"

check_finish "dependency-bots-agree: every bot prefix is a PR-title type and every cooldown agrees."
