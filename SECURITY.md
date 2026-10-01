# Security Policy

## Reporting a Vulnerability

**Do NOT open a public issue for security vulnerabilities.**

Please report security vulnerabilities through
[GitHub Security Advisories](https://github.com/your-username/my-app/security/advisories/new).

Include:

- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Suggested fix (if available)

## Response

This project is maintained on a best-effort basis and makes no guaranteed response
time. Reports are acknowledged and assessed as maintainer time allows, and a fix
ships in the next release once one is ready.

<!-- bootstrap:template-only-begin -->
A repository created from this template should replace this section with the
commitments its own maintainers can keep.

<!-- bootstrap:template-only-end -->
## Supported Versions

| Version | Supported |
|---|---|
| Latest release | Yes |
| Previous minor | Best effort |

## Supply-Chain Posture

This repository pins every GitHub Action to a full commit SHA, pins CLI tools
in `mise.toml`, runs zizmor and OpenSSF Scorecard, and delays automated
dependency updates with a Dependabot cooldown. Scorecard's Fuzzing and
Packaging checks legitimately read N/A for an iOS app, which ships no
installable package.

CodeQL (`.github/workflows/codeql.yml`) builds the Swift package with
`swift build --package-path Packages/MyAppKit`. It analyzes `MyAppCore`,
`MyAppUI`, and `MyAppPlatform` as compiled for the macOS host (`Package.swift`
declares `.macOS(.v27)`); `App/` (the thin composition root) and code under
`#if os(iOS)` are not analyzed.

`main`'s intended branch protection is defined as code in
[`.github/rulesets/main.json`](.github/rulesets/main.json) (PR required, checks
green, no force-push or deletion) and applied by a repository admin running
`just ruleset` (`scripts/apply-ruleset.sh`). Whether it is actually in force on
this repository is visible only via `gh api repos/{owner}/{repo}/rulesets`, not
from the checkout — rulesets are server-side configuration.

<!-- bootstrap:template-only-begin -->
"Use this template" does not copy rulesets, so a repository created from this
template needs its own admin to apply it.

<!-- bootstrap:template-only-end -->
## Responsible Disclosure

We follow a coordinated disclosure process. We ask that you:

1. Report the issue privately using the method above
2. Allow reasonable time for a fix before public disclosure
3. Avoid exploiting the vulnerability beyond what is necessary to demonstrate it

We will credit reporters in the release notes unless they prefer to remain
anonymous.
