# my-app

[![CI][ci-badge]][ci-workflow]
[![License: MIT][license-mit]](LICENSE)

An iOS 27+ SwiftUI app built with XcodeGen and a local Swift package, with SwiftData
behind a repository port, and quality gates and an agent harness (Claude Code, Codex
CLI) from the first commit. It ships a small to-do list that exercises every seam an
app needs: `@Observable` view models, a port with a SwiftData adapter, a fake and a
contract suite run against both, typed navigation with deep links, and an XCUITest.

<!-- bootstrap:template-only-begin -->
This repository is a template: cut your own app from it with "Use this template" and
`scripts/bootstrap.sh` — jump to [Using This Template](#using-this-template). It is the
iOS sibling of [macos-app-template][macos-app-template],
whose harness it shares.
<!-- bootstrap:template-only-end -->

## Quickstart

Prerequisites: Xcode (the version in `.xcode-version`) **with its iOS platform
installed** (Xcode › Settings › Components), [mise][mise], and
[Just][just] (`brew install mise just`).

```bash
git clone https://github.com/your-username/my-app.git
cd my-app
mise trust     # approve mise.toml once — mise refuses untrusted configs
just install   # pinned tools via mise + git hooks + xcodegen generate
just check     # verify-hooks → fmt → lint → test-scripts → check-harness → test → build
just run       # build, then install and launch the app in the iOS Simulator
```

`just run` boots an iOS Simulator (`SIMULATOR_DEVICE` picks which) and opens
Device Hub with the fresh build running. [docs/getting-started.md](docs/getting-started.md)
walks through the rest.

## How It Is Built

```
App/                      # Thin @main shell: the composition root and resources, no logic
Packages/MyAppKit/        # All real code, a local Swift package that swift test runs on the host
├── Sources/MyAppCore/    # Domain values, view models, ports, wording — coverage-gated
├── Sources/MyAppUI/      # SwiftUI views that render Core state
├── Sources/MyAppPlatform/  # Adapters behind Core ports: SwiftData, URLSession, UserDefaults
└── Tests/                # Swift Testing suites, each port's fake and contract
LaunchUITests/            # The XCUITest launch test
project.yml               # XcodeGen manifest; MyApp.xcodeproj is generated and gitignored
```

[AGENTS.md](AGENTS.md)'s Architecture section holds the layer rules and what is contract.
How each part is built, and why, lives in the skill under
[`.agents/skills/`](.agents/skills) that owns the subject — `designing-core-logic` for
the layers, `persisting-data` for storage, `building-swiftui-screens` and `designing-ui`
for screens, `changing-gates` for the toolchain — indexed by `AGENTS.md`'s Skills table.
There is no separate architecture or roadmap document.

## Development

The everyday recipes; [CONTRIBUTING.md](CONTRIBUTING.md) lists every one, and how to
run each without Just.

| Recipe | What it does |
|---|---|
| `just install` | Install pinned tools, git hooks, and generate the Xcode project |
| `just test` | Package tests on the host Mac, with the coverage floor on `MyAppCore` |
| `just lint` | SwiftFormat, SwiftLint, ShellCheck, actionlint, typos, and the skills mirror |
| `just run` | Build, then launch in the iOS Simulator |
| `just run-device` | Build, then launch on your connected iPhone |
| `just uitest` | The XCUITest launch test on an iOS Simulator |
| `just check` | Everything: verify-hooks → fmt → lint → test-scripts → check-harness → test → build |

## Documentation

- [AGENTS.md](AGENTS.md) — the guide every agent (and contributor) reads first:
  commands, validation, architecture, and what needs a human's sign-off
- [CONTRIBUTING.md](CONTRIBUTING.md) — setup, every `just` recipe, and the pull
  request process
- [Getting Started](docs/getting-started.md) — first run, the simulator and your
  iPhone, and removing the example code
- [Design System](docs/design-system.md) — the research behind the default tokens and
  the design lock
- [Running on Your Own iPhone](docs/running-on-device.md) — `Config/Local.xcconfig`
  and `just run-device`
- [Security Policy](SECURITY.md) — how to report a vulnerability
- [Changelog](CHANGELOG.md) — user-facing changes, release by release

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
   (`scripts/checks/product-section-filled.sh`). The app's direction is that
   section plus its open issues (the `triaging-issues` skill).
4. Verify the rename: `just install && just check`
5. Create the label set on the new repository: `just labels`
   (`.github/labels.yml`; issue forms rely on these labels existing)
6. Update `README.md` (this file), `SECURITY.md`, the rest of `AGENTS.md`, and
   `CODE_OF_CONDUCT.md` for your app (the conduct-reporting contact stays
   `you@example.com` if `--email` was omitted, so check it), and review
   `LICENSE`'s copyright line (`CHANGELOG.md` is reset automatically)
7. Replace or remove the example code — the to-do list: its `TodoRepository`
   port, the SwiftData adapter, the in-memory fake and contract suite, the views,
   and the view model — following the checklist in
   [docs/getting-started.md › Removing the example code](docs/getting-started.md#removing-the-example-code);
   keep the Core/UI/Platform split and the tests
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

[ci-badge]: https://github.com/your-username/my-app/actions/workflows/ci.yml/badge.svg
[ci-workflow]: https://github.com/your-username/my-app/actions/workflows/ci.yml
[license-mit]: https://img.shields.io/badge/license-MIT-blue.svg
[macos-app-template]: https://github.com/tomada1114/macos-app-template
[mise]: https://mise.jdx.dev/
[just]: https://just.systems
