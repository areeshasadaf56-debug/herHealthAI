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
