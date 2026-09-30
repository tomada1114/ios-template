# The coverage floor

Read from [SKILL.md's `scripts/coverage.sh` section](../SKILL.md#scriptscoveragesh)
before touching what `scripts/coverage.sh` measures or how its floors are set.

It gates on line and function coverage of `Sources/MyAppCore/` only, by filtering
llvm-cov's report to that path. `MyAppUI` and `MyAppPlatform` are outside it because a
view or an adapter holds translation rather than a decision (`AGENTS.md`'s
"Architecture") — not because nothing exercises them: `MyAppPlatformTests` runs under
plain `swift test`, so under `just test` and CI's `test` job, against an in-memory
SwiftData store that needs no device and no permission. The filter is a path, not a
target list, so those tests add nothing to the floor. The floors are `readonly COVERAGE_FLOOR=80` (lines) and
`FUNCTION_COVERAGE_FLOOR=75` in the script and nothing else — no environment variable or
flag moves either, so every change is a reviewed diff of this file, and only ever a
raise. The function floor sits lower because llvm-cov counts compiler-generated closures
(an `os.Logger` interpolation) as functions no test evaluates; the script's header
records the value it was set against. The script rejects the environment override it
used to read with `ERR_COVERAGE_OVERRIDE_REMOVED` before any test runs, rather than
silently ignoring it; `scripts/tests/coverage_test.sh` holds that. Adding a new way to
set the floor from a recipe, workflow, or hook is lowering it by another route.
