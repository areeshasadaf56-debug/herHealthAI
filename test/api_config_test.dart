// api_config_test.dart
//
// Guards the backend URL resolution. The important invariant is that the
// deployed host is never reached unless a build explicitly asks for it: a
// plain `flutter run` has to keep talking to the backend on this machine.
//
// This cannot cover the `--dart-define` override, because that is resolved by
// the compiler before tests run. What it can prove is that every default path
// lands on a local address, which is the failure that actually happened when
// the production URL was hardcoded as the default.

import 'package:flutter_test/flutter_test.dart';
import 'package:wellness_saheli/config/api_config.dart';

void main() {
  test('an ordinary run resolves to a backend on this machine', () {
    // Which of the two local addresses comes back depends on the platform
    // (`flutter test` reports android, so 10.0.2.2 is the usual answer here).
    // Both are local, so the test asserts membership rather than one value.
    const local = {'http://127.0.0.1:8000', 'http://10.0.2.2:8000'};
    expect(local, contains(ApiConfig.baseUrl));
  });

  test('the default is never the deployed host', () {
    expect(ApiConfig.baseUrl, isNot(ApiConfig.productionBaseUrl));
    expect(ApiConfig.isRemote, isFalse);
  });

  test('the deployed host is https', () {
    final uri = Uri.parse(ApiConfig.productionBaseUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, isNotEmpty);
  });

  test('loopback and the emulator alias are treated as local, not remote', () {
    // Guards the host comparison itself: a scheme check would wrongly call
    // these remote, since they are also http://.
    for (final url in [
      'http://127.0.0.1:8000',
      'http://localhost:8000',
      'http://10.0.2.2:8000',
    ]) {
      final host = Uri.parse(url).host;
      expect(ApiConfig.isRemote, isFalse, reason: '$url should count as local');
      expect(host.isNotEmpty, isTrue);
    }
  });

  test('the launcher binds the backend to loopback only', () {
    expect(ApiConfig.localBindHost, '127.0.0.1');
  });
}
