# Researching the design lock with /refero-design

How an app cut from this template researches its design-lock ADR. The template ran the
same workflow for its own neutral defaults; `docs/design-system.md` is the worked record
to copy — its brief, query table, reviewed screens, reference lock, and ledger.

## Which path

- **`/refero-design` and the `refero_*` tools are available** (Claude Code with the
  owner's user-level `refero-design` skill and a signed-in Refero MCP server): follow the
  steps below. Neither is a project dependency; nothing in the repository calls them.
- **Either is missing** (Codex CLI, or no Refero account): the rules in `designing-ui`'s
  `SKILL.md` and the HIG pages it cites are the research. Write the lock from them, and
  say in the ADR's Context that research was HIG-only. Never write a Refero ID you did
  not get from a tool call.

## Steps

1. **Brief.** Invoke `/refero-design` and give it the template's brief (the fenced block
   under "Brief" in `docs/design-system.md`) with the product filled in from `AGENTS.md`'s
   `## Product`: what the app is and for whom goes in the first line, the core
   interaction in Goal, the non-goals under Constraints. Replace Tone and "Must remember"
   with the app's own; keep the platform constraints (iOS 27 floor, Xcode 27 SDK,
   `MyAppUI` also builds for macOS). The template's "stay unbranded" override does not
   carry over: an app's lock is where brand is decided.
2. **Research screens and flows on `platform: "ios"`.** Refero's styles cover web pages,
   not iOS app screens, so they are a secondary check at most.
   - `refero_search_screens` for the app's core interaction, its empty state, its
     creation or editing screen, and its settings — five or more queries. Open the
     strongest 6–10 with `refero_get_screen`, and widen one or two with
     `refero_get_similar_screens`.
   - `refero_search_flows` for the core task and for any permission the app requests;
     open the best of each with `refero_get_flow`.
   - Record, per reviewed screen: content margins, row spacing, corner radii, hit-target
     sizes, type roles, and accent use.
3. **Synthesize.** What the references agree on, where they disagree, and the call for
   each disagreement — one direction, not an average.
4. **Reference lock and decision ledger.** In the skill's format: Primary, Preserve,
   Borrow only, Role rules, Media strategy, Reject, Token commitments; and a ledger row
   (Decision, Source, Rule/role, Why) per lock field.
5. **Write the ADR.** Map the research into `docs/architecture/adr/template.md`:

   | Research output | ADR section |
   |---|---|
   | The brief and the product it came from | Context |
   | The reference lock, as one value per `design-lock.md` field | Decision |
   | The ledger, and each rejected direction with why it lost | Considered options |
   | Choices the owner has not made, claims not yet checked (`Unverified:`) | Open questions |
   | Every Refero ID reviewed and every Apple URL cited, with the checked date | Sources |

   Status Proposed; only the owner accepts it.
6. **Implement and look.** Land the values where `design-lock.md` says, then run
   `designing-ui`'s review pass — light, dark, the largest text size, Increase Contrast —
   and compare the screenshots against the reference lock. Fix drift before the pull
   request, or name it there as accepted.

## Keep out of the lock

- Tokens taken from a web style: a hex palette or a web font stack is not an iOS color
  or text style.
- A value copied from one reference: every value traces to the synthesis, a user
  constraint, or a HIG rule.
- Anything that fights the platform — a custom bar that replaces a standard one, a fixed
  font size, a color that only works in one appearance.
