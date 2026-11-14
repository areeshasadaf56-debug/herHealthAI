import 'package:flutter_test/flutter_test.dart';

import 'package:wellness_saheli/models/health_profile.dart';
import 'package:wellness_saheli/services/chat_profile_updates.dart';

/// Task 1.7 -- the AI's structured `profile_updates` payload is the
/// model writing into the user's health profile. These tests pin the
/// allow-list (unknown sections/keys dropped), the value-type rules,
/// and the removal of the redundant `life_context` channel.
void main() {
  group('sanitizeChatProfileUpdates (allow-list)', () {
    test('keeps allowed keys, drops everything else', () {
      final sanitized = sanitizeChatProfileUpdates({
        'lifestyle': {
          'average_sleep_hours': '6.5',
          'evil_key': '<script>',
          'contraception_history': [
            {'hacked': true},
          ],
        },
        'mental_health': {
          'self_reported_stress_level': 4,
          'notes': 'long days',
        },
        'reproductive_history': {'cycle_regularity': 'Irregular'},
      });

      expect(sanitized, isNotNull);
      expect(sanitized!['lifestyle'], {'average_sleep_hours': '6.5'});
      expect(sanitized['mental_health'], {
        'self_reported_stress_level': 4,
        'notes': 'long days',
      });
      expect(sanitized['reproductive_history'], {
        'cycle_regularity': 'Irregular',
      });
    });

    test('life_context is a removed channel -- always dropped', () {
      final sanitized = sanitizeChatProfileUpdates({
        'life_context': {
          'financial_stress': 'high',
          'relationship_status': 'single',
        },
      });
      expect(sanitized, isNull);
    });

    test('unknown top-level sections are dropped', () {
      final sanitized = sanitizeChatProfileUpdates({
        'demographics': {'age_yrs': 999},
        'privacy_settings': {'ai_can_access_diary': true},
      });
      expect(sanitized, isNull);
    });

    test('wrong value types are dropped', () {
      final sanitized = sanitizeChatProfileUpdates({
        'lifestyle': {
          'average_sleep_hours': [1, 2, 3], // list, not number
          'regular_exercise': {'a': 1}, // map, not bool
        },
        'mental_health': {
          'self_reported_stress_level': 'feeling great', // non-numeric string
        },
        'reproductive_history': {
          'cycle_length_days': 'long', // non-numeric string
        },
      });
      expect(sanitized, isNull);
    });

    test('stringified bools/numbers are accepted (tolerant parsing)', () {
      final sanitized = sanitizeChatProfileUpdates({
        'lifestyle': {'regular_exercise': 'true', 'average_sleep_hours': '7'},
      });
      expect(sanitized, isNotNull);
      expect(sanitized!['lifestyle'], {
        'regular_exercise': 'true',
        'average_sleep_hours': '7',
      });
    });

    test('a section that is not a Map is ignored, not thrown on', () {
      final sanitized = sanitizeChatProfileUpdates({
        'lifestyle': 'I exercise sometimes',
      });
      expect(sanitized, isNull);
    });
  });

  group('applyChatProfileUpdates', () {
    test('merges over existing values without losing untouched fields', () {
      final current = HealthProfile.empty('u1').copyWith(
        lifestyle: Lifestyle(
          exerciseFrequency: '1-2x/week',
          dietQuality: 'Good',
        ),
      );

      final updated = applyChatProfileUpdates(current, {
        'lifestyle': {'average_sleep_hours': '6.5'},
      });

      // New value applied...
      expect(updated.lifestyle.averageSleepHours, 6.5);
      // ...existing values kept.
      expect(updated.lifestyle.exerciseFrequency, '1-2x/week');
      expect(updated.lifestyle.dietQuality, 'Good');
    });

    test('stress from the AI clamps into 1..5 (model rule)', () {
      final current = HealthProfile.empty('u1');
      final updated = applyChatProfileUpdates(current, {
        'mental_health': {'self_reported_stress_level': 11},
      });
      expect(updated.mentalHealth.selfReportedStressLevel, 5);
    });

    test('AI cannot fake last_check_in -- the app stamps it', () {
      final current = HealthProfile.empty('u1');
      final before = DateTime.now();
      final updated = applyChatProfileUpdates(current, {
        'mental_health': {
          'last_check_in': '1999-01-01T00:00:00.000Z',
          'notes': 'stressed about exams',
        },
      });
      final stamped = DateTime.parse(
        updated.mentalHealth.lastCheckIn!.toIso8601String(),
      );
      expect(
        stamped.isAfter(before.subtract(const Duration(seconds: 5))),
        isTrue,
        reason: 'last_check_in must be "now", not the AI-supplied 1999 value',
      );
      expect(updated.mentalHealth.notes, 'stressed about exams');
    });

    test('reproductive merge keeps app-managed contraception history', () {
      final current = HealthProfile.empty('u1').copyWith(
        reproductiveHistory: ReproductiveHistory(
          currentContraceptionMethod: 'Condoms',
        ),
      );
      final updated = applyChatProfileUpdates(current, {
        'reproductive_history': {'cycle_regularity': 'Regular'},
      });
      expect(updated.reproductiveHistory.cycleRegularity, 'Regular');
      expect(updated.reproductiveHistory.currentContraceptionMethod, 'Condoms');
    });

    test('mental-health-only update leaves other sections untouched', () {
      final current = HealthProfile.empty(
        'u1',
      ).copyWith(lifestyle: Lifestyle(dietQuality: 'Poor'));
      final updated = applyChatProfileUpdates(current, {
        'mental_health': {'notes': 'feeling low'},
      });
      expect(updated.lifestyle.dietQuality, 'Poor');
      expect(updated.mentalHealth.notes, 'feeling low');
    });
  });
}
