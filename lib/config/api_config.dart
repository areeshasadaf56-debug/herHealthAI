// api_config.dart
//
// Single source of truth for the backend base URL. Every API service
// (eligibility_api_service.dart, ai_service.dart, pcos_api_service.dart,
// cycle_provider.dart) should read from ApiConfig.baseUrl rather than
// hardcoding a URL directly.
//
// The default is platform-aware. This used to hardcode
// 'http://10.0.2.2:8000', which only resolves on the Android emulator --
// on Windows and iOS nothing listens there, so every request failed with
// "could not reach the server" even when the backend was running.

import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Set at build/run time with:
  ///   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
  /// When non-empty this always wins, so a real deployment can point
  /// anywhere without touching code.
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// The Android emulator reaches the host machine's loopback through
  /// this special address.
  static const String _androidEmulator = 'http://10.0.2.2:8000';

  /// Correct for Windows desktop, iOS simulator, and macOS desktop.
  static const String _loopback = 'http://127.0.0.1:8000';

  /// The deployed PythonAnywhere host, written down in exactly one place.
  ///
  /// This is deliberately NOT a default. The resolution order in [baseUrl]
  /// still falls through to emulator/loopback, so a plain `flutter run`
  /// keeps talking to the local backend and local development is never
  /// silently pointed at production. Reach it in one of two explicit ways:
  ///
  ///   flutter run -d chrome --dart-define=API_BASE_URL=https://...
  ///   .\run_app.ps1 -Backend live
  static const String productionBaseUrl =
      'https://areeshasadaf56.pythonanywhere.com';

  /// Hosts that mean "a backend on this machine".
  static const Set<String> _localHosts = {'127.0.0.1', 'localhost', '10.0.2.2'};

  /// True when [baseUrl] points at the shared deployed host rather than at
  /// a backend on this machine.
  ///
  /// Compared against the host name rather than the scheme, because a plain
  /// `flutter run` also produces an `http://` URL -- loopback and the
  /// emulator alias are local, not remote.
  static bool get isRemote {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) return false;
    return !_localHosts.contains(uri.host);
  }

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    // kIsWeb must be checked first: on web `dart:io` is a stub that throws
    // `UnsupportedError` on any access, so Platform.* cannot be touched.
    if (kIsWeb) return _loopback;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _androidEmulator;
    }
    return _loopback;
  }

  /// Port the backend is expected to listen on, parsed from [baseUrl].
  /// The auto-launcher uses this so a custom `--dart-define` port is
  /// respected instead of hardcoding 8000 in two places.
  static int get port {
    final uri = Uri.tryParse(baseUrl);
    if (uri != null && uri.hasPort) return uri.port;
    return baseUrl.startsWith('https') ? 443 : 80;
  }

  /// Host the backend should bind to when we start it ourselves.
  /// Loopback only -- this is a local dev/demo backend holding real
  /// health data, so it must not be exposed to the network.
  static String get localBindHost => '127.0.0.1';
}
