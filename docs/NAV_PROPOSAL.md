# Navigation proposal (task 2.4) — for owner review

**Status:** design document only. Nothing here is implemented; any change
needs explicit owner approval (Phase 7 gate).

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
| 7 | AI Check-in | heart | Chat |

Sub-navigation also exists *inside* screens (in-tab `_tabButton` rows in
Health Diary, Protection and PCOS screens) and via the app-wide AI
check-in FAB (`LanguageFab` is separate — that one is language only).

## Problems identified in review

1. **8 tabs is above every platform guideline** (Material recommends
   3–5; Apple recommends 3–5, hard maximum ~7). Each tab gets only
   ~12% of the width, forcing the 7.5sp labels that were fixed in code
   (now 10sp) but cannot grow further.
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

## Recommendation

Option B, implemented in a later approved phase, with:
- unchanged tab order for the five survivors,
- Home gaining a "health tools" section with Ovulation/PCOS/Endo cards,
- the `onNavigateToTab` name map kept as the single router so nav hints
  ("Take me to PCOS") keep working across reshuffles,
- a migration note that deep links / saved tab index in memory are
  remapped to the new indices.

## Open questions for the owner

1. Which option (A/B/C or a variant)?
2. If B: does Ovulation deserve its own tab in *this* app's usage, or is
   chip-under-Home enough?
3. If B/C: should the bottom bar show labels at all on small phones
   (icon-only mode below 360dp)?
