import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellness_saheli/l10n/language_provider.dart';
import 'package:wellness_saheli/models/health_profile.dart';
import 'package:wellness_saheli/providers/cycle_provider.dart';
import 'package:wellness_saheli/screens/home_screen.dart';
import 'package:wellness_saheli/services/auth_session.dart';
import 'package:wellness_saheli/services/health_profile_service.dart';

/// Mocks flutter_secure_storage: under testWidgets' fakeAsync an
/// unmocked platform channel await NEVER resolves (it does under plain
/// test()), which wedged every CycleProvider/AuthSession call inside a
/// widget test. An empty no-reply mock keeps SecureStore on its legacy
/// SharedPreferences fallback path.
void _mockSecureStorage(WidgetTester tester) {
  const mainChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(mainChannel, (call) async => null);
}

Map<String, dynamic> _profileJson({
  required String userId,
  int? stress,
  String? diaryMood,
}) => {
  'user_id': userId,
  'demographics': <String, dynamic>{},
  'lifestyle': <String, dynamic>{},
  'reproductive_history': <String, dynamic>{},
  'pcos_history': <dynamic>[],
  'eligibility_history': <dynamic>[],
  'mental_health': {
    'self_reported_stress_level': ?stress,
    if (diaryMood != null) 'last_check_in': DateTime.now().toIso8601String(),
  },
  'conversation_log': <dynamic>[],
  'privacy_settings': <String, dynamic>{},
  'diary_entries': [
    if (diaryMood != null)
      {
        'date': DateTime.now().toIso8601String(),
        'mood': diaryMood,
        'text': 'diary entry',
      },
  ],
  'last_updated': DateTime.now().toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // HomeScreen uses google_fonts TextStyle helpers; in the test
  // environment font downloads are intercepted (HTTP 400 from the test
  // messenger) and would otherwise throw. Render from local fallbacks.
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    // Keep the mock store FRESH per test, but stay synchronous here:
    // any await in setUp runs before _mockSecureStorage registers and
    // would wedge AuthSession.clear under testWidgets' fakeAsync.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    HealthProfileService.overrideHttpClient(null);
  });

  test('profileUpdated fires on saves and carries the newest document each '
      'time (the contract Home + AI tab listeners rely on)', () async {
    // Plain test(): unmocked secure-storage channel resolves instantly
    // here, so clearing the session is safe.
    await AuthSession.clear();
    HealthProfileService.overrideHttpClient(_HitsBackendOK());
    final service = HealthProfileService();
    await AuthSession.update(userId: 'listen-u1', token: 'tok');

    final events = <HealthProfile>[];
    service.profileUpdated.addListener(() {
      final v = service.profileUpdated.value;
      if (v != null) events.add(v);
    });

    await service.saveProfile(HealthProfile.empty('listen-u1'));
    await service.appendConversationEntry('user', 'hello');

    expect(events, hasLength(2));
    // The event carries exactly what was saved, not something stale:
    expect(
      events.last.conversationLog.last.message,
      'hello',
      reason: 'the last fired event must be the freshest save',
    );
    // A listener reading the notifier value at callback time (what the
    // screens do for "live privacy at send time") always sees the newest.
    expect(
      service.profileUpdated.value!.conversationLog.single.message,
      'hello',
    );
  });

  testWidgets('HomeScreen re-renders from a profile saved by ANOTHER screen '
      'via profileUpdated (no remount needed) - task 1.4', (tester) async {
    _mockSecureStorage(tester);
    await AuthSession.update(userId: 'home-live-1', token: 'tok');

    // Seed the local cache with a calm profile: no stress, no check-ins.
    SharedPreferences.setMockInitialValues({
      'health_profile_cache_home-live-1': jsonEncode(
        _profileJson(userId: 'home-live-1'),
      ),
      'isLoggedIn': true,
    });
    // ignore: avoid_print
    print('WIDGET-TEST: seeded');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CycleProvider()),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    // Bounded pumps only -- HomeScreen has ambience widgets whose
    // repeating animations would keep pumpAndSettle from ever settling.
    // ignore: avoid_print
    print('WIDGET-TEST: pumped');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // ignore: avoid_print
    print('WIDGET-TEST: settled');

    // Before any profile update: generic greeting.
    expect(
      find.textContaining("Haven't met yet"),
      findsOneWidget,
      reason: 'empty profile should show the first-meeting greeting',
    );

    // ANOTHER screen (e.g. the AI check-in) saves a profile with high
    // stress. Home should repaint on the event, without a remount.
    await tester.runAsync(() async {
      await HealthProfileService().saveProfile(
        HealthProfile.fromJson(
          _profileJson(
            userId: 'home-live-1',
            stress: 5,
            diaryMood: 'Feeling anxious',
          ),
        ),
      );
      // Let the save's chained background work finish before draining
      // the notification queue frame by frame.
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.textContaining('Things have seemed heavy'),
      findsOneWidget,
      reason: 'a live profile event must drive the Home greeting',
    );
  });
}

/// GET answers 404 (fresh local cache is the answer), PUT successes.
class _HitsBackendOK extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      request is http.Request && request.method == 'PUT' ? 200 : 404,
    );
  }
}
