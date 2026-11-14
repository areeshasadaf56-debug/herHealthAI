import '../utils/app_dates.dart';

/// The user's cycle settings plus the anchor date all cycle math
/// derives from.
class CycleData {
  /// Midnight of the day the last recorded period started, or null
  /// while the user hasn't set it yet (task 3.2). Null is a real,
  /// supported state: the provider no longer fabricates a placeholder
  /// date, and screens showing cycle math prompt for the date instead
  /// of displaying invented day numbers.
  DateTime? lastPeriodStart;
  int cycleLength; // average days between periods
  int periodDuration; // how many days the period lasts

  CycleData({
    this.lastPeriodStart,
    this.cycleLength = 28,
    this.periodDuration = 5,
  });

  /// True once a period start is recorded and the derived math below
  /// is meaningful.
  bool get hasPeriodData => lastPeriodStart != null;

  // Which day of the cycle is it today (1-based); null while no period
  // start is recorded.
  int? getCurrentCycleDay() => getCurrentCycleDayOn(DateTime.now());

  /// The same computation against an arbitrary date: the testable seam
  /// for the cycle math (task 3.4) and the building block for the
  /// phase/ovulation getters that consolidate the duplicated copies
  /// across screens (task 3.1).
  int? getCurrentCycleDayOn(DateTime today) {
    final start = lastPeriodStart;
    if (start == null) return null;
    final daysSince = daysBetween(start, today);
    return (daysSince % cycleLength) + 1;
  }

  /// Day on which ovulation is expected, in the app's display
  /// convention: mid-cycle, floored (day 14 of a 28-day cycle). This
  /// getter is the single source of truth (task 3.1) -- the ovulation
  /// screen, the home fertility card and the phase math each kept
  /// their own copy of this formula, and two of them disagreed about
  /// where the Ovulation phase starts.
  int get ovulationDay => (cycleLength / 2).floor();

  // Rough phase name for a given cycle day (1-based). Boundaries line
  // up with the ovulation screen's rows: Ovulation is the ovulation
  // day itself plus the following day, Luteal starts the day after
  // that.
  String getPhaseOn(int day) {
    if (day <= periodDuration) return "Menstrual";
    if (day < ovulationDay) return "Follicular";
    if (day <= ovulationDay + 1) return "Ovulation";
    return "Luteal";
  }

  // Rough phase name based on the current cycle day; null while no
  // period start is recorded.
  String? getPhase() {
    final day = getCurrentCycleDay();
    return day == null ? null : getPhaseOn(day);
  }

  /// Days until the next ovulation (0 = today is the ovulation day).
  /// Wraps once ovulation has passed. Null while no period start is
  /// recorded. The parameterized variant is the testable seam, same
  /// pattern as getCurrentCycleDayOn.
  int? get daysUntilOvulation => daysUntilOvulationOn(DateTime.now());

  int? daysUntilOvulationOn(DateTime today) {
    final day = getCurrentCycleDayOn(today);
    if (day == null) return null;
    final diff = ovulationDay - day;
    return diff >= 0 ? diff : cycleLength + diff;
  }

  /// Whole days since the recorded period start (0 = started today).
  /// NOT wrapped by the cycle length -- values beyond [cycleLength]
  /// are exactly how a late period is measured (task 3.3), while the
  /// cycle-day math above keeps wrapping. Null while no period start
  /// is recorded.
  int? get daysSinceLastPeriodStart =>
      daysSinceLastPeriodStartOn(DateTime.now());

  int? daysSinceLastPeriodStartOn(DateTime today) {
    final start = lastPeriodStart;
    if (start == null) return null;
    return daysBetween(start, today);
  }

  /// True once today is past the expected next-period day. Always
  /// false while no period start is recorded -- lateness is undefined
  /// without an anchor date.
  bool get isLate => daysLate > 0;

  /// Days past the expected next period start: 0 before it and on the
  /// due day itself, then the number of days overdue. 0 while no
  /// period start is recorded.
  int get daysLate => daysLateOn(DateTime.now());

  int daysLateOn(DateTime today) {
    final since = daysSinceLastPeriodStartOn(today);
    if (since == null) return 0;
    return since > cycleLength ? since - cycleLength : 0;
  }

  // Days until next period; null while no period start is recorded.
  int? daysUntilNextPeriod() {
    final day = getCurrentCycleDay();
    if (day == null) return null;
    return cycleLength - day + 1;
  }

  // Convert to JSON for saving with shared_preferences. The
  // lastPeriodStart key is always written (null included) so readers
  // can tell "not set" apart from an absent key (task 3.2).
  Map<String, dynamic> toJson() => {
    'lastPeriodStart': lastPeriodStart?.toIso8601String(),
    'cycleLength': cycleLength,
    'periodDuration': periodDuration,
  };

  // Create from saved JSON. A missing or null lastPeriodStart means
  // "not set yet" (task 3.2) -- old saves always wrote the key, so
  // existing data reads back unchanged.
  factory CycleData.fromJson(Map<String, dynamic> json) {
    return CycleData(
      lastPeriodStart: json['lastPeriodStart'] == null
          ? null
          : DateTime.parse(json['lastPeriodStart'] as String),
      cycleLength: json['cycleLength'] ?? 28,
      periodDuration: json['periodDuration'] ?? 5,
    );
  }
}
