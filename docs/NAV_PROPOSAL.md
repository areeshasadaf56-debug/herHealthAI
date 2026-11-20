# Navigation proposal (task 2.4) — for owner review

**Status:** design document only. Nothing here is implemented; any change
needs explicit owner approval (Phase 7 gate).

**DECIDED (Phase 7, 2026-11-15):** the owner approved a **variant of
Option B with 6 tabs** — see [Decision](#decision-phase-7-2026-11-15)
below. Implementation has NOT started; building it needs its own
approved phase.

## Current state

One `Scaffold` bottom bar with **8 tabs**, all alive in an `IndexedStack`
(`lib/screens/home_shell.dart`):

| # | Tab | Icon | Short label |
|---|-----|------|-------------|
| 0 | Cycle | moon | Cycle |
| 1 | Ovulation | egg | Ovu |
| 2 | Protection | shield | Prot |
| 3 | PCOS | bubbles | PCOS |
| 4 | Endo | flower | Endo |
| 5 | Learn | book | Learn |
| 6 | Settings | gear | Set |
| 7 | Check-in | heart | Chat |

Sub-navigation also exists *inside* screens (in-tab `_tabButton` rows in
Health Diary, Protection and PCOS screens) and via the app-wide AI
check-in FAB (`LanguageFab` is separate — that one is language only).

## Problems identified in review

1. **8 tabs is above every platform guideline** (Material recommends
   3–5; Apple recommends 3–5, hard maximum ~7). Each tab gets only
   ~12% of the width; the labels were 7.5sp at review time, then raised
   to 10sp (task 2.4) and 11sp (task 2.7, the app's readable floor),
   where they cannot grow further.
2. **Information architecture is flat.** Cycle / Ovulation / PCOS / Endo
   are all "health tracking" surfaces of different depth; Learn and
   Protection are content; Settings is meta. Flat + 8 wide makes
   hierarchy invisible.
3. **Two "entry point" patterns coexist:** the AI check-in is both a
   bottom tab (`Chat`) AND reachable via nav hints / Home cards, which
   dilutes both.
4. Settings contains both "app prefs" and "account + data lifecycle"
   (logout, data & privacy), which deserve separation.

## Options

### Option A — keep 8 tabs, polished (lowest effort, current trajectory)

Keep all 8; rely on the 2.4 fixes (10sp labels, ≥48dp targets,
semantics). Acceptable short-term; does not fix the crowding at 320dp
widths (small phones) where short labels still risk truncation.

### Option B — 5 tabs + "More" sheet (recommended)

Bottom bar: **Home (Cycle) · Protection · Learn · Check-in · Settings**.
Ovulation, PCOS, Endo move under Home as top chips/cards (Home already
links to them) and into a "More" bottom sheet as a fallback.

* Pros: guideline-compliant, labels can be 11sp+ and untruncated, AI
  check-in keeps a first-class slot (matches usage), Settings stops
  competing with health content.
* Cons: Ovulation/PCOS/Endo lose one-tap reachability (mitigation: Home
  quick-cards keep them 2 taps deep); needs an owner IA decision.

### Option C — 4 tabs + AI FAB

Home · Protection · Learn · Settings, AI Check-in as the app-wide FAB
(joins the language FAB).

* Pros: most room per label; AI entry matches the "assistant" pattern.
* Cons: two floating buttons (language + AI) must not collide — layout
  work; AI check-in demoted from tab hurts discoverability of a
  flagship feature.

## Recommendation (superseded by the Decision below — kept for the record)

Option B, implemented in a later approved phase, with:
- unchanged tab order for the five survivors,
- Home gaining a "health tools" section with Ovulation/PCOS/Endo cards,
- the `onNavigateToTab` name map kept as the single router so nav hints
  ("Take me to PCOS") keep working across reshuffles,
- a migration note that deep links / saved tab index in memory are
  remapped to the new indices.

## Decision (Phase 7, 2026-11-20)

Owner decisions recorded below; none of them is implemented yet.

**Q1 — Structure: Option B variant with 6 tabs.**
Bottom bar: **Cycle · Ovulation · Protection · Learn · Check-in · Settings**.
- Option B's 5-tab core adopted (Home=Cycle, Protection, Learn, Check-in, Settings).
- Variant: Ovulation keeps its own tab (6 total), so all cycle tools stay
  one tap away. PCOS and Endo move under Home quick-cards per Option B.
- Consensus rationale: 6 tabs is just above Apple's soft guideline but
  keeps the app's flagship cycle surfaces at one-tap depth; labels can
  stay at the app's 11sp readable floor without truncation risk on ~320dp
  phones since only one extra tab is added vs the 5-tab baseline.
- PCOS/Endo cards on Home and a fallback "More" sheet remain part of the
  design regardless of which screen owns the tab.

**Q2 — Small-phone labels: always shown.**
The bottom bar keeps labels at every width; no icon-only mode below 360dp.
Rationale: labels are already at the 11sp floor and 48dp targets are met,
so truncation risk at 6 tabs is low on small phones; icon-only mode would
lose the language/label clarity the pill already provides.

**Q3 — Language pill: keep app-global.**
The EN | اردو pill stays pinned to every screen (owner-approved in
review item 2.6, `main.dart:44–47`). Translated content remains chat-only
until FR-48's localization work happens; see `docs/OPEN_QUESTIONS.md` §6.

None of Q1–Q3 changes code yet. Implementation of any part requires a
separately approved phase.

## Open questions for the owner

1. **(Resolved — Q1 above)** Option B variant with 6 tabs; Ovulation keeps its tab.
2. **(Resolved — Q2 above)** Labels always shown; no icon-only mode below 360dp.
3. **(Resolved — Q3 above)** Language pill stays app-global.
