# shellcheck shell=bash
# Path-shaped commit rules: which staged paths are refused on their name alone.
# Sourced, never executed (like scripts/tests/lib.sh, it carries no shebang or `set`
# line of its own):
#
#   . "scripts/guard/paths.sh"
#   if is_blocked_path "App/.env"; then echo "blocked: ${BLOCKED_REASON}"; fi
#
# Read by scripts/check-staged.sh (the pre-commit hook's "Staged guard" section),
# which classifies every staged path here first and only inspects the content of a
# path that passes (scripts/guard/credentials.sh).
#
# Only what the path alone decides lives here. Deliberately NOT blocked:
#   - `.cer` and `.certSigningRequest`: a public certificate and a signing request
#     hold no private key;
#   - `.key`: the extension collides with Keynote documents;
#   - `.env.example`, `.env.sample`, `.env.template` (and the same `.envrc.*`
#     samples): committed, secret-free samples;
#   - a bare `.envrc`: direnv projects commit it on purpose; only `.envrc.*`
#     variants, which by convention hold per-machine values, are refused;
#   - a regenerated file such as `Package.resolved`: committing one is normal, and
#     whether it was hand-edited is not something a path can tell;
#   - every xcconfig but `Local.xcconfig`: `Config/Debug.xcconfig` is committed on
#     purpose and holds no per-machine value (project.yml's `configFiles`).
# A new pattern needs a case in scripts/tests/guard-paths_test.sh.
#
# Basename matches are case-insensitive (`Cert.P12` is as secret as `cert.p12`, and
# the default macOS file system does not tell them apart); the `secrets` segment
# match is exact. Bash 3.2-compatible: lowercasing uses `tr`, not `${var,,}`.

# is_blocked_path PATH — returns 0 when PATH (repository-relative, slash-separated)
# must not be committed, and sets BLOCKED_REASON to why; returns 1 otherwise, with
# BLOCKED_REASON empty.
# shellcheck disable=SC2034 # BLOCKED_REASON is this function's output, read by the caller.
is_blocked_path() {
    local path="$1" name lower
    BLOCKED_REASON=""
    name="${path##*/}"
    lower=$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')

    case "/${path}/" in
        */secrets/*)
            BLOCKED_REASON="a path segment is \`secrets\`"
            return 0
            ;;
    esac

    case "${path}" in
        .claude/settings.local.json | */.claude/settings.local.json)
            BLOCKED_REASON="Claude Code's local settings are per-user, gitignored, and can widen an agent's own permissions"
            return 0
            ;;
    esac

    case "${lower}" in
        .envrc.*)
            case "${lower}" in
                *.example | *.sample | *.template) return 1 ;;
            esac
            BLOCKED_REASON="a direnv variant file (\`.envrc.*\`) can hold real values"
            return 0
            ;;
        .env | .env.*)
            case "${lower}" in
                *.example | *.sample | *.template) return 1 ;;
            esac
            BLOCKED_REASON="an environment file (\`.env\` or \`.env.*\`) can hold real values"
            return 0
            ;;
        *.p12 | *.pfx)
            BLOCKED_REASON="a certificate exported with its private key (PKCS#12)"
            ;;
        *.p8)
            BLOCKED_REASON="a PKCS#8 private key, such as an App Store Connect API key"
            ;;
        *.provisionprofile | *.mobileprovision)
            BLOCKED_REASON="a provisioning profile"
            ;;
        *.keychain | *.keychain-db)
            BLOCKED_REASON="a keychain"
            ;;
        *key*.pem)
            BLOCKED_REASON="a PEM file named as a key"
            ;;
        .netrc)
            BLOCKED_REASON="a .netrc holds login credentials"
            ;;
        credentials.json | secrets.json)
            BLOCKED_REASON="a credentials or secrets file"
            ;;
        private-key.*)
            BLOCKED_REASON="a file named as a private key"
            ;;
        local.xcconfig)
            BLOCKED_REASON="a local xcconfig names a signing identity and team, which are per-machine and gitignored"
            ;;
        googleservice-info.plist)
            BLOCKED_REASON="Firebase configuration (API keys and project identifiers); keep it out of the repository and inject it at build time"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}
