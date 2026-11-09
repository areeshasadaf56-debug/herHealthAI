# Review verification snapshot — Phase 0 (2026-11-09)

Every reviewer item below was checked against the **live tree** on branch
`fix/review-pass-1` (base: `main` @ `316d71b`, which is 8 ahead / 10 behind
`origin/main`, not pushed). Statuses: **Confirmed** (still broken as
described), **Partially** (root cause present, some part already fixed),
**Already fixed**, **Different** (behaves differently from the snapshot the
reviewer saw). `file:line` was read on this tree.

## Snapshot differences (brief vs this tree)

| Brief said | This tree |
| --- | --- |
| Repo `wellness-saheli-v2`; backend is a separate PythonAnywhere service | Repo `wellness_saheli`; the Flask backend (`pcos_ml_project`) **is in-repo** but is still treated as out-of-bounds per ground rules |
| `lib/providers/cycle_data.dart` | Cycle math lives in `lib/models/cycle_data.dart` (`getPhase()` L20, modulo wrap L15). Brief's path is wrong |
| `lib/services/auth_session.dart` missing | **Exists** (class `AuthSession`, L12) but no service imports it yet — still a gap, see 1.2 |
| Token must move to secure storage | Token already stored in `flutter_secure_storage` (`secure_store.dart`, `SecureStore.read` used by `cycle_provider.dart:128`); expiry too (`:129`) |
| "Log Out dialog only navigates" | Dialog now **does** call `CycleProvider.logout()` non-awaited (`settings_screen.dart:359–366`) — but with no per-user scoping, so data leaks across accounts (1.1) |
| Forgot-password is `onPressed: () {}` | Fully implemented vs real backend: `ForgotPasswordScreen` (email → code → new password, `forgot_password_screen.dart:19,32`) hitting `/verify_email/request` + `/reset_password` (`cycle_provider.dart:303,394`). No `kPasswordResetEnabled` gate — it's live because the backend exists |
| Language pill only in chat header; clipped in Settings | Pill is now a global `LanguageFab` rendered for **every** screen via `MaterialApp.builder` (`main.dart:44–47`) — owner-requested change. Only chat copy is still localized (SRS FR-48) |
| Android voice manifest missing | `AndroidManifest.xml` already has `RECORD_AUDIO` + recognition-service `<queries>` entry |
| 4 switch styles | `switchTheme` already added to `buildAppTheme()` (`app_theme.dart:263`) with white thumb / primary track; 8 per-screen overrides still bypass it (list at 2.1) |
| ~36 `withOpacity` uses | **0** left in `lib/` — full migration already done (6.2) |
| `lib/widget/accordion_row.dart` to merge | Already deleted/merged into `lib/widgets/` (earlier commit) |
| Fake pubspec description | Already a real description (`pubspec.yaml:2`) |

## Phase 1 — session, data integrity, error handling

| ID | Status | Evidence |
| --- | --- | --- |
| 1.1 Logout & per-user data | **Partially** | `logout()` invoked but not awaited (`settings_screen.dart:366`; `cycle_provider.dart:435`). No `:userId` scoping of `lastPeriodStart`/`cycleLength`/`periodDuration`/`dailyLogs`/`remindersEnabled`/`userName` keys anywhere in `cycle_provider.dart`; no legacy-key migration; no "remove data" second option |
| 1.2 Session/token | **Partially** | `_loadData` clears the token when expired (`cycle_provider.dart:128–138`) but `isLoggedIn` flag handling still leaves gaps; `AuthSession` exists yet no other service imports it; `AiService` solves 401 itself by throwing `AuthRequiredException` (`ai_service.dart:127–131`) with no re-sign-in routing; `health_profile_service.dart:66` comment admits its 401s just fall into try/catch |
| 1.3 Profile service singleton/queue/sync-state | **Confirmed** | No `factory`, no `_instance`, no update queue, no `syncState`/`ValueListenable`, no 250 KB guard in `health_profile_service.dart` (only `profileUpdated` notifier L97 + `forceServer`) |
| 1.4 Live profile in screens | **Partially** | `profileUpdated` notifier exists and `health_diary_screen.dart:78,121` listens. `HomeScreen._profile` loaded once (`home_screen.dart:28,39`); `AiCheckinScreen._loadInitialState` runs once from `initState` (`ai_checkin_screen.dart:104–106,260`) with no listener |
| 1.5 PCOS save race | **Confirmed** | `pcos_screen.dart:1077` `appendPcosResult` + `:1085` `updateProfile` back-to-back, not awaited |
| 1.6 Tolerant parsing | **Confirmed** | No `_asInt/_asDouble/_asBool` helpers; no clamping in `health_profile.dart` |
| 1.7 AI structured updates | **Confirmed** | `_applyStructuredUpdates` at `ai_checkin_screen.dart:571`; `life_context` merged at `:585` and dropped (no model field) |
| 1.8 Central errors | **Confirmed** | `lib/services/api_error.dart` does not exist; `eligibility_api_service.dart` has **zero** `.timeout` calls; `_authBaseUrl` is now an alias of `ApiConfig.baseUrl` (`cycle_provider.dart:34`) — already fine |

