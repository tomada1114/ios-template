# Why the code is shaped this way

The reasoning behind the layers every app cut from this template starts with. The rules
themselves are `AGENTS.md`'s Architecture section; this file holds only the why. A change
that replaces one of these choices is a design change (`AGENTS.md`'s "Before changing the
architecture") and rewrites its entry here, in the present tense, in place of the old
reason.

## A thin app shell and one local Swift package

`App/` holds only the `@main` entry point, the composition root, and resources.
Everything real lives in the local package `Packages/MyAppKit`, split into `MyAppCore`,
`MyAppUI`, and `MyAppPlatform`, so the module boundaries are ones the compiler enforces,
and the package's tests run under plain `swift test` with no simulator — which is also
why the package builds for macOS (`AGENTS.md`'s Architecture section). Precedent:
pointfreeco's isowords.

## Core, UI, and Platform, and a coverage floor on Core only

`MyAppCore` holds all logic and imports no UI, persistence, or OS-integration framework;
`MyAppUI` holds thin views; `MyAppPlatform` holds the adapters that talk to the OS, each
behind a protocol Core declares, so a test substitutes a fake and `App/` decides which
implementation the app gets. A view cannot reach SwiftData and an adapter cannot reach a
view: the only place both halves meet is `App/`. The 80% line and 75% function coverage
floors (`scripts/coverage.sh`) apply to Core only, which is what makes a strict numeric
gate honest for a UI app instead of an invitation to write meaningless view tests
(`changing-gates`' `references/coverage-floor.md`).

## MVVM with `@MainActor @Observable` view models in Core

The view model is plain Swift that `swift test` drives in milliseconds, so every decision
a screen makes is unit-tested and coverage-gated; the view stays a thin renderer. How a
view model is shaped, owned, and wired: `SKILL.md`'s "Action-shaped view models" and
[view-models.md](view-models.md).

## No package dependencies

`Packages/MyAppKit/Package.swift` declares no package dependency. Every third-party
package is a supply-chain and upgrade cost, and an app template should not impose an
opinion about networking, persistence, or analytics frameworks: SwiftData, `URLSession`,
and `UserDefaults` are first-party and sit behind ports, and an app adds what it needs.
A new dependency needs a human's sign-off (`AGENTS.md`'s "Security and human approval")
and passes the Dependency Policy in `.claude/rules/project.md`.

## Patterns not adopted

- **The Composable Architecture**, or any architecture framework — a dependency and a
  learning curve for what `@Observable` plus ports already give.
- **Combine for state** — the Observation framework replaces it.
- **Singletons or a global service locator** — the composition root passes everything
  explicitly, by named initializer parameters ([view-models.md](view-models.md) › "The
  composition root").
- **Core Data** — SwiftData is its successor on this OS floor (`persisting-data`).

`SKILL.md`'s "Deliberately not adopted" table lists the rest, each with its reason.
