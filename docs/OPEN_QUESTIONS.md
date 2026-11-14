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
