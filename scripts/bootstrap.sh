#!/usr/bin/env bash
# bootstrap:keep-begin
# Template bootstrap: rename every placeholder to your app's identity.
#
#   scripts/bootstrap.sh NewName [--bundle-id-prefix ID] [--github-user USER]
#                                [--author "Full Name"] [--email ADDRESS] [--repo slug]
#
# Replaces (in all git-tracked text files):
#   MyApp        -> NewName            (also MyAppKit/MyAppCore/MyAppUI/MyAppPlatform/
#                                      MyAppTestSupport/MyAppApp/MyAppLaunchUITests)
#   my-app       -> repo slug          (default: kebab-case of NewName)
#   com.example  -> --bundle-id-prefix (kept if omitted; also AppLog.subsystem)
#   your-username / Your Name / you@example.com -> optional args (kept if omitted)
#
# Then renames MyApp* paths, regenerates the Xcode project, and runs SwiftFormat over
# the tree (a new name can push a line past the width or change the imports' sorted
# order, and the pre-commit hook would otherwise refuse the bootstrap commit).
# Also removes the template-only passages (from a line naming the template-only-begin
# marker through the next line naming the template-only-end marker — TEMPLATE_ONLY_BEGIN
# and TEMPLATE_ONLY_END below spell them), resets CHANGELOG.md, and removes the
# template-only CI job (bootstrap-smoke) and its required check in
# .github/rulesets/main.json.
# Records the template commit and repository in .template-origin (first run only;
# never rewritten by the rename, and "unknown" when this checkout's history does not
# start at the template's root commit — see the comment above the ORIGIN_FILE block).
# Running it again with the same name is a no-op, so it is safe to re-run
# (values a previous run already replaced are not replaced again).
#
# Passages that explain the placeholders (this header, README's "Using This
# Template", the starting-an-app skill) sit between a keep-begin and a keep-end
# marker line (KEEP_BEGIN and KEEP_END below spell them) and are never
# rewritten, so they still read correctly after the rename.
#
# Git work tree: required — the rename enumerates tracked files (git ls-files), so it
# refuses to run outside one (ERR_BOOTSTRAP_NOT_A_REPO).
#
# Errors (each followed by Expected:/Actual:/Next: lines, exit 1):
#   ERR_BOOTSTRAP_USAGE                  no name, an unknown option, or an option without a value
#   ERR_BOOTSTRAP_BAD_NAME               the name is not PascalCase, or contains the app-name placeholder
#   ERR_BOOTSTRAP_BAD_SLUG               the repo slug contains the slug placeholder
#   ERR_BOOTSTRAP_NOT_A_REPO             not run inside a git work tree
#   ERR_BOOTSTRAP_TEMPLATE_ONLY_UNCLOSED a template-only-begin marker has no template-only-end after it
#   ERR_BOOTSTRAP_RETIRE_FAILED          the bootstrap-smoke job or its ruleset entry could not be removed
#   ERR_BOOTSTRAP_GENERATE_FAILED        xcodegen generate failed
#   ERR_BOOTSTRAP_FORMAT_FAILED          swiftformat failed on the renamed tree
# bootstrap:keep-end
set -euo pipefail

# The placeholder literals are quote-split so replace() below never rewrites
# this script's own match sources — a re-run keeps matching the original
# placeholders instead of whatever a previous run substituted for them.
PH_NAME='My''App'
PH_SLUG='my''-app'
PH_BUNDLE='com''.example'
PH_USER='your''-username'
PH_AUTHOR='Your'' Name'
PH_EMAIL='you''@example.com'
# The keep markers, split for the same reason: replace() would otherwise treat
# the lines below that name them as markers.
KEEP_BEGIN='bootstrap:keep''-begin'
KEEP_END='bootstrap:keep''-end'
# The template-only markers, split so strip_template_only() never deletes this
# script's own lines, and so no line of the renamed tree still names one.
TEMPLATE_ONLY_BEGIN='bootstrap:template''-only-begin'
TEMPLATE_ONLY_END='bootstrap:template''-only-end'

USAGE='usage: scripts/bootstrap.sh NewName [--bundle-id-prefix ID] [--github-user USER] [--author "Full Name"] [--email ADDRESS] [--repo slug]'

fail() { # fail <code> <what failed> <expected> <actual> <next>
    echo "$1: $2" >&2
    echo "Expected: $3" >&2
    printf 'Actual: %s\n' "$4" | sed '2,$s/^/  /' >&2
    echo "Next: $5" >&2
    exit 1
}

