# Researching the design lock

How an app cut from this template researches its design lock. The research needs nothing
outside this repository and Apple's documentation: Apple's Human Interface Guidelines,
Apple's own apps that do the same task, `designing-ui`'s `SKILL.md`, and
`.claude/rules/ui.md`. `docs/design-system.md` is the template's own research record; its
Brief, Reference lock, Decision ledger, and Sources sections are the shape an app's
record takes.

## Steps

1. **Brief.** Write the brief the lock answers, in the fenced format under "Brief" in
   `docs/design-system.md`, with the product filled in from `AGENTS.md`'s `## Product`:
   what the app is and for whom goes in the first line, the core interaction in Goal, the
   non-goals under Constraints. Replace Tone and "Must remember" with the app's own; keep
   the platform constraints (iOS 27 floor, Xcode 27 SDK, `MyAppUI` also builds for macOS).
   The template's "stay unbranded" override does not carry over: an app's lock is where
   brand is decided.
2. **Read the HIG for what the app shows.** Open the HIG page for each component the
   core interaction uses (lists and tables, sheets, toolbars, text fields, tab bars or
   sidebars) and for layout, color, typography, accessibility, materials, motion, and SF
   Symbols. Record each URL with the date you checked it and the rule it gives.
3. **Look at Apple's own apps doing the same task.** On a simulator or a device, open the
   built-in apps closest to the core interaction (Reminders and Notes for lists, Settings
   for preferences, Mail or Messages for composing) and screenshot the core screen, its
   empty state, its creation or editing screen, and its settings. Record, per screen:
   content margins, row spacing, corner radii, hit-target sizes, type roles, and accent
   use.
4. **Synthesize.** What the sources agree on, where they disagree, and the call for each
   disagreement — one direction, not an average.
5. **Reference lock and decision ledger.** The reference lock is one line each:
   - **Primary reference/direction** — the one screen or HIG pattern the app follows;
   - **Preserve** — what the system already does that the app keeps;
   - **Borrow only** — each specific element taken from elsewhere, with its source;
   - **Role rules** — what the accent, red, and secondary styles may mark, and that color
     is never the only signal;
   - **Media strategy** — symbols, images, illustration, or none;
   - **Reject** — directions considered and ruled out;
   - **Token commitments** — background, type, accent, spacing, radius, minimum hit
     target, motion, shadows and materials.

   The ledger has one row (Decision, Source, Rule/role, Why) per lock field.
6. **Write the record, then the lock.** Rewrite `docs/design-system.md` in place for the
   app as the research record: the brief and the product it came from under Brief, the
   HIG pages and the Apple-app screens reviewed under Sources with the checked date, and
   the ledger with each rejected direction and why it lost. Then rewrite
   `design-lock.md`'s "The lock", beside this file, as one value per field. Choices the
   owner has not made and claims not yet checked (`Unverified:`) go in the pull request
   as open questions; the owner reviews the lock there. Never cite a page you did not
   open.
7. **Implement and look.** Land the values where `design-lock.md` says, then take the
   screenshot set `.claude/rules/ui.md` › Verifying a screen names and compare it
   against the lock. Fix drift before the pull request, or name it there as accepted.

## Keep out of the lock

- Tokens taken from a web style: a hex palette or a web font stack is not an iOS color
  or text style.
- A value copied from one reference: every value traces to the synthesis, a user
  constraint, or a HIG rule.
- Anything that fights the platform — a custom bar that replaces a standard one, a fixed
  font size, a color that only works in one appearance.
