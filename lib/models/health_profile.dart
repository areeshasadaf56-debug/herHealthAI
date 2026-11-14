/// MODULE: models/health_profile.dart
/// ROLE: The single source of truth for everything the app knows about a
/// user over time -- their "health diary". Every tab (PCOS, Protection,
/// Diary, and the AI check-in chat) reads from and writes to this same
/// model, so the AI agent can reference past answers instead of
/// re-asking, and so a PCOS result, a contraception choice, or an
/// eligibility check made today is still visible next month.
///
/// This is intentionally a loose, nested JSON-friendly structure (not a
/// rigid SQL schema) because the fields here will keep growing as you add
/// features -- adding a new field just means adding it to the map, no
/// migration needed on the backend (see health_profile_api.py).
///
/// NOTE: This file defines the app's `PrivacySettings` class (below),
/// used throughout the app (fields: aiCanAccessDiary, aiMemoryEnabled).
/// (An earlier, unused duplicate class of the same name that lived in
/// models/privacy_settings.dart has been removed — this is the only
/// PrivacySettings class in the codebase now.)
///
/// USED BY: services/health_profile_service.dart (all reads/writes go
/// through here), screens/pcos_screen.dart, screens/protection_screen.dart,
/// screens/health_diary_screen.dart, screens/ai_checkin_screen.dart,
/// widgets/wellness_check_in_dialog.dart, widgets/diary_entry_dialog.dart.
library;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Tolerant parsing helpers (review task 1.6).
//
// fromJson used to trust every field's declared type, so one oddly-typed
// value from the backend or an old cached copy (an int user_id, a
// stringified number "26", a bool as 1/0, a malformed date) threw a
// cast/format exception and made the ENTIRE stored profile unparseable
// -- the app then fell back to an empty profile and looked like every
// bit of history just vanished. These helpers coerce the common
// envelopes instead of throwing; truly absurd values become null (or
// the documented default) and never take the whole document down.
// ---------------------------------------------------------------------------

/// Sentinel for the copyWith methods below: "leave this field alone"
/// (the implicit default -- a plain omitted argument). Any OTHER value
/// replaces the field, with null meaning CLEAR it -- the old copyWith
/// treated null and omitted identically, which made fields impossible
/// to reset once set.
const Object _unset = Object();

int? _asInt(Object? v, {int? min, int? max}) {
  int? value;
  if (v is int) {
    value = v;
  } else if (v is num) {
    value = v.toInt();
  } else if (v is bool) {
    value = v ? 1 : 0;
  } else if (v is String) {
    value = int.tryParse(v.trim());
  }
  if (value == null) return null;
  if (min != null && value < min) value = min;
  if (max != null && value > max) value = max;
  return value;
}

double? _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.trim().replaceAll(',', '.'));
  }
  return null;
}

bool? _asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.trim().toLowerCase();
    if (t == 'true' || t == 'yes' || t == '1') return true;
    if (t == 'false' || t == 'no' || t == '0') return false;
  }
  return null;
}

String? _asString(Object? v) {
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return null;
}

DateTime? _asDateTime(Object? v) {
  if (v is DateTime) return v;
  if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
  // Some writers store epoch millis.
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}

List<String> _stringList(Object? v) {
  if (v is List) return v.whereType<String>().toList();
  return const [];
}

Map<String, dynamic> _asMap(Object? v) =>
    v is Map<String, dynamic> ? v : const {};

/// Turns a JSON list of objects into typed model entries, skipping
/// (with a debug note) anything that isn't a map or that an
/// all-tolerant fromJson still can't digest -- one bad row used to
/// poison the whole profile.
List<T> _mapList<T>(Object? v, T Function(Map<String, dynamic>) decode) {
  if (v is! List) return const [];
  final out = <T>[];
  for (final entry in v) {
    final map = _asMap(entry);
    if (map.isEmpty) continue;
    try {
      out.add(decode(map));
    } catch (e) {
      debugPrint('health_profile: skipping undecodable list entry: $e');
    }
  }
  return out;
}

/// Self-reported stress is a 1..5 scale wherever it's edited; older
/// copies of the app or a loose AI value could be 0..10 or a string --
/// coerce and clamp here so nothing outside the documented range is
/// ever stored/shown.
int? _asStress(Object? v) => _asInt(v, min: 1, max: 5);

