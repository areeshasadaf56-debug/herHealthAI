import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellness_saheli/services/eligibility_api_service.dart';

/// A rating that came from the PDF by machine matching, rather than from a
/// clinician reading the printed table, must be distinguishable in the client.
/// Otherwise the app silently presents unreviewed medical guidance as though
/// it were signed off, and there is no way for a reader to tell the two apart.
void main() {
  group('Condition provenance', () {
    test('parses hand_verified and reports it as verified', () {
      final c = Condition.fromJson({
        'id': 'migraine_with_aura',
        'label': 'Migraine with aura',
        'provenance': 'hand_verified',
      });
      expect(c.provenance, 'hand_verified');
      expect(c.isClinicallyVerified, isTrue);
    });

    test('parses extracted_pending_review and does not claim verification', () {
      final c = Condition.fromJson({
        'id': 'epilepsy',
        'label': 'Epilepsy',
        'provenance': 'extracted_pending_review',
      });
      expect(c.provenance, 'extracted_pending_review');
      expect(c.isClinicallyVerified, isFalse);
    });

    test('an absent provenance field is treated as unreviewed, not verified', () {
      // Defaulting to verified would let any future backend that forgets the
      // field present every rating as clinician-checked.
      final c = Condition.fromJson({'id': 'epilepsy', 'label': 'Epilepsy'});
      expect(c.isClinicallyVerified, isFalse);
    });

    test('an unrecognised provenance value is not trusted', () {
      final c = Condition.fromJson({
        'id': 'epilepsy',
        'label': 'Epilepsy',
        'provenance': 'trust_me',
      });
      expect(c.isClinicallyVerified, isFalse);
    });
  });

  group('MethodResult pending review', () {
    test('parses pending_review and keeps a null category', () {
      final r = MethodResult.fromJson({
        'method_label': 'Condoms',
        'category': null,
        'pending_review': true,
        'note': 'Not yet assessed',
      });
      expect(r.category, isNull);
      expect(r.pendingReview, isTrue);
      expect(r.note, 'Not yet assessed');
    });

    test('a rated but unreviewed result still carries its warning note', () {
      // The category IS shown here, so the caveat must survive parsing: this
      // is the case where a reader is shown a number that is not signed off.
      final r = MethodResult.fromJson(
        jsonDecode('''
        {
          "method_label": "Combined hormonal contraceptives",
          "category": 1,
          "pending_review": true,
          "note": "Matched automatically from the WHO MEC tables and not yet reviewed by a clinician."
        }
        ''') as Map<String, dynamic>,
      );
      expect(r.category, 1);
      expect(r.pendingReview, isTrue);
      expect(r.note, contains('not yet reviewed'));
    });

    test('a missing pending_review field defaults to reviewed', () {
      final r = MethodResult.fromJson({
        'method_label': 'Combined hormonal contraceptives',
        'category': 4,
      });
      expect(r.pendingReview, isFalse);
      expect(r.note, isNull);
    });
  });
}
