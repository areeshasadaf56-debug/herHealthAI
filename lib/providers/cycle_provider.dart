import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cycle_data.dart';
import '../models/daily_log.dart';
import '../config/api_config.dart';
import '../services/api_error.dart';
import '../services/auth_session.dart';
import '../services/health_profile_service.dart';

class CycleProvider extends ChangeNotifier {
  // No fabricated placeholder (task 3.2): an account without a stored
  // period start stays unset until the user picks one, and screens
  // prompt instead of showing invented day numbers.
  CycleData _cycleData = CycleData();

  bool _isLoaded = false;
  bool _remindersEnabled = true;

  // --- Auth / profile state ---
  bool _isLoggedIn = false;
  String _userName = '';
  String? _userId;
  String? _authToken;
  DateTime? _tokenExpiresAt;

  /// Set when /signin returns 403 needs_verification: the credentials
  /// were correct but the account's email hasn't been verified yet. The
  /// sign-in screen reads this to route to the verification-code screen.
  String? _emailNeedingVerification;

  // Accounts now live on the backend server (see /signup, /signin,
  // /reset_password) so they survive app reinstalls and work across
  // devices. Only the "remember me" flag + name are cached locally
  // below, purely so the splash screen can skip sign-in on relaunch.
  static const String _authBaseUrl = ApiConfig.baseUrl;

  Map<String, DailyLog> _dailyLogs = {};

  DateTime? _selectedPeriodDate;

  CycleData get cycleData => _cycleData;
  bool get isLoaded => _isLoaded;
  Map<String, DailyLog> get dailyLogs => _dailyLogs;
  DateTime? get selectedPeriodDate => _selectedPeriodDate;

  // Task 3.2: derived cycle values are null while no period start is
  // recorded; screens guard on hasPeriodData and prompt instead.
  int? get currentCycleDay => _cycleData.getCurrentCycleDay();
  String? get currentPhase => _cycleData.getPhase();
  int? get daysUntilNextPeriod => _cycleData.daysUntilNextPeriod();
  int get cycleLength => _cycleData.cycleLength;
  int get periodDuration => _cycleData.periodDuration;

  /// Single source of truth lives on CycleData (task 3.1); screens
  /// read it through here instead of recomputing the formula.
  int get ovulationDay => _cycleData.ovulationDay;
  int? get daysUntilOvulation => _cycleData.daysUntilOvulation;

  /// Late-period state (task 3.3): the wrapped cycle day silently
  /// restarts once the period is due, so screens surface lateness
  /// through these instead.
  int? get daysSinceLastPeriodStart => _cycleData.daysSinceLastPeriodStart;
  bool get isLate => _cycleData.isLate;
  int get daysLate => _cycleData.daysLate;

  /// True once a period start is recorded; cycle math is only shown
  /// when this holds (task 3.2).
  bool get hasPeriodData => _cycleData.hasPeriodData;

  bool get remindersEnabled => _remindersEnabled;

  bool get isLoggedIn => _isLoggedIn;
  String get userName => _userName;
  String? get userId => _userId;
  String? get authToken => _authToken;

  /// The email a fresh verification code should be sent to, set only
  /// right after a legitimate 403 needs_verification sign-in attempt.
  String? get emailNeedingVerification => _emailNeedingVerification;

  /// True once we have a token that isn't (as far as we know) expired
  /// yet. Callers that hit authenticated endpoints should check this
  /// before bothering to attach the Authorization header.
  bool get hasValidSession =>
      _authToken != null &&
      (_tokenExpiresAt == null || _tokenExpiresAt!.isAfter(DateTime.now()));

  CycleProvider() {
    _loadData();
  }

