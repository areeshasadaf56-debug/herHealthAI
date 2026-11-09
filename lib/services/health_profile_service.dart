/// health_profile_service.dart
///
/// Loads, caches, and saves the user's HealthProfile. This is the ONE
/// place every screen should go through to read or update profile data
/// -- don't call the backend directly from individual screens, so we
/// have a single place to add offline support, retry logic, etc. later.
///
/// Requires two packages in pubspec.yaml:
///   shared_preferences: ^2.2.0
///   http: ^1.1.0
/// (You likely already have `http` from pcos_api_service.dart /
/// eligibility_api_service.dart.)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart'; // ValueNotifier (sync signal)
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/health_profile.dart';
import 'secure_store.dart';

class HealthProfileService {
  static const _deviceIdKey = 'health_profile_device_id';
  static const _localProfileKeyPrefix = 'health_profile_cache_';

  // Written by CycleProvider on sign-in/out -- read directly here so
  // every screen that already constructs `HealthProfileService()` picks
  // up authenticated sync automatically, with no call-site changes.

  String? _cachedUserId;
  HealthProfile? _cachedProfile;

  /// Returns the anonymous device id, generating and persisting one on
  /// first ever call. Used as a fallback identity for local-only usage
  /// before the user signs in; once signed in, [_effectiveUserId] uses
  /// the real account id instead so profile data actually reaches the
  /// backend under an identity the server will authorize.
  Future<String> getDeviceId() async {
    if (_cachedUserId != null) return _cachedUserId!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = _generateId();
      await prefs.setString(_deviceIdKey, id);
    }
    _cachedUserId = id;
    return id;
  }

  /// The id to use for talking to the backend: the signed-in account's
  /// real user id when available (required -- the backend now rejects
  /// `/profile/<id>` calls whose id doesn't match the authenticated
  /// token), falling back to the anonymous per-device id otherwise.
  Future<String> _effectiveUserId() async {
    final accountId = await SecureStore.read(SecureStore.userIdKey);
    if (accountId != null && accountId.isNotEmpty) return accountId;
    return getDeviceId();
  }

  /// `Authorization: Bearer <token>` header when a still-valid session
  /// exists, or an empty map when signed out / expired -- in which case
  /// backend calls will simply 401 and the existing try/catch fallbacks
  /// keep the UI on local-only data, same as being offline.
  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStore.read(SecureStore.tokenKey);
    if (token == null || token.isEmpty) return {};

    final expiresMillis = await SecureStore.readExpiryMillis();
    if (expiresMillis != null &&
        DateTime.fromMillisecondsSinceEpoch(
          expiresMillis,
        ).isBefore(DateTime.now())) {
      return {};
    }
    return {'Authorization': 'Bearer $token'};
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

  /// Fired whenever a server sync (background or explicit refresh)
  /// adopts a newer profile than the one in the local cache. Open
  /// screens listen and redraw -- previously the background sync
  /// silently updated an in-memory cache no screen ever re-read, which
  /// is why the Diary's refresh button looked completely dead.
  final ValueNotifier<HealthProfile?> profileUpdated =
      ValueNotifier<HealthProfile?>(null);

  /// True when the most recent [loadProfile] call reached the backend
  /// successfully (only meaningful when forceServer is true).
  bool lastServerSyncReached = false;

  /// Loads the profile: LOCAL CACHE FIRST, backend as a background sync.
  ///
  /// This used to check the backend first and fall back to local cache
  /// only on failure. That was backwards in practice: if the backend
  /// ever had an older/emptier profile than what's on-device (e.g. a
  /// previous saveProfile()'s background PUT silently failed due to a
  /// network hiccup, CORS, or the endpoint not being fully live yet),
  /// the *next* loadProfile() would happily fetch that stale backend
  /// copy and overwrite fresh local writes -- so a PCOS result or
  /// contraception choice saved seconds ago could vanish from the
  /// Diary the moment you reopened it, even though it was safely
  /// sitting in local storage the whole time.
  ///
  /// Now: local cache is returned immediately (it's authoritative for
  /// "what did this device just do"), and a backend fetch happens in
  /// the background purely to pick up data saved from a *different*
  /// device -- and even then, it's only adopted if it's actually newer
  /// than what's already local (compared via lastUpdated), so a stale
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

    final local = await _loadFromCache(userId);

    if (forceServer) {
      final remote = await _fetchFromBackend(userId);
      lastServerSyncReached = remote != null;

      if (local == null || (remote?.lastUpdated.isAfter(local.lastUpdated) ?? false)) {
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
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/profile/$userId');
      final headers = await _authHeaders();
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return HealthProfile.fromJson(json);
    } catch (_) {
      return null;
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
  /// never waits on the network), then pushes to the backend in the
  /// background. If the backend call fails, the local cache still has
  /// the update -- the next successful loadProfile()/saveProfile() call
  /// will resync.
  Future<void> saveProfile(HealthProfile profile) async {
    _cachedProfile = profile;
    await _cacheLocally(profile.userId, profile);

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/profile/${profile.userId}');
      final headers = {
        'Content-Type': 'application/json',
        ...await _authHeaders(),
      };
      await http
          .put(uri, headers: headers, body: jsonEncode(profile.toJson()))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Background sync failed silently -- local cache is still correct,
      // and will be retried on the next saveProfile()/loadProfile() call.
      // (If you want the user to see a "not synced" indicator, surface
      // this instead of swallowing it.)
    }
  }

  /// Convenience: apply a partial update without needing the caller to
  /// hand back a full HealthProfile. Example:
  ///   await service.updateProfile((p) => p.copyWith(
  ///     lifestyle: p.lifestyle.copyWith(regularExercise: true),
  ///   ));
  Future<HealthProfile> updateProfile(
    HealthProfile Function(HealthProfile current) updater,
  ) async {
    final current = _cachedProfile ?? await loadProfile();
    final updated = updater(current);
    await saveProfile(updated);
    return updated;
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
  // saving keeps the deletion consistent across the timeline, the Profile
  // tab stats, and the backend sync (saveProfile pushes the shorter
  // lists server-side, so a background re-sync can't resurrect them).

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
          currentContraceptionMethod:
              updated.isNotEmpty ? updated.last.method : null,
        ),
      );
    });
  }

  /// Removes one saved eligibility check.
  Future<HealthProfile> removeEligibilityCheckAt(int index) {
    return updateProfile((p) {
      if (index < 0 || index >= p.eligibilityHistory.length) return p;
      final updated =
          List<EligibilityCheckResult>.from(p.eligibilityHistory)
            ..removeAt(index);
      return p.copyWith(eligibilityHistory: updated);
    });
  }

  /// Removes one saved AI conversation turn.
  Future<HealthProfile> removeConversationAt(int index) {
    return updateProfile((p) {
      if (index < 0 || index >= p.conversationLog.length) return p;
      final updated =
          List<ConversationEntry>.from(p.conversationLog)..removeAt(index);
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
    } catch (_) {
      return null;
    }
  }
}
