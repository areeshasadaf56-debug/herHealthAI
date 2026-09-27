// eligibility_provenance_test.dart
//
// Replays the two real response shapes POST /eligibility produces.
//
// The important one is the second. The build still deployed at the
// PythonAnywhere host answers *every* condition with a flat category 1
// across all nine methods and sends no `pending_review` and no `note`.
// Captured live:
//
//   [{"category":1,"method_label":"Combined hormonal contraceptives"}, ...]
//
// The reviewed backend instead returns `category: null` plus a note for
// anything unverified. Because the flat payload also parses cleanly, the
// client used to render it as a settled all-clear -- telling a woman with
// a history of DVT/PE, or migraine with aura, that every method was safe.
// WHO MEC rates both of those category 4 (unacceptable) for CHC.
//
// These tests pin that such a payload is flagged instead of trusted.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wellness_saheli/services/eligibility_api_service.dart';

/// The exact shape returned by the older deployed build, trimmed to three
/// methods for readability. Same absence of `pending_review` and `note`.
const String legacyStubBody = '''
[
  {"category": 1, "method_label": "Combined hormonal contraceptives"},
  {"category": 1, "method_label": "Barrier methods"},
  {"category": 1, "method_label": "Copper intrauterine device"}
]
''';

/// A row from the reviewed backend, mid-matrix and machine-matched.
const String reviewedPendingBody = '''
[
  {"method_label": "Combined hormonal contraceptives", "category": 4,
   "pending_review": false, "note": null},
  {"method_label": "Barrier methods", "category": 1,
   "pending_review": true,
   "note": "Matched automatically from the WHO MEC tables and not yet reviewed."},
  {"method_label": "Copper intrauterine device", "category": null,
   "pending_review": false,
   "note": "Not yet assessed: the WHO MEC matrix for this method has not been verified."}
]
''';

EligibilityApiService serviceReturning(String body) {
  return EligibilityApiService(
    baseUrl: 'https://example.test',
    client: MockClient(
      (http.Request request) async => http.Response(
        body,
        200,
        headers: {'content-type': 'application/json'},
      ),
    ),
  );
}

void main() {
  group('un-audited backend responses are flagged, not trusted', () {
    test('a flat all-ones payload is never reported as settled', () async {
      final results = await serviceReturning(
        legacyStubBody,
      ).checkEligibility(['vte_history']);

      expect(results, hasLength(3));
      for (final r in results) {
        expect(
          r.serverAudited,
          isFalse,
          reason: '${r.methodLabel} came from an un-audited build',
        );
        expect(r.pendingReview, isTrue);
        expect(r.needsCaveat, isTrue);
        expect(r.note, MethodResult.unverifiedNote);
      }
    });

    test(
      'the caveat is added even though the payload carried no note',
      () async {
        final results = await serviceReturning(
          legacyStubBody,
        ).checkEligibility(['migraine_with_aura']);
        expect(
          results.every((r) => r.note != null && r.note!.isNotEmpty),
          isTrue,
          reason: 'a number with no stated origin must still say so',
        );
      },
    );

    test('a missing method_label does not throw', () async {
      final results = await serviceReturning(
        '[{"category": 2}]',
      ).checkEligibility(['obesity_bmi30']);
      expect(results.single.methodLabel, 'Unknown method');
      expect(results.single.serverAudited, isFalse);
    });
  });

  group('the reviewed backend is passed through unchanged', () {
    test('audited rows keep their own provenance', () async {
      final results = await serviceReturning(
        reviewedPendingBody,
      ).checkEligibility(['vte_history']);

      expect(results, hasLength(3));
      for (final r in results) {
        expect(r.serverAudited, isTrue);
      }
    });

    test('a verified row needs no caveat', () async {
      final chc = (await serviceReturning(
        reviewedPendingBody,
      ).checkEligibility(['vte_history'])).first;
      expect(chc.category, 4, reason: 'WHO MEC 4 for history of DVT/PE');
      expect(chc.pendingReview, isFalse);
      expect(chc.needsCaveat, isFalse);
      expect(chc.note, isNull);
    });

    test('a machine-matched row is still caveated', () async {
      final barrier = (await serviceReturning(
        reviewedPendingBody,
      ).checkEligibility(['vte_history']))[1];
      expect(barrier.pendingReview, isTrue);
      expect(barrier.needsCaveat, isTrue);
      expect(barrier.note, isNotNull);
    });

    test('an unassessed method stays null and keeps its own note', () async {
      final iud = (await serviceReturning(
        reviewedPendingBody,
      ).checkEligibility(['vte_history']))[2];
      expect(
        iud.category,
        isNull,
        reason: 'a blank must never be rendered as "safe"',
      );
      expect(iud.note, contains('Not yet assessed'));
    });
  });

  test(
    'the request body uses the field name the reviewed API expects',
    () async {
      late String captured;
      final service = EligibilityApiService(
        baseUrl: 'https://example.test',
        client: MockClient((http.Request request) async {
          captured = request.body;
          return http.Response('[]', 200);
        }),
      );

      await service.checkEligibility(['vte_history', 'migraine_with_aura']);
      expect(jsonDecode(captured), {
        'condition_ids': ['vte_history', 'migraine_with_aura'],
      });
    },
  );
}
