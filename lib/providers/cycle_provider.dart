import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/cycle_data.dart';
import '../models/daily_log.dart';

/// Whether the backend the app is talking to lives on this machine.
///
/// `10.0.2.2` is the Android emulator's alias for the host's loopback, so a
/// failure there is a local-process failure, not an internet one.
bool get _backendIsLocal {
  final host = Uri.tryParse(ApiConfig.baseUrl)?.host ?? '';
  return host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '10.0.2.2' ||
      host == '0.0.0.0';
}

/// Turns a transport-layer failure into a user-facing message.
///
/// The friendly wording is preserved, but the real cause is appended instead
/// of being discarded by a bare `catch (_)`. Several very different failures
/// (DNS/socket refusal, CORS rejection in a browser, TLS, unsupported
/// operation on the web target) were previously all reported as the same
/// unhelpful "could not reach the server" text, which hid the actual defect.
///
/// Telling the user to "check your internet connection" was actively wrong in
/// the most common case: the API is a local FastAPI process, so the usual
/// cause is simply that the backend is not running. `flutter run` does not
/// start it -- `run_app.ps1` / `run_app.bat` do. That was reported as an
/// internet problem and recurred more than once, so the local case now names
/// the real cause and the command that fixes it.
String _transportError(Object error) {
  final type = error.runtimeType.toString();
  final detail = error.toString().trim();
  final cause = detail.isEmpty ? type : '$type: $detail';
  if (_backendIsLocal) {
    return 'Cannot reach the local backend at ${ApiConfig.baseUrl}. '
        'It is not running. Start it with run_app.ps1 (Windows) or '
        'run_app.bat -- those start the API and the app together. '
        'Note: flutter run on its own does not start the backend. ($cause)';
  }
  return 'Could not reach the server. Please check your internet connection '
      'and try again. ($cause)';
}

class PasswordResetRequestResult {
  final String? error;
  final String? debugCode;
  const PasswordResetRequestResult({this.error, this.debugCode});
}

class CycleProvider extends ChangeNotifier {
  CycleData _cycleData = CycleData(
    lastPeriodStart: DateTime.now().subtract(const Duration(days: 14)),
  );

  bool _isLoaded = false;
  bool _remindersEnabled = true;

  // --- Auth / profile state ---
  bool _isLoggedIn = false;
  String _userName = '';

  // The server-issued account id + session token. These are what
  // /profile and /chat now require (Authorization: Bearer <token>) --
  // see HealthProfileService and AiService, which read these same
  // SharedPreferences keys directly. Previously the app used a
  // random per-device UUID for profile sync and never sent any auth
  // header at all, so /profile could be read/written by anyone who
  // knew or guessed a user_id. This is what fixes that.
  String? _authToken;
  String? _accountUserId;

  // When the server-issued token stops being valid. The backend returns
  // `expires_at` with every signup/signin, and sessions are only good for
  // that window, so the app checks it locally before trusting a stored
  // token -- otherwise a returning user would sit on the home screen with
  // a dead Authorization header and every request would 401.
  DateTime? _tokenExpiresAt;

  // Accounts live on the backend server (see /signup, /signin,
  // /reset_password) so they survive app reinstalls and work across
  // devices.

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
  String? get authToken => _authToken;
  String? get accountUserId => _accountUserId;
  DateTime? get tokenExpiresAt => _tokenExpiresAt;

  /// True when there is a stored token that has not passed its expiry.
  /// A token with no recorded expiry is treated as valid, because older
  /// installs stored the token without one and dropping those sessions
  /// would sign every existing user out on upgrade.
  bool get hasValidSession {
    final token = _authToken;
    if (token == null || token.isEmpty) return false;
    final expiry = _tokenExpiresAt;
    if (expiry == null) return true;
    return expiry.isAfter(DateTime.now());
  }

  CycleProvider() {
    _loadData();
  }