  String _keyFor(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DailyLog getLogFor(DateTime date) {
    return _dailyLogs[_keyFor(date)] ?? DailyLog();
  }

  bool isSelectedDay(DateTime date) {
    if (_selectedPeriodDate == null) return false;
    return _isSameDay(_selectedPeriodDate!, date);
  }

  // ---- Per-account local cycle data (review task 1.1) -----------------
  //
  // The cycle keys used to be global, so a second account that signed
  // in saw the first account's logs. Now everything is stored as
  // `<key>:<accountUserId>`; the legacy unscoped copies written by
  // older app versions are migrated ONCE, into the FIRST account that
  // signs in after this change (never silently for later accounts).

  /// Every base key whose storage must be scoped to an account.
  static const List<String> _userScopedKeys = [
    'lastPeriodStart',
    'cycleLength',
    'periodDuration',
    'dailyLogs',
    'remindersEnabled',
    'userName',
  ];

  static const String _legacyMigratedMarker = 'cycleLegacyMigratedBy';

  String _scopedKey(String baseKey) =>
      (_userId == null || _userId!.isEmpty) ? baseKey : '$baseKey:$_userId';

  /// Copies any legacy unscoped cycle data to the signing-in account,
  /// exactly once (the first account only). Existing accounts that
  /// already carry scoped data are never touched, and later accounts
  /// cannot inherit someone else's leftover keys.
  Future<void> _migrateLegacyDataForUser(SharedPreferences prefs) async {
    if (_userId == null || _userId!.isEmpty) return;
    if (prefs.getString(_legacyMigratedMarker) != null) return;
    final anyScoped = _userScopedKeys.any(
      (k) => prefs.containsKey('$k:$_userId'),
    );
    if (anyScoped) return;

    var copied = false;
    Future<void> copyInt(String key) async {
      final v = prefs.getInt(key);
      if (v != null) {
        await prefs.setInt('$key:$_userId', v);
        copied = true;
      }
    }

    Future<void> copyString(String key) async {
      final v = prefs.getString(key);
      if (v != null) {
        await prefs.setString('$key:$_userId', v);
        copied = true;
      }
    }

    Future<void> copyBool(String key) async {
      final v = prefs.getBool(key);
      if (v != null) {
        await prefs.setBool('$key:$_userId', v);
        copied = true;
      }
    }

    await copyInt('lastPeriodStart');
    await copyInt('cycleLength');
    await copyInt('periodDuration');
    await copyString('dailyLogs');
    await copyBool('remindersEnabled');
    await copyString('userName');
    if (copied) {
      // Blob marker records WHICH account inherited the legacy data, so
      // it can be the cleanup target on "remove data" logouts too.
      await prefs.setString(_legacyMigratedMarker, _userId!);
    }
  }

  /// Re-reads the signed-in user's scoped data into memory (called
  /// right after a sign-in/migration so the UI reflects the new
  /// account immediately). Deliberately resets to blank whenever the
  /// account has nothing stored -- in-memory data that existed before
  /// the sign-in belongs to the previous identity, never to this one.
  Future<void> _reloadPerUserData(SharedPreferences prefs) async {
    final lastPeriodMillis = prefs.getInt(_scopedKey('lastPeriodStart'));
    if (lastPeriodMillis != null) {
      _cycleData = CycleData(
        lastPeriodStart: DateTime.fromMillisecondsSinceEpoch(lastPeriodMillis),
        cycleLength: prefs.getInt(_scopedKey('cycleLength')) ?? 28,
        periodDuration: prefs.getInt(_scopedKey('periodDuration')) ?? 5,
      );
      _selectedPeriodDate = _cycleData.lastPeriodStart;
    } else {
      // Fresh account, no stored dates: blank state, never the
      // previous account's or the signed-out session's data.
      // (Task 3.2: blank means no period date at all.)
      _cycleData = CycleData();
      _selectedPeriodDate = null;
    }

    final logsJson = prefs.getString(_scopedKey('dailyLogs'));
    if (logsJson != null) {
      try {
        final decoded = jsonDecode(logsJson) as Map<String, dynamic>;
        _dailyLogs = decoded.map((k, v) => MapEntry(k, DailyLog.fromJson(v)));
      } catch (_) {
        _dailyLogs = {};
      }
    } else {
      _dailyLogs = {};
    }

    _remindersEnabled = prefs.getBool(_scopedKey('remindersEnabled')) ?? true;
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // Restore auth state FIRST: per-user data reads below need the
    // signed-in account id to pick the right scoped keys.
    // Secrets live behind AuthSession -> SecureStore (Android Keystore /
    // iOS Keychain), never plain SharedPreferences; SecureStore also
    // migrates legacy plain-text copies on first read. An expired
    // stored token is treated as signed out and wiped right there, so
    // the app can't boot holding a dead session.
    await AuthSession.ensureLoaded();
    _userId = AuthSession.userId;
    _authToken = AuthSession.token;
    _tokenExpiresAt = AuthSession.expiresAt;
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    // "Logged in" must mean "has a usable session". Otherwise Splash
    // would route to Home while authenticated calls fail with 401.
    if (_isLoggedIn && !hasValidSession) {
      _isLoggedIn = false;
      await prefs.setBool('isLoggedIn', false);
    }

    // One-time inheritance of pre-accounts data for a restored session:
    // the first account that appears after this change claims the
    // legacy unscoped copies (login() handles the sign-in path).
    if (_isLoggedIn && _userId != null && _userId!.isNotEmpty) {
      await _migrateLegacyDataForUser(prefs);
    }

    final signedIn = _isLoggedIn && _userId != null && _userId!.isNotEmpty;
    final legacyClaimed = prefs.getString(_legacyMigratedMarker) != null;

    /// Scoped-first key lookup. Anonymous usage keeps the bare key;
    /// signed-in usage prefers `<key>:<userId>` and only falls back to
    /// the legacy key while NO account has yet claimed it (after that,
    /// missing scoped data must mean defaults, never another
    /// account's/anonymous leftovers).
    String keyFor(String base) {
      if (!signedIn) return base;
      final scoped = '$base:$_userId';
      if (prefs.containsKey(scoped)) return scoped;
      return legacyClaimed ? scoped : base;
    }

    final lastPeriodMillis = prefs.getInt(keyFor('lastPeriodStart'));
    final cycleLength = prefs.getInt(keyFor('cycleLength'));
    final periodDuration = prefs.getInt(keyFor('periodDuration'));

    if (lastPeriodMillis != null) {
      _cycleData = CycleData(
        lastPeriodStart: DateTime.fromMillisecondsSinceEpoch(lastPeriodMillis),
        cycleLength: cycleLength ?? 28,
        periodDuration: periodDuration ?? 5,
      );
      _selectedPeriodDate = _cycleData.lastPeriodStart;
    }

    final logsJson = prefs.getString(keyFor('dailyLogs'));
    if (logsJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(logsJson);
        _dailyLogs = decoded.map(
          (key, value) => MapEntry(key, DailyLog.fromJson(value)),
        );
      } catch (_) {
        _dailyLogs = {};
      }
    }

    _remindersEnabled = prefs.getBool(keyFor('remindersEnabled')) ?? true;
    _userName = prefs.getString(keyFor('userName')) ?? '';

    _isLoaded = true;
    notifyListeners();
  }

