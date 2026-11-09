/// health_profile_service.dart
///
/// Loads, caches, and saves the user's HealthProfile. This is the ONE
/// place every screen should go through to read or update profile data
/// -- don't call the backend directly from individual screens, so we
/// have a single place to add offline support, retry logic, etc. later.
///
/// The service is a shared singleton (`factory HealthProfileService() =>
/// instance`), so every screen constructing one with no args shares the
/// same in-memory cache and the same update queue. Previously each
/// screen kept its own copy and a long-lived instance (the AI tab,
/// kept alive by the IndexedStack) could write a stale snapshot back,
/// silently clobbering newer data.
///
/// Saves follow SRS FR-79: the local cache is written first, the UI is
/// never blocked on the network, and the backend PUT runs in a
/// background queue. Failures surface through [syncState] and are
/// retried on the next save, load, and app resume.
///
/// Requires two packages in pubspec.yaml:
///   shared_preferences: ^2.2.0
///   http: ^1.1.0
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart'; // ValueNotifier (sync signal)
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/health_profile.dart';
import 'auth_session.dart';

/// How the most recent profile change relates to the backend.
enum ProfileSyncState {
  /// Everything the user has on this device is also on the server.
  synced,

  /// A change is saved locally and its upload is queued/in flight.
  pending,

  /// The last upload didn't reach the server; see [HealthProfileService.lastSyncError].
  ///
  /// Local data is NEVER dropped in this state -- it stays cached on
  /// the device and a retry happens on the next save/load/app resume.
  failed,
}

class HealthProfileService {
  static const _deviceIdKey = 'health_profile_device_id';
  static const _localProfileKeyPrefix = 'health_profile_cache_';

  static final _instance = HealthProfileService._();

  /// Shared singleton: call sites construct the service unchanged
  /// (`HealthProfileService()`) and get the one shared cache + queue.
  factory HealthProfileService() => _instance;

  HealthProfileService._();

  static const int maxSyncPayloadBytes =
      250 * 1024; // hard stop well under the SRS 300,000-byte cap

  // ---- Test seam (overrideHttpClient) ------------------------------------
  static http.Client? _testClient;

  /// Swap the HTTP client behind every backend call, for unit tests
  /// only (they must not touch the real network). Pass null to restore.
  @visibleForTesting
  static void overrideHttpClient(http.Client? client) {
    _testClient?.close();
    _testClient = client;
  }

  http.Client _newClient() {
    final test = _testClient;
    if (test != null) return test; // shared stub; the caller must not close it
    return http.Client();
  }

  String? _cachedDeviceId;
  HealthProfile? _cachedProfile;

  /// The identity the in-memory cache was populated for. When it
  /// changes (sign-in to another account, log out, app resume) the
  /// cache and any queued upload are discarded so one account's data
  /// can never leak into another's.
  String? _activeUserId;

  HealthProfile? _nextPush;
  bool _pushDraining = false;

