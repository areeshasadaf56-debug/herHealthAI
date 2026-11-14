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

  // Rough phase name based on current cycle day
  String getPhase() {
    final day = getCurrentCycleDay();
    if (day <= periodDuration) return "Menstrual";
    if (day <= (cycleLength / 2).floor()) return "Follicular";
    if (day <= (cycleLength / 2).floor() + 2) return "Ovulation";
    return "Luteal";
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
