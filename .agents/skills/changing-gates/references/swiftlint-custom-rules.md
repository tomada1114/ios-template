# `.swiftlint.yml` custom rules in detail

The detail behind `changing-gates`' `.swiftlint.yml` section: what each of the two
`custom_rules:` holds and which parts of it are load-bearing.

`no_ui_import_in_core` keeps `MyAppCore` from importing a UI, persistence, or
OS-integration framework, attributed and kind-qualified spellings included. The list
is the module alternation in the rule's `regex:`, thirteen modules today: the UI
frameworks (SwiftUI, UIKit, and the two Mac UI modules the host build could otherwise
reach, Cocoa and the one beneath it), persistence (SwiftData, CoreData, CloudKit), and
OS services (UserNotifications, CoreLocation, Photos, PhotosUI, StoreKit, WidgetKit).
Read the regex itself for the exact spelling. `ArchitectureBoundaryTests` in
`MyAppCoreTests` enforces the same boundary a second way, and its `forbiddenModules`
and the regex change together, in one commit — adding a framework to one and not the
other leaves the boundary enforced once, and `scripts/checks/core-ban-lists-agree.sh`
(`just check-harness`) fails while the two sets differ. Adding to that list strengthens
the gate and is the routine direction; removing from it is weakening one. `os` and
`OSLog` are deliberately not on it, so Core can log (`docs/architecture.md` › Logging);
a test case pins their absence. Its `included` regex names the package and module, so a
new Core-like target means widening it and the test's path. The sibling boundary —
`MyAppUI` and `MyAppPlatform` never importing each other — and the rule that no shipped
module imports `MyAppTestSupport` are held by `ArchitectureBoundaryTests` alone, with
no lint-rule twin.

`no_print_in_sources` rejects `print(`, `debugPrint(`, and `NSLog(` under
`Packages/*/Sources/` and `App/`, because an app launched from the Home Screen has
nowhere to send stdout: shipped code logs through `MyAppCore`'s `AppLog` instead
(`docs/architecture.md` › Logging). Four parts of it are load-bearing, and a widening
edit usually breaks one:

- `match_kinds: [identifier]` spares a `print(` inside a comment or a string literal —
  only a real call site is an identifier;
- `[^\w.]` before the name spares `blueprint(` and member calls like `.print()`;
- `included` and `excluded` are substring matches against the *whole* path, never
  repository-relative globs, so both are written to survive any ancestor directory.
  `included` is `(^|/)(App/[^/]+|Packages/[^/]+/Sources/[^/]+/.+)\.swift$`: its `App/`
  alternative allows exactly one component after `App/`, because the shell is flat, and
  its `Packages/` alternative requires a module directory, so `Packages/*/Tests/` cannot
  satisfy it. Loosen either and a checkout under `~/App/` — or under any path with
  that shape, such as a renamed app's directory — starts matching test files;
- `excluded: '(^|/)[A-Za-z0-9]*Tests/'` is the second line of defence for the same
  worry: no `*Tests/` directory is ever linted by this rule. Test code prints freely.

Matching a path *suffix* rather than a repository-relative path is also what keeps the
rule firing over the temp tree the pre-commit hook exports with
`git checkout-index --prefix=`. It catches a call site, not a deliberate bypass:
`Swift.print(` is out of its reach and is PR review's to catch.
