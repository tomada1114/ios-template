---
name: starting-an-app
description: >
  Covers turning this template into a new iOS application with scripts/bootstrap.sh:
  its arguments, the placeholder literals it replaces across git-tracked files, the
  template-only passages it removes, the SwiftFormat pass over the renamed tree,
  re-running it safely, the leftover check, what the new repository keeps untouched,
  and the app's first two decisions - the device family (iPhone only or iPhone and
  iPad, TARGETED_DEVICE_FAMILY, orientations, multiple windows) and the capabilities
  and entitlements it takes (Push Notifications, iCloud, App Groups). Use when
  starting an app from this repository, running or editing scripts/bootstrap.sh, a
  rename left a placeholder behind, filling in AGENTS.md's Product section (what the
  app is, its non-goals) or product-section-filled.sh failing, deciding whether the
  app supports iPad, adding a capability or an entitlements file, CI's bootstrap-smoke
  job fails, or setting up a new repository's labels (just labels) and branch ruleset
  (just ruleset).
---

# Starting an App

**Owns:** turning this repository into a new application — the rename
`scripts/bootstrap.sh` performs, the order around it, the first two decisions after it,
and what the new app keeps.
**Does not own:** how a skill is authored or mirrored (`authoring-skills`); how a
repository script is written or tested (`writing-repo-scripts`); what a gate file may
contain (`changing-gates`); how an ADR is written (`recording-architecture-decisions`);
the README's own prose (`updating-docs`).

<!-- bootstrap:keep-begin -->
This repository ships a bootstrap script on purpose. Its placeholders are a fixed,
small set of literals — `MyApp`, `my-app`, `com.example`, `your-username`, `Your Name`,
and `you@example.com` — with no framework inventory to enumerate, so a single literal
find-and-replace over tracked files is the whole job, and a script does it more
reliably than a checklist would. The script stays in the tree after it runs, so the
record of what it did is a file anyone can still read, and CI's `bootstrap-smoke` job
runs it on a pristine clone on every pull request, so it cannot silently rot.
<!-- bootstrap:keep-end -->

## The order

Rename first, so nothing downstream is written against the template's identity. Then
write the one thing no literal replace can write — `AGENTS.md`'s `## Product` section —
then verify, then hand-edit the rest of what a replace cannot decide, then set up the
new repository on GitHub. `README.md`'s "Using This Template" section is the reader-facing
list of those steps; the script prints the same list when it finishes.

## The rename

```bash
scripts/bootstrap.sh CoolApp --bundle-id-prefix io.example --github-user janedoe \
  --author "Jane Doe" --email jane@example.com [--repo cool-app]
```

- **Arguments** (usage prints the script's header, which also lists its
  `ERR_BOOTSTRAP_<WHAT>` codes). The name is required and PascalCase; the slug defaults
  to its kebab-case (`--repo` overrides it); an omitted option leaves its placeholder.
  A name or slug that itself contains the placeholder is refused, because a later run
  would match it again and corrupt it.
- **The placeholder map** is the six `PH_*` variables at the top of the script. Each
  literal is quote-split there (`'My''App'`) so the replacement never rewrites the
  script's own match sources — a re-run keeps looking for the original placeholders.
  The bundle-id prefix reaches both `project.yml` and `AppLog.subsystem`, which
  `AppLogTests` holds equal.
- **`replace()`** walks `git ls-files`, so only tracked files are touched: commit or
  stage a new file first if it should be renamed too. Binary and empty files are
  skipped. This is why the script refuses to run outside a git checkout
  (`ERR_BOOTSTRAP_NOT_A_REPO`; **BACKGROUND:** `writing-repo-scripts`).
- **Keep markers:** a line containing the keep-begin marker (the text `bootstrap:keep-`
  followed by `begin`) through the next line containing the keep-end marker is never
  rewritten. The passages that explain the placeholders — the script's header,
  `README.md`'s "Using This Template" paragraph, and this skill's opening and
  path-rename bullet — are wrapped in them (an HTML comment in Markdown, a `#` comment
  in shell), so they still name the placeholders after the rename. CI's
  `bootstrap-smoke` asserts they survive, and its leftover check ignores kept lines.