  void toggleReminders(bool value) async {
    _remindersEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // Scoped per account (falls back to the bare key when signed out).
    await prefs.setBool(_scopedKey('remindersEnabled'), value);
  }

  /// Call on successful sign in / sign up. Persists the logged-in flag,
  /// the name, and -- when the server returned one -- the account's
  /// opaque user id + session token, so authenticated endpoints
  /// (profile sync, AI chat) can attach a valid Authorization header.
  Future<void> login(
    String name, {
    String? userId,
    String? token,
    DateTime? tokenExpiresAt,
  }) async {
    _isLoggedIn = true;
    _userName = name;
    if (userId != null) _userId = userId;
    if (token != null) _authToken = token;
    if (tokenExpiresAt != null) _tokenExpiresAt = tokenExpiresAt;
    _emailNeedingVerification =
        null; // only ever set by a failed-at-verify sign-in
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    // Secrets go through the shared AuthSession accessor, which keeps
    // its in-memory mirror AND the encrypted store (Android Keystore /
    // iOS Keychain) in sync, never plain SharedPreferences.
    await AuthSession.update(
      userId: userId,
      token: token,
      expiresAt: tokenExpiresAt,
    );
    // Re-derive from the accessor: whatever identity is now established
    // decides which scoped keys the reload below reads.
    _userId = AuthSession.userId;

    // One-time inheritance of pre-accounts data (first account only),
    // then load THIS account's cycle state into memory so the UI
    // immediately reflects the freshly signed-in account (second
    // accounts get defaults, never the previous account's data).
    await _migrateLegacyDataForUser(prefs);
    await prefs.setString(_scopedKey('userName'), name);
    await _reloadPerUserData(prefs);

    // Drop any legacy plain-text copies left by older versions.
    await prefs.remove('authUserId');
    await prefs.remove('authToken');
    await prefs.remove('authTokenExpiresAt');

    // The reload above swapped the visible cycle state to the new
    // account's -- make sure the UI hears about that too, not just the
    // initial identity flip notified at the top.
    notifyListeners();
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  /// Creates a new account on the server. Returns null on success, or
  /// an error message string on failure (e.g. email already taken, or
  /// no internet connection).
  Future<String?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_authBaseUrl/signup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'email': _normalizeEmail(email),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body);

