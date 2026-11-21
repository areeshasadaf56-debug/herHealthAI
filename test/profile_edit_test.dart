import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellness_saheli/l10n/language_provider.dart';
import 'package:wellness_saheli/screens/profile_edit_screen.dart';
import 'package:wellness_saheli/services/health_profile_service.dart';
import 'package:wellness_saheli/theme/app_theme.dart';

/// Task 9.1: the Profile tab used to be read-only (SRS FR-84). This test
/// drives the new editor end-to-end: values typed into a blank profile
/// are validated, persisted to the same local cache the rest of the app
/// reads, and rejected when out of range.
class _StubClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(const <int>[]), 404);
}

/// Minimal host page: the editor pops itself after saving, so the test
/// must push it onto a route instead of making it the root.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const ValueKey('open-editor'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
          ),
          child: const Text('Edit profile'),
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    HealthProfileService.overrideHttpClient(_StubClient());

    const secureChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);
  });

  tearDown(() {
    HealthProfileService.overrideHttpClient(null);
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => LanguageProvider())],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const _Host(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-editor')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsOneWidget);
    // The editor loads the profile before it builds the form.
    expect(find.text('Save profile'), findsOneWidget);
  }

  Future<void> tapSave(WidgetTester tester) async {
    // The save button sits at the bottom of a long form. Coordinate taps
    // at that offset are unreliable under the test viewport (the button
    // renders below the 800x600 surface), so drive the same callback the
    // tap performs; the assertions below are on the resulting save.
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('profile-save')))
        .onPressed!();
    await tester.pumpAndSettle();
  }

  testWidgets('saves demographics to the local profile cache', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(find.byKey(const ValueKey('profile-age')), '30');
    await tester.enterText(find.byKey(const ValueKey('profile-weight')), '58');
    await tester.enterText(find.byKey(const ValueKey('profile-height')), '162');

    await tapSave(tester);

    // Saved -> snackbar shown, editor popped back to the host page.
    expect(find.text('Health profile saved'), findsOneWidget);
    expect(find.byType(ProfileEditScreen), findsNothing);

    // The values are in the same SharedPreferences cache the app reads.
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = prefs.getKeys().firstWhere(
      (k) => k.startsWith('health_profile_cache_'),
    );
    final json = jsonDecode(prefs.getString(cacheKey)!) as Map<String, dynamic>;
    expect(json['demographics']['age_yrs'], 30);
    expect((json['demographics']['weight_kg'] as num).toDouble(), 58.0);
    expect((json['demographics']['height_cm'] as num).toDouble(), 162.0);

    // And a fresh load (new screen, cold cache read) shows them again.
    final reloaded = await HealthProfileService().loadProfile();
    expect(reloaded.demographics.ageYrs, 30);
    expect(reloaded.demographics.weightKg, 58.0);
    expect(reloaded.demographics.heightCm, 162.0);
  });

  testWidgets('rejects an out-of-range age without saving', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);

    await tester.enterText(find.byKey(const ValueKey('profile-age')), '5');
    await tapSave(tester);

    // Still on the editor, with the range error visible.
    expect(find.byType(ProfileEditScreen), findsOneWidget);
    expect(find.text('Must be between 10 and 100'), findsOneWidget);
    expect(find.text('Health profile saved'), findsNothing);

    // Nothing was written.
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.startsWith('health_profile_cache_')),
      isEmpty,
    );
  });
}
