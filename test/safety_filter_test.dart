import 'package:flutter_test/flutter_test.dart';
import 'package:wellness_saheli/services/safety_filter.dart';

void main() {
  group('containsCrisisSignal (task 4.4)', () {
    test('empty and blank text never signal', () {
      expect(containsCrisisSignal(''), isFalse);
      expect(containsCrisisSignal('   '), isFalse);
    });

    test('explicit crisis phrases are caught across casing, punctuation, '
        'hyphens, apostrophes, and whitespace', () {
      expect(containsCrisisSignal('I want to kill myself'), isTrue);
      expect(containsCrisisSignal('KILL MYSELF'), isTrue);
      expect(containsCrisisSignal('sometimes i think about suicide.'), isTrue);
      expect(containsCrisisSignal('I feel suicidal'), isTrue);
      expect(containsCrisisSignal('i self-harm'), isTrue); // hyphen normalized
      expect(containsCrisisSignal('i self harm'), isTrue);
      expect(containsCrisisSignal("I don't want to live"), isTrue);
      // Curly quotes from mobile keyboards normalize to straight ones.
      expect(
        containsCrisisSignal('\u2018I don\u2019t want to live\u2019'),
        isTrue,
      );
      expect(containsCrisisSignal('i    want    to    die'), isTrue);
      expect(containsCrisisSignal('end my life tonight'), isTrue);
      expect(containsCrisisSignal('hurt myself badly'), isTrue);
      expect(
        containsCrisisSignal('they would be better off without me'),
        isTrue,
      );
    });

    test('everyday language stays unflagged', () {
      expect(containsCrisisSignal('deadline at work today'), isFalse);
      expect(containsCrisisSignal('this headache is killing me'), isFalse);
      expect(containsCrisisSignal('my grandfather died last year'), isFalse);
      expect(containsCrisisSignal('want to dye my hair'), isFalse);
      expect(containsCrisisSignal('I had a stressful day'), isFalse);
      expect(containsCrisisSignal('period pain is bad today'), isFalse);
    });

    test('matches only on word boundaries', () {
      // "kill" inside other words ("skillfully") must not trigger; the
      // list has no bare "kill" phrase, so nothing matches here.
      expect(containsCrisisSignal('she handled it very skillfully'), isFalse);
    });
  });
}
