#!/usr/bin/env bash
# Tests for scripts/guard/credentials.sh, a sourced library (not a script directly
# under scripts/), so it gets its own test file named after it.
#
# Fixture safety: every credential-shaped value is assembled at runtime from pieces
# that do not match on their own (the prefix is split across two quoted strings), so
# this file passes the very guard it tests and GitHub push protection. Never write a
# whole value as one literal here.
set -euo pipefail
# shellcheck source=scripts/tests/lib.sh
. "$(dirname "$0")/lib.sh"
trap cleanup_temp EXIT
# shellcheck source=scripts/guard/credentials.sh
. "${REPO_ROOT}/scripts/guard/credentials.sh"

BODY_40="0123456789abcdefghijABCDEFGHIJ0123456789"
GH_CLASSIC="gh""p_${BODY_40}"
GH_OAUTH="gh""o_${BODY_40}"
GH_FINE_GRAINED="github""_pat_11ABCDEFG0123456789_abcdefghij"
AWS_KEY_ID="AK""IA""ABCDEFGHIJ012345"
AWS_SESSION_KEY_ID="AS""IA""ABCDEFGHIJ012345"
BODY_20="abcdefghijKLMNOPQRST"
AWS_SECRET="wJalrXUtnFEMI/K7MDENG+bPxRfiCY""EXAMPLEKEY"
AWS_SECRET_ENV="AWS_SECRET_ACCESS_KEY""=${AWS_SECRET}"
AWS_SECRET_INI="aws_secret_access_key"" = ${AWS_SECRET}"
ANTHROPIC_KEY="sk-""ant-api03-${BODY_40}"
OPENAI_PROJECT_KEY="sk-""proj-${BODY_40}_x"
OPENAI_LEGACY_KEY="sk-""${BODY_20}T3Blbk""FJ${BODY_20}"
SLACK_BOT="xo""xb-123456789012-1234567890123-${BODY_20}"
SLACK_USER="xo""xp-123456789012-1234567890123-${BODY_20}"
GOOGLE_KEY="AI""za${BODY_20}0123456789abcde"
STRIPE_LIVE="sk""_live_${BODY_20}0123456789"
STRIPE_RESTRICTED="rk""_live_${BODY_20}0123456789"
STRIPE_TEST="sk""_test_${BODY_20}0123456789"
JWT_TOKEN="ey""JhbGciOiJIUzI1NiJ9.ey""JzdWIiOiIxMjM0NTY3ODkwIn0.${BODY_20}_-x"
PEM_RSA="-----BEGIN ""RSA PRIVATE KEY-----"
PEM_PKCS8="-----BEGIN ""PRIVATE KEY-----"
PEM_OPENSSH="-----BEGIN ""OPENSSH PRIVATE KEY-----"

# write_file NAME CONTENT — writes CONTENT into a fresh file under CASE_DIR and prints
# its path.
write_file() {
    printf '%s\n' "$2" >"${CASE_DIR}/$1"
    echo "${CASE_DIR}/$1"
}

# expect_category CATEGORY VALUE — VALUE embedded in ordinary text is detected as
# CATEGORY, and the output is exactly the category name, never the value.
expect_category() {
    local file
    file=$(write_file sample.txt "let config = \"$2\" // pasted by mistake")
    capture credential_category "${file}"
    assert_exit 0
    [ "$(cat "${CASE_DIR}/stdout")" = "$1" ] || _fail "expected stdout to be exactly $1"
    assert_stdout_not_contains "$2" "the credential-shaped value"
    assert_stderr_not_contains "$2" "the credential-shaped value"
}

expect_nothing() {
    capture credential_category "$1"
    assert_exit 1
    [ ! -s "${CASE_DIR}/stdout" ] || _fail "expected no output for a clean file"
}

case_private_key_detected() {
    expect_category private-key "${PEM_RSA}"
    expect_category private-key "${PEM_PKCS8}"
    expect_category private-key "${PEM_OPENSSH}"
}

case_github_tokens_detected() {
    expect_category github-token "${GH_CLASSIC}"
    expect_category github-token "${GH_OAUTH}"
    expect_category github-token "${GH_FINE_GRAINED}"
}

case_aws_key_ids_detected() {
    expect_category aws-access-key-id "${AWS_KEY_ID}"
    expect_category aws-access-key-id "${AWS_SESSION_KEY_ID}"
}

case_aws_secret_access_key_detected() {
    expect_category aws-secret-access-key "${AWS_SECRET_ENV}"
    expect_category aws-secret-access-key "${AWS_SECRET_INI}"
}

