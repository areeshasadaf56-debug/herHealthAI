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
3. **AI provider identity (SEC-16).** The Data & Privacy copy says
   replies come from "an external AI service" because the owner has not
   confirmed which service actually powers `/chat`. Needed before
   release: the real provider name (replaces the `// OWNER:` placeholder
   in `lib/config/disclosures.dart`) and a review of that provider's
   terms for health-data processing.

## Live AI chat — retired Groq model (2026-11)

**Symptom:** the Chat tab answers with a generic "couldn't reach the AI
service" bubble.

**Diagnosis (verified):**
- `POST https://areeshasadaf56.pythonanywhere.com/chat` is reachable:
  an unauthenticated request returns `401`, and the CORS preflight
  allows the web origin. The route itself is fine.
- A freshly generated Groq key is valid (`GET /models` succeeds and a
  tool-calling smoke test passes).
- `llama-3.3-70b-versatile` — the model the deployed backend used — has
  been retired by Groq and now returns `404 model_not_found`. That makes
  every `/chat` call fail.

**Fix (in the local backend checkout):**
- `chat_api.py` and `app_backend/chat.py` now use
  `openai/gpt-oss-120b`, which is in the account's `/models` list and
  passes a tool-calling smoke test. `max_tokens` stays at 800; gpt-oss
  spends some tokens on reasoning, so very low limits return an empty
  reply.
- `GROQ_API_KEY` is set in the backend's gitignored `.env`, and
  `.vscode/launch.json` starts `main_flask.py` with that file.

**Deployment (owner, PythonAnywhere):**
1. Upload/replace `chat_api.py` (and `app_backend/chat.py` if the
   FastAPI app is what is deployed), or `git pull` if the web app is a
   checkout of the repo.
2. Set `GROQ_API_KEY` in the web app's environment (WSGI file) or in a
   `.env` next to `main_flask.py`. Never commit the key and never ship
   it in the Flutter app.
3. Reload the web app, then send a chat message from a signed-in
   account.

The Flutter client needs no change: it already points at
`ApiConfig.baseUrl` and maps a `401` to "session expired".