  ThemeMode? get themeMode => null;

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
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    _userName = prefs.getString('userName') ?? '';
    _authToken = prefs.getString('authToken');
    final expiresMillis = prefs.getInt('authTokenExpiresAt');
    _tokenExpiresAt = expiresMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresMillis)
        : null;

    // A token that has already expired is useless -- clear it so the
    // rest of the app correctly treats this as "no session" rather than
    // attaching a dead Authorization header to every request.
    if (_authToken != null && !hasValidSession) {
      _authToken = null;
      _accountUserId = null;
      _tokenExpiresAt = null;
      _isLoggedIn = false;
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

  /// Call on successful sign in / sign up. Persists the logged-in
  /// flag, name, and (when provided) the session token + account id
  /// that every authenticated request now needs.
  Future<void> login(
    String name, {
    String? userId,
    String? token,
    DateTime? expiresAt,
  }) async {
    _isLoggedIn = true;
    _userName = name;
    if (userId != null) _accountUserId = userId;
    if (token != null) _authToken = token;
    if (expiresAt != null) _tokenExpiresAt = expiresAt;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userName', name);
    if (userId != null) await prefs.setString('accountUserId', userId);
    if (token != null) await prefs.setString('authToken', token);
    if (expiresAt != null) {
      await prefs.setInt(
        'authTokenExpiresAt',
        expiresAt.millisecondsSinceEpoch,
      );
    }
  }

  /// Reads the `expires_at` timestamp the backend sends with every session.
  /// Returns null when it is missing or unparseable, which the expiry check
  /// then treats as "no known expiry" rather than "expired".
  DateTime? _parseExpiry(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  /// Safely decodes a JSON response body. Returns an empty map instead
  /// of throwing when the body is empty or not valid JSON (e.g. a
  /// proxy error page, a crashed-server HTML response, or a timeout
  /// page) so callers can still build a sensible error message instead
  /// of the whole request falling through to a generic "could not
  /// reach the server" message that hides the real problem.
  Map<String, dynamic> _safeDecode(String rawBody) {
    if (rawBody.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  String _errorMessageFor(http.Response response) {
    final body = _safeDecode(response.body);
    final detail = body['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    // Fall back to something that at least tells you a real server
    // response came back, rather than pretending it's a network issue.
    return 'Server returned an error (status ${response.statusCode}). Please try again.';
  }

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
            Uri.parse('${ApiConfig.baseUrl}/signup'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'email': _normalizeEmail(email),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return _errorMessageFor(response);
      }

      final body = _safeDecode(response.body);
      await login(
        body['name'] ?? name,
        userId: body['user_id']?.toString(),
        token: body['token'] as String?,
        expiresAt: _parseExpiry(body['expires_at']),
      );
      return null;
    } on http.ClientException catch (error) {
      return _transportError(error);
    } catch (error) {
      return _transportError(error);
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
            Uri.parse('${ApiConfig.baseUrl}/signin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _normalizeEmail(email),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return _errorMessageFor(response);
      }

      final body = _safeDecode(response.body);
      await login(
        body['name'] ?? '',
        userId: body['user_id']?.toString(),
        token: body['token'] as String?,
        expiresAt: _parseExpiry(body['expires_at']),
      );
      return null;
    } on http.ClientException catch (error) {
      return _transportError(error);
    } catch (error) {
      return _transportError(error);
    }
  }

  /// Step 1 of password reset: ask the server to email a verification
  /// code. Returns a result whose `error` is non-null on failure.
  ///
  /// `debugCode` is only ever populated when the backend is running with
  /// debug reset codes enabled (development). In production the server
  /// deliberately omits it so account existence can't be probed, and the
  /// UI must not depend on it.
  Future<PasswordResetRequestResult> requestPasswordReset({
    required String email,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/reset_password/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': _normalizeEmail(email)}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return PasswordResetRequestResult(error: _errorMessageFor(response));
      }

      final body = _safeDecode(response.body);
      final debugCode = body['debug_code'];
      return PasswordResetRequestResult(
        debugCode: debugCode is String && debugCode.isNotEmpty
            ? debugCode
            : null,
      );
    } catch (error) {
      return PasswordResetRequestResult(
        error: _transportError(error),
      );
    }
  }

  /// Resets the password for an existing account on the server. Returns
  /// null on success, or an error message string on failure.
  Future<String?> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/reset_password/confirm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _normalizeEmail(email),
              'code': code.trim(),
              'new_password': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return _errorMessageFor(response);
      }

      return null;
    } catch (error) {
      return _transportError(error);
    }
  }

  /// Call from the Settings logout button. Clears the flag + session
  /// so Splash routes back to Sign In next launch, but keeps cycle/log
  /// data intact. Best-effort tells the server to invalidate the
  /// token too -- if that call fails (offline, etc.) local logout
  /// still proceeds.
  Future<void> logout() async {
    final tokenToInvalidate = _authToken;

    _isLoggedIn = false;
    _authToken = null;
    _accountUserId = null;
    _tokenExpiresAt = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('authToken');
    await prefs.remove('accountUserId');
    await prefs.remove('authTokenExpiresAt');

    if (tokenToInvalidate != null) {
      try {
        await http
            .post(
              Uri.parse('${ApiConfig.baseUrl}/logout'),
              headers: {'Authorization': 'Bearer $tokenToInvalidate'},
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Best-effort only -- local logout already happened above.
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
}