# A bare 40-character base64 string, or the variable name without a value, is not
# enough.
case_aws_secret_near_miss_clean() {
    local valueless="export AWS_SECRET_ACCESS_KEY""=read-from-keychain"
    expect_nothing "$(write_file aws.txt "$(printf '%s\n' "checksum ${AWS_SECRET}" "${valueless}")")"
}

case_api_tokens_detected() {
    expect_category anthropic-key "${ANTHROPIC_KEY}"
    expect_category openai-key "${OPENAI_PROJECT_KEY}"
    expect_category openai-key "${OPENAI_LEGACY_KEY}"
    expect_category slack-token "${SLACK_BOT}"
    expect_category slack-token "${SLACK_USER}"
    expect_category google-api-key "${GOOGLE_KEY}"
    expect_category stripe-live-key "${STRIPE_LIVE}"
    expect_category stripe-live-key "${STRIPE_RESTRICTED}"
    expect_category jwt "${JWT_TOKEN}"
}

# One near miss per shape: a prefix without enough body, a Stripe test key, a
# kebab-case slug that starts like an OpenAI key, and a two-segment JWT lookalike.
case_api_token_near_misses_clean() {
    expect_nothing "$(write_file near.txt "$(printf '%s\n' \
        "sk-""ant-api03-short" \
        "sk-""proj-short_value" \
        "sk-""${BODY_40}${BODY_20}" \
        "risk-assessment-for-the-quarterly-review-of-infrastructure-costs" \
        "xo""xb-12345-abc" \
        "AI""za${BODY_20}" \
        "${STRIPE_TEST}" \
        "sk""_live_short" \
        "ey""JhbGciOiJIUzI1NiJ9.ey""JzdWIiOiIxMjM0NTY3ODkwIn0")")"
}

# A binary file (NUL bytes around the value) is scanned too, thanks to grep -a.
case_binary_file_scanned() {
    local file="${CASE_DIR}/blob.bin"
    { printf '\000\001\002'; printf '%s' "${GH_CLASSIC}"; printf '\000\377'; } >"${file}"
    capture credential_category "${file}"
    assert_exit 0
    assert_stdout_contains "github-token"
    assert_stdout_not_contains "${GH_CLASSIC}" "the credential-shaped value"
}

case_swift_source_clean() {
    expect_nothing "${REPO_ROOT}/Packages/MyAppKit/Sources/MyAppCore/TodoListViewModel.swift"
    expect_nothing "$(write_file View.swift 'struct KeyView { let apiKeyName = "GITHUB_TOKEN"; let pem = "-----BEGIN CERTIFICATE-----" }')"
}

case_markdown_clean() {
    expect_nothing "${REPO_ROOT}/README.md"
    local short_prefix="gh""p_abc"
    expect_nothing "$(write_file notes.md "$(printf '%s\n' "# Keys" \
        "Store the token in the keychain; never paste a private key here." \
        "A short prefix like ${short_prefix} is not a token.")")"
}

# The library's own source must pass itself, or it could never be committed.
case_guard_sources_clean() {
    expect_nothing "${REPO_ROOT}/scripts/guard/credentials.sh"
    expect_nothing "${REPO_ROOT}/scripts/guard/paths.sh"
    expect_nothing "${REPO_ROOT}/scripts/check-staged.sh"
    expect_nothing "$0"
}

case_too_short_values_not_detected() {
    expect_nothing "$(write_file short.txt "gh""p_${BODY_40:0:35} ${AWS_KEY_ID:0:19}")"
}

case_unreadable_file_returns_2() {
    capture credential_category "${CASE_DIR}/does-not-exist"
    assert_exit 2
}

run_case "PEM private-key headers are detected as private-key" case_private_key_detected
run_case "classic, OAuth, and fine-grained GitHub tokens are detected" case_github_tokens_detected
run_case "AKIA and ASIA access key ids are detected" case_aws_key_ids_detected
run_case "an AWS secret access key next to its variable name is detected" case_aws_secret_access_key_detected
run_case "a bare 40-char base64 string or a valueless AWS variable yields nothing" case_aws_secret_near_miss_clean
run_case "Anthropic, OpenAI, Slack, Google, Stripe live, and JWT shapes are detected" case_api_tokens_detected
run_case "near misses of each API-token shape yield nothing" case_api_token_near_misses_clean
run_case "a binary file is scanned and the value is not printed" case_binary_file_scanned
run_case "ordinary Swift content yields nothing" case_swift_source_clean
run_case "ordinary Markdown content yields nothing" case_markdown_clean
run_case "the guard's own sources and this test yield nothing" case_guard_sources_clean
run_case "values shorter than a pattern's bound are not detected" case_too_short_values_not_detected
run_case "a missing file returns 2" case_unreadable_file_returns_2
finish