  /// Queues local profile mutations so concurrent callers can't race.
  /// Every updateProfile/remove* call runs strictly one at a time, and
  /// each reads the FRESH cached profile (never a stale snapshot).
  Future<void> _queueTail = Future.value();

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queueTail.then((_) => task());
    // Keep the queue alive even when a task throws: the tail always
    // completes successfully.
    _queueTail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Returns the anonymous device id, generating and persisting one on
  /// first ever call. Used as a fallback identity for local-only usage
  /// before the user signs in; once signed in, [_effectiveUserId] uses
  /// the real account id instead so profile data actually reaches the
  /// backend under an identity the server will authorize.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = _generateId();
      await prefs.setString(_deviceIdKey, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  /// The id to use for talking to the backend: the signed-in account's
  /// real user id when available (required -- the backend now rejects
  /// `/profile/<id>` calls whose id doesn't match the authenticated
  /// token), falling back to the anonymous per-device id otherwise.
  Future<String> _effectiveUserId() async {
    await AuthSession.ensureLoaded();
    final accountId = AuthSession.userId;
    if (accountId != null && accountId.isNotEmpty) return accountId;
    return getDeviceId();
  }

  /// `Authorization: Bearer <token>` when AuthSession reports a usable
  /// session, or an empty map when signed out / expired -- in which case
  /// backend calls will simply 401 and the existing try/catch fallbacks
  /// keep the UI on local-only data, same as being offline.
  Future<Map<String, String>> _authHeaders() async {
    await AuthSession.ensureLoaded();
    return AuthSession.authHeaders;
  }

  String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    // Simple UUID-v4-shaped string, good enough as an opaque identifier
    // (doesn't need to be a *real* RFC4122 UUID for our purposes).
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Fired whenever the profile the screens should show changes -- on
  /// every local save/update AND whenever a newer remote copy is
  /// adopted. Open screens listen and redraw, so a privacy toggle made
  /// in Data & Privacy reaches the AI tab (and new diary entries reach
  /// Home) without restarting.
  final ValueNotifier<HealthProfile?> profileUpdated =
      ValueNotifier<HealthProfile?>(null);

  /// Publishes [ProfileSyncState] for the small "saved / saving /
  /// needs retry" indicator in the Health Diary.
  final ValueNotifier<ProfileSyncState> syncState =
      ValueNotifier<ProfileSyncState>(ProfileSyncState.synced);

  /// Why the last upload failed, when [syncState] is `failed`. Purely
  /// user-facing text (never raw error bodies) -- e.g. "no internet",
  /// "too large", "sign in again".
  String? lastSyncError;

  /// True when the most recent [loadProfile] call reached the backend
  /// successfully (only meaningful when forceServer is true).
  bool lastServerSyncReached = false;

  /// Swaps the cached profile for [userId]'s if the effective identity
  /// changed since we last served data: wipes the in-memory cache, any
  /// queued upload from the previous account, and the sync state.
  Future<void> _ensureUserContext(String userId) async {
    if (_activeUserId == userId) return;
    _activeUserId = userId;
    _cachedProfile = null;
    _nextPush = null;
    lastSyncError = null;
    syncState.value = ProfileSyncState.synced;
  }

  /// Loads the profile: LOCAL CACHE FIRST, backend as a background sync.
  ///
  /// Local cache is returned immediately (it's authoritative for "what
  /// did this device just do"), and a backend fetch happens in the
  /// background purely to pick up data saved from a *different* device
  /// -- and even then, it's only adopted if it's actually newer than
  /// what's already local (compared via lastUpdated), so a stale
  /// backend record can never clobber a fresher local one.
  ///
  /// [forceServer] is for EXPLICIT user refresh actions (the Diary's
  /// refresh button / pull-to-refresh): the backend GET is awaited
  /// before returning, a newer server copy is adopted (and announced
  /// via [profileUpdated]) synchronously, and [lastServerSyncReached]
  /// tells the caller whether the server answered at all -- so the UI
  /// can show honest feedback instead of a spinner that changes nothing
  /// visible.
  Future<HealthProfile> loadProfile({bool forceServer = false}) async {
    final userId = await _effectiveUserId();
    await _ensureUserContext(userId);

    // A pending failed sync retries right away whenever the app looks
    // at profile data again (FR-79 backpressure point).
    if (syncState.value == ProfileSyncState.failed) {
      unawaited(retryPendingSync());
    }

    final local = await _loadFromCache(userId);

    if (forceServer) {
      final remote = await _fetchFromBackend(userId);
      lastServerSyncReached = remote != null;

      if (local == null ||
          (remote?.lastUpdated.isAfter(local.lastUpdated) ?? false)) {
        final adopted = remote;
        if (adopted != null) {
          await _cacheLocally(userId, adopted);
          _cachedProfile = adopted;
          profileUpdated.value = adopted;
          return adopted;
        }
      }

      if (local != null) {
        _cachedProfile = local;
        return local;
      }
      // Backend unreachable and nothing cached: fall through to blank.
      final blank = HealthProfile.empty(userId);
      _cachedProfile = blank;
      return blank;
    }

    // Fire-and-forget: sync from backend if it turns out to be newer.
    // Intentionally not awaited -- the UI should never block on this,
    // and _refreshFromBackendIfNewer() safely no-ops on any failure.
    unawaited(_refreshFromBackendIfNewer(userId, local));

    if (local != null) {
      _cachedProfile = local;
      return local;
    }

    // No local cache at all (first-ever launch on this device) -- in
    // this one case it's worth waiting on the network, since there's
    // nothing better to show yet.
    final fetched = await _fetchFromBackend(userId);
    if (fetched != null) {
      await _cacheLocally(userId, fetched);
      _cachedProfile = fetched;
      return fetched;
    }

    final blank = HealthProfile.empty(userId);
    _cachedProfile = blank;
    return blank;
  }

  /// Goes to the backend for the current profile. Returns null on any
  /// failure (not signed in, server down, timeout, bad payload).
  Future<HealthProfile?> _fetchFromBackend(String userId) async {
    http.Client? owned;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/profile/$userId');
      final headers = await _authHeaders();
      final client = _newClient();
      owned = _testClient == null ? client : null;
      final response = await client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return HealthProfile.fromJson(json);
    } catch (_) {
      return null;
    } finally {
      owned?.close();
    }
  }

