import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellness_saheli/main.dart';
import 'package:wellness_saheli/screens/home_shell.dart';
import 'package:wellness_saheli/screens/sign_in_screen.dart';

/// Task 5.3: the original smoke test pumped the app and finished while
/// the splash's navigation timer was still pending (guaranteed
/// "Timer is still pending" failure), with no platform-channel mocks.
/// This version mocks the channels and pumps through the splash's
/// 50 ms login-state polling + 900 ms minimum duration, then asserts
/// the app actually lands somewhere.
void main() {
  testWidgets('App launches past the splash into its start screen', (
    WidgetTester tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // Same mock pattern as profile_update_events_test.dart: under
    // testWidgets' fake async, real platform channels never answer.
    const secureChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async => null);
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.pumpWidget(const WellnessSaheliApp());
    expect(find.byType(WellnessSaheliApp), findsOneWidget);

    // Splash: one 50 ms poll tick, then advance past the 900 ms minimum
    // splash duration (the poll loop exits once CycleProvider has read
    // the mocked empty prefs). The next pump flushes the scheduled
    // navigation, so no timer is left pending at test end.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump();

    // Fresh state (no saved login) must land on Sign In -- the splash
    // only skips it with BOTH the flag and a valid session.
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });
}
