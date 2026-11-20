# Open questions for the owner

Collected during the review pass (items that need an owner decision or
real-world facts; nothing here is invented by code changes).

## 1. Profile sync payload growth (raised by task 1.3)

The SRS caps a synced profile at 300,000 bytes. The client now refuses
to upload anything over 250 KB and keeps every byte locally instead of
silently trimming data (its sync state says syncing is paused).

**Question:** how should an oversized profile be handled long-term?
Lead candidate: archiving (moving conversations older than N months
into an on-device export file) so active data stays under the cap.
Needs owner + backend confirmation before any change.

**Temporarily mitigated by:** never dropping data + a clear sync
indicator in the Health Diary.

## 2. AI privacy flag semantics (task 4.2 will record this)

`aiMemoryEnabled` currently conflates two ideas: using profile/diary
data in the *current* session and remembering *past* chats. Proposal
(recorded here for later): split it into two independent toggles —
"use my diary & profile" and "remember my previous check-ins". Not
changed yet.

## 3. Reminders toggle has no notification backend (task 2.2)

The Settings > Reminders switch is persisted per account, but nothing
in the app schedules notifications — no local-notification package,
no platform channel. The row now says so honestly ("Notification
delivery isn't set up yet") instead of implying reminders exist.

**Question:** until a notification backend exists, should the default
stay ON (current: `remindersEnabled ?? true`) or default OFF so a
fresh install doesn't show an enabled toggle that does nothing?

**Related owner decision:** which package to adopt (allowed deps list
currently has no notification package — adding one needs approval).

## 4. Cycle input ranges are not unified (task 3.5)

Two entry points accept a "cycle length" today, and they disagree on
bounds:

| Entry point | Bounds |
| --- | --- |
| Cycle tracker (Settings → Cycle Data stepper) | clamped 21–45 days, period duration 2–10 days (`cycle_data_screen.dart`) — now also enforced at the provider write point |
| PCOS/ML form ("Cycle length (days)" free-text field) | no validation — any parseable integer goes into `ReproductiveHistory.cycleLengthDays` and is sent to the ML backend as a feature (`pcos_screen.dart`) |

The AI chat cannot change cycle settings (the 1.7 allow-list has no
cycle surface), so these are the only two paths.

**Questions for the owner:**
1. Should the two entry points share one range? If yes, which — the
   tracker's 21–45, or something else?
2. Are the tracker's existing bounds (21–45 length, 2–10 duration)
   clinically right for this app's audience? Not verified against any
   source during this pass — confirming or changing them is an owner
   decision, not something the code change should invent.
3. Should the ML form get range validation at all, given the backend
   (`pcos_ml_project`, out of bounds) consumes these values as model
   features? Whatever the client accepts should be within what the
   model was trained to expect — a backend contract question.

No medical range was changed by task 3.5: the provider clamp only
enforces the bounds the tracker UI already declared.

## 5. Deletion candidates the owner chose to keep (task 6.1)

The review pass flagged three files for cleanup; the owner decided to
KEEP them all for now, so they stay in the repo:

- `flutter_01.png` (root; plus similar root artifacts `flutter_02.png`
  and `flutter_01.log` found during 6.1)
- `docs/WELLNESS_SAHELI_UML_DOCUMENTATION (1).md` (duplicated file name)
- `lib/server/requirement.txt` (suspected duplicate of the backend's
  requirements file)

**Question for a later pass:** are any of these worth deleting (and is
`lib/server/` itself still meaningful)? Deleting anything here remains
an owner call.

## 6. Language switch placement vs FR-48 (task 6.3)

The SRS (FR-48) assumes Urdu support is a chat-only feature. In the
current UI the `EN | اردو` switch is a fixed pill pinned to the top
right of every screen (`lib/l10n/language_fab.dart`), while translated
*content* still exists only in the AI chat.

**Question:** what is the intended scope?
1. Keep the pill app-global as a promise of future coverage, or
2. move it back into the chat screen until FR-48's content work is
   actually done (its current state can look like the whole app is
   bilingual when it is not).

**Decided (Phase 7, 2026-11-20):** option 1 — keep the pill app-global
(see `docs/NAV_PROPOSAL.md`, Decision Q3). The caveat stands: only chat
*content* is translated today; the remaining localization is still open
under FR-48.
