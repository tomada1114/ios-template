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

## Design Philosophy

Every choice in this template has a reason. If you disagree with a decision,
you know exactly what to change and why it was there in the first place.

### Why XcodeGen with a gitignored `.xcodeproj`?

`project.yml` is declarative, diffable, and safely editable by both humans and
AI agents; a raw `pbxproj` is a UUID graph that merge conflicts and agents can
silently corrupt. The generated project is treated like a lockfile-derived
artifact: regenerate, never hand-edit ([`project.yml`](project.yml), `just generate`).
Trade-off: XcodeGen is a third-party tool with its own bus factor — but the
manifest is simple enough to migrate away from if that ever matters.

### Why a thin app shell + local Swift package?

[`App/`](App/MyAppApp.swift) contains only the `@main` entry point, the composition
root, and resources. Everything real lives in the local package under
[`Packages/`](Packages), so its tests run with plain `swift test`. The package also
builds for macOS for exactly that reason: `swift test` runs on the host in seconds,
with no simulator boot and no signing
([docs/architecture.md › Why the package also builds for macOS](docs/architecture.md#why-the-package-also-builds-for-macos)).
Precedent: pointfreeco's isowords.

### Why the Core/UI/Platform split and a coverage floor on Core only?

`MyAppCore` holds all logic and never imports a UI, persistence, or OS-integration
framework (the list is in [`.swiftlint.yml`](.swiftlint.yml)'s `no_ui_import_in_core`,
and `ArchitectureBoundaryTests` holds it a second time); `MyAppUI` holds thin views;
`MyAppPlatform` holds the adapters that talk to the OS — the SwiftData repository is
the worked example — each behind a protocol Core declares, so a test substitutes a
fake and `App/` decides which implementation the app gets. The 80% line and 75%
function coverage floors ([`scripts/coverage.sh`](scripts/coverage.sh)) apply to Core
only, which is what makes a strict numeric gate honest for a UI app instead of an
invitation to write meaningless view tests.

### Why SwiftData behind a repository port?

SwiftData is first-party, so persistence costs no dependency, and it ships with a
versioned schema and a migration plan from day one, so the first model change is a
migration rather than a data loss. Core never sees it: `TodoRepository` is a port in
Core's vocabulary, `SwiftDataTodoRepository` is its adapter, and when the store will not
open `App/` hands the view model `UnavailableTodoRepository`, a null object, so the
app still launches. One contract function,
[`TodoRepositoryContract`](Packages/MyAppKit/Tests/MyAppTestSupport/TodoRepositoryContract.swift),
runs against both the in-memory fake and the real adapter, so the fake cannot drift.

### Why one String Catalog in Core, and English only?

User-facing wording is a decision like any other, so it lives where the coverage
floor sees it: Core view models return `LocalizedStringResource`, and the one
[`Localizable.xcstrings`](Packages/MyAppKit/Sources/MyAppCore/Resources/Localizable.xcstrings)
sits in `MyAppCore` beside them. Views render those resources and carry no literal of
their own. The template ships English alone, since a second language makes every later
string owe a translation and a reviewer; an app that wants one records it as an ADR.
`LocalizationTests` holds Core's keys and English to the catalog.

### Why Swift Testing?

`@Test`, `#expect`, and parameterized `@Test(arguments:)` are the modern default
shipped with the toolchain, and every package suite uses them. XCTest appears exactly
once — in the XCUITest target, [`LaunchUITests/`](LaunchUITests/LaunchTests.swift),
because Apple has not ported UI automation to Swift Testing.

### Why system-first design tokens?

The template must not impose a brand, so its default is neutral:
[`DesignTokens`](Packages/MyAppKit/Sources/MyAppUI/DesignSystem/DesignTokens.swift) is a
small spacing and size scale, while color and type come from the system — semantic
colors and text styles that are right in light, dark, every Dynamic Type size, and
Increase Contrast. Liquid Glass arrives through standard components with no custom glass. Brand belongs to each app's own design lock, an ADR
([docs/design-system.md](docs/design-system.md)).

### Why zero dependencies?

An app template should not impose opinions about networking, persistence, or analytics
frameworks. `Package.swift` declares no package dependency: SwiftData, `URLSession`,
and `UserDefaults` sit behind ports, and you add what you need — a new dependency
needs a human's sign-off and an ADR ([`AGENTS.md`](AGENTS.md)).

### Why Just?

One command — `just check` — runs the same gate locally that CI runs. Just has cleaner
syntax than Make and is a task runner, not a build system, which is exactly what an
Xcode project needs. Every recipe in the [`justfile`](justfile) also works without
Just (see [CONTRIBUTING.md](CONTRIBUTING.md)).

### Why AGENTS.md, `.claude/rules/`, and skills?

AI-assisted development is the norm, not the exception. [`AGENTS.md`](AGENTS.md),
the path-scoped rules under [`.claude/rules/`](.claude/rules), and one skill per kind
of change under [`.agents/skills/`](.agents/skills) give agents the project's
standards, architecture, and hard prohibitions (never lower the coverage floor, never
disable safety lint rules) — reducing review cycles. Skills are authored under
`.agents/skills/`, the path Codex CLI reads, and `just agents-sync` mirrors them
byte-for-byte into `.claude/skills/`, the path Claude Code reads.

### Why an ADR tree that ships empty?

The template's own decisions are the ones above, and this section is where they live.
An app cut from the template makes decisions of a different kind — its device family,
where it keeps state, which capabilities and permissions it takes, how it ships — and
records each as an Architecture Decision Record under
[`docs/architecture/`](docs/architecture/README.md), whose index the template ships
empty. `AGENTS.md`'s "Before changing the architecture" names the changes that owe
one. A replaced decision gets a new ADR rather than a rewrite, so the reasoning that
held at the time stays readable.

### Why a gitignored `Config/Local.xcconfig` for device runs, and no distribution pipeline?

The apps cut from this template run on the owner's own iPhone. Your development team
is yours and your machine's, so it stays out of every tracked file: it lives in
`Config/Local.xcconfig`, which is gitignored, which the pre-commit guard refuses, and
which [`Config/Debug.xcconfig`](Config/Debug.xcconfig) includes only when it exists.
`just run-device` then builds, installs, and launches from the command line. App Store
or TestFlight distribution is left to the app that needs it
([docs/running-on-device.md](docs/running-on-device.md)).

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
- [Architecture](docs/architecture.md) — the layers, ports and adapters, and the
  reasoning behind them
- [Architecture Decisions](docs/architecture/README.md) — the app's ADR index and its
  roadmap
- [Design System](docs/design-system.md) — the default tokens and the research behind
  them
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
