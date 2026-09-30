#!/usr/bin/env bash
# Tests for scripts/guard/paths.sh, a sourced library (not a script directly under
# scripts/), so it gets its own test file named after it. is_blocked_path is pure
# string classification: no case touches the file system or git.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT
# shellcheck source=scripts/guard/paths.sh
. "${REPO_ROOT}/scripts/guard/paths.sh"

# expect_blocked PATH... — every PATH is blocked with a non-empty reason.
expect_blocked() {
    local path
    for path in "$@"; do
        BLOCKED_REASON=""
        if ! is_blocked_path "${path}"; then
            echo "  FAIL: expected ${path} to be blocked" >&2
            exit 1
        fi
        [ -n "${BLOCKED_REASON}" ] || {
            echo "  FAIL: ${path} was blocked without a BLOCKED_REASON" >&2
            exit 1
        }
    done
}

# expect_allowed PATH... — no PATH is blocked, and BLOCKED_REASON is left empty.
expect_allowed() {
    local path
    for path in "$@"; do
        BLOCKED_REASON="stale"
        if is_blocked_path "${path}"; then
            echo "  FAIL: expected ${path} to be allowed, got: ${BLOCKED_REASON}" >&2
            exit 1
        fi
        [ -z "${BLOCKED_REASON}" ] || {
            echo "  FAIL: ${path} was allowed but BLOCKED_REASON was not cleared" >&2
            exit 1
        }
    done
}

case_env_files_blocked() {
    expect_blocked .env App/.env .env.local .env.production config/.env.dev .ENV
}

case_env_samples_allowed() {
    expect_allowed .env.example .env.sample .env.template App/.env.local.example
}

case_envrc_variants_blocked() {
    expect_blocked .envrc.local .envrc.private App/.envrc.dev .ENVRC.Local
}

case_envrc_and_samples_allowed() {
    expect_allowed .envrc App/.envrc .envrc.example .envrc.sample .envrc.template .envrcfile
}

case_claude_local_settings_blocked() {
    expect_blocked .claude/settings.local.json sub/project/.claude/settings.local.json
}

case_claude_shared_settings_allowed() {
    expect_allowed .claude/settings.json settings.local.json docs/claude/settings.local.json
}

case_secrets_segment_blocked() {
    expect_blocked secrets/token.txt App/secrets/config.plist secrets
}

case_secrets_substring_allowed() {
    expect_allowed docs/secrets-policy.md App/mysecrets/x.txt secretsfile
}

case_signing_material_blocked() {
    expect_blocked Signing/DeveloperID.p12 cert.pfx AuthKey_ABC123.p8 \
        MyApp.provisionprofile MyApp.mobileprovision build.keychain login.keychain-db \
        Cert.P12
}

case_named_key_and_credential_files_blocked() {
    expect_blocked private_key.pem certs/signing-key.pem .netrc home/.netrc \
        credentials.json config/secrets.json private-key.txt keys/private-key.der
}

case_local_xcconfig_blocked() {
    expect_blocked Config/Local.xcconfig Local.xcconfig config/local.xcconfig Config/LOCAL.XCCONFIG
}

case_other_xcconfigs_allowed() {
    expect_allowed Config/Debug.xcconfig Config/Release.xcconfig Config/LocalOverrides.xcconfig \
        Config/Local.xcconfig.example
}

case_google_service_info_blocked() {
    expect_blocked App/GoogleService-Info.plist
}

case_google_service_info_any_case_blocked() {
    expect_blocked Config/googleservice-info.PLIST
}

case_public_and_ordinary_files_allowed() {
    expect_allowed App/MyApp.entitlements cert.cer Signing/Request.certSigningRequest \
        Slides.key Package.resolved README.md cert.pem \
        Packages/MyAppKit/Sources/MyAppCore/TodoListViewModel.swift
}

run_case "every .env and .env.* is blocked" case_env_files_blocked
run_case ".env.example, .env.sample, .env.template are allowed" case_env_samples_allowed
run_case ".envrc.* variants are blocked" case_envrc_variants_blocked
run_case "a bare .envrc and .envrc.* samples are allowed" case_envrc_and_samples_allowed
run_case ".claude/settings.local.json is blocked in any directory" case_claude_local_settings_blocked
run_case ".claude/settings.json and other settings.local.json paths are allowed" case_claude_shared_settings_allowed
run_case "a path with a secrets segment is blocked" case_secrets_segment_blocked
run_case "secrets as a substring of a segment is allowed" case_secrets_substring_allowed
run_case "p12, pfx, p8, provisioning profiles, and keychains are blocked" case_signing_material_blocked
run_case "key-named .pem, .netrc, credentials/secrets.json, private-key.* are blocked" case_named_key_and_credential_files_blocked
run_case "a Local.xcconfig is blocked, in any directory or case" case_local_xcconfig_blocked
run_case "every other xcconfig is allowed" case_other_xcconfigs_allowed
run_case "App/GoogleService-Info.plist is blocked" case_google_service_info_blocked
run_case "a GoogleService-Info.plist is blocked in any case" case_google_service_info_any_case_blocked
run_case "entitlements, .cer, CSR, Keynote .key, Package.resolved are allowed" case_public_and_ordinary_files_allowed
finish