class HealthProfile {
  final String userId;

  final Demographics demographics;
  final Lifestyle lifestyle;
  final ReproductiveHistory reproductiveHistory;
  final List<PcosCheckResult> pcosHistory;
  final List<EligibilityCheckResult> eligibilityHistory;
  final MentalHealthFlags mentalHealth;
  final List<ConversationEntry> conversationLog;

  /// User-controlled toggles for what the AI check-in is allowed to use
  /// -- e.g. whether it remembers past chat turns, and whether it can
  /// read recent free-text diary entries as context. Read/written from
  /// data_privacy_screen.dart.
  final PrivacySettings privacySettings;

  /// Free-text personal journal entries (separate from the
  /// auto-generated Health Diary timeline in health_diary_screen.dart,
  /// which is built from PCOS/Protection/Cycle/AI history instead of
  /// entries the user writes themselves).
  final List<DiaryEntry> diaryEntries;

  final DateTime lastUpdated;

  const HealthProfile({
    required this.userId,
    required this.demographics,
    required this.lifestyle,
    required this.reproductiveHistory,
    required this.pcosHistory,
    required this.eligibilityHistory,
    required this.mentalHealth,
    required this.conversationLog,
    required this.privacySettings,
    required this.diaryEntries,
    required this.lastUpdated,
  });

  /// A blank profile for a brand-new user (first app launch).
  factory HealthProfile.empty(String userId) {
    return HealthProfile(
      userId: userId,
      demographics: const Demographics(),
      lifestyle: const Lifestyle(),
      reproductiveHistory: const ReproductiveHistory(),
      pcosHistory: const [],
      eligibilityHistory: const [],
      mentalHealth: const MentalHealthFlags(),
      conversationLog: const [],
      privacySettings: const PrivacySettings(),
      diaryEntries: const [],
      lastUpdated: DateTime.now(),
    );
  }

  HealthProfile copyWith({
    Demographics? demographics,
    Lifestyle? lifestyle,
    ReproductiveHistory? reproductiveHistory,
    List<PcosCheckResult>? pcosHistory,
    List<EligibilityCheckResult>? eligibilityHistory,
    MentalHealthFlags? mentalHealth,
    List<ConversationEntry>? conversationLog,
    PrivacySettings? privacySettings,
    List<DiaryEntry>? diaryEntries,
  }) {
    return HealthProfile(
      userId: userId,
      demographics: demographics ?? this.demographics,
      lifestyle: lifestyle ?? this.lifestyle,
      reproductiveHistory: reproductiveHistory ?? this.reproductiveHistory,
      pcosHistory: pcosHistory ?? this.pcosHistory,
      eligibilityHistory: eligibilityHistory ?? this.eligibilityHistory,
      mentalHealth: mentalHealth ?? this.mentalHealth,
      conversationLog: conversationLog ?? this.conversationLog,
      privacySettings: privacySettings ?? this.privacySettings,
      diaryEntries: diaryEntries ?? this.diaryEntries,
      lastUpdated: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'demographics': demographics.toJson(),
    'lifestyle': lifestyle.toJson(),
    'reproductive_history': reproductiveHistory.toJson(),
    'pcos_history': pcosHistory.map((e) => e.toJson()).toList(),
    'eligibility_history': eligibilityHistory.map((e) => e.toJson()).toList(),
    'mental_health': mentalHealth.toJson(),
    'conversation_log': conversationLog.map((e) => e.toJson()).toList(),
    'privacy_settings': privacySettings.toJson(),
    'diary_entries': diaryEntries.map((e) => e.toJson()).toList(),
    'last_updated': lastUpdated.toIso8601String(),
  };

  factory HealthProfile.fromJson(Map<String, dynamic> json) {
    // Int-tolerant everywhere: the backend may hand back numbers where
    // the model expects strings (user_id especially), and the nested
    // decoders below each guard their own fields.
    return HealthProfile(
      userId: _asString(json['user_id']) ?? '',
      demographics: Demographics.fromJson(_asMap(json['demographics'])),
      lifestyle: Lifestyle.fromJson(_asMap(json['lifestyle'])),
      reproductiveHistory: ReproductiveHistory.fromJson(
        _asMap(json['reproductive_history']),
      ),
      pcosHistory: _mapList(json['pcos_history'], PcosCheckResult.fromJson),
      eligibilityHistory: _mapList(
        json['eligibility_history'],
        EligibilityCheckResult.fromJson,
      ),
      mentalHealth: MentalHealthFlags.fromJson(_asMap(json['mental_health'])),
      conversationLog: _mapList(
        json['conversation_log'],
        ConversationEntry.fromJson,
      ),
      privacySettings: PrivacySettings.fromJson(
        _asMap(json['privacy_settings']),
      ),
      diaryEntries: _mapList(json['diary_entries'], DiaryEntry.fromJson),
      lastUpdated: _asDateTime(json['last_updated']) ?? DateTime.now(),
    );
  }
}

/// ---------------------------------------------------------------
/// Privacy settings -- user-controlled toggles for what the AI
/// check-in is allowed to use. Both default to true so existing AI
/// features keep working exactly as before for anyone who never
/// visits Settings > Data & Privacy to change them; the toggles exist
/// so users CAN opt out, not so the app starts locked down.
/// ---------------------------------------------------------------
class PrivacySettings {
  /// Whether the AI check-in sends past turns of the current chat
  /// session as context on each new message (i.e. "remembers" the
  /// conversation so far). When false, each message is sent with no
  /// history, so the AI has no memory even within one session.
  final bool aiMemoryEnabled;