usage_fail() { # usage_fail <what failed> <actual> — prints the header, then fails
    # The header comment: lines after the shebang up to the first non-comment line,
    # without the keep-marker lines.
    awk 'NR > 1 && !/^#/ { exit } /bootstrap:keep-/ { next } NR > 1 { sub(/^# ?/, ""); print }' "$0"
    fail ERR_BOOTSTRAP_USAGE "$1" "an app name, then only the options listed above, each with a value" "$2" "${USAGE}"
}

[ $# -ge 1 ] || usage_fail "no app name given" "no arguments"
NEW_NAME="$1"
shift

if ! [[ "${NEW_NAME}" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
    fail ERR_BOOTSTRAP_BAD_NAME "'${NEW_NAME}' is not PascalCase" \
        "a name matching ^[A-Z][A-Za-z0-9]*\$ (e.g. CoolApp)" "'${NEW_NAME}'" \
        "re-run with a PascalCase name: scripts/bootstrap.sh CoolApp …"
fi
if [[ "${NEW_NAME}" == *"${PH_NAME}"* ]]; then
    fail ERR_BOOTSTRAP_BAD_NAME "'${NEW_NAME}' contains the placeholder '${PH_NAME}'" \
        "a name without '${PH_NAME}' in it — a re-run would match it again and corrupt the rename" \
        "'${NEW_NAME}'" "re-run with a different name"
fi

# Default slug: kebab-case of NewName (DemoApp -> demo-app, HTTPServer -> http-server).
DEFAULT_SLUG=$(echo "${NEW_NAME}" | perl -pe 's/([A-Z]+)([A-Z][a-z])/$1-$2/g; s/([a-z0-9])([A-Z])/$1-$2/g' | tr '[:upper:]' '[:lower:]')

BUNDLE_ID_PREFIX=""
GITHUB_USER=""
AUTHOR=""
EMAIL=""
REPO_SLUG="${DEFAULT_SLUG}"

while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-id-prefix | --github-user | --author | --email | --repo)
            [ $# -ge 2 ] || usage_fail "option '$1' needs a value" "'$1' is the last argument"
            ;;
        *) usage_fail "unknown option '$1'" "argument '$1'" ;;
    esac
    case "$1" in
        --bundle-id-prefix) BUNDLE_ID_PREFIX="$2" ;;
        --github-user) GITHUB_USER="$2" ;;
        --author) AUTHOR="$2" ;;
        --email) EMAIL="$2" ;;
        --repo) REPO_SLUG="$2" ;;
    esac
    shift 2
done

if [[ "${REPO_SLUG}" == *"${PH_SLUG}"* ]]; then
    fail ERR_BOOTSTRAP_BAD_SLUG "repo slug '${REPO_SLUG}' contains the placeholder '${PH_SLUG}'" \
        "a slug without '${PH_SLUG}' in it — a re-run would match it again and corrupt the rename" \
        "'${REPO_SLUG}'" "re-run with a different --repo"
fi

cd "$(dirname "$0")/.."

# replace() enumerates git-tracked files, so a checkout without .git cannot be
# bootstrapped (e.g. a GitHub ZIP download, or a clone whose .git was removed).
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]; then
    fail ERR_BOOTSTRAP_NOT_A_REPO "bootstrap.sh needs a git checkout to enumerate files (git ls-files)" \
        "$(pwd) inside a git work tree" "\`git rev-parse --is-inside-work-tree\` is not true there" \
        "clone the repository with git, or re-create the history first: git init && git add -A"
fi

ORIGIN_FILE=".template-origin"

# tracked_text_files_containing <literal> — NUL-separated tracked text files holding
# <literal>, never the recorded origin: a fork of this template can be owned by, or
# named after, one of the placeholder literals above, and a rewritten URL would point
# at a repository that does not exist.
tracked_text_files_containing() {
    local file
    git ls-files -z | while IFS= read -r -d '' file; do
        [ -f "${file}" ] || continue
        [ "${file}" != "${ORIGIN_FILE}" ] || continue
        grep -Iq . "${file}" 2>/dev/null || continue # skip binary and empty files
        grep -qF -- "$1" "${file}" || continue       # leave non-matching files untouched
        printf '%s\0' "${file}"
    done
}