## Phase 2 — UI/UX

| ID | Status | Evidence |
| --- | --- | --- |
| 2.1 One switch theme | **Partially** | Theme exists (`app_theme.dart:263`). Overrides remain: `ai_checkin_screen.dart:1509,1546`, `data_privacy_screen.dart:371`, `pcos_screen.dart:933`, `protection_screen.dart:1862–1863`, `settings_screen.dart:324`, `pcos_comfort.dart:629` |
| 2.2 Reminders row | **Confirmed** | Plain `Switch` row + emoji 🔔 (`settings_screen.dart:314ff`), defaults ON (`cycle_provider.dart:16` `_remindersEnabled = true`, `:118` `?? true`) |
| 2.3 640px content cap | **Confirmed** | No width constraint in `home_shell.dart` body (only local chat bubbles etc. use `BoxConstraints`) |
| 2.4 Bottom nav | **Partially** | Active-tab pill + icon scale already added (motion pass), but labels are 7.5sp, tap targets < 48dp, no `Semantics`, `docs/NAV_PROPOSAL.md` not written |
| 2.5 Settings regroup | **Confirmed** | Emoji icons (🩸 at `settings_screen.dart:73`, 🔔 at `:314`), "Data & Privacy" under CYCLE SETTINGS (L71ff), no `SettingsTile` |
| 2.6 Language pill | **Different** | Global FAB app-wide (owner-approved, `main.dart:44–47`); revisit only if other screens get localized (Phase 7) |
| 2.7 Small text | **Confirmed** | 28 usages of `size: 8–10.5` found (brief said 27), e.g. `home_screen.dart:336,368,429,543`, `protection_screen.dart:2000,2565,3036…` |

## Phase 3 — cycle logic