  /// Whether the AI check-in may read recent free-text diaryEntries as
  /// additional context (mood, symptom tags, journal text) when
  /// building its replies.
  final bool aiCanAccessDiary;

  const PrivacySettings({
    this.aiMemoryEnabled = true,
    this.aiCanAccessDiary = true,
  });

  PrivacySettings copyWith({bool? aiMemoryEnabled, bool? aiCanAccessDiary}) {
    return PrivacySettings(
      aiMemoryEnabled: aiMemoryEnabled ?? this.aiMemoryEnabled,
      aiCanAccessDiary: aiCanAccessDiary ?? this.aiCanAccessDiary,
    );
  }

  Map<String, dynamic> toJson() => {
    'ai_memory_enabled': aiMemoryEnabled,
    'ai_can_access_diary': aiCanAccessDiary,
  };

  factory PrivacySettings.fromJson(Map<String, dynamic> json) {
    return PrivacySettings(
      aiMemoryEnabled: _asBool(json['ai_memory_enabled']) ?? true,
      aiCanAccessDiary: _asBool(json['ai_can_access_diary']) ?? true,
    );
  }
}

/// ---------------------------------------------------------------
/// A free-text personal journal entry -- distinct from the
/// auto-generated Health Diary timeline (health_diary_screen.dart),
/// which is built purely from PCOS/Protection/Cycle/AI history rather
/// than something the user writes themselves.
/// ---------------------------------------------------------------
class DiaryEntry {
  final DateTime date;
  final String? mood;
  final List<String> symptomTags;
  final String text;

  const DiaryEntry({
    required this.date,
    this.mood,
    this.symptomTags = const [],
    required this.text,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'mood': mood,
    'symptom_tags': symptomTags,
    'text': text,
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    return DiaryEntry(
      date: _asDateTime(json['date']) ?? DateTime.now(),
      mood: _asString(json['mood']),
      symptomTags: _stringList(json['symptom_tags']),
      text: _asString(json['text']) ?? '',
    );
  }
}

/// ---------------------------------------------------------------
/// Demographics -- who the user is. Kept separate from lifestyle so
/// the PCOS/Protection forms can pull just this section without
/// pulling everything else.
/// ---------------------------------------------------------------
class Demographics {
  final int? ageYrs;
  final double? weightKg;
  final double? heightCm;

  /// 'Single', 'Married', 'Divorced', 'Widowed', or null if not provided.
  /// Relevant because some contraception/PCOS guidance differs by this
  /// (e.g. fertility planning conversations, some WHO MEC categories).
  final String? maritalStatus;

  const Demographics({
    this.ageYrs,
    this.weightKg,
    this.heightCm,
    this.maritalStatus,
  });

