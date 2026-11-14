# Backend contract notes (`pcos_ml_project`)

Facts the Flutter client depends on, verified against the client code
(`lib/`) and the backend route signatures during review-pass 1. The
backend folder itself is out of bounds for edits from the app side —
changes here need an owner/backend decision and are recorded as gaps.

## Auth endpoints (client: `lib/providers/cycle_provider.dart`)

| Endpoint | Used for | Client expectation |
| --- | --- | --- |
| `POST /signup` | Account creation | Errors surfaced verbatim to the sign-up screen |
| `POST /signin` | Sign-in | `403` with a "needs_verification" shape routes the user to the email-code screen instead of showing an error; success carries session token + user id + expiry |
| `POST /logout` | Best-effort token invalidation (8s timeout, failure ignored) | |
| `POST /verify_email/request` | 6-digit codes for both signup verification and password reset (`purpose: 'reset'`) | |
| `POST /verify_email/confirm` | Verifying the emailed code | |
| `POST /reset_password` | Sets a new password **only with a valid emailed code** — there is no single-step reset (the old dead one was removed) | |

## Profile sync (client: `lib/services/health_profile_service.dart`)

| Endpoint | Used for |
| --- | --- |
| `GET /profile/<user_id>` | Fetch the account's whole profile document |
| `PUT /profile/<user_id>` | Newest-wins whole-document upload (client caps payloads at 250 KB, see `OPEN_QUESTIONS.md` §1) |
| `DELETE /profile/<user_id>` | **Wired from task 4.3** ("Delete my data from the server") — the backend already implements it with an owner check (`health_profile_api.py`) |

The document includes: demographics, lifestyle, reproductive history,
PCOS + eligibility history, mental-health flags, AI conversation log,
diary entries, and privacy settings.

## Gaps (need a backend decision)

1. **Account deletion.** `DELETE /profile/<user_id>` removes the health
   profile document only — the account itself (credentials in
   `accounts.db`) has no delete endpoint, so a user cannot fully delete
   their account from the app. Needed for task 4.3's full story
   (e.g. `DELETE /account` with owner auth + email-verification
   semantics). Until it exists, the app's deletion button honestly
   says it removes profile data and clears the device.
2. **Password storage claim.** The Data & Privacy copy avoids claiming
   how passwords are stored; if the backend wants that disclosed
   (e.g. "hashed"), it should confirm the mechanism so the client can
   state it as fact.
