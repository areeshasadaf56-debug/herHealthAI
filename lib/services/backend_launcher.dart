// backend_launcher.dart
//
// Starts the FastAPI backend automatically on Windows desktop.
//
// Why this exists: the app used to assume the backend was already running.
// If it wasn't, every screen that talked to the API showed
// "could not reach the server" -- the user had to remember to launch a
// Python server by hand before the Flutter app was usable. This service
// makes the app self-sufficient: it checks the API, and if nothing is
// listening it spawns uvicorn itself and waits until the API answers.
//
// Design notes:
//  * Health-check first. If a backend is already up (started manually,
//    or left over from a previous run) it is reused, so launching the app
//    twice never creates a duplicate server or a port conflict.
//  * Windows only. On a phone the backend is a remote server and must
//    not be spawned from the device.
//  * Logs go to a file instead of a console, because a Flutter Windows
//    build has no attached console and output would just be lost.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../config/api_config.dart';

class BackendLauncher {
  /// The process we spawned, if any. Kept so it can be reused/stopped.
  static Process? _process;

  /// Where we found (or should look for) the backend project.
  static Directory? _backendRoot;

  /// Test seam. When set, [ensureRunning] returns this value immediately
  /// without touching the network or spawning a process.
  ///
  /// Widget tests must set this: the real implementation polls with
  /// `Future.delayed`, which leaves pending timers and makes
  /// `pumpAndSettle` fail, and it would try to launch a real Python
  /// server during the test run.
  static Future<bool> Function()? override;

  /// Restores real behaviour. Call from a test's tearDown.
  static void resetForTesting() {
    override = null;
    _process = null;
    _backendRoot = null;
  }

  /// Only Windows desktops can host a local Python backend.
  /// `kIsWeb` is checked before any `dart:io` access because on web `dart:io`
  /// is a stub that throws `UnsupportedError: Platform._operatingSystem`.
  static bool get canAutoStart => !kIsWeb && Platform.isWindows;

  /// True when [ApiConfig] points at this machine, i.e. starting a local
  /// server is actually the right thing to do. If the app is pointed at a
  /// deployed server we must never spawn a local one.
  static bool get _targetIsLocal {
    final host = Uri.tryParse(ApiConfig.baseUrl)?.host;
    return host == null ||
        host == '127.0.0.1' ||
        host == 'localhost' ||
        host == '10.0.2.2';
  }

