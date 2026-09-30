# iOS App Template

A strict starting point for an iOS app built with SwiftUI, designed to be developed
largely by coding agents (Claude Code, Codex CLI) under human review.

- **iOS 18+, Swift 6, SwiftUI.** XcodeGen generates the project from `project.yml`; all
  code lives in a local Swift package, `Packages/MyAppKit`.
- **Layered for testability.** `MyAppCore` holds domain values, `@Observable` view
  models, and ports (protocols); `MyAppPlatform` holds adapters (SwiftData today);
  `MyAppUI` holds thin SwiftUI views; `App/` only wires them together.
- **A worked example of every seam** — a to-do list with a repository port, a SwiftData
  adapter, an in-memory fake, one contract suite run against both, view-model tests,
  and an XCUITest.
- **Gates from day one** — SwiftLint strict, SwiftFormat, warnings as errors, a coverage
  floor on Core, a pre-commit hook, and CI on every pull request.
- **An agent harness** — `AGENTS.md`, skills under `.agents/skills/` (mirrored for Claude
  Code), sub-agent tiers, and an issue backlog shaped for the `shipping-issues` skill.

The design and the reasoning behind each choice are in
[`docs/architecture.md`](docs/architecture.md). This template is the iOS sibling of
[macos-app-template](https://github.com/tomada1114/macos-app-template), whose harness it is
being brought up to one issue at a time (`AGENTS.md` › Harness status).

## Requirements

- macOS with Xcode (the version in `.xcode-version`) and its **iOS platform** installed
  (Xcode › Settings › Components)
- [mise](https://mise.jdx.dev) — installs the pinned CLI tools in `mise.toml`

## Quick start

```bash
just install   # pinned tools, git hooks, and the generated Xcode project
just test      # package tests on the host Mac, with the coverage floor
just run       # build and launch on an iOS Simulator
just check     # everything CI's lint and test jobs run, plus the simulator build
```

`just` alone lists every recipe.

## Using This Template

1. Click **"Use this template"** on GitHub and clone your new repository
   (the bootstrap script enumerates files with `git ls-files`, so it needs a
   git checkout — a ZIP download must be `git init`-ed first)
2. Run the bootstrap script to rename everything:

   ```bash
   scripts/bootstrap.sh CoolApp \
     --bundle-id-prefix io.example --github-user janedoe \
     --author "Jane Doe" --email jane@example.com
   ```

   <!-- bootstrap:keep-begin -->
   This replaces `MyApp` (and `MyAppKit`/`MyAppCore`/`MyAppUI`/`MyAppPlatform`), `my-app`,
   `com.example`, `your-username`, `Your Name`, and `you@example.com` across
   all tracked files, renames the matching paths, regenerates the Xcode
   project, and re-formats the renamed tree with SwiftFormat. It also removes the
   passages that only describe the template, resets `CHANGELOG.md`, and removes
   the template-only CI job. Omitted optional arguments leave their placeholders
   as-is. This paragraph, and the other passages that explain the placeholders,
   sit between keep markers the script never rewrites, so they still read
   correctly after it runs.
   <!-- bootstrap:keep-end -->
3. Fill in `AGENTS.md`'s `## Product` section: what the app is and who it is
   for, the core interaction, and the **Non-goals** it must not grow — the
   agent instructions have no other in-repo answer to "is this in scope?".
   Delete every `TODO:` marker as you go; `just check` fails while one is left
   (`scripts/checks/product-section-filled.sh`).
   Then fill in the `docs/architecture/roadmap.md` skeleton — the Now, Next,
   and Later outcomes that follow from it (the `steering-the-roadmap` skill);
   nothing checks that page, so its `TODO:` lines stay until you replace them
4. Verify the rename: `just install && just check`
5. Create the label set on the new repository: `just labels`
   (`.github/labels.yml`; issue forms rely on these labels existing)
6. Update `README.md` (this file), `SECURITY.md`, the rest of `AGENTS.md`, and
   `CODE_OF_CONDUCT.md` for your app (the conduct-reporting contact stays
   `you@example.com` if `--email` was omitted, so check it), and review
   `LICENSE`'s copyright line (`CHANGELOG.md` is reset automatically)
7. Replace or remove the example code — the to-do list: its `TodoRepository`
   port, the SwiftData adapter, the in-memory fake and contract suite, the view,
   and the view model; keep the Core/UI/Platform split and the tests
8. Optional, repository admin only: once the bootstrap commit is on `main`,
   protect it with `just ruleset` (`.github/rulesets/main.json`; it requires
   pull requests from then on, and needs a paid plan on a private repository)
9. Private repository only, before step 8: delete
   `.github/workflows/scorecard.yml`, `codeql.yml`, and `dependency-review.yml`
   (they need a public repository or GitHub Advanced Security), and drop the
   `Dependency Review` context from `.github/rulesets/main.json` — otherwise no
   pull request can merge. Details:
   [private-repository.md](.agents/skills/starting-an-app/references/private-repository.md)

To find any placeholders the script left untouched (the pattern uses `.`
wildcards so the rename cannot rewrite this very command into your new names):

```bash
rg -i "my.?app|com\.example|your.username|Your.Name|you@example"
```

### Keeping up with template updates

A repository generated from a GitHub template has no upstream link — the files
are copied once. The bootstrap script therefore writes `.template-origin`: the
template commit your app was created from on line 1, the template repository on
line 2. To pull later template improvements (CI hardening, lint-rule bumps,
workflow fixes) into your app:

```bash
git remote add template https://github.com/tomada1114/ios-template.git
git fetch template
git log --oneline "$(sed -n 1p .template-origin)"..template/main   # what you don't have yet
git cherry-pick <sha>    # or: git merge template/main --allow-unrelated-histories
```

Both lines read `unknown` when the script could not know them honestly: it records
`HEAD` only when the history's root commit is the template's own first commit.
GitHub's "Use this template" gives the new repository a fresh root instead, so its
`HEAD` is not a template commit and its `origin` is your app rather than the template.
The file then names the file tree to look for, so one `git log --format='%H %T'`
over `template/main` finds the commit — fill the two lines in and the command
above works from then on. Update line 1 yourself whenever you adopt template
changes; the script never rewrites an existing file.

Cherry-picking narrowly scoped commits is usually cleaner than a full merge:
the bootstrap rename means most template commits touch files whose names and
contents differ in your repository. Treat the template as a starting point,
not a dependency — adopt the changes that earn their place.

## License

[MIT](LICENSE)