  /// Self-documenting for callers: omit a parameter to keep the old
  /// value, pass an explicit null to CLEAR it, pass a value to change
  /// it. (The old signature could neither clear fields nor accept
  /// coerced values, which is how stale demographics went sticky.)
  Demographics copyWith({
    Object? ageYrs = _unset,
    Object? weightKg = _unset,
    Object? heightCm = _unset,
    Object? maritalStatus = _unset,
  }) {
    return Demographics(
      ageYrs: ageYrs == _unset ? this.ageYrs : _asInt(ageYrs),
      weightKg: weightKg == _unset ? this.weightKg : _asDouble(weightKg),
      heightCm: heightCm == _unset ? this.heightCm : _asDouble(heightCm),
      maritalStatus: maritalStatus == _unset
          ? this.maritalStatus
          : _asString(maritalStatus),
    );
  }

  Map<String, dynamic> toJson() => {
    'age_yrs': ageYrs,
    'weight_kg': weightKg,
    'height_cm': heightCm,
    'marital_status': maritalStatus,
  };

  factory Demographics.fromJson(Map<String, dynamic> json) {
    return Demographics(
      ageYrs: _asInt(json['age_yrs']),
      weightKg: _asDouble(json['weight_kg']),
      heightCm: _asDouble(json['height_cm']),
      maritalStatus: _asString(json['marital_status']),
    );
  }
}

/// ---------------------------------------------------------------
/// Lifestyle -- the day-to-day habits the AI check-in asks about
/// (exercise, diet, fast food, sleep) and uses to drive
/// recommendations.
/// ---------------------------------------------------------------
class Lifestyle {
  final bool? regularExercise;
  final String? exerciseFrequency; // e.g. 'Never', '1-2x/week', '3+/week'
  final String? dietQuality; // e.g. 'Poor', 'Average', 'Good'
  final bool? fastFoodFrequent;
  final double? averageSleepHours;

  /// Free-text notes captured verbatim from the AI chat, in case the
  /// structured fields above don't capture everything the user said.
  final String? notes;

  const Lifestyle({
    this.regularExercise,
    this.exerciseFrequency,
    this.dietQuality,
    this.fastFoodFrequent,
    this.averageSleepHours,
    this.notes,
  });

  /// Omit to keep, explicit null to clear, value to change.
  Lifestyle copyWith({
    Object? regularExercise = _unset,
    Object? exerciseFrequency = _unset,
    Object? dietQuality = _unset,
    Object? fastFoodFrequent = _unset,
    Object? averageSleepHours = _unset,
    Object? notes = _unset,
  }) {
    return Lifestyle(
      regularExercise: regularExercise == _unset
          ? this.regularExercise
          : _asBool(regularExercise),
      exerciseFrequency: exerciseFrequency == _unset
          ? this.exerciseFrequency
          : _asString(exerciseFrequency),
      dietQuality: dietQuality == _unset
          ? this.dietQuality
          : _asString(dietQuality),
      fastFoodFrequent: fastFoodFrequent == _unset
          ? this.fastFoodFrequent
          : _asBool(fastFoodFrequent),
      averageSleepHours: averageSleepHours == _unset
          ? this.averageSleepHours
          : _asDouble(averageSleepHours),
      notes: notes == _unset ? this.notes : _asString(notes),
    );
  }

  Map<String, dynamic> toJson() => {
    'regular_exercise': regularExercise,
    'exercise_frequency': exerciseFrequency,
    'diet_quality': dietQuality,
    'fast_food_frequent': fastFoodFrequent,
    'average_sleep_hours': averageSleepHours,
    'notes': notes,
  };

  factory Lifestyle.fromJson(Map<String, dynamic> json) {
    return Lifestyle(
      regularExercise: _asBool(json['regular_exercise']),
      exerciseFrequency: _asString(json['exercise_frequency']),
      dietQuality: _asString(json['diet_quality']),
      fastFoodFrequent: _asBool(json['fast_food_frequent']),
      averageSleepHours: _asDouble(json['average_sleep_hours']),
      notes: _asString(json['notes']),
    );
  }
}

/// ---------------------------------------------------------------
/// Reproductive history -- cycle info and contraception choices over
/// time, feeding both the Protection tab and future PCOS pre-fill.
/// ---------------------------------------------------------------
class ReproductiveHistory {
  final String? cycleRegularity; // 'Regular' or 'Irregular'

  /// WRITTEN COPY of the user's cycle length (task 3.6): the tracker's
  /// `CycleData.cycleLength` (cycle_provider) is the source of truth
  /// and mirrors into this field on every tracker change. The PCOS
  /// form also writes its own entered value here directly (it feeds ML
  /// features). Read paths (Health Diary display, PCOS prefill) use
  /// this copy; never treat it as an independent setting.
  final int? cycleLengthDays;

