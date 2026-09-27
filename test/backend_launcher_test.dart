// backend_launcher_test.dart
//
// Regression tests for the backend auto-start path.
//
// Why these exist: `resolvePython()` used to look for the virtual environment
// at `<pcos_ml_project>/../.venv`, but this repo's venv actually lives at
// `<pcos_ml_project>/venv`. The lookup therefore always missed and silently
// fell through to whatever `python` was on PATH. On a machine without the
// dependencies the spawned server died immediately, and the user just saw
// "could not reach the server" at sign-in with no indication that the backend
// was the thing that was missing. That failure recurred, so the path search is
// now asserted here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellness_saheli/services/backend_launcher.dart';

void main() {
  tearDown(BackendLauncher.resetForTesting);

  test('finds the backend project from the Flutter project directory', () {
    BackendLauncher.resetForTesting();
    final root = BackendLauncher.resolveBackendRoot();
    expect(
      root,
      isNotNull,
      reason: 'must locate pcos_ml_project by walking up from the cwd',
    );
    expect(
      File('${root!.path}${Platform.pathSeparator}app_backend'
              '${Platform.pathSeparator}main.py')
          .existsSync(),
      isTrue,
      reason: 'the resolved root must actually contain the FastAPI app',
    );
  });

  test('resolves a python that can import the server dependencies', () {
    BackendLauncher.resetForTesting();
    final python = BackendLauncher.resolvePython();
    expect(
      python,
      isNotNull,
      reason: 'a usable interpreter must be found, otherwise the app cannot '
          'auto-start the backend and sign-in always fails',
    );

    // The chosen interpreter must genuinely be able to run the server, not
    // merely exist. This is the check that was missing.
    final probe = Process.runSync(
      python!,
      ['-c', 'import uvicorn, fastapi, app_backend.main'],
      workingDirectory: BackendLauncher.resolveBackendRoot()?.path,
    );
    expect(
      probe.exitCode,
      0,
      reason: 'resolved interpreter $python cannot import the server '
          'dependencies:\n${probe.stdout}\n${probe.stderr}',
    );
  });

  test('prefers the project virtual environment over PATH', () {
    BackendLauncher.resetForTesting();
    final root = BackendLauncher.resolveBackendRoot();
    final python = BackendLauncher.resolvePython();
    expect(root, isNotNull, reason: 'backend root is required for this check');
    expect(python, isNotNull);

    // If the repo's own venv is present, that is what must be used. Falling
    // back to PATH risks a different set of package versions than the model
    // and the server were tested against.
    final sep = Platform.pathSeparator;
    final projectVenvs = [
      '${root!.path}$sep.venv',
      '${root.path}$sep' 'venv',
    ];
    final hasProjectVenv =
        projectVenvs.any((d) => Directory(d).existsSync());
    if (hasProjectVenv) {
      expect(
        python,
        startsWith(root.path),
        reason: 'the project venv exists at $projectVenvs, so PATH python '
            'must not be preferred',
      );
    }
  });
}