  /// Returns true if the API answers its health check.
  static Future<bool> isHealthy() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final request = await client
            .getUrl(Uri.parse('${ApiConfig.baseUrl}/'))
            .timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(
          const Duration(seconds: 3),
        );
        // Drain so the socket can be reused/closed cleanly.
        await response.drain<void>();
        return response.statusCode == 200;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      // Connection refused, DNS failure, timeout -- all just mean
      // "not running right now".
      return false;
    }
  }

  /// Finds the folder containing `pcos_ml_project/app_backend/main.py`.
  ///
  /// Walks up from the current directory and from the executable's
  /// directory, so this works both under `flutter run` (cwd is the Flutter
  /// project) and from a built `wellness_saheli.exe` nested in
  /// `build/windows/x64/runner/<mode>/`.
  ///
  /// Can be overridden at build time with
  /// `--dart-define=BACKEND_ROOT=/path/to/pcos_ml_project`.
  static Directory? resolveBackendRoot() {
    if (_backendRoot != null) return _backendRoot;

    const override = String.fromEnvironment('BACKEND_ROOT');
    if (override.isNotEmpty) {
      final dir = Directory(override);
      if (_looksLikeBackend(dir)) {
        return _backendRoot = dir;
      }
    }

    final starts = <Directory>[
      Directory.current,
      // Resolves to the folder containing the .exe.
      File(Platform.resolvedExecutable).parent,
    ];

    for (final start in starts) {
      var dir = start.absolute;
      // Bounded walk so we can't spin forever on a strange layout.
      for (var i = 0; i < 8; i++) {
        final candidate = Directory(
          '${dir.path}${Platform.pathSeparator}'
          'pcos_ml_project',
        );
        if (_looksLikeBackend(candidate)) {
          return _backendRoot = candidate;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  static bool _looksLikeBackend(Directory dir) {
    if (!dir.existsSync()) return false;
    return File(
      '${dir.path}${Platform.pathSeparator}app_backend'
      '${Platform.pathSeparator}main.py',
    ).existsSync();
  }

  /// Locates a usable Python interpreter, preferring the project's own
  /// virtual environment over anything on PATH.
  ///
  /// A candidate is only accepted if it can actually import the packages the
  /// server needs. Finding "a python" is not enough: the launcher used to fall
  /// back to whatever `python` was on PATH, which on a machine without the
  /// dependencies produced a server that died on startup and left the user with
  /// the same "could not reach the server" error with nothing to act on.
  static String? resolvePython() {
    final root = resolveBackendRoot();
    final sep = Platform.pathSeparator;
    final exe = Platform.isWindows ? 'python.exe' : 'python';

    // Every layout this repo has actually used, most specific first. The venv
    // is inside pcos_ml_project as `venv`; an earlier version looked only for
    // `../.venv` next to the folder, which does not exist, so auto-start
    // silently fell through to PATH on every launch.
    String inVenv(String base, String name) {
      final bin = Platform.isWindows ? 'Scripts' : 'bin';
      return '$base$sep$name$sep$bin$sep$exe';
    }

    final venvCandidates = <String>[
      if (root != null) ...[
        inVenv(root.path, '.venv'),
        inVenv(root.path, 'venv'),
        inVenv('${root.path}$sep..', '.venv'),
        inVenv('${root.path}$sep..', 'venv'),
      ],
    ];

    for (final candidate in venvCandidates) {
      if (File(candidate).existsSync() && _canServe(candidate)) {
        return candidate;
      }
    }

    // Last resort: whatever python is on PATH, but only if it can actually run
    // the server.
    for (final candidate in ['python', 'python3']) {
      if (_canServe(candidate)) return candidate;
    }
    return null;
  }

  /// Whether [python] can import what `uvicorn app_backend.main:app` needs.
  ///
  /// A cheap import check is far better than discovering the problem 45
  /// seconds later as a poll timeout with no explanation.
  static bool _canServe(String python) {
    // Only bare command names need a shell. `runInShell: true` hands the
    // command line to cmd.exe unquoted, so an absolute path containing a space
    // -- and this repo's does, "reproductive-health app" -- is split at the
    // space and the probe fails, which silently demoted the project venv in
    // favour of PATH python. Process.start, used for the real spawn, does not
    // have this problem, so the probe must not introduce it.
    final isAbsolute =
        Platform.isWindows && (python.contains(':\\') || python.startsWith('\\\\'));
    try {
      final result = Process.runSync(
        python,
        ['-c', 'import uvicorn, fastapi, app_backend.main'],
        runInShell: !isAbsolute,
        workingDirectory: resolveBackendRoot()?.path,
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Ensures a backend is available, starting one if needed.
  ///
  /// Returns true when the API is reachable by the time this completes.
  /// Never throws -- a failure here must not take the whole app down, it
  /// just means the screens will show their own error.
  static Future<bool> ensureRunning({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final testOverride = override;
    if (testOverride != null) return testOverride();

    // Already up (manually started, or our own from a previous launch).
    if (await isHealthy()) return true;

    if (!canAutoStart || !_targetIsLocal) return false;

    final root = resolveBackendRoot();
    if (root == null) return false;

    final python = resolvePython();
    if (python == null) return false;

    await _startProcess(python: python, root: root);
    if (_process == null) return false;

    // Poll until it answers. Loading the ML model makes the first start
    // slow, so this waits generously rather than a fixed short delay.
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (await isHealthy()) return true;
    }
    return false;
  }

  static Future<void> _startProcess({
    required String python,
    required Directory root,
  }) async {
    final sep = Platform.pathSeparator;
    final logDir = Directory(
      '${root.path}$sep'
      'logs',
    );
    if (!logDir.existsSync()) logDir.createSync(recursive: true);
    final logFile = File(
      '${logDir.path}$sep'
      'backend_auto.log',
    );

    void log(String prefix, String line) {
      try {
        logFile.writeAsStringSync(
          '$prefix$line\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Logging must never break startup.
      }
    }

    // Pass the key through if the user has one in their environment, so
    // the auto-started backend can reach the real AI service.
    final groqKey = Platform.environment['GROQ_API_KEY'];
    final environment = <String, String>{'PYTHONUNBUFFERED': '1'};
    if (groqKey != null && groqKey.isNotEmpty) {
      environment['GROQ_API_KEY'] = groqKey;
    }

    try {
      final process = await Process.start(
        python,
        [
          '-m',
          'uvicorn',
          'app_backend.main:app',
          '--host',
          ApiConfig.localBindHost,
          '--port',
          '${ApiConfig.port}',
        ],
        workingDirectory: root.path,
        // Detached so the backend outlives any Flutter child process and
        // can be reused on the next app launch.
        mode: ProcessStartMode.detachedWithStdio,
        environment: environment,
      );
      _process = process;
      process.stdout
          .transform(utf8.decoder)
          .listen((line) => log('OUT ', line))
          .onError((Object _) {});
      process.stderr
          .transform(utf8.decoder)
          .listen((line) => log('ERR ', line))
          .onError((Object _) {});
    } catch (error) {
      _process = null;
      log('FAIL ', 'Could not start the backend: $error');
    }
  }

  /// Stops a backend we started. Safe to call when we didn't start one.
  static Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    try {
      process.kill();
    } catch (_) {
      // Already gone.
    }
  }
}
