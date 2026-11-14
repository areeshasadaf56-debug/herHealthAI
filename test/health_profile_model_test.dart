import 'package:flutter_test/flutter_test.dart';
import 'package:wellness_saheli/models/health_profile.dart';

void main() {
  group('tolerant fromJson (task 1.6)', () {
    test('stringified numbers / bool-as-1-0 / int user_id all decode', () {
      final p = HealthProfile.fromJson({
        'user_id': 42, // server sent an int, model wants String
        'demographics': {
          'age_yrs': '26', // stringified int
          'weight_kg': '68.5',
          'height_cm': 165, // num where double expected
        },
        'lifestyle': {
          'regular_exercise': 1, // bool as 1/0
          'fast_food_frequent': '0',
          'average_sleep_hours': '7,5', // European decimal comma
        },
        'mental_health': {'self_reported_stress_level': '3'},
        'reproductive_history': {'cycle_length_days': 35},
        'privacy_settings': {'ai_memory_enabled': 'true'},
      });

      expect(p.userId, '42');
      expect(p.demographics.ageYrs, 26);
      expect(p.demographics.weightKg, 68.5);
      expect(p.demographics.heightCm, 165.0);
      expect(p.lifestyle.regularExercise, isTrue);
      expect(p.lifestyle.fastFoodFrequent, isFalse);
      expect(p.lifestyle.averageSleepHours, 7.5);
      expect(p.mentalHealth.selfReportedStressLevel, 3);
      expect(p.reproductiveHistory.cycleLengthDays, 35);
      expect(p.privacySettings.aiMemoryEnabled, isTrue);
      // Deliberate default flip (task 4.2): diary access is opt-in --
      // the Data & Privacy screen has always said "off by default".
      expect(p.privacySettings.aiCanAccessDiary, isFalse);
    });

    test('absurd values become null/defaults instead of throwing', () {
      final p = HealthProfile.fromJson({
        'demographics': {'age_yrs': 'not a number at all'},
        'lifestyle': {'average_sleep_hours': 'zzz'},
        'mental_health': {'last_check_in': 'not a date'},
      });

      expect(p.demographics.ageYrs, isNull);
      expect(p.lifestyle.averageSleepHours, isNull);
      expect(p.mentalHealth.lastCheckIn, isNull);
    });

    test('poisoned history rows are skipped; the rest survives', () {
      final p = HealthProfile.fromJson({
        'pcos_history': [
          'not a map at all', // used to crash the WHOLE profile load
          {
            'date': '2026-01-15T10:00:00',
            'prediction': 'PCOS Detected',
            'pcos_probability': 72.5,
            'model_used': 'svc',
          },
        ],
        'diary_entries': [
          {
            'text': 'kept despite broken sibling',
            'date': '(LayoutBreakpoint)', // malformed date
          },
        ],
      });

      expect(p.pcosHistory, hasLength(1));
      expect(p.pcosHistory.single.prediction, 'PCOS Detected');
      expect(p.pcosHistory.single.pcosProbability, 72.5);

      expect(p.diaryEntries, hasLength(1));
      expect(p.diaryEntries.single.text, 'kept despite broken sibling');
      // Malformed date degrades to ~now instead of killing the doc.
      expect(p.diaryEntries.single.date.year, greaterThanOrEqualTo(2025));
    });

    test('self-reported stress clamps into the documented 1..5 scale', () {
      final over = MentalHealthFlags.fromJson({
        'self_reported_stress_level': 7,
      });
      final zero = MentalHealthFlags.fromJson({
        'self_reported_stress_level': 0,
      });
      final asString = MentalHealthFlags.fromJson({
        'self_reported_stress_level': '5',
      });
      // "8" on the old 0..10 style misencoding lands at the top of our
      // documented scale rather than being stored as an impossible 8.
      expect(over.selfReportedStressLevel, 5);
      expect(zero.selfReportedStressLevel, 1);
      expect(asString.selfReportedStressLevel, 5);
    });

    test('sentinel copyWith: omission keeps, explicit null clears '
        '(the sticky-field fix)', () {
      const demo = Demographics(ageYrs: 26, maritalStatus: 'Married');

      final changed = demo.copyWith(ageYrs: 27);
      expect(changed.ageYrs, 27);
      expect(changed.maritalStatus, 'Married');

      final clearedAge = demo.copyWith(ageYrs: null);
      expect(clearedAge.ageYrs, isNull);
      expect(clearedAge.maritalStatus, 'Married');

      const life = Lifestyle(notes: 'old note', regularExercise: true);
      final noNotes = life.copyWith(notes: null);
      expect(noNotes.notes, isNull);
      expect(noNotes.regularExercise, isTrue);

      const repro = ReproductiveHistory(currentContraceptionMethod: 'Pills');
      final switched = repro.copyWith(currentContraceptionMethod: null);
      expect(switched.currentContraceptionMethod, isNull);

      const mental = MentalHealthFlags(
        selfReportedStressLevel: 4,
        notes: 'feeling tense',
      );
      final destressed = mental.copyWith(selfReportedStressLevel: null);
      expect(destressed.selfReportedStressLevel, isNull);
      expect(destressed.notes, 'feeling tense');

      // CopyWith clamps too, matching the parse-side documented scale.
      final clamped = mental.copyWith(selfReportedStressLevel: 9);
      expect(clamped.selfReportedStressLevel, 5);
    });

    test('profile round-trips through toJson/fromJson without loss', () async {
      final original = HealthProfile.empty('user-x').copyWith(
        pcosHistory: [
          PcosCheckResult(
            date: DateTime(2026, 2, 1),
            prediction: 'No PCOS Detected',
            pcosProbability: 18.25,
            modelUsed: 'svc',
          ),
        ],
        privacySettings: const PrivacySettings(
          aiMemoryEnabled: false,
          aiCanAccessDiary: true,
        ),
      );

      final copy = HealthProfile.fromJson(original.toJson());
      expect(copy.userId, 'user-x');
      expect(copy.pcosHistory.single.pcosProbability, 18.25);
      expect(copy.pcosHistory.single.prediction, 'No PCOS Detected');
      expect(copy.privacySettings.aiMemoryEnabled, isFalse);
      expect(copy.lastUpdated, original.lastUpdated);
    });
  });

  group('privacy settings: consent record + opt-in defaults (task 4.2)', () {
    test('fresh profile: diary access off, no consent timestamp yet', () {
      final p = HealthProfile.empty('consent-x');
      expect(p.privacySettings.aiMemoryEnabled, isTrue);
      expect(p.privacySettings.aiCanAccessDiary, isFalse);
      expect(p.privacySettings.consentAcceptedAt, isNull);
    });

    test('consentAcceptedAt round-trips through toJson/fromJson', () {
      final when = DateTime.utc(2026, 11, 14, 9, 30);
      final original = HealthProfile.empty('consent-x').copyWith(
        privacySettings: const PrivacySettings().copyWith(
          consentAcceptedAt: when,
        ),
      );

      // The key is always written (even when null) so an
      // accepted-then-cleared consent round-trips as "not accepted",
      // not as "absent field".
      expect(
        original.toJson()['privacy_settings'],
        containsPair('consent_accepted_at', when.toIso8601String()),
      );

      final copy = HealthProfile.fromJson(original.toJson());
      expect(copy.privacySettings.consentAcceptedAt, when);
    });

    test('absent or garbage consent timestamp decodes to null (tolerant)', () {
      final absent = HealthProfile.fromJson({
        'user_id': 'consent-x',
        'privacy_settings': <String, dynamic>{},
      });
      expect(absent.privacySettings.consentAcceptedAt, isNull);

      final garbage = HealthProfile.fromJson({
        'user_id': 'consent-x',
        'privacy_settings': {'consent_accepted_at': 'not a date'},
      });
      expect(garbage.privacySettings.consentAcceptedAt, isNull);
    });
  });
}
