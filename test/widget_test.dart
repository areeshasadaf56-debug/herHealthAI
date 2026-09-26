import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellness_saheli/main.dart';
import 'package:wellness_saheli/providers/cycle_provider.dart';
import 'package:wellness_saheli/screens/settings_screen.dart';
import 'package:wellness_saheli/services/backend_launcher.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  // The splash screen now brings the backend up before routing. In tests
  // that must not happen: the real launcher polls a socket with
  // Future.delayed (leaving pending timers that fail pumpAndSettle) and
  // would spawn a real Python process. Stub it out instead.
  setUp(() {
    BackendLauncher.override = () async => true;
  });

  tearDown(() {
    BackendLauncher.resetForTesting();
  });

  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const WellnessSaheliApp());
    expect(find.byType(WellnessSaheliApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  test(
    'Launcher reports failure instead of throwing when unreachable',
    () async {
      // The splash calls this on every launch. Whatever happens, it must
      // return a bool promptly rather than throw or hang -- otherwise a
      // missing backend takes the whole app down at startup.
      BackendLauncher.override = () async => false;
      final result = await BackendLauncher.ensureRunning(
        timeout: const Duration(milliseconds: 50),
      );
      expect(result, isFalse);
    },
  );

  test('Launcher reports success when the API is already up', () async {
    BackendLauncher.override = () async => true;
    expect(await BackendLauncher.ensureRunning(), isTrue);
  });

  testWidgets('Settings logout clears the local session', (tester) async {
    final provider = CycleProvider();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await provider.login('Flutter Tester', userId: '1', token: 'test-token');

    await tester.pumpWidget(
      ChangeNotifierProvider<CycleProvider>.value(
        value: provider,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    final logoutButton = find.text('Log Out').first;
    await tester.ensureVisible(logoutButton);
    await tester.tap(logoutButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Log Out').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(provider.isLoggedIn, isFalse);
    expect(provider.authToken, isNull);
  });
}
