import 'package:flutter_test/flutter_test.dart';

import 'package:wellness_saheli/models/cycle_data.dart';
import 'package:wellness_saheli/utils/app_dates.dart';

/// Task 3.4 -- shared date helpers. The point of the whole task is that
/// cycle-day arithmetic stops being time-of-day sensitive and stops
/// being duplicated, so these tests pin both.
void main() {
  group('dateOnly', () {
    test('strips the time of day', () {
      final d = DateTime(2026, 3, 15, 23, 59, 59);
      expect(dateOnly(d), DateTime(2026, 3, 15));
    });

    test('keeps the calendar day even across DST-ish edge hours', () {
      // 00:00 stays the same day; 23:59 stays the same day.
      expect(dateOnly(DateTime(2026, 1, 1)), DateTime(2026, 1, 1));
      expect(dateOnly(DateTime(2026, 1, 1, 23, 59)), DateTime(2026, 1, 1));
    });
  });

  group('daysBetween', () {
    test('counts whole calendar days, ignoring time of day', () {
      final from = DateTime(2026, 3, 1, 22, 0);
      final to = DateTime(2026, 3, 2, 5, 0);
      // Raw difference().inDays would say 0 (only 7h apart); calendar
      // days say 1.
      expect(daysBetween(from, to), 1);
    });

    test('is negative backwards', () {
      expect(daysBetween(DateTime(2026, 3, 10), DateTime(2026, 3, 1)), -9);
    });

    test('same instant is 0', () {
      final d = DateTime(2026, 5, 5, 13, 30);
      expect(daysBetween(d, d), 0);
      // Same day, different time is still 0.
      expect(daysBetween(d, DateTime(2026, 5, 5, 20, 0)), 0);
    });
  });

  group('CycleData cycle-day math (midnight-anchored)', () {
    test('getCurrentCycleDayOn is 1-based and wraps', () {
      // Oct 18 -> Nov 14 = 27 days -> day 28 in a 28-day cycle.
      final data = CycleData(
        lastPeriodStart: DateTime(2026, 10, 18),
        cycleLength: 28,
      );
      expect(data.getCurrentCycleDayOn(DateTime(2026, 11, 14)), 28);
      // The next day wraps back to day 1 of a fresh cycle.
      expect(data.getCurrentCycleDayOn(DateTime(2026, 11, 15)), 1);
    });

    test('survives a DST spring-forward (US, March 2026)', () {
      // Midnight-to-midnight across the Mar 8 transition is 23 real
      // hours; local difference().inDays would call it 8 days. The
      // UTC-anchored helper must still say 9 -> cycle day 10.
      final data = CycleData(
        lastPeriodStart: DateTime(2026, 3, 1),
        cycleLength: 28,
      );
      expect(data.getCurrentCycleDayOn(DateTime(2026, 3, 10)), 10);
    });

    test('time of day of the period start never shifts the count', () {
      // Logged at 23:00 today -> still day 1 today (raw difference()
      // running late at night computed day 0 / wrapped wrong).
      final today = DateTime.now();
      final data = CycleData(
        lastPeriodStart: DateTime(today.year, today.month, today.day, 23, 0),
        cycleLength: 28,
      );
      expect(data.getCurrentCycleDay(), 1);
    });

    test('getCurrentCycleDay() delegates to the fixed-date variant', () {
      final data = CycleData(
        lastPeriodStart: DateTime(2026, 10, 18),
        cycleLength: 28,
      );
      expect(
        data.getCurrentCycleDay(),
        data.getCurrentCycleDayOn(DateTime.now()),
      );
    });

    test('daysUntilNextPeriod stays within 1..cycleLength', () {
      // day is always 1..cycleLength, so the complement is too.
      final data = CycleData(
        lastPeriodStart: DateTime(2026, 10, 18),
        cycleLength: 28,
      );
      expect(data.daysUntilNextPeriod(), inInclusiveRange(1, 28));
    });
  });
}
