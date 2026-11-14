import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellness_saheli/models/health_profile.dart';
import 'package:wellness_saheli/services/auth_session.dart';
import 'package:wellness_saheli/services/health_profile_service.dart';

/// GET answers 404 (nothing on the server yet), PUT answers 200 —
/// enough to exercise the cache-first + queue logic in unit tests.
class _OkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final status = request is http.Request && request.method == 'GET'
        ? 404
        : 200;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(_blankProfileJson()))),
      status,
    );
  }
}

/// PUT blocks on [gate]; GET answers 404. Lets a test observe that the
/// save() await returned while the upload hadn't even started.
class _SlowPutClient extends http.BaseClient {
  final Completer<http.Response> gate = Completer<http.Response>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request && request.method == 'PUT') {
      final response = await gate.future;
      return http.StreamedResponse(
        Stream.value(utf8.encode('{}')),
        response.statusCode,
      );
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 404);
  }
}

/// Records PUT attempts — proves the oversized payload never uploaded.
/// GETs answer 404: this suite only cares about pushes, and a lying
/// empty `{}` GET would now (post-tolerant-parsing) decode into a
/// userId-less profile instead of failing loudly as it used to.
class _CountingClient extends http.BaseClient {
  int putCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request && request.method == 'PUT') putCount++;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      request is http.Request && request.method == 'PUT' ? 200 : 404,
    );
  }
}

/// Records every request (`"METHOD url"`); GET answers 404 with a blank
/// profile, PUT answers 200, and DELETE answers [deleteStatus] -- enough
/// to exercise the server-deletion flow and its resurrection guard.
class _DeleteTestClient extends http.BaseClient {
  final int deleteStatus;
  final List<String> calls = [];

  _DeleteTestClient(this.deleteStatus);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRequest = request is http.Request;
    calls.add('${request.method} ${request.url}');
    final status = isRequest && request.method == 'DELETE'
        ? deleteStatus
        : isRequest && request.method == 'GET'
        ? 404
        : 200;
    final body = isRequest && request.method == 'DELETE'
        ? jsonEncode({'status': 'deleted'})
        : isRequest && request.method == 'GET'
        ? jsonEncode(_blankProfileJson())
        : '{}';
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }
}

Map<String, dynamic> _blankProfileJson() => {
  'user_id': 'device-id',
  'demographics': <String, dynamic>{},
  'lifestyle': <String, dynamic>{},
  'reproductive_history': <String, dynamic>{},
  'pcos_history': <dynamic>[],
  'eligibility_history': <dynamic>[],
  'mental_health': <String, dynamic>{},
  'conversation_log': <dynamic>[],
  'privacy_settings': <String, dynamic>{},
  'diary_entries': <dynamic>[],
  'last_updated': DateTime(2026, 1, 1).toIso8601String(),
};