  /// Background helper for loadProfile(): fetches the backend copy and
  /// only adopts it (overwriting local cache + in-memory cache) if it
  /// is strictly newer than what's already local. This is what makes
  /// cross-device sync safe without risking data loss on this device.
  /// On adoption it announces the new profile through [profileUpdated]
  /// so any open screen can re-render with the fresh data.
  Future<void> _refreshFromBackendIfNewer(
    String userId,
    HealthProfile? local,
  ) async {
    final remote = await _fetchFromBackend(userId);
    if (remote == null) return;

    if (local == null || remote.lastUpdated.isAfter(local.lastUpdated)) {
      await _cacheLocally(userId, remote);
      _cachedProfile = remote;
      profileUpdated.value = remote;
    }
  }

  /// Saves the profile: writes to local cache immediately (so the UI
  /// never waits on the network -- SRS FR-79), then queues the backend
  /// push. If the push fails the local cache still has the update, and
  /// a retry happens on the next save, load, or app resume.
  Future<void> saveProfile(HealthProfile profile) async {
    await _ensureUserContext(profile.userId);
    _cachedProfile = profile;
    await _cacheLocally(profile.userId, profile);
    // Announce immediately so open screens (AI tab, Home, Diary) redraw
    // with the fresh data.
    profileUpdated.value = profile;
    _scheduleServerPush(profile);
  }

  /// Queues the profile for upload. Newest snapshot wins: only the most
  /// recent full document is ever uploaded (the server keeps whole
  /// documents), so an interrupted in-flight push simply makes way.
  void _scheduleServerPush(HealthProfile profile) {
    _nextPush = profile;
    if (_pushDraining) return;
    _pushDraining = true;
    if (syncState.value == ProfileSyncState.failed) {
      // A new save clears earlier failure text and gets a fresh chance.
      lastSyncError = null;
    }
    if (syncState.value != ProfileSyncState.pending) {
      syncState.value = ProfileSyncState.pending;
    }
    unawaited(_drainPushQueue());
  }

  /// Serialized (and newest-only) uploader. Never throws.
  Future<void> _drainPushQueue() async {
    try {
      while (_nextPush != null) {
        final profile = _nextPush!;
        _nextPush = null;
        try {
          final payload = jsonEncode(profile.toJson());
          final result = await _attemptPush(profile, payload: payload);
          if (result.isOk) {
            lastSyncError = null;
            syncState.value = ProfileSyncState.synced;
          } else {
            lastSyncError = result.message;
            syncState.value = ProfileSyncState.failed;
          }
        } on TimeoutException {
          // The 8s put deadline passed -- keep local, retry later.
          lastSyncError =
              "Couldn't reach the server right now. Your changes are "
              'saved on this device and will sync next time you open the app.';
          syncState.value = ProfileSyncState.failed;
        } catch (e) {
          debugPrint('HealthProfileService push error: $e');
          lastSyncError =
              "Couldn't reach the server right now. Your changes are "
              'saved on this device and will sync next time you open the app.';
          syncState.value = ProfileSyncState.failed;
        }
      }
    } finally {
      _pushDraining = false;
    }
  }

