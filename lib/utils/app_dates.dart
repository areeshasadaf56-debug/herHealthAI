/// Date helpers for cycle math (task 3.4) and date display formatting
/// (task 6.2).
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

// ---------------------------------------------------------------------------
// Display formatting (task 6.2).
//
// Ten screens used to each declare their own copy of the month/weekday
// name arrays (12+ copies, some full names, some short). The constants
// and helpers below are the single source; every output string is
// byte-identical to what the replaced local copies produced, and they
// are English-only by design (content localization is chat-only, SRS
// FR-48).
// ---------------------------------------------------------------------------

/// Short English month names; index with `[d.month - 1]`.
const List<String> kShortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Full English month names; index with `[d.month - 1]`.
const List<String> kFullMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Short English weekday names (Mon..Sun); index with `[d.weekday - 1]`.
const List<String> kShortWeekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Full English weekday names (Monday..Sunday); index with
/// `[d.weekday - 1]`.
const List<String> kFullWeekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// `'Mon, Jan 5'` — the tab-header date stamp (was duplicated in 5+ screens).
String formatShortDateStamp(DateTime d) =>
    '${kShortWeekdays[d.weekday - 1]}, ${kShortMonths[d.month - 1]} ${d.day}';

/// `'Mon, January 5'` — the Protection tab's full-month variant.
String formatFullMonthDateStamp(DateTime d) =>
    '${kShortWeekdays[d.weekday - 1]}, ${kFullMonths[d.month - 1]} ${d.day}';

/// `'Jan 5'` — compact month-day labels (status cards, ovulation date).
String formatMonthDay(DateTime d) => '${kShortMonths[d.month - 1]} ${d.day}';

/// `'Jan 5, 2026'` — dated list headers/timestamps.
String formatShortDate(DateTime d) =>
    '${kShortMonths[d.month - 1]} ${d.day}, ${d.year}';

/// `'Monday, Jan 5, 2026'` — diary day headers.
String formatFullWeekdayDate(DateTime d) =>
    '${kFullWeekdays[d.weekday - 1]}, ${formatShortDate(d)}';

/// `'Jan 5, 2026 · 3:07 PM'` — timestamped timeline entries. The
/// 12-hour rendering (including the midnight/noon `% 12 == 0 -> 12`
/// rule) matches the formatter this replaces in the Health Diary.
String formatShortDateTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '${formatShortDate(d)} · $hour:${d.minute.toString().padLeft(2, '0')} $ampm';
}
