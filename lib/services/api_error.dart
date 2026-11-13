import 'dart:async';

import 'package:http/http.dart' as http;

/// Central place that turns anything thrown while talking to the backend
/// into a short message that is safe to show a user.
///
/// Services throw friendly [Exception]s for the cases they can identify
/// (status codes, bad JSON, ...). Screens then wrap whatever still leaks
/// through -- an unexpected [TypeError] from parsing, a socket failure
/// surfacing as a raw dump, a timeout -- in [ApiError.friendly], so the
/// user never sees stack frames, host names or exception class names.
///
/// Web-safe by design: [SocketException] only exists on io platforms, so
/// it is recognized by message text (see [_networkMarkers]), not by
/// type, and this file must NOT import `dart:io`.
class ApiError {
  ApiError._();

  /// No route to the server: airplane mode, dead Wi-Fi, wrong host.
  static const String network =
      'Could not reach the server. Please check your internet connection '
      'and try again.';

  /// The request went out but no complete answer came back in time.
  static const String timeout =
      'The server took too long to reply. Please try again.';

  /// An answer came back but it wasn't the JSON shape we expected.
  static const String unreadable =
      "The server sent a response we couldn't read. Please try again.";

  /// Anything we can't classify.
  static const String fallback = 'Something went wrong. Please try again.';

  /// Fragments whose presence means "the request never got through":
  /// the message maps to [network], not to [fallback], because "check
  /// your internet connection" is far more actionable than "something
  /// went wrong".
  static const List<String> _networkMarkers = <String>[
    'SocketException',
    'ClientException',
    'Connection refused',
    'Connection reset',
    'Connection terminated',
    'Connection closed while receiving data',
    'Failed host lookup',
    'Network is unreachable',
    'XMLHttpRequest', // web: network layer errors carry this class name
    'HttpException',
  ];

  /// Fragments that mark [message] as a raw technical dump rather than
  /// a sentence written for humans.
  static const List<String> _technicalMarkers = <String>[
    'Exception: ', // a nested exception toString, not a message
    'TypeError',
    'CastError',
    'RangeError',
    'StateError',
    'ArgumentError',
    'NoSuchMethodError',
    'type \'', // Dart type-cast dump: "type 'int' is not a subtype..."
    'Instance of ', // "Instance of 'Object'" -- no message at all
    '#0 ', // stack frame
  ];

  /// Longest message we will ever show verbatim; anything longer is
  /// treated as a dump (e.g. a whole HTML error page) and mapped to
  /// [fallback].
  static const int _maxShownLength = 300;

  /// Maps [error] to a user-facing message.
  ///
  /// * Known exception types ([TimeoutException], [http.ClientException],
  ///   [FormatException]) map to the matching constant above.
  /// * Anything else is cleaned (an [Exception] toString is prefixed
  ///   with "Exception: ", which is not for humans) and shown as-is,
  ///   so messages the services already wrote for users survive.
  /// * Text that clearly means "no connection" maps to [network].
  /// * If the cleaned message looks like a technical dump, or no clean
  ///   message survives, [orElse] (or the [fallback] constant) is
  ///   returned.
  static String friendly(Object? error, {String? orElse}) {
    if (error == null) return orElse ?? fallback;
    if (error is TimeoutException) return timeout;
    if (error is http.ClientException) return network;
    if (error is FormatException) return unreadable;

    final raw = error.toString();
    // Strip any number of leading "Exception: " prefixes: services may
    // wrap a friendly message in another Exception while rethrowing.
    var message = raw;
    while (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }
    message = message.trim();

    if (_containsAny(message, _networkMarkers)) return network;
    if (message.isEmpty || _containsAny(message, _technicalMarkers)) {
      return orElse ?? fallback;
    }
    if (message.length > _maxShownLength) return orElse ?? fallback;
    return message;
  }

  static bool _containsAny(String message, List<String> markers) {
    for (final marker in markers) {
      if (message.contains(marker)) return true;
    }
    return false;
  }
}
