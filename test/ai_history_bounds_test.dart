import 'package:flutter_test/flutter_test.dart';
import 'package:wellness_saheli/models/health_profile.dart';
import 'package:wellness_saheli/services/ai_service.dart';

/// The backend caps `ChatRequest.history` at 10 entries and each history
/// message at 4000 characters, returning 422 otherwise. The chat screen passes
/// the entire conversation to `sendMessage`, so if the service stops trimming,
/// the seventh turn is rejected and the chat silently stops working.
void main() {
  // Every message carries its index so trimming can be verified by content
  // rather than by role parity.
  ConversationEntry entry(int i, {int messageChars = 10}) {
    final index = '[$i]';
    final filler = 'm' * (messageChars - index.length);
    return ConversationEntry(
      timestamp: DateTime(2026, 1, 1).add(Duration(minutes: i)),
      role: i.isEven ? 'user' : 'assistant',
      message: '$index$filler',
    );
  }

  group('AiService history encoding', () {
    test('keeps short histories untouched', () {
      final history = [entry(0), entry(1), entry(2)];
      final encoded = AiService.encodeHistory(history);
      expect(encoded.length, 3);
      expect(encoded.first, {'role': 'user', 'message': entry(0).message});
      expect(encoded.last, {'role': 'user', 'message': entry(2).message});
      // Nothing was clipped, and ordering is preserved.
      expect(entry(0).message.length, 10);
      expect(
        encoded.map((e) => e['message']).toList(),
        history.map((e) => e.message).toList(),
      );
    });

    test('trims to the most recent 10 entries', () {
      final history = List.generate(25, (i) => entry(i));
      final encoded = AiService.encodeHistory(history);
      expect(encoded.length, AiService.maxHistoryEntries);
      // Oldest entries (0..14) dropped, newest (15..24) retained in order.
      expect(encoded.first['message'], entry(15).message);
      expect(encoded.last['message'], entry(24).message);
      expect(
        encoded.map((e) => e['message']).toList(),
        List.generate(10, (i) => entry(15 + i).message),
      );
    });

    test('exactly 10 entries is left alone', () {
      final history = List.generate(10, (i) => entry(i));
      final encoded = AiService.encodeHistory(history);
      expect(encoded.length, 10);
      expect(encoded.first['message'], entry(0).message);
    });

    test('clips each message to the server limit', () {
      final long = List.generate(3, (i) => entry(i, messageChars: 9000));
      final encoded = AiService.encodeHistory(long);
      for (final e in encoded) {
        expect(
          (e['message'] as String).length,
          AiService.maxHistoryMessageChars,
        );
      }
    });

    test('every encoded message satisfies the backend bound', () {
      // Mixed sizes: the worst case a real conversation produces.
      final history = List.generate(
        40,
        (i) => entry(i, messageChars: 1 + (i * 977) % 9000),
      );
      final encoded = AiService.encodeHistory(history);
      expect(encoded.length, lessThanOrEqualTo(AiService.maxHistoryEntries));
      for (final e in encoded) {
        expect(e['role'], anyOf('user', 'assistant'));
        expect((e['message'] as String).length, lessThanOrEqualTo(4000));
        expect((e['message'] as String).isNotEmpty, isTrue);
      }
    });

    test('empty history stays empty', () {
      expect(AiService.encodeHistory([]), isEmpty);
    });
  });
}