  Future<_PushResult> _attemptPush(
    HealthProfile profile, {
    required String payload,
  }) async {
    // Not signed in -- anonymous local-only usage. There's nobody to
    // sync with and nothing wrong, so this stays quiet (matching how
    // the app behaved before accounts existed).
    await AuthSession.ensureLoaded();
    if (!AuthSession.isValid) {
      return _PushResult.ok();
    }

    // Whole-document limit check. Never silently trim data (SRS):
    // an oversized document simply stays on the device and the sync
    // state says so. See docs/OPEN_QUESTIONS.md (data archiving).
    final payloadBytes = utf8.encode(payload);
    if (payloadBytes.length > maxSyncPayloadBytes) {
      debugPrint(
        'HealthProfileService: sync payload too large '
        '(${payloadBytes.length} bytes) -- not uploading, data kept locally.',
      );
      return _PushResult.fail(
        'This device has saved more health data than the server can '
        'store, so syncing is paused. Nothing was lost -- it is all on '
        'this device.',
      );
    }

    http.Client? owned;
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/profile/${profile.userId}');
      final client = _newClient();
      owned = _testClient == null ? client : null;
      final response = await client
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              ...AuthSession.authHeaders,
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _PushResult.ok();
      }
      if (response.statusCode == 401) {
        // The server no longer accepts this session. Clear it (same as
        // the other services do on 401); the local data is safe and
        // will sync again once the user signs back in.
        await AuthSession.clear();
        return _PushResult.fail(
          'Your sign-in session expired, so syncing is paused. Your '
          'changes are saved on this device -- sign in again to sync them.',
        );
      }
      return _PushResult.fail(
        'The server couldn’t accept the update right now (HTTP '
        '${response.statusCode}). Your changes are saved on this device.',
      );
    } finally {
      owned?.close();
    }
  }

  /// Willing retry hook for the next save, load, or app resume.
  Future<void> retryPendingSync() async {
    if (syncState.value != ProfileSyncState.failed) return;
    final userId = await _effectiveUserId();
    if (userId != _activeUserId) return; // identity changed; nothing retryable

    final profile = _cachedProfile ?? await _loadFromCache(userId);
    if (profile == null) return;
    _scheduleServerPush(profile);
  }

  /// Convenience: apply a partial update without needing the caller to
  /// hand back a full HealthProfile. Example:
  ///   await service.updateProfile((p) => p.copyWith(
  ///     lifestyle: p.lifestyle.copyWith(regularExercise: true),
  ///   ));
  ///
  /// Calls are serialized through the internal queue -- two call sites
  /// updating concurrently always land on top of each other, and both
  /// persist.
  Future<HealthProfile> updateProfile(
    HealthProfile Function(HealthProfile current) updater,
  ) {
    return _enqueue(() async {
      // Identity first: if the session changed since the cache was
      // populated (sign-in to another account, sign-out), the cache is
      // discarded here so an update can never land on top of a
      // previous account's snapshot.
      final userId = await _effectiveUserId();
      await _ensureUserContext(userId);
      final current = _cachedProfile ?? await loadProfile();
      final updated = updater(current);
      await saveProfile(updated);
      return updated;
    });
  }

  /// Appends one turn to the AI conversation log and saves. Kept as a
  /// dedicated method since this will be called frequently once the AI
  /// chat screen exists, and callers shouldn't need to hand-roll the
  /// list-append logic every time.
  Future<HealthProfile> appendConversationEntry(
    String role,
    String message, {
    String? sessionId,
  }) {
    return updateProfile((p) {
      final updatedLog = List<ConversationEntry>.from(p.conversationLog)
        ..add(
          ConversationEntry(
            timestamp: DateTime.now(),
            role: role,
            message: message,
            sessionId: sessionId,
          ),
        );
      return p.copyWith(conversationLog: updatedLog);
    });
  }

  /// Appends a new PCOS result to history (call this right after a
  /// successful /predict call in pcos_screen.dart) instead of only
  /// keeping the latest result in local widget state.
  Future<HealthProfile> appendPcosResult({
    required String prediction,
    required double pcosProbability,
    required String modelUsed,
  }) {
    return updateProfile((p) {
      final updatedHistory = List<PcosCheckResult>.from(p.pcosHistory)
        ..add(
          PcosCheckResult(
            date: DateTime.now(),
            prediction: prediction,
            pcosProbability: pcosProbability,
            modelUsed: modelUsed,
          ),
        );
      return p.copyWith(pcosHistory: updatedHistory);
    });
  }

  /// Appends a new eligibility-check result -- the conditions the user
  /// selected in Protection > My Plan > Eligibility tool, plus the
  /// per-method category results the check returned -- to the diary.
  /// Without this, running the eligibility tool never left a trace
  /// anywhere once the user navigated away from that screen.
  Future<HealthProfile> appendEligibilityCheck({
    required List<String> conditions,
    required List<EligibilityResultEntry> results,
  }) {
    return updateProfile((p) {
      final updatedHistory =
          List<EligibilityCheckResult>.from(p.eligibilityHistory)..add(
            EligibilityCheckResult(
              date: DateTime.now(),
              conditions: conditions,
              results: results,
            ),
          );
      return p.copyWith(eligibilityHistory: updatedHistory);
    });
  }

  // ---- Per-entry removal (delete buttons in the Health Diary timeline) ----
  //
  // Each takes the index of the entry within the SAME profile list the
  // timeline was built from (the diary screen builds entries with the
  // matching list index attached, then calls back in here). Splicing +
  // saving keeps the deletion consistent across the timeline, the
  // Profile tab stats, and the server sync (the shorter list is pushed
  // server-side, so a background re-sync can't resurrect them).

  /// Removes one saved PCOS check result from history.
  Future<HealthProfile> removePcosCheckAt(int index) {
    return updateProfile((p) {
      if (index < 0 || index >= p.pcosHistory.length) return p;
      final updated = List<PcosCheckResult>.from(p.pcosHistory)
        ..removeAt(index);
      return p.copyWith(pcosHistory: updated);
    });
  }

  /// Removes one logged contraception entry. "Current method" (shown in
  /// the Profile summary and used as AI context) is kept consistent with
  /// whatever history remains: the most recent surviving entry, or none.
  Future<HealthProfile> removeContraceptionAt(int index) {
    return updateProfile((p) {
      final history = p.reproductiveHistory.contraceptionHistory;
      if (index < 0 || index >= history.length) return p;
      final updated = List<ContraceptionLogEntry>.from(history)
        ..removeAt(index);
      return p.copyWith(
        reproductiveHistory: p.reproductiveHistory.copyWith(
          contraceptionHistory: updated,
          currentContraceptionMethod: updated.isNotEmpty
              ? updated.last.method
              : null,
        ),
      );
    });
  }

  /// Removes one saved eligibility check.
  Future<HealthProfile> removeEligibilityCheckAt(int index) {
    return updateProfile((p) {
      if (index < 0 || index >= p.eligibilityHistory.length) return p;
      final updated = List<EligibilityCheckResult>.from(p.eligibilityHistory)
        ..removeAt(index);
      return p.copyWith(eligibilityHistory: updated);
    });
  }

  /// Removes one saved AI conversation turn.
  Future<HealthProfile> removeConversationAt(int index) {
    return updateProfile((p) {
      if (index < 0 || index >= p.conversationLog.length) return p;
      final updated = List<ConversationEntry>.from(p.conversationLog)
        ..removeAt(index);
      return p.copyWith(conversationLog: updated);
    });
  }

  /// Removes one free-text journal entry the user wrote.
  Future<HealthProfile> removeDiaryEntryAt(int index) {
    return updateProfile((p) {
      if (index < 0 || index >= p.diaryEntries.length) return p;
      final updated = List<DiaryEntry>.from(p.diaryEntries)..removeAt(index);
      return p.copyWith(diaryEntries: updated);
    });
  }

  Future<void> _cacheLocally(String userId, HealthProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_localProfileKeyPrefix$userId',
      jsonEncode(profile.toJson()),
    );
  }

  Future<HealthProfile?> _loadFromCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_localProfileKeyPrefix$userId');
    if (raw == null) return null;
    try {
      return HealthProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('HealthProfileService: cached profile failed to parse: $e');
      return null;
    }
  }
}

class _PushResult {
  final bool isOk;
  final String message;
  const _PushResult.ok() : isOk = true, message = '';
  const _PushResult.fail(this.message) : isOk = false;
}
