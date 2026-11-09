import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cycle_data.dart';
import '../models/daily_log.dart';
import '../config/api_config.dart';
import '../services/auth_session.dart';

class CycleProvider extends ChangeNotifier {
  CycleData _cycleData = CycleData(
    lastPeriodStart: DateTime.now().subtract(const Duration(days: 14)),
  );

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

  int get currentCycleDay => _cycleData.getCurrentCycleDay();
  String get currentPhase => _cycleData.getPhase();
  int get daysUntilNextPeriod => _cycleData.daysUntilNextPeriod();
  int get cycleLength => _cycleData.cycleLength;
  int get periodDuration => _cycleData.periodDuration;

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

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final lastPeriodMillis = prefs.getInt('lastPeriodStart');
    final cycleLength = prefs.getInt('cycleLength');
    final periodDuration = prefs.getInt('periodDuration');

    if (lastPeriodMillis != null) {
      _cycleData = CycleData(
        lastPeriodStart: DateTime.fromMillisecondsSinceEpoch(lastPeriodMillis),
        cycleLength: cycleLength ?? 28,
        periodDuration: periodDuration ?? 5,
      );
      _selectedPeriodDate = _cycleData.lastPeriodStart;
    }

    final logsJson = prefs.getString('dailyLogs');
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

    _remindersEnabled = prefs.getBool('remindersEnabled') ?? true;

    // Restore auth/profile state so a returning user skips sign-in.
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
    _userName = prefs.getString('userName') ?? '';

    // "Logged in" must mean "has a usable session". Otherwise Splash
    // would route to Home while authenticated calls fail with 401.
    if (_isLoggedIn && !hasValidSession) {
      _isLoggedIn = false;
      await prefs.setBool('isLoggedIn', false);
    }

    _isLoaded = true;
    notifyListeners();
  }

  void toggleReminders(bool value) async {
    _remindersEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remindersEnabled', value);
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
    await prefs.setString('userName', name);
    // Secrets go through the shared AuthSession accessor, which keeps
    // its in-memory mirror AND the encrypted store (Android Keystore /
    // iOS Keychain) in sync, never plain SharedPreferences.
    await AuthSession.update(
      userId: userId,
      token: token,
      expiresAt: tokenExpiresAt,
    );
    // Drop any legacy plain-text copies left by older versions.
    await prefs.remove('authUserId');
    await prefs.remove('authToken');
    await prefs.remove('authTokenExpiresAt');
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
        return body['detail'] ?? 'Something went wrong. Please try again.';
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
      return 'Could not reach the server. Please check your internet connection and try again.';
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
        return body['detail'] ?? 'Please verify your email first.';
      }

      if (response.statusCode != 200) {
        return body['detail'] ?? 'Something went wrong. Please try again.';
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
      return 'Could not reach the server. Please check your internet connection and try again.';
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
      return (
        error:
            'Could not reach the server. Please check your internet connection and try again.',
        devCode: null,
      );
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
        return body['detail'] ?? 'That code is invalid. Please try again.';
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
      return 'Could not reach the server. Please check your internet connection and try again.';
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
        return body['detail'] ?? 'Something went wrong. Please try again.';
      }

      return null;
    } catch (_) {
      return 'Could not reach the server. Please check your internet connection and try again.';
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
  /// routes back to Sign In next launch, but keeps cycle/log data intact.
  /// Also best-effort invalidates the session token server-side and
  /// clears it locally so no stale Authorization header lingers around.
  Future<void> logout() async {
    final tokenToInvalidate = _authToken;

    _isLoggedIn = false;
    _userId = null;
    _authToken = null;
    _tokenExpiresAt = null;
    _emailNeedingVerification = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
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
    await prefs.setString('userName', name);
  }

  Future<void> _saveCycleData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'lastPeriodStart',
      _cycleData.lastPeriodStart.millisecondsSinceEpoch,
    );
    await prefs.setInt('cycleLength', _cycleData.cycleLength);
    await prefs.setInt('periodDuration', _cycleData.periodDuration);
  }

  Future<void> _saveDailyLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> encoded = _dailyLogs.map(
      (key, value) => MapEntry(key, value.toJson()),
    );
    await prefs.setString('dailyLogs', jsonEncode(encoded));
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