| ID | Status | Evidence |
| --- | --- | --- |
| 3.1 One source of truth | **Confirmed** | `CycleData.getPhase()` uses `(cycleLength/2).floor()` boundaries (`models/cycle_data.dart:23–24`) → Ovulation = days 15–16 for L=28; `ovulation_screen.dart:35` computes `14` locally and marks 14–15 active (`:80`); `home_screen.dart:514` has its own copy. No `ovulationDay`/`fertileWindow*` getters exist |
| 3.2 Fabricated default date | **Confirmed** | `lastPeriodStart: DateTime.now().subtract(const Duration(days: 14))` (`cycle_provider.dart:12`) |
| 3.3 Late periods / modulo wrap | **Confirmed** | `getCurrentCycleDay` wraps with `% cycleLength` (`models/cycle_data.dart:15`); calendar prediction wraps too (`month_calendar.dart:91–92`); no `days_late` anywhere |
| 3.4 Date helpers | **Confirmed** | No `dateOnly`/`daysBetween`/`date_utils` anywhere |
| 3.5 Input ranges | **Confirmed** | Cycle-length slider 21–45, duration 2–10 (`cycle_data_screen.dart:130–131,144–145`); date picker limited to 365 days back (`cycle_data_screen.dart:50`). (Brief guessed duration was 1–7; it's 2–10 here) |
| 3.6 Cycle length duplication | **Confirmed** | `CycleData.cycleLength` vs `ReproductiveHistory.cycleLengthDays` both live and used (`pcos_screen.dart:103–106`, `health_diary_screen.dart:926–927`) |

## Phase 4 — privacy, consent, safety

| ID | Status | Evidence |
| --- | --- | --- |
| 4.1 Privacy/terms copy | **Confirmed** | Copy claims "nothing is backed up to an external server" (`data_privacy_screen.dart:200`) and PCOS/eligibility requests "not stored" while the client PUTs the entire profile (incl. diary + mental-health flags) to `/profile/<id>`; no `kAiProviderName`, no `kPolicyLastUpdated`. SRS SEC-16 still open |
| 4.2 Consent | **Confirmed** | No checkbox/Terms links in `sign_up_screen.dart`; `aiCanAccessDiary` defaults **true** (`health_profile.dart:182`); no consent sheet/dialog/timestamp |
| 4.3 Account/data deletion | **Confirmed** | No `DELETE` call anywhere in `lib/services/` (only per-entry removal comment `health_profile_service.dart:330`) |
| 4.4 Crisis safety net | **Confirmed** | Only the server's `crisis_concern` flag is parsed (`ai_response.dart:24`); no `safety_filter.dart`, no `support_resources.dart`, no `url_launcher`, no dialed helplines |
| 4.5 Forgot password | **Already fixed (different)** | 2-step email→code→reset flow live against `/verify_email/request` + `/reset_password` (`forgot_password_screen.dart:19,32`, `cycle_provider.dart:303,394`). No gate flag needed; remaining: documented contract in `BACKEND_TODO.md` + removing any dead single-step `resetPassword` references |

## Phase 5 — platform, tests, CI

| ID | Status | Evidence |
| --- | --- | --- |
| 5.1 Android voice | **Already fixed** | Manifest permissions/queries in place |
| 5.2 iOS voice | **Confirmed** | No `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` in `ios/Runner/Info.plist` |
| 5.3 Tests | **Confirmed** | Only `test/widget_test.dart` exists — bare smoke test, **fails** at baseline (no `setMockInitialValues`, runtime Google Fonts). All listed unit/widget tests missing |
| 5.4 CI & signing | **Partially** | `.github/workflows/build.yml` exists but pins `'3.x'` (L10) and builds only `apk` (L23). No `ci.yml`. `android/app/key.properties` + `build.gradle.kts:12–48` already wire real signing. Remaining: pin Flutter, add CI, `appbundle`, loud failure when `key.properties` missing |
| 5.5 Bundled fonts | **Confirmed (optional)** | `google_fonts` runtime fetch, no font assets |

## Phase 6 — housekeeping, docs

| ID | Status | Evidence |
| --- | --- | --- |
| 6.1 Cleanup | **Partially** | `crypto: ^3.0.3` in `pubspec.yaml:36` but no `package:crypto` import anywhere → safe to remove. Ask-before-delete files all present: `flutter_01.png`, `docs/WELLNESS_SAHELI_UML_DOCUMENTATION (1).md`, `lib/server/requirement.txt`. Accordion + description already done |
| 6.2 Code quality | **Partially** | `withOpacity` already 0. 12+ duplicated month-name arrays + date-formatting helpers (`month_calendar.dart:24`, `cycle_data_screen.dart:30`, `ai_checkin_screen.dart:449`, `endo_screen.dart:22`, `health_diary_screen.dart:58,1028`, `home_screen.dart:45,466`, `pcos_screen.dart:145`, `ovulation_screen.dart:13,205`, `learn_screen.dart:461`); `intl` not yet a dependency (allowed) |
| 6.3 Docs | **Confirmed** | README describes a pre-endo/pre-verify app and still says "no third-party data sharing" (L73); SRS flags listed below |

## SRS ↔ code disagreements (`requirements.md`)

- **FR-79** (background save, never block UI) — code awaits the PUT; disagree.
- **FR-94** (640px cap) — not implemented in `home_shell.dart`.
- **FR-95** (bounded height via `LayoutBuilder`, marked `[FIXED]` vs `home_shell.dart`) — there is **no** `LayoutBuilder` in `home_shell.dart` here; SRS stale.
- **FR-86** (delete whole profile) — not implemented client-side.
- **SEC-12** (`[OPEN]` no ownership proof) — outdated: emailed-code reset now exists (4.5).
- **SEC-16** — still open; no provider disclosure.
- **FR-48** (only chat bilingual) — still true for content, but the EN/اردو pill is now global UI, so the SRS assumption about placement changed.

## Baseline runs (recorded)

- `flutter pub get` → OK.
- `flutter analyze` → **1 info / 0 errors** (legacy deprecation: `SpeechListenOptions.localeId`, `ai_checkin_screen.dart:162`).
- `flutter test` → **1 failure**: `widget_test.dart` "App launches without crashing" (expected reviewer 5.3).
- Release-signing note: `upload-keystore.jks` was removed from the repo by the catch-all commit `316d71b` (`git add -A` of pre-existing working-tree state). Recovery is one command from git history — owner decision.