replace() { # replace <from> <to> — literal replacement in all tracked text files,
    # except lines from a KEEP_BEGIN marker line through the next KEEP_END line
    local from="$1" to="$2" file
    [ "${from}" = "${to}" ] && return 0
    tracked_text_files_containing "${from}" | while IFS= read -r -d '' file; do
        FROM="${from}" TO="${to}" KB="${KEEP_BEGIN}" KE="${KEEP_END}" perl -pi -e '
            $keep = 1 if index($_, $ENV{KB}) >= 0;
            s/\Q$ENV{FROM}\E/$ENV{TO}/g unless $keep;
            $keep = 0 if index($_, $ENV{KE}) >= 0;
        ' "${file}"
    done
}

# Checked before anything is written: a begin marker with no end marker after it would
# delete the rest of its file, so the run stops while the tree is still untouched.
# shellcheck disable=SC2016 # the perl program's $ variables are perl's, not the shell's
UNCLOSED=$(tracked_text_files_containing "${TEMPLATE_ONLY_BEGIN}" |
    TB="${TEMPLATE_ONLY_BEGIN}" TE="${TEMPLATE_ONLY_END}" xargs -0 perl -ne '
        $open = $. if index($_, $ENV{TB}) >= 0;
        $open = 0 if $open && index($_, $ENV{TE}) >= 0;
        if (eof) { print "$ARGV:$open\n" if $open; $open = 0; close ARGV }
    ')
if [ -n "${UNCLOSED}" ]; then
    fail ERR_BOOTSTRAP_TEMPLATE_ONLY_UNCLOSED "a template-only block is never closed" \
        "every line naming ${TEMPLATE_ONLY_BEGIN} followed, in the same file, by a line naming ${TEMPLATE_ONLY_END}" \
        "unclosed at: ${UNCLOSED}" \
        "add the missing end-marker line after each file:line listed, then re-run this script (nothing was changed)"
fi

# Record which template commit this app was cut from, so "what has the template
# fixed since?" is one command instead of a two-history read. Decisions encoded here:
#   * Written only when the file is absent. A re-run, and any hand-edit made after
#     merging template changes, therefore survives untouched.
#   * replace() skips it (see above), so the rename cannot rewrite the URL.
#   * HEAD is recorded only when this history really is the template's: its root
#     commit is TEMPLATE_ROOT, the template's first commit, which every clone and fork
#     of the template shares and which no rename touches. GitHub's "Use this template"
#     gives the new repository a fresh root instead — there HEAD is a commit the
#     template has never seen (however many commits follow it) and "origin" is the new
#     app, not the template — so both values are "unknown". A SHA that
#     `git log <sha>..template/main` rejects as an unknown revision is worse than an
#     honest "unknown", so the file names the tree to search the template's history
#     for instead. A shallow clone cannot show its root, so it is "unknown" too.
TEMPLATE_ROOT="825217867f85f1f4f9635db043f08e2f2b89c456"
if [ -e "${ORIGIN_FILE}" ]; then
    echo "==> Keeping the existing ${ORIGIN_FILE}"
else
    ORIGIN_SHA="unknown"
    ORIGIN_URL="unknown"
    ORIGIN_TREE="$(git rev-parse 'HEAD^{tree}' 2>/dev/null || echo unknown)"
    if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" != "true" ] &&
        grep -qx "${TEMPLATE_ROOT}" <<<"$(git rev-list --max-parents=0 HEAD 2>/dev/null)"; then
        ORIGIN_SHA="$(git rev-parse HEAD)"
        ORIGIN_URL="$(git config --get remote.origin.url || echo unknown)"
    fi
    echo "==> Recording the template origin in ${ORIGIN_FILE} (${ORIGIN_SHA})"
    {
        echo "${ORIGIN_SHA}"
        echo "${ORIGIN_URL}"
        echo "# Written once by scripts/bootstrap.sh; a re-run leaves this file alone."
        echo "# Line 1: the template commit this app was created from. Line 2: its repository."
        if [ "${ORIGIN_SHA}" = "unknown" ]; then
            cat <<EOF
# Both are unknown: this checkout's history does not start at the template's root
# commit (or is a shallow clone), so its HEAD is not known to be a template commit and
# "origin" is this app rather than the template. That is what GitHub's "Use this
# template" produces. Find the template commit holding the same files, then fill both
# lines in by hand:
#   git log --format='%H %T' template/main | grep ${ORIGIN_TREE}
EOF
        fi
        echo "# See README.md, \"Keeping up with template updates\"."
    } >"${ORIGIN_FILE}"
fi

# Reset the template's own CHANGELOG history for the new project. Guarded by a
# marker so a re-run (documented as safe) never wipes the new app's entries.
if grep -qF 'Initial template: an iOS 18 SwiftUI app generated by XcodeGen' CHANGELOG.md 2>/dev/null; then
    echo "==> Resetting CHANGELOG.md for the new project"
    cat >CHANGELOG.md <<EOF
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial project scaffold from [ios-template](https://github.com/tomada1114/ios-template)

[Unreleased]: https://github.com/${PH_USER}/${PH_SLUG}/commits/main
EOF
fi

# Retire the template-only CI job. bootstrap-smoke renames a pristine copy of the
# template; once this rename has run there is nothing left for it to rename, so it
# can only fail. Remove the job and its required-check entry together. Guarded by
# their presence, so a re-run (or an app that already removed them) is a no-op.
CI_FILE=".github/workflows/ci.yml"
RULESET_FILE=".github/rulesets/main.json"
SMOKE_JOB='  bootstrap-smoke:'
SMOKE_NAME='Template Bootstrap Smoke'
smoke_job_present() { # the job key in ci.yml, or the job's name in either file
    grep -qxF "${SMOKE_JOB}" "${CI_FILE}" 2>/dev/null && return 0
    grep -qF "${SMOKE_NAME}" "${CI_FILE}" "${RULESET_FILE}" 2>/dev/null
}
if smoke_job_present; then
    echo "==> Retiring the template-only bootstrap-smoke CI job"
    # The job key, then every following line that is blank or indented 4+ spaces,
    # i.e. up to (not including) the next 2-space-indented job key or EOF.
    [ -f "${CI_FILE}" ] && perl -0pi -e 's/^  bootstrap-smoke:\n(?:(?:    [^\n]*)?\n)*//m' "${CI_FILE}"
    # Only the one-line, comma-terminated shape is deleted, so the JSON stays valid;
    # any other shape is left alone and reported below.
    [ -f "${RULESET_FILE}" ] && perl -ni -e 'print unless /^\s*\{ "context": "Template Bootstrap Smoke", "integration_id": \d+ \},\s*$/' "${RULESET_FILE}"
    if smoke_job_present; then
        fail ERR_BOOTSTRAP_RETIRE_FAILED "could not retire the template's bootstrap-smoke job automatically" \
            "no '${SMOKE_JOB}' job in ${CI_FILE} and no \"${SMOKE_NAME}\" in ${CI_FILE} or ${RULESET_FILE}" \
            "still present (anything already removed was left removed):
$(grep -nE "^${SMOKE_JOB}\$|${SMOKE_NAME}" "${CI_FILE}" "${RULESET_FILE}" 2>/dev/null || true)" \
            "remove those lines by hand (keep ${RULESET_FILE} valid JSON), then re-run this script"
    fi
fi

# Remove the passages that describe the template itself (SECURITY.md's notes to a
# repository created from it, for one). Every block is closed (checked above), so each
# deletion stops at its own end marker; a re-run finds no begin marker and does nothing.
TEMPLATE_ONLY_FILES=$(tracked_text_files_containing "${TEMPLATE_ONLY_BEGIN}" | tr '\0' '\n')
if [ -n "${TEMPLATE_ONLY_FILES}" ]; then
    echo "==> Removing template-only passages"
    while IFS= read -r file; do
        [ -n "${file}" ] || continue
        echo "    ${file}"
        TB="${TEMPLATE_ONLY_BEGIN}" TE="${TEMPLATE_ONLY_END}" perl -ni -e '
            $drop = 1 if index($_, $ENV{TB}) >= 0;
            print unless $drop;
            $drop = 0 if index($_, $ENV{TE}) >= 0;
        ' "${file}"
    done <<<"${TEMPLATE_ONLY_FILES}"
fi

echo "==> Replacing placeholders"
replace "${PH_NAME}" "${NEW_NAME}"
replace "${PH_SLUG}" "${REPO_SLUG}"
[ -n "${BUNDLE_ID_PREFIX}" ] && replace "${PH_BUNDLE}" "${BUNDLE_ID_PREFIX}"
[ -n "${GITHUB_USER}" ] && replace "${PH_USER}" "${GITHUB_USER}"
[ -n "${AUTHOR}" ] && replace "${PH_AUTHOR}" "${AUTHOR}"
[ -n "${EMAIL}" ] && replace "${PH_EMAIL}" "${EMAIL}"

echo "==> Renaming ${PH_NAME}* paths"
# Drop any stale generated project first; it is rebuilt below.
rm -rf "${PH_NAME}.xcodeproj" "${NEW_NAME}.xcodeproj"
# -depth renames the deepest entries first, so only basenames need rewriting.
# Skip VCS internals and build artifacts (SwiftPM's Packages/*/.build and the
# derived-data dir build/) — they are regenerable and full of matching paths.
find . -depth -name "*${PH_NAME}*" \
    -not -path "./.git/*" -not -path "*/.build/*" -not -path "./build/*" |
    while IFS= read -r path; do
        base=$(basename "${path}")
        # Unquoted expansions: bash 3.2 (the runners' /bin/bash) treats quotes
        # inside ${var//pat/rep} literally. Both values are validated alphanumeric.
        target="$(dirname "${path}")/${base//${PH_NAME}/${NEW_NAME}}"
        if [ "${path}" != "${target}" ]; then
            mv "${path}" "${target}"
        fi
    done

echo "==> Regenerating Xcode project"
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate || fail ERR_BOOTSTRAP_GENERATE_FAILED "xcodegen generate failed on the renamed project.yml" \
        "\`xcodegen generate\` to exit 0" "it failed; its output is above" "fix project.yml, then run: just generate"
elif command -v mise >/dev/null 2>&1; then
    mise exec -- xcodegen generate || fail ERR_BOOTSTRAP_GENERATE_FAILED "xcodegen generate failed on the renamed project.yml" \
        "\`mise exec -- xcodegen generate\` to exit 0" "it failed; its output is above" \
        "run \`mise trust && mise install\` if mise refused, fix project.yml otherwise, then run: just generate"
else
    echo "warning: xcodegen not found — run 'just generate' after installing tools" >&2
fi

# A new name can push a line past the width or change the imports' sorted order, so the
# renamed tree is formatted here; otherwise the pre-commit hook's swiftformat --lint
# refuses the bootstrap commit.
echo "==> Formatting the renamed tree"
if command -v swiftformat >/dev/null 2>&1; then
    swiftformat . || fail ERR_BOOTSTRAP_FORMAT_FAILED "swiftformat failed on the renamed tree" \
        "\`swiftformat .\` to exit 0" "it failed; its output is above" "fix the file it names, then run: just fmt"
elif command -v mise >/dev/null 2>&1; then
    mise exec -- swiftformat . || fail ERR_BOOTSTRAP_FORMAT_FAILED "swiftformat failed on the renamed tree" \
        "\`mise exec -- swiftformat .\` to exit 0" "it failed; its output is above" \
        "run \`mise trust && mise install\` if mise refused, fix the file it names otherwise, then run: just fmt"
else
    echo "warning: swiftformat not found — run 'just fmt' after installing tools" >&2
fi

echo
echo "Bootstrap complete: ${PH_NAME} -> ${NEW_NAME} (repo slug: ${REPO_SLUG})"
[ -n "${BUNDLE_ID_PREFIX}" ] && echo "  bundle-id prefix: ${BUNDLE_ID_PREFIX}"
echo
echo "Next steps:"
echo "  1. Fill in AGENTS.md's '## Product' section (what the app is, who for, the"
echo "     core interaction, its non-goals) and delete every TODO: marker there —"
echo "     'just check' fails until you do"
echo "     Then fill in the docs/architecture/roadmap.md skeleton (steering-the-roadmap"
echo "     skill); nothing checks that page"
echo "  2. Verify the rename: just install && just check"
echo "  3. Create the label set on the new repository: just labels"
echo "  4. Review the changes: git diff"
echo "  5. Update README.md, SECURITY.md, the rest of AGENTS.md, and CODE_OF_CONDUCT.md"
echo "     for your app, and review LICENSE's copyright line (year and holder)"
echo "  6. Replace or remove the Todo example: its TodoRepository port, SwiftData"
echo "     adapter, fake, contract, view, and view model (keep the layers and the tests)"
echo "  7. Check for leftovers: rg -i '${PH_NAME}|${PH_SLUG}|${PH_BUNDLE}|${PH_USER}'"
echo "     (the passages that explain the placeholders are kept on purpose)"
echo "  8. Commit: git add -A && git commit -m 'chore: bootstrap ${NEW_NAME} from template'"
echo "  9. Optional, repository admin only, after pushing that commit: just ruleset"
echo "     (applies the main branch ruleset, which then requires pull requests)"