HealthProfile _profileWithDiary(String userId, String text) {
  return HealthProfile.empty(userId).copyWith(
    diaryEntries: [DiaryEntry(date: DateTime.now(), text: text)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthSession.clear();
  });

  tearDown(() {
    HealthProfileService.overrideHttpClient(null);
  });

  test('concurrent updateProfile calls from two call sites both persist '
      '(the second reads the first result, no stale-base overwrite)', () async {
    HealthProfileService.overrideHttpClient(_OkClient());
    final service = HealthProfileService();
    // Unique identity per test: no leakage between suites.
    await AuthSession.update(userId: 'queue-A1', token: 'tok-A1');

    final entryA = DiaryEntry(date: DateTime.now(), text: 'entry A');
    final entryB = DiaryEntry(date: DateTime.now(), text: 'entry B');

    await Future.wait([
      service.updateProfile(
        (p) => p.copyWith(diaryEntries: [...p.diaryEntries, entryA]),
      ),
      service.updateProfile(
        (p) => p.copyWith(diaryEntries: [...p.diaryEntries, entryB]),
      ),
    ]);

    final stored = await service.loadProfile();
    expect(stored.diaryEntries, hasLength(2));
    expect(
      stored.diaryEntries.map((e) => e.text),
      containsAll(<String>['entry A', 'entry B']),
    );
    expect(stored.userId, 'queue-A1');
  });

  test('saving never waits on the network: the PUT is still pending '
      'while the local cache is already updated', () async {
    final client = _SlowPutClient();
    HealthProfileService.overrideHttpClient(client);

    await AuthSession.update(userId: 'slow-A2', token: 'tok-A2');

    final profile = _profileWithDiary('slow-A2', 'kept locally first');
    final stopwatch = Stopwatch()..start();
    await HealthProfileService().saveProfile(profile);
    stopwatch.stop();

    // The await returned (didn't wait for the still-gated PUT) and the
    // change is already in the local cache.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    final reloaded = await HealthProfileService().loadProfile();
    expect(reloaded.diaryEntries, hasLength(1));
    expect(reloaded.diaryEntries.first.text, 'kept locally first');

    // The push is (still) pending, and honest about it.
    expect(HealthProfileService().syncState.value, ProfileSyncState.pending);

    // Let the queued work finish before the test ends.
    client.gate.complete(http.Response('{}', 200));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(HealthProfileService().syncState.value, ProfileSyncState.synced);
  });

  test('oversized payloads upload nothing, never trim data, and set a '
      '"too large" sync-failure reason', () async {
    final client = _CountingClient();
    HealthProfileService.overrideHttpClient(client);

    await AuthSession.update(userId: 'big-A3', token: 'tok-A3');

    // > 250 KB of UTF-8 text.
    final giant = 'x' * (HealthProfileService.maxSyncPayloadBytes + 1000);
    await HealthProfileService().updateProfile(
      (p) => p.copyWith(
        diaryEntries: [DiaryEntry(date: DateTime.now(), text: giant)],
      ),
    );

    // Give the background push a beat to run its check.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(client.putCount, 0);
    expect(HealthProfileService().syncState.value, ProfileSyncState.failed);
    expect(
      HealthProfileService().lastSyncError,
      contains('more health data than the server can store'),
    );

    // Data is not touched: unchanged, cached on device.
    final stored = await HealthProfileService().loadProfile();
    final DiaryEntry(:text) = stored.diaryEntries.single;
    expect(text.length, giant.length);
  });

  test('changing identity resets caches so one account never sees '
      "another's data", () async {
    HealthProfileService.overrideHttpClient(_OkClient());
    final service = HealthProfileService();

    // Account A saves a private entry.
    await AuthSession.update(userId: 'identity-A4', token: 'tok-A4');
    await service.updateProfile(
      (p) => p.copyWith(
        diaryEntries: [
          DiaryEntry(date: DateTime.now(), text: "A's private entry"),
        ],
      ),
    );

    // A different account signs in: it must NOT see A's data.
    await AuthSession.update(userId: 'identity-B4', token: 'tok-B4');
    final forB = await service.loadProfile();

    expect(forB.userId, 'identity-B4');
    expect(forB.diaryEntries, isEmpty);

    // Sign back out and back in as A: A's own data is still there.
    await AuthSession.update(userId: 'identity-A4', token: 'tok-A4');
    final forA = await service.loadProfile();
    expect(forA.diaryEntries.map((e) => e.text), contains("A's private entry"));
  });

  test('deleteServerProfile succeeds (200), discards the cached copy, and '
      'never re-uploads it afterwards', () async {
    final client = _DeleteTestClient(200);
    HealthProfileService.overrideHttpClient(client);
    await AuthSession.update(userId: 'delete-A5', token: 'tok-A5');
    final service = HealthProfileService();

    await service.updateProfile(
      (p) => p.copyWith(
        diaryEntries: [DiaryEntry(date: DateTime.now(), text: 'to be deleted')],
      ),
    );
    final error = await service.deleteServerProfile();
    expect(error, isNull);

    // The DELETE reached the right owner-checked endpoint, AFTER the
    // queued PUT -- an upload that lands after a delete would
    // resurrect the profile server-side.
    expect(
      client.calls.any(
        (c) => c.startsWith('DELETE') && c.contains('/profile/delete-A5'),
      ),
      isTrue,
    );
    final putIndex = client.calls.indexWhere((c) => c.startsWith('PUT'));
    final deleteIndex = client.calls.indexWhere((c) => c.startsWith('DELETE'));
    expect(deleteIndex, greaterThan(putIndex));

    // Simulate the caller's logout(removeData: true) local wipe: with
    // the on-device copy gone, a fresh load must be blank AND must not
    // push anything -- the deleted profile can never be synced back up.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('health_profile_cache_delete-A5');
    final after = await service.loadProfile();
    expect(after.diaryEntries, isEmpty);
    expect(client.calls.where((c) => c.startsWith('PUT')), hasLength(1));
  });

  test('deleteServerProfile treats 404 as success (already gone)', () async {
    HealthProfileService.overrideHttpClient(_DeleteTestClient(404));
    await AuthSession.update(userId: 'delete-A6', token: 'tok-A6');
    final error = await HealthProfileService().deleteServerProfile();
    expect(error, isNull);
  });

  test('deleteServerProfile reports session-expiry errors and clears the '
      'stale token', () async {
    HealthProfileService.overrideHttpClient(_DeleteTestClient(401));
    await AuthSession.update(userId: 'delete-A7', token: 'tok-A7');
    final error = await HealthProfileService().deleteServerProfile();
    expect(error, isNotNull);
    expect(error, contains('Sign in again'));
    // Same treatment as the upload path on 401: the dead token is
    // cleared so nothing keeps attaching it to new requests.
    expect(AuthSession.isValid, isFalse);
  });

  test('deleteServerProfile reports server refusals without touching '
      'local data', () async {
    HealthProfileService.overrideHttpClient(_DeleteTestClient(500));
    await AuthSession.update(userId: 'delete-A8', token: 'tok-A8');
    final service = HealthProfileService();
    await service.updateProfile(
      (p) => p.copyWith(
        diaryEntries: [DiaryEntry(date: DateTime.now(), text: 'kept')],
      ),
    );
    final error = await service.deleteServerProfile();
    expect(error, isNotNull);
    expect(error, contains('Nothing was deleted'));
    // Failure keeps everything exactly as it was: the local copy (and
    // the server copy) still exists.
    final after = await service.loadProfile();
    expect(after.diaryEntries, hasLength(1));
  });
}
