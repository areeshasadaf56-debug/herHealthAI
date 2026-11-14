import '../utils/app_dates.dart';

class CycleData {
  DateTime lastPeriodStart;
  int cycleLength; // average days between periods
  int periodDuration; // how many days the period lasts

  CycleData({
    required this.lastPeriodStart,
    this.cycleLength = 28,
    this.periodDuration = 5,
  });

  // Which day of the cycle is it today (1-based)
  int getCurrentCycleDay() => getCurrentCycleDayOn(DateTime.now());

  /// The same computation against an arbitrary date: the testable seam
  /// for the cycle math (task 3.4) and the building block for the
  /// phase/ovulation getters that consolidate the duplicated copies
  /// across screens (task 3.1).
  int getCurrentCycleDayOn(DateTime today) {
    final daysSince = daysBetween(lastPeriodStart, today);
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

  // Rough phase name based on current cycle day
  String getPhase() => getPhaseOn(getCurrentCycleDay());

  /// Days until the next ovulation (0 = today is the ovulation day).
  /// Wraps once ovulation has passed. The parameterized variant is the
  /// testable seam, same pattern as getCurrentCycleDayOn.
  int get daysUntilOvulation => daysUntilOvulationOn(DateTime.now());

  int daysUntilOvulationOn(DateTime today) {
    final diff = ovulationDay - getCurrentCycleDayOn(today);
    return diff >= 0 ? diff : cycleLength + diff;
  }

  /// Whole days since the recorded period start (0 = started today).
  /// NOT wrapped by the cycle length -- values beyond [cycleLength]
  /// are exactly how a late period is measured (task 3.3), while the
  /// cycle-day math above keeps wrapping.
  int get daysSinceLastPeriodStart =>
      daysSinceLastPeriodStartOn(DateTime.now());

  int daysSinceLastPeriodStartOn(DateTime today) =>
      daysBetween(lastPeriodStart, today);

  /// True once today is past the expected next-period day.
  bool get isLate => daysLate > 0;

  /// Days past the expected next period start: 0 before it and on the
  /// due day itself, then the number of days overdue.
  int get daysLate => daysLateOn(DateTime.now());

  int daysLateOn(DateTime today) {
    final since = daysSinceLastPeriodStartOn(today);
    return since > cycleLength ? since - cycleLength : 0;
  }

  // Days until next period
  int daysUntilNextPeriod() {
    final day = getCurrentCycleDay();
    return cycleLength - day + 1;
  }

  // Convert to JSON for saving with shared_preferences
  Map<String, dynamic> toJson() => {
    'lastPeriodStart': lastPeriodStart.toIso8601String(),
    'cycleLength': cycleLength,
    'periodDuration': periodDuration,
  };

  // Create from saved JSON
  factory CycleData.fromJson(Map<String, dynamic> json) {
    return CycleData(
      lastPeriodStart: DateTime.parse(json['lastPeriodStart']),
      cycleLength: json['cycleLength'] ?? 28,
      periodDuration: json['periodDuration'] ?? 5,
    );
  }
}
