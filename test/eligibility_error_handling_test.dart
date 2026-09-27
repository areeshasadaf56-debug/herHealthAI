// Regression tests for the eligibility service's ERROR path.
//
// The original code called jsonDecode() on any non-200 body:
//
//     final body = jsonDecode(response.body);
//     throw Exception(body['detail'] ?? '...');
//
// An unhandled server error replies with a plain-text body (uvicorn returns
// a bare `Internal Server Error`), so jsonDecode threw a FormatException.
// That replaced the real HTTP status with a decoding error, meaning a
// genuine 500 could never be surfaced or diagnosed. These tests pin the
// fixed behaviour: the status code is always preserved and a non-JSON body
// never masks it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellness_saheli/services/eligibility_api_service.dart';

/// Starts a loopback server that always answers with [status] and [body].
Future<HttpServer> _serverReturning(
  int status,
  String body, {
  String contentType = 'text/plain',
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.parse(contentType);
    request.response.write(body);
    await request.response.close();
  });
  return server;
}

void main() {
  group('eligibility error handling', () {
    test('plain-text 500 keeps its status code and does not throw FormatException',
        () async {
      final server = await _serverReturning(500, 'Internal Server Error');
      addTearDown(() => server.close(force: true));

      final api = EligibilityApiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      Object? caught;
      try {
        await api.checkEligibility(['vte_current']);
      } catch (e) {
        caught = e;
      }

      expect(caught, isNotNull, reason: 'a failure must still be reported');
      expect(caught, isNot(isA<FormatException>()),
          reason: 'the decoding error must not replace the real failure');
      expect(caught.toString(), contains('500'),
          reason: 'the HTTP status must survive so the cause is diagnosable');
    });

    test('HTML error page is truncated rather than flooding the UI', () async {
      final html = '<html><body>${'gateway error ' * 200}</body></html>';
      final server = await _serverReturning(
        502,
        html,
        contentType: 'text/html',
      );
      addTearDown(() => server.close(force: true));

      final api = EligibilityApiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      Object? caught;
      try {
        await api.fetchConditions();
      } catch (e) {
        caught = e;
      }

      expect(caught, isNot(isA<FormatException>()));
      final message = caught.toString();
      expect(message, contains('502'));
      expect(message.length, lessThan(320),
          reason: 'a long HTML page must be truncated');
    });

    test('structured 422 detail is still surfaced verbatim', () async {
      final server = await _serverReturning(
        422,
        jsonEncode({'detail': 'Unknown condition id(s): smoking_35_plus'}),
        contentType: 'application/json',
      );
      addTearDown(() => server.close(force: true));

      final api = EligibilityApiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      Object? caught;
      try {
        await api.checkEligibility(['smoking_35_plus']);
      } catch (e) {
        caught = e;
      }

      expect(caught.toString(), contains('smoking_35_plus'),
          reason: 'the backend\'s specific 422 message must reach the user');
    });

    test('empty error body still reports the status code', () async {
      final server = await _serverReturning(500, '');
      addTearDown(() => server.close(force: true));

      final api = EligibilityApiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      Object? caught;
      try {
        await api.checkEligibility(['obesity_bmi30']);
      } catch (e) {
        caught = e;
      }

      expect(caught.toString(), contains('500'));
    });

    test('a healthy response still parses, including null categories', () async {
      final payload = jsonEncode([
        {'method_label': 'Combined hormonal contraceptives',
         'category': 4, 'note': null},
        {'method_label': 'Lactational amenorrhoea method',
         'category': null, 'note': 'Not yet assessed'},
      ]);
      final server = await _serverReturning(
        200,
        payload,
        contentType: 'application/json',
      );
      addTearDown(() => server.close(force: true));

      final api = EligibilityApiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      final results = await api.checkEligibility(['vte_current']);
      expect(results, hasLength(2));
      expect(results[0].category, 4);
      expect(results[1].category, isNull,
          reason: 'an unassessed method must stay null, never default to 1');
    });
  });
}
