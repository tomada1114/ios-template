# What `scripts/guard/` blocks, and what it deliberately does not

The detail behind `changing-gates`' `scripts/guard/` section. `scripts/guard/paths.sh`
and `scripts/guard/credentials.sh` remain the authoritative list.

- **Blocked by path:** `.env`, `.env.*`, and `.envrc.*` (except
  `.example`/`.sample`/`.template`), Claude Code's per-user `settings.local.json` under
  `.claude/`,
  any `secrets` path segment, signing material and credential files (`.p12`,
  `.pfx`, `.p8`, provisioning profiles, keychains, `*key*.pem`, `.netrc`,
  `credentials.json`, `secrets.json`, `private-key.*`), `Local.xcconfig` — a
  per-machine signing identity and team, gitignored as well — and
  `GoogleService-Info.plist`, Firebase configuration that is injected at build time
  rather than committed.
- **Blocked by content:** literal patterns for a PEM private-key header, GitHub tokens,
  AWS access key ids, an AWS secret access key assigned to its variable name,
  Anthropic and OpenAI API keys, Slack tokens, Google API keys, Stripe live keys (not
  test keys), and JWTs. It prints the category, never the matched text.
- **Deliberately not blocked:** `.cer` and `.certSigningRequest` (public), `.key`
  (collides with Keynote documents), a bare `.envrc` (direnv projects commit it on
  purpose), a regenerated `Package.resolved`, and anything that needs judgment rather
  than a pattern — no entropy heuristic. Whether a commit *should* contain what it
  contains stays in PR review.

## Adding or removing a pattern

A new pattern starts from a real false negative and lands with a fixture case in
`scripts/tests/guard-paths_test.sh` or `scripts/tests/guard-credentials_test.sh`.
Fixtures are assembled at runtime from pieces that do not match on their own, so no
committed file — the tests included — is secret-shaped; GitHub push protection is the
server-side layer and would refuse such a file too. Removing a pattern or a path rule is
weakening a gate.
