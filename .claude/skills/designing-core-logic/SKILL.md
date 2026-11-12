---
name: designing-core-logic
description: >
  Design judgment for Core - why the code is split into Core, UI, and Platform,
  how view models are owned and survive reentrancy, AppModel as the composition root,
  how a scene's lifecycle phase reaches Core, and how the String Catalog behaves in each
  build. Use when changing a view model's shape or ownership, adding a layer, a port, or
  an AppModel factory, reacting to the app entering the foreground or background,
  finding catalog drift or adding a second language, or questioning one of the
  template's design decisions. Conventions are .claude/rules/core.md.
---

# Designing Core Logic

**Owns:** the reasoning behind how `MyAppCore` is shaped — why the layers are what they
are, how a view model is owned and written for reentrancy, how `App/` and `AppModel`
wire the ports, what a scene's lifecycle phase does in Core, and what each build does
with the String Catalog. **Does not own:** the
conventions a Core change follows — test first, injected time, locale and randomness,
`Tuning`, the view-model shape, errors, wording, and the patterns not adopted
(`.claude/rules/core.md`, loaded with any file under `MyAppCore/`); storage behind a port
(`persisting-data`); an OS service or the HTTP client (`integrating-system-apis`); the
layer rules and what is contract (`AGENTS.md` › Architecture).

The rule says what to do; load this skill when the question is whether the shape itself
should change.

**Worked example of injected time, randomness, and `Tuning`:** `RetryingAPIClient`
(`MyAppCore/Networking`) waits on an `any Clock<Duration>`, draws jitter from an injected
generator, and takes its numbers from `Tuning.retry`, a `RetryPolicy`. The
`RetryPolicy…Tests` suites drive it with `ManualClock` and `SplitMix64` from
`Tests/MyAppTestSupport`, so every backoff wait and a cancellation mid-wait are asserted
with no real time passing. Copy that shape for the next debounce, timeout, or tick; why
the retry sits over `APIClient` is `integrating-system-apis`'
`references/http-client.md` › Retrying a call.

## When to load it

- Changing a view model's shape or who owns it, adding an `AppModel` stored model or
  `make…ViewModel(…)` factory, or changing what a scene's return to the foreground or
  move to the background does: **REQUIRED:**
  [references/view-models.md](references/view-models.md) (reentrancy after an `await`,
  the composition root, the lifecycle).
- Adding a layer, a target, or a Core port, or questioning one of the template's starting
  choices (the package split, MVVM, no dependencies, a pattern
  `.claude/rules/core.md` › Deliberately not adopted rules out): **REQUIRED:**
  [references/design-reasons.md](references/design-reasons.md).
- Finding drift between code and the String Catalog, checking what shipped, or adding a
  second language: [references/localization.md](references/localization.md).

## Changing a design decision

Each of these is a design change (`AGENTS.md` › Before changing the architecture). The
pull request that makes one rewrites the matching reference here — and the
`.claude/rules/core.md` row or rule it replaces — in place, in the present tense, saying
what the current shape could not solve. It never adds a dated entry beside the old
reason, and the owner reviews the rewritten reasoning with the change.