- **Template-only blocks** are the opposite: a passage about the template itself
  (`SECURITY.md`'s notes to a repository created from it) sits between HTML-comment
  lines naming the template-only-begin and template-only-end markers (the `bootstrap:`
  prefix, then that name), and the script deletes each block, markers included. An
  unclosed block stops the run before anything is written. Never spell a marker whole
  in prose: the deletion matches it anywhere on a line.
<!-- bootstrap:keep-begin -->
- **Paths** named after the app (`MyAppCore`, `MyAppUI`, …) are renamed deepest-first,
  skipping `.git/` and build output, and the Xcode project is regenerated.
<!-- bootstrap:keep-end -->
- **Formatting:** after the rename and `xcodegen generate`, the script runs
  `swiftformat .` over the tree. A new name can push a line past the width or change
  the imports' sorted order, so without this the pre-commit hook refuses the bootstrap
  commit (`ERR_BOOTSTRAP_FORMAT_FAILED` if SwiftFormat itself fails).
- **`.template-origin`** records the template commit (line 1) and repository (line 2).
  It is written only when absent, `replace()` never touches it, and `HEAD` is recorded
  only when the history's root commit is the template's first commit (the script's
  `TEMPLATE_ROOT`); a "Use this template" repository or a shallow clone gets `unknown`
  plus the tree to search for. The script's comment above `TEMPLATE_ROOT` holds the
  reasoning; `README.md`'s "Keeping up with template updates" is the reader-facing half.
- **`CHANGELOG.md`** is reset to a one-entry history for the new project, guarded by a
  marker line so a re-run never wipes the new app's own entries.
- **Template-only CI job:** `bootstrap-smoke` and its `Template Bootstrap Smoke` context
  in `.github/rulesets/main.json` are removed together; keep that context one
  comma-terminated line, or the run stops with `ERR_BOOTSTRAP_RETIRE_FAILED`.
- **Idempotent:** running it again with the same name changes nothing further.

When it finishes, it prints next steps, including a leftover check: an `rg -i` over the
app name, slug, bundle-id, and GitHub-user placeholders. Anything it still finds is
either an optional argument you omitted or a string written in a shape the literal
replace cannot see — fix those by hand. `README.md`'s own leftover command spells the
placeholders with `.` wildcards for the same reason the script quote-splits them.

Changing the script means keeping `bootstrap-smoke` green. It bootstraps a clone as
`LongDemoApplication` (long enough to push lines past the width), asserts each effect
above — no placeholder outside kept passages, kept passages intact, no template-only
marker left, the reset, the origin, the retirement, and `product-section-filled.sh` now
*failing* on the renamed tree — then runs `scripts/lint.sh`, `swift test`, and a
simulator `xcodebuild` on it. Its leftover grep is case-insensitive and allows a missing
hyphen, so a spelling the literal replace does not cover fails that job.

The rename leaves the example code in place: the to-do list — its `TodoRepository`
port, the SwiftData adapter, the in-memory fake and the contract suite, the view, and
the view model — is an illustration, not the app. Replace or remove it as one change,
keeping the layers and a port's fake-plus-contract shape.

## Filling in the Product section

`AGENTS.md`'s `## Product` section is the one part of that file about the application
rather than the harness: what the app is and who it is for, the core interaction, the
**Non-goals**, and where those decisions are recorded. Write it immediately after the
rename, before `just check` and before the first feature — an agent picking up an issue
here has no other in-repo answer to "is this in scope?", and a non-goal nobody wrote
down is one an eager implementer reads as a feature.

`scripts/checks/product-section-filled.sh` (`just check-harness`, so `just check` too)
holds both directions off one signal. While `project.yml` still names the app-name
placeholder this is the template, where the section must stay a `TODO:` skeleton —
filling it in here would hand every app cut afterwards a product description that is
not its own. Once the rename has removed that placeholder, no `TODO:` marker may survive
in the section, and it must still name its non-goals. No check can judge the prose that
replaces a marker; that stays with the person who wrote it.

## Choosing the device family

The template ships iPhone and iPad: `TARGETED_DEVICE_FAMILY: "1,2"` in `project.yml`,
on the app target and the UI-test target alike. Narrowing it to `"1"`, iPhone only, is
the common first decision for a phone-only app — every screen then owes one family's
layouts, not two, and the App Store lists it for iPhone. Decide it with the supported
orientations (`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` and `_iPad`) and,
while iPad stays, whether the iPad build supports multiple windows
(`UIApplicationSupportsMultipleScenes`), before the first feature: retrofitting a second
family, or a second window, costs far more than deciding it now.
[references/device-families.md](references/device-families.md) holds what changes in
`project.yml`, in `App/MyAppApp.swift`, and in `LaunchUITests` for each choice. How a
screen adapts to size classes is `building-swiftui-screens`'s subject, not this one.

## Capabilities and entitlements

Every iOS app is sandboxed; that is not a decision. What an app decides is which
capabilities it adds on top: Push Notifications, iCloud, App Groups, Background Modes,
Associated Domains, Sign in with Apple, and the rest. The template ships no
`.entitlements` file and no capability. Adding one, or any capability that needs a
provisioning profile, ties the app to an App ID configuration outside the repository:
it owes an ADR, and it is a signing change that needs the owner's sign-off
(`AGENTS.md` › "Security and human approval") — propose it and name the feature that
needs it, never add it yourself. A capability is declared in `project.yml`
(`entitlements:` on the app target, which XcodeGen writes to the file and wires into
`CODE_SIGN_ENTITLEMENTS`), never in a hand-edited Xcode project, which `just generate`
overwrites. A privacy-gated permission (camera, location, contacts) is its own ADR
trigger and needs its `INFOPLIST_KEY_NS…UsageDescription` build setting in the same
file.

## Recording both decisions

Both steps end in the new app's first two ADRs, written after the rename in the tree
`recording-architecture-decisions` owns: copy `docs/architecture/adr/template.md` to
`docs/architecture/adr/0001-device-family.md` (iPhone only or iPhone and iPad, the
orientations, multiple windows, and why) and `0002-capabilities.md` (the capability set,
empty included, naming the feature that forces each one), each with status Proposed —
only the owner accepts — and add both rows to `docs/architecture/README.md`'s Decisions
table in the same change. Every external claim in them (an App Store rule, what a
capability requires) carries its URL and checked date. The template itself ships no
ADRs; these belong to the app.

## What the new app keeps

Everything below is about the repository rather than the application, so it survives
the rename unchanged and is most of what starting from this template buys:

- **The gate set** — the `justfile` recipes and the scripts under `scripts/` they call,
  and `.github/workflows/`. A red run early in a new project is an argument for fixing
  the code, never for deleting the check that found it. `bootstrap-smoke` is the one
  job about the template rather than the app, so `scripts/bootstrap.sh` removes it and
  its ruleset entry, and `just ruleset` then requires only jobs the app runs.
- **The commit-time guard** — `.githooks/pre-commit` and its "Staged guard" section
  (`scripts/check-staged.sh`, with the rules in `scripts/guard/`), the one layer that
  stops a secret-shaped path or credential before it reaches history. It knows nothing
  about the app, so keep it whatever the app becomes.
- **The skills** under `.agents/skills/` and their mirror in `.claude/skills/`. Drop one
  only when the subject it owns actually leaves the repository — this one, for example,
  once the rename has landed. **REQUIRED:** `authoring-skills` for the mirror loop and
  the `AGENTS.md` Skills table row that `just check-harness` requires for every skill.
- **The label taxonomy** — `.github/labels.yml`, created on the new repository by
  `just labels`. Run it early: GitHub silently drops a label that an issue form applies
  when the repository does not have it yet. **BACKGROUND:** `triaging-issues` for what
  the labels mean.
- **The branch ruleset** — `.github/rulesets/main.json`, applied by a repository admin
  with `just ruleset`. "Use this template" does not copy rulesets, so the new
  repository has no protection on `main` until someone runs it; on a private
  repository it needs a paid GitHub plan. Run it last, after the bootstrap commit is on
  `main`: from then on every change needs a pull request whose required checks pass,
  so the check list must name only jobs the new app still runs.
  On a **private repository**, delete the workflows it cannot run and drop their
  required contexts first — **REQUIRED:** `references/private-repository.md`.

Both `just labels` and `just ruleset` write to the live repository, so they need a
human's sign-off (`AGENTS.md`'s "Security and human approval") — for a brand-new
repository, that is its owner deciding to run them.
