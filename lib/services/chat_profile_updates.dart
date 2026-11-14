// Task 1.7: allow-listed, type-checked application of the AI's
// structured profile updates.
//
// The backend's /chat reply may carry a `profile_updates` object the
// model produced from free conversation. This is effectively the AI
// writing into the user's health profile, so:
//
// * only the sections and keys listed in [kAllowedChatUpdateKeys] are
//   accepted -- anything else (unknown keys, nested objects, lists)
//   is dropped, never merged;
// * every accepted value's type is checked ([chatUpdateValueTypeOk]);
// * `life_context`, the redundant parallel channel for
//   mental-health-adjacent fields, was removed entirely --
//   `mental_health` is the one structured channel for these fields.
//
// Pure functions, no I/O, so they are unit-testable in isolation.

import '../models/health_profile.dart';

/// The ONLY sections and keys the AI may touch, with the value types
/// each key may carry.
///
/// Deliberately NOT included:
/// * `contraception_history` (app-managed, written by the Protection
///   screen)
/// * `last_check_in` (the app stamps it itself on mental_health
///   updates -- the AI must not fake timestamps)
/// * `life_context` (the removed redundant channel)
const Map<String, Set<String>> kAllowedChatUpdateKeys = {
  'lifestyle': {
    'regular_exercise',
    'exercise_frequency',
    'diet_quality',
    'fast_food_frequent',
    'average_sleep_hours',
    'notes',
  },
  'mental_health': {'self_reported_stress_level', 'notes'},
  'reproductive_history': {
    'cycle_regularity',
    'cycle_length_days',
    'current_contraception_method',
  },
};

/// Value-type rules per key. Bools may also arrive as 'true'/'false'
/// strings and numbers as numeric strings (the model's tolerant
/// parsers normalize them) -- but lists, maps and other objects are
/// always dropped.
bool chatUpdateValueTypeOk(String key, dynamic value) {
  const boolKeys = {'regular_exercise', 'fast_food_frequent'};
  const numKeys = {
    'average_sleep_hours',
    'cycle_length_days',
    'self_reported_stress_level',
  };
  if (boolKeys.contains(key)) {
    return value is bool || value is String;
  }
  if (numKeys.contains(key)) {
    return value is num || (value is String && num.tryParse(value) != null);
  }
  return value is String;
}

/// Filters [rawUpdates] down to the allow-list above. Returns null when
/// nothing acceptable remains, so no update round-trip happens for
/// garbage payloads.
Map<String, Map<String, dynamic>>? sanitizeChatProfileUpdates(
  Map<String, dynamic> rawUpdates,
) {
  final sanitized = <String, Map<String, dynamic>>{};
  for (final entry in kAllowedChatUpdateKeys.entries) {
    final section = rawUpdates[entry.key];
    if (section is! Map || section.isEmpty) continue;
    final accepted = <String, dynamic>{};
    section.forEach((key, value) {
      final name = key.toString();
      if (!entry.value.contains(name)) return;
      if (!chatUpdateValueTypeOk(name, value)) return;
      accepted[name] = value;
    });
    if (accepted.isNotEmpty) sanitized[entry.key] = accepted;
  }
  return sanitized.isEmpty ? null : sanitized;
}

/// Applies already-sanitized updates to [current]: each allowed section
/// is merged over the existing values and re-parsed through the model's
/// tolerant fromJson (which also clamps stress to 1..5 and normalizes
/// stringified numbers).
HealthProfile applyChatProfileUpdates(
  HealthProfile current,
  Map<String, dynamic> updates,
) {
  var result = current;

  final lifestyleUpdate = updates['lifestyle'] as Map<String, dynamic>?;
  if (lifestyleUpdate != null && lifestyleUpdate.isNotEmpty) {
    final merged = {...result.lifestyle.toJson(), ...lifestyleUpdate};
    result = result.copyWith(lifestyle: Lifestyle.fromJson(merged));
  }

  final mentalHealthUpdate = updates['mental_health'] as Map<String, dynamic>?;
  if (mentalHealthUpdate != null && mentalHealthUpdate.isNotEmpty) {
    final merged = {
      ...result.mentalHealth.toJson(),
      ...mentalHealthUpdate,
      // The app stamps the check-in time itself; the AI payload is
      // allow-listed so it can never carry its own last_check_in.
      'last_check_in': DateTime.now().toIso8601String(),
    };
    result = result.copyWith(mentalHealth: MentalHealthFlags.fromJson(merged));
  }

  final reproUpdate = updates['reproductive_history'] as Map<String, dynamic>?;
  if (reproUpdate != null && reproUpdate.isNotEmpty) {
    final merged = {...result.reproductiveHistory.toJson(), ...reproUpdate};
    result = result.copyWith(
      reproductiveHistory: ReproductiveHistory.fromJson(merged),
    );
  }

  return result;
}
