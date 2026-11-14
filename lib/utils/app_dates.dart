/// Date helpers for cycle math (task 3.4).
///
/// All cycle-day arithmetic previously used raw
/// `DateTime.difference().inDays`, which is time-of-day sensitive: a
/// period logged at 11pm made "days since" jump a day early. These
/// helpers compare whole calendar days instead, so every consumer
/// (CycleData, calendar predictions, home cards) agrees on what
/// "one day later" means.
library;

/// [d] with the time-of-day stripped (midnight of that calendar day).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [from] to [to] (positive when [to] is
/// later). The y/m/d components are re-anchored in UTC before
/// differencing: DST transitions can make a local midnight-to-midnight
/// gap 23 or 25 real hours, which Duration.inDays truncates to the
/// wrong day count (measured on a Pacific-time machine: Mar 1 -> Mar
/// 10 2026 is 8 days locally but 9 calendar days). Anchoring in UTC is
/// transition-proof.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
