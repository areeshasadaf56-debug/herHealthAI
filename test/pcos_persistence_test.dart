import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellness_saheli/screens/pcos_screen.dart';
import 'package:wellness_saheli/services/health_profile_service.dart';
import 'package:wellness_saheli/services/pcos_api_service.dart';
import 'package:wellness_saheli/theme/app_theme.dart';

/// FR-21 / AC-22: a successful PCOS detection must write the form inputs
/// back to the profile (age, weight, height, cycle regularity, cycle
/// length), not just keep the result in widget state. Before the fix the
/// Diary's Profile tab stayed "Not set" no matter how many checks ran.
class _OfflineProfileClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(const <int>[]), 404);
}

/// Answers `/predict` with a valid result so the success path runs.
class _PredictClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'prediction': 'PCOS',
      'pcos_probability': 0.82,
      'model_used': 'test-model',
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    HealthProfileService.overrideHttpClient(_OfflineProfileClient());
    PcosApiService.overrideHttpClient(_PredictClient());

    const secureChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);
  });

  tearDown(() {
    HealthProfileService.overrideHttpClient(null);
    PcosApiService.overrideHttpClient(null);
  });

  testWidgets('successful detection saves the inputs to the profile', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const Scaffold(body: PcosScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The form lives on the second tab.
    tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.text('Detection'),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTap!();
    await tester.pumpAndSettle();

    // Fill every required numeric field, in form order: age, weight,
    // height, cycle length, PRL, Vit D3, PRG, RBS, systolic, diastolic,
    // follicle L, follicle R, average size L, average size R, endometrium.
    const values = [
      '24',
      '58',
      '162',
      '30',
      '18.5',
      '32',
      '1.2',
      '95',
      '120',
      '80',
      '12',
      '10',
      '6',
      '5',
      '8',
    ];
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(values.length));
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(fields.at(i), values[i]);
    }

    tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.text('Irregular'),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTap!();
    await tester.pump();

    // The button can sit below the test viewport; invoke it directly.
    tester
        .widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Run PCOS Detection'),
        )
        .onPressed!();
    await tester.pumpAndSettle();

    // The result is on screen ...
    expect(find.textContaining('PCOS'), findsWidgets);

    // ... and the inputs are in the profile the rest of the app reads.
    final saved = await HealthProfileService().loadProfile();
    expect(saved.demographics.ageYrs, 24);
    expect(saved.demographics.weightKg, 58);
    expect(saved.demographics.heightCm, 162);
    expect(saved.reproductiveHistory.cycleRegularity, 'Irregular');
    expect(saved.reproductiveHistory.cycleLengthDays, 30);
    expect(saved.pcosHistory, hasLength(1));
    expect(saved.pcosHistory.single.prediction, 'PCOS');
  });
}
