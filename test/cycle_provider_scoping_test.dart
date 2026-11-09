import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellness_saheli/providers/cycle_provider.dart';
import 'package:wellness_saheli/services/auth_session.dart';

/// Test seam: CycleProvider self-loads in its constructor; wait for the
/// async _loadData() to finish so assertions see steady state.
Future<CycleProvider> _loadedProvider() async {
  final provider = CycleProvider();
  var waited = 0;
  while (!provider.isLoaded && waited < 1000) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    waited += 5;
  }
  expect(provider.isLoaded, isTrue, reason: 'provider never finished loading');
  return provider;
}

Future<void> _signIn(CycleProvider provider, String name, String userId) async {
  await provider.login(
    name,
    userId: userId,
    token: 'tok-$userId',
    tokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Mock store per test AND a cleared session: static state persists
    // across tests in the same run, which is exactly the leak class we're
    // testing against.
    SharedPreferences.setMockInitialValues({});
    await AuthSession.clear();
  });

  test('legacy unscoped data migrates to the FIRST account that signs in, '
      'and the migration marker records it', () async {
    // Pre-accounts data written by an older app version (or anonymous
    // use): bare keys with no account suffix.
    SharedPreferences.setMockInitialValues({
      'lastPeriodStart': 123000,
      'cycleLength': 26,
      'periodDuration': 4,
      'dailyLogs': '{}',
      'remindersEnabled': false,
      'userName': 'Old Me',
    });

    final provider = await _loadedProvider();
    // Signed out at boot: the bare legacy keys are what anonymous use
    // reads, so they must load even before any account exists.
    expect(provider.cycleData.cycleLength, 26);

    // First account signs in -- it inherits the legacy data.
    await _signIn(provider, 'First', 'uid-first');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('lastPeriodStart:uid-first'), 123000);
    expect(prefs.getInt('cycleLength:uid-first'), 26);
    expect(prefs.getInt('periodDuration:uid-first'), 4);
    expect(prefs.getString('dailyLogs:uid-first'), '{}');
    expect(prefs.getBool('remindersEnabled:uid-first'), false);
    expect(prefs.getString('userName:uid-first'), 'First');
    expect(prefs.getString('cycleLegacyMigratedBy'), 'uid-first');

    // And the provider now reflects the migrated account data.
    expect(provider.cycleData.lastPeriodStart.millisecondsSinceEpoch, 123000);
    expect(provider.cycleData.cycleLength, 26);
    expect(provider.remindersEnabled, false);
  });

  test('a SECOND account gets blank defaults and never sees the first '
      "account's data", () async {
    final first = await _loadedProvider();
    await _signIn(first, 'First', 'uid-firstA');

    // The first account writes real data. (update* are fire-and-forget
    // -- give their async saves a beat to land before reading prefs.)
    first.updateCycleLength(33);
    first.updateUserName('First A');
    first.updateLastPeriodStart(DateTime(2026, 2, 2));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('cycleLength:uid-firstA'), 33);

    // Ordinary sign-out keeps data (the "keep data" choice).
    await first.logout(removeData: false);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('cycleLength:uid-firstA'), isTrue);

    // A brand-new account signs in on a fresh provider.
    final second = await _loadedProvider();
    expect(second.isLoggedIn, isFalse, reason: 'signed-out session');
    await _signIn(second, 'Second', 'uid-second');

    expect(second.cycleData.cycleLength, 28, reason: 'default, not 33');
    expect(second.userName, 'Second');
    expect(second.dailyLogs, isEmpty);
    expect(
      second.cycleData.lastPeriodStart.day,
      isNot(2),
      reason: 'not the first account period date 2026-02-02',
    );
  });

  test('"Remove cycle data & log out" wipes scoped + legacy + marker + '
      'profile caches and resets memory', () async {
    SharedPreferences.setMockInitialValues({
      'lastPeriodStart': 999,
      'cycleLegacyMigratedBy': 'uid-older',
    });

    final provider = await _loadedProvider();
    await _signIn(provider, 'Removee', 'uid-remove');

    var prefs = await SharedPreferences.getInstance();
    prefs.setString('health_profile_cache_uid-remove', '{"user_id":"x"}');
    await Future<void>.delayed(const Duration(milliseconds: 10)); // settle
    provider.updateLastPeriodStart(DateTime(2026, 3, 3));
    provider.updateCycleLength(29);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // settle

    await provider.logout(removeData: true);

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('lastPeriodStart:uid-remove'), isNull);
    expect(prefs.getInt('cycleLength:uid-remove'), isNull);
    // Legacy copies + marker are gone too.
    expect(prefs.getInt('lastPeriodStart'), isNull);
    expect(prefs.getString('cycleLegacyMigratedBy'), isNull);
    expect(prefs.containsKey('health_profile_cache_uid-remove'), isFalse);
    // In-memory state reset.
    expect(provider.cycleData.cycleLength, 28);
    expect(provider.remindersEnabled, isTrue);
    expect(provider.userName, isEmpty);
    expect(provider.isLoggedIn, isFalse);
    expect(provider.dailyLogs, isEmpty);
    // Session cleared.
    expect(AuthSession.userId, isNull);
  });
}
