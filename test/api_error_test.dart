import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:wellness_saheli/services/api_error.dart';

/// Task 1.8 -- contract tests for the central error-to-message mapper.
///
/// `ApiError.friendly` is the last line of defense between a failing
/// backend call and the user's eyes: known exception types map to
/// fixed sentences, messages the services already wrote for humans are
/// passed through, and raw technical dumps fall back to something
/// short and calm.
void main() {
  group('ApiError.friendly', () {
    test('TimeoutException maps to the timeout message', () {
      expect(
        ApiError.friendly(TimeoutException('future timed out')),
        ApiError.timeout,
      );
    });

    test('http.ClientException maps to the network message', () {
      expect(
        ApiError.friendly(http.ClientException('connection closed')),
        ApiError.network,
      );
    });

    test('FormatException maps to the unreadable message', () {
      expect(
        ApiError.friendly(const FormatException('bad json')),
        ApiError.unreadable,
      );
    });

    test('SocketException (io platform) maps to the network message', () {
      // Type-checked only via message text -- ApiError must stay
      // web-safe and cannot import dart:io itself.
      expect(
        ApiError.friendly(
          const SocketException('Failed host lookup: api.example.com'),
        ),
        ApiError.network,
      );
    });

    test('exceptions whose text contains network markers map to network', () {
      expect(
        ApiError.friendly(Exception('Connection refused by the server')),
        ApiError.network,
      );
    });

    test('friendly Exception messages survive unchanged', () {
      expect(
        ApiError.friendly(
          Exception(
            'The server had a problem (HTTP 500). Please try again shortly.',
          ),
        ),
        'The server had a problem (HTTP 500). Please try again shortly.',
      );
    });

    test('nested Exception prefixes are stripped', () {
      expect(
        ApiError.friendly(Exception('Exception: Could not load conditions.')),
        'Could not load conditions.',
      );
    });

    test('long dumps (whole HTML error pages) fall back', () {
      final html = 'x' * 500;
      expect(
        ApiError.friendly(Exception('Server error: $html')),
        ApiError.fallback,
      );
    });

    test('type-cast dumps fall back', () {
      expect(
        ApiError.friendly(Exception("type 'int' is not a subtype of 'String'")),
        ApiError.fallback,
      );
    });

    test('objects with no message ("Instance of ...") fall back', () {
      expect(ApiError.friendly(Object()), ApiError.fallback);
    });

    test('custom orElse wins over the default fallback', () {
      expect(
        ApiError.friendly(Object(), orElse: 'Could not load conditions.'),
        'Could not load conditions.',
      );
    });

    test('null error uses orElse, then the default fallback', () {
      expect(ApiError.friendly(null), ApiError.fallback);
      expect(ApiError.friendly(null, orElse: 'custom'), 'custom');
    });

    test('multi-line dumps (stack traces) fall back', () {
      expect(
        ApiError.friendly(Exception('boom\n#0      main (file.dart:1)')),
        ApiError.fallback,
      );
    });
  });
}