  /// The contraception method currently in use, if any (matches the
  /// method names used in protection_screen.dart's _methods list).
  final String? currentContraceptionMethod;

  /// Every eligibility check or method chosen over time, most recent
  /// last -- lets "My Plan" show a real history instead of only the
  /// latest result.
  final List<ContraceptionLogEntry> contraceptionHistory;

  const ReproductiveHistory({
    this.cycleRegularity,
    this.cycleLengthDays,
    this.currentContraceptionMethod,
    this.contraceptionHistory = const [],
  });

  /// Omit to keep, explicit null to clear, value to change.
  ReproductiveHistory copyWith({
    Object? cycleRegularity = _unset,
    Object? cycleLengthDays = _unset,
    Object? currentContraceptionMethod = _unset,
    List<ContraceptionLogEntry>? contraceptionHistory,
  }) {
    return ReproductiveHistory(
      cycleRegularity: cycleRegularity == _unset
          ? this.cycleRegularity
          : _asString(cycleRegularity),
      cycleLengthDays: cycleLengthDays == _unset
          ? this.cycleLengthDays
          : _asInt(cycleLengthDays),
      currentContraceptionMethod: currentContraceptionMethod == _unset
          ? this.currentContraceptionMethod
          : _asString(currentContraceptionMethod),
      contraceptionHistory: contraceptionHistory ?? this.contraceptionHistory,
    );
  }

  Map<String, dynamic> toJson() => {
    'cycle_regularity': cycleRegularity,
    'cycle_length_days': cycleLengthDays,
    'current_contraception_method': currentContraceptionMethod,
    'contraception_history': contraceptionHistory
        .map((e) => e.toJson())
        .toList(),
  };

  factory ReproductiveHistory.fromJson(Map<String, dynamic> json) {
    return ReproductiveHistory(
      cycleRegularity: _asString(json['cycle_regularity']),
      cycleLengthDays: _asInt(json['cycle_length_days']),
      currentContraceptionMethod: _asString(
        json['current_contraception_method'],
      ),
      contraceptionHistory: _mapList(
        json['contraception_history'],
        ContraceptionLogEntry.fromJson,
      ),
    );
  }
}

class ContraceptionLogEntry {
  final DateTime date;
  final String method;
  final String? note;

  const ContraceptionLogEntry({
    required this.date,
    required this.method,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'method': method,
    'note': note,
  };

  factory ContraceptionLogEntry.fromJson(Map<String, dynamic> json) {
    return ContraceptionLogEntry(
      date: _asDateTime(json['date']) ?? DateTime.now(),
      method: _asString(json['method']) ?? 'Not recorded',
      note: _asString(json['note']),
    );
  }
}

/// ---------------------------------------------------------------
/// PCOS check history -- every result the user has ever gotten from
/// the Detection tab, so trends over time are possible later (e.g.
/// "your estimated likelihood has gone from 40% to 65% over 3
/// months" -- a much more useful signal than a single snapshot).
/// ---------------------------------------------------------------
class PcosCheckResult {
  final DateTime date;
  final String prediction; // 'PCOS Detected' / 'No PCOS Detected'
  final double pcosProbability;
  final String modelUsed;

  const PcosCheckResult({
    required this.date,
    required this.prediction,
    required this.pcosProbability,
    required this.modelUsed,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'prediction': prediction,
    'pcos_probability': pcosProbability,
    'model_used': modelUsed,
  };

  factory PcosCheckResult.fromJson(Map<String, dynamic> json) {
    return PcosCheckResult(
      date: _asDateTime(json['date']) ?? DateTime.now(),
      prediction: _asString(json['prediction']) ?? 'Not recorded',
      pcosProbability: _asDouble(json['pcos_probability']) ?? 0.0,
      modelUsed: _asString(json['model_used']) ?? 'unknown',
    );
  }
}

/// ---------------------------------------------------------------
/// Eligibility check history -- every time the user runs the
/// Protection > My Plan > Eligibility tool, the conditions they
/// selected and the per-method category results are saved here, so
/// past checks are visible in the Health Diary instead of vanishing
/// the moment the user leaves that screen.
/// ---------------------------------------------------------------
class EligibilityResultEntry {
  final String methodLabel;
  final int category;

