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

Until `scripts/bootstrap.sh` is ported (an open issue), rename by hand: replace `MyApp`
(including `MyAppKit`, `MyAppCore`, `MyAppUI`, `MyAppPlatform`, and their test targets),
`com.example`, and the `Your Name` in `LICENSE`, then fill in `AGENTS.md`'s `## Product`
section.

## License

[MIT](LICENSE)
