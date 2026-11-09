/// auth_session.dart
///
/// The ONE accessor for "who is signed in right now". CycleProvider
/// tells it about sign-in/sign-out; every service that talks to an
/// authenticated backend endpoint (HealthProfileService, AiService)
/// reads its identity + Authorization header exclusively from here, so
/// there is exactly one source of truth and no drifting copies.
///
/// Storage still lives behind [SecureStore] (Android Keystore /
/// iOS Keychain) -- this class is the thin, synchronous in-memory
/// façade over it, including the one-time load from storage at app
/// start and the expiry check that treats an expired token as
/// "signed out".
library;

import 'secure_store.dart';

class AuthSession {
  AuthSession._();

  static bool _loaded = false;
  static String? _userId;
  static String? _token;
  static DateTime? _expiresAt;

  static bool get isLoaded => _loaded;
  static String? get userId => _userId;
  static String? get token => _token;
  static DateTime? get expiresAt => _expiresAt;

  /// True only when a usable (non-expired) token is in hand. Services
  /// treat false as "no session" -- expired must mean logged out, not
  /// "attach a dead header and wait for a 401".
  static bool get isValid =>
      _token != null &&
      (_expiresAt == null || _expiresAt!.isAfter(DateTime.now()));

  /// `Authorization: Bearer <token>` when a session exists, else {}.
  static Map<String, String> get authHeaders =>
      _token == null ? {} : {'Authorization': 'Bearer $_token'};

  /// Loads the stored session once per app run. Reads secrets from
  /// SecureStore (which itself migrates any legacy plain-text copies
  /// from SharedPreferences and deletes them). An expired or unusable
  /// stored token is wiped from storage right here, so the app can
  /// never boot into a "signed-in but doomed" state.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    _userId = await SecureStore.read(SecureStore.userIdKey);
    _token = await SecureStore.read(SecureStore.tokenKey);
    final expiresMillis = await SecureStore.readExpiryMillis();
    _expiresAt = expiresMillis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresMillis);

    if (_token != null && !isValid) {
      // Expired session: clear memory AND storage so nothing attaches a
      // dead Authorization header to outgoing requests.
      await clear();
    }
  }

  /// Called by CycleProvider after a successful sign-in / sign-up /
  /// verification. Keeps the in-memory mirror and the encrypted store
  /// in sync; null values are left untouched (same as before). Marks
  /// the session as established so a later ensureLoaded() can never
  /// clobber this freshly-written state with stale storage contents.
  static Future<void> update({
    String? userId,
    String? token,
    DateTime? expiresAt,
  }) async {
    _loaded = true;
    if (userId != null) {
      _userId = userId;
      await SecureStore.write(SecureStore.userIdKey, userId);
    }
    if (token != null) {
      _token = token;
      await SecureStore.write(SecureStore.tokenKey, token);
    }
    if (expiresAt != null) {
      _expiresAt = expiresAt;
      await SecureStore.write(
        SecureStore.expiresKey,
        expiresAt.millisecondsSinceEpoch.toString(),
      );
    }
  }

  /// Signed out / session rejected / expired / 401. Wipes the memory
  /// mirror and the encrypted storage (including legacy plain-text
  /// copies), so every consumer sees "not signed in" immediately.
  /// Counts as "established" too: after a deliberate sign-out we KNOW
  /// the session is empty; reloading from storage must not resurrect
  /// anything.
  static Future<void> clear() async {
    _loaded = true;
    _userId = null;
    _token = null;
    _expiresAt = null;
    await SecureStore.clearSession();
  }
}