  const EligibilityResultEntry({
    required this.methodLabel,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'method_label': methodLabel,
    'category': category,
  };

  factory EligibilityResultEntry.fromJson(Map<String, dynamic> json) {
    return EligibilityResultEntry(
      methodLabel: _asString(json['method_label']) ?? 'Unknown method',
      category: _asInt(json['category']) ?? 0,
    );
  }
}

class EligibilityCheckResult {
  final DateTime date;

  /// Human-readable labels of the conditions the user selected (not raw
  /// backend IDs), so the Diary can display something meaningful without
  /// needing to re-fetch the condition list.
  final List<String> conditions;
  final List<EligibilityResultEntry> results;

  const EligibilityCheckResult({
    required this.date,
    required this.conditions,
    required this.results,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'conditions': conditions,
    'results': results.map((e) => e.toJson()).toList(),
  };

  factory EligibilityCheckResult.fromJson(Map<String, dynamic> json) {
    return EligibilityCheckResult(
      date: _asDateTime(json['date']) ?? DateTime.now(),
      conditions: _stringList(json['conditions']),
      results: _mapList(json['results'], EligibilityResultEntry.fromJson),
    );
  }
}

/// ---------------------------------------------------------------
/// Mental health flags -- deliberately lightweight and NON-diagnostic.
/// This app must never claim to diagnose anxiety, depression, or any
/// mental health condition. These fields exist only to let the AI
/// check-in be gentler/more relevant on a return visit (e.g. "last
/// time you mentioned feeling stressed about work -- how's that
/// going?") and to decide when to show a "please consider talking to
/// someone" prompt with real crisis resources, never a label.
/// ---------------------------------------------------------------
class MentalHealthFlags {
  /// Self-reported 1-5 scale, set by the user/AI chat, never inferred
  /// or asserted by the app on its own.
  final int? selfReportedStressLevel;
  final String? notes;
  final DateTime? lastCheckIn;

  const MentalHealthFlags({
    this.selfReportedStressLevel,
    this.notes,
    this.lastCheckIn,
  });

  /// Omit to keep, explicit null to clear, value to change. A stress
  /// value passed here goes through the same 1..5 clamp as parsing.
  MentalHealthFlags copyWith({
    Object? selfReportedStressLevel = _unset,
    Object? notes = _unset,
    Object? lastCheckIn = _unset,
  }) {
    return MentalHealthFlags(
      selfReportedStressLevel: selfReportedStressLevel == _unset
          ? this.selfReportedStressLevel
          : _asStress(selfReportedStressLevel),
      notes: notes == _unset ? this.notes : _asString(notes),
      lastCheckIn: lastCheckIn == _unset
          ? this.lastCheckIn
          : _asDateTime(lastCheckIn),
    );
  }

  Map<String, dynamic> toJson() => {
    'self_reported_stress_level': selfReportedStressLevel,
    'notes': notes,
    'last_check_in': lastCheckIn?.toIso8601String(),
  };

  factory MentalHealthFlags.fromJson(Map<String, dynamic> json) {
    return MentalHealthFlags(
      selfReportedStressLevel: _asStress(json['self_reported_stress_level']),
      notes: _asString(json['notes']),
      lastCheckIn: _asDateTime(json['last_check_in']),
    );
  }
}

/// ---------------------------------------------------------------
/// Conversation log -- the raw AI check-in chat history, so the AI
/// agent has memory of past conversations instead of starting fresh
/// every time.
/// ---------------------------------------------------------------
class ConversationEntry {
  final DateTime timestamp;
  final String role; // 'user' or 'assistant'
  final String message;

  /// Groups turns into distinct chat sessions (see AiCheckinScreen's
  /// "Chats" history sheet). Entries saved before this field existed
  /// have no sessionId, so the screen treats those as one combined
  /// "legacy" session rather than losing them.
  final String? sessionId;

  const ConversationEntry({
    required this.timestamp,
    required this.role,
    required this.message,
    this.sessionId,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'role': role,
    'message': message,
    'session_id': sessionId,
  };

  factory ConversationEntry.fromJson(Map<String, dynamic> json) {
    return ConversationEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      role: json['role'] as String,
      message: json['message'] as String,
      sessionId: json['session_id'] as String?,
    );
  }
}