      if (response.statusCode != 200) {
        // `detail` is user-facing only as a plain string; FastAPI
        // validation errors arrive as a list, whose toString() is a
        // dump.
        return body['detail'] is String
            ? body['detail'] as String
            : 'Something went wrong. Please try again.';
      }

      await login(
        body['name'] ?? name,
        userId: body['user_id']?.toString(),
        token: body['token'] as String?,
        tokenExpiresAt: body['expires_at'] != null
            ? DateTime.tryParse(body['expires_at'] as String)
            : null,
      );
      return null;
    } catch (e) {
      debugPrint('signUp error: $e');
      return ApiError.friendly(e);
    }
  }

  /// Validates credentials against the server. Returns null on success,
  /// or an error message string on failure.
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_authBaseUrl/signin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _normalizeEmail(email),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body);

      // 403 + needs_verification: credentials are correct but the email
      // was never verified. Stash the email so the sign-in screen can
      // route to the verification-code screen instead of Home.
      if (response.statusCode == 403 && body['needs_verification'] == true) {
        _emailNeedingVerification = _normalizeEmail(email);
        return body['detail'] is String
            ? body['detail'] as String
            : 'Please verify your email first.';
      }

      if (response.statusCode != 200) {
        return body['detail'] is String
            ? body['detail'] as String
            : 'Something went wrong. Please try again.';
      }

      await login(
        body['name'] ?? '',
        userId: body['user_id']?.toString(),
        token: body['token'] as String?,
        tokenExpiresAt: body['expires_at'] != null
            ? DateTime.tryParse(body['expires_at'] as String)
            : null,
      );
      return null;
    } catch (e) {
      debugPrint('signIn error: $e');
      return ApiError.friendly(e);
    }
  }

  /// Asks the server to email a 6-digit verification code. Used by the
  /// verification screen after signup ('signup') and by the password
  /// reset flow ('reset'). Returns (error, devCode): error is null on
  /// success, and devCode is only ever non-null in LOCAL DEV when the
  /// server has no SMTP credentials configured -- the code is shown on
  /// screen and printed to the server console instead of emailed, so the
  /// flow stays testable without a real inbox.
  Future<({String? error, String? devCode})> requestVerificationCode({
    required String email,
    required String purpose, // 'signup' or 'reset'
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_authBaseUrl/verify_email/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _normalizeEmail(email),
              'purpose': purpose,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body);
      if (response.statusCode != 200) {
        return (
          error: body['detail'] is String
              ? body['detail'] as String
              : 'Something went wrong. Please try again.',
          devCode: null,
        );
      }
      return (
        error: null,
        devCode: body['dev_code'] is String ? body['dev_code'] as String : null,
      );
    } catch (e) {
      debugPrint('requestVerificationCode error: $e');
      return (error: ApiError.friendly(e), devCode: null);
    }
  }

  /// Confirms a 6-digit code. For purpose 'signup' the server marks the
  /// email verified and returns the account's first session token, so a
  /// successful confirm immediately signs the user in. Returns null on
  /// success, or an error message on failure.
  Future<String?> confirmVerificationCode({
    required String email,
    required String purpose, // 'signup' or 'reset'
    required String code,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_authBaseUrl/verify_email/confirm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _normalizeEmail(email),
              'purpose': purpose,
              'code': code.trim(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body);
      if (response.statusCode != 200) {
        return body['detail'] is String
            ? body['detail'] as String
            : 'That code is invalid. Please try again.';
      }

      if (purpose == 'signup') {
        _emailNeedingVerification = null;
        await login(
          body['name'] ?? '',
          userId: body['user_id']?.toString(),
          token: body['token'] as String?,
          tokenExpiresAt: body['expires_at'] != null
              ? DateTime.tryParse(body['expires_at'] as String)
              : null,
        );
      }
      return null;
    } catch (e) {
      debugPrint('confirmVerificationCode error: $e');
      return ApiError.friendly(e);
    }
  }

  /// Sets a new password for an existing account -- but ONLY after the
  /// emailed 6-digit code proves the caller controls that email. Request
  /// the code first via requestVerificationCode(purpose: 'reset'), then
  /// call this with the code from the email. Returns null on success, or
  /// an error message on failure.
  Future<String?> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_authBaseUrl/reset_password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _normalizeEmail(email),
              'code': code.trim(),
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body);
        return body['detail'] is String
            ? body['detail'] as String
            : 'Something went wrong. Please try again.';
      }

      return null;
    } catch (e) {
      debugPrint('resetPassword error: $e');
      return ApiError.friendly(e);
    }
  }

  /// Drops the local session (flag + token) without contacting the server.
  /// Used when the app already knows the session is unusable (no token,
  /// expired, or rejected with a 401) so the user can sign in again cleanly.
  Future<void> clearSession() async {
    _isLoggedIn = false;
    _userId = null;
    _authToken = null;
    _tokenExpiresAt = null;
    _emailNeedingVerification = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    // Wipes AuthSession's memory mirror and the encrypted store (and any
    // legacy plain-text copies) in one place.
    await AuthSession.clear();
  }

  /// Call from the Settings logout button. Clears the flag so Splash
  /// routes back to Sign In next launch, keeps cycle/log data intact by
  /// default, and -- when [removeData] is true -- additionally erases
  /// this account's locally stored cycle data (plus the legacy unscoped
  /// copies some first account inherited them from), the profile sync
  /// caches, and resets the in-memory cycle state to blank.
  /// Also best-effort invalidates the session token server-side and
  /// clears it locally so no stale Authorization header lingers around.
  Future<void> logout({bool removeData = false}) async {
    final tokenToInvalidate = _authToken;
    // Remember WHICH account is leaving before the identity is cleared,
    // so "remove data" can target its scoped keys.
    final removedUserId = _userId;

    _isLoggedIn = false;
    _userId = null;
    _authToken = null;
    _tokenExpiresAt = null;
    _emailNeedingVerification = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);

    if (removeData) {
      // "Remove cycle data & log out": wipe scoped keys for this
      // account, the legacy unscoped copies (which the first signed-in
      // account inherited its data from, and which anonymous use
      // writes to), and the once-only migration marker so nothing
      // re-inherits from now-erased data.
      for (final base in _userScopedKeys) {
        if (removedUserId != null && removedUserId.isNotEmpty) {
          await prefs.remove('$base:$removedUserId');
        }
        await prefs.remove(base);
      }
      await prefs.remove(_legacyMigratedMarker);
      // Profile-sync caches for every identity on this device, so the
      // removed account's cache can never resurface its data after a
      // "remove" logout (accounts re-fetch their remote copy on sign-in).
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('health_profile_cache_')) {
          await prefs.remove(key);
        }
      }
      // In-memory: blank cycle state so no removed data lingers on
      // screen behind the sign-in navigation.
      _cycleData = CycleData();
      _selectedPeriodDate = null;
      _dailyLogs = {};
      _remindersEnabled = true;
      _userName = '';
      HealthProfileService().discardCachedProfile();
      // The identity flip was notified above; notify again so the UI
      // repaints with the blanked state.
      notifyListeners();
    }

    // Single source of truth: AuthSession wipes its memory mirror AND
    // the encrypted store (plus legacy plain-text copies).
    await AuthSession.clear();

    if (tokenToInvalidate != null) {
      try {
        await http
            .post(
              Uri.parse('$_authBaseUrl/logout'),
              headers: {'Authorization': 'Bearer $tokenToInvalidate'},
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Best-effort only -- the local session is already cleared
        // above regardless of whether this network call succeeds.
      }
    }
  }

  void updateUserName(String name) async {
    _userName = name;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // Scoped per account (falls back to the bare key when signed out).
    await prefs.setString(_scopedKey('userName'), name);
  }

  Future<void> _saveCycleData() async {
    final prefs = await SharedPreferences.getInstance();
    // Scoped per account (falls back to the bare key when signed out),
    // so a second account signing in never reads the first one's dates.
    // Task 3.2: an unset period start removes the key instead of
    // persisting a placeholder, so the load path reads it back as unset.
    final start = _cycleData.lastPeriodStart;
    if (start != null) {
      await prefs.setInt(
        _scopedKey('lastPeriodStart'),
        start.millisecondsSinceEpoch,
      );
    } else {
      await prefs.remove(_scopedKey('lastPeriodStart'));
    }
    await prefs.setInt(_scopedKey('cycleLength'), _cycleData.cycleLength);
    await prefs.setInt(_scopedKey('periodDuration'), _cycleData.periodDuration);
  }

  Future<void> _saveDailyLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> encoded = _dailyLogs.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    // Scoped per account (falls back to the bare key when signed out).
    await prefs.setString(_scopedKey('dailyLogs'), jsonEncode(encoded));
  }

  void updateLastPeriodStart(DateTime date) {
    _cycleData.lastPeriodStart = date;
    _saveCycleData();
    notifyListeners();
  }

  void updateCycleLength(int length) {
    _cycleData.cycleLength = length;
    _saveCycleData();
    notifyListeners();
  }

  void updatePeriodDuration(int duration) {
    _cycleData.periodDuration = duration;
    _saveCycleData();
    notifyListeners();
  }

  void logPeriodStartToday() {
    selectPeriodDate(DateTime.now());
  }

  void selectPeriodDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);

    if (_selectedPeriodDate != null) {
      final oldKey = _keyFor(_selectedPeriodDate!);
      if (_dailyLogs.containsKey(oldKey)) {
        _dailyLogs[oldKey]!.isPeriodDay = false;
      }
    }

    if (_selectedPeriodDate != null &&
        _isSameDay(_selectedPeriodDate!, normalized)) {
      _selectedPeriodDate = null;
    } else {
      _selectedPeriodDate = normalized;
      final newKey = _keyFor(normalized);
      final existing = _dailyLogs[newKey] ?? DailyLog();
      existing.isPeriodDay = true;
      _dailyLogs[newKey] = existing;

      _cycleData.lastPeriodStart = normalized;
      _saveCycleData();
    }

    _saveDailyLogs();
    notifyListeners();
  }

  void logMood(DateTime date, String mood) {
    final key = _keyFor(date);
    final existing = _dailyLogs[key] ?? DailyLog();
    existing.mood = mood;
    _dailyLogs[key] = existing;
    _saveDailyLogs();
    notifyListeners();
  }

  void logSymptoms(DateTime date, List<String> symptoms) {
    final key = _keyFor(date);
    final existing = _dailyLogs[key] ?? DailyLog();
    existing.symptoms = symptoms;
    _dailyLogs[key] = existing;
    _saveDailyLogs();
    notifyListeners();
  }

  void logFlowIntensity(DateTime date, String intensity) {
    final key = _keyFor(date);
    final existing = _dailyLogs[key] ?? DailyLog();
    existing.flowIntensity = intensity;
    _dailyLogs[key] = existing;
    _saveDailyLogs();
    notifyListeners();
  }

  /// Removes one logged field from a day (used by the Health Diary
  /// timeline's per-entry delete button). `field` is exactly one of
  /// 'period', 'mood', or 'symptoms'. Once a day's log ends up completely
  /// empty it is dropped from the map entirely.
  void clearCycleField(DateTime date, String field) {
    final key = _keyFor(DateTime(date.year, date.month, date.day));
    final existing = _dailyLogs[key];
    if (existing == null) return;

    switch (field) {
      case 'period':
        existing.isPeriodDay = false;
        existing.flowIntensity = null;
        // Clearing the period-day log on the currently selected period
        // date also clears the selection (same as tapping the day again
        // in the cycle calendar).
        if (_selectedPeriodDate != null &&
            _isSameDay(_selectedPeriodDate!, date)) {
          _selectedPeriodDate = null;
        }
        break;
      case 'mood':
        existing.mood = null;
        break;
      case 'symptoms':
        existing.symptoms = [];
        break;
    }

    final isEmptyLog =
        existing.isPeriodDay != true &&
        (existing.flowIntensity == null || existing.flowIntensity!.isEmpty) &&
        (existing.mood == null || existing.mood!.isEmpty) &&
        existing.symptoms.isEmpty;
    if (isEmptyLog) {
      _dailyLogs.remove(key);
    }

    _saveDailyLogs();
    notifyListeners();
  }
}
