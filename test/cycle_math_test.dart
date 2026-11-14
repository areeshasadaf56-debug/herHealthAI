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

  group('ovulation day + phase boundaries (task 3.1)', () {
    final data = CycleData(
      lastPeriodStart: DateTime(2026, 10, 18),
      cycleLength: 28,
    );

    test('ovulationDay is mid-cycle, floored', () {
      expect(data.ovulationDay, 14);
      expect(
        CycleData(
          lastPeriodStart: DateTime(2026, 1, 1),
          cycleLength: 21,
        ).ovulationDay,
        10,
      );
      expect(
        CycleData(
          lastPeriodStart: DateTime(2026, 1, 1),
          cycleLength: 35,
        ).ovulationDay,
        17,
      );
    });

    test('phase boundaries for a 28-day cycle (5-day period)', () {
      // Menstrual 1-5, Follicular 6-13, Ovulation 14-15, Luteal 16-28.
      expect(data.getPhaseOn(1), 'Menstrual');
      expect(data.getPhaseOn(5), 'Menstrual');
      expect(data.getPhaseOn(6), 'Follicular');
      expect(data.getPhaseOn(13), 'Follicular');
      expect(data.getPhaseOn(14), 'Ovulation');
      expect(data.getPhaseOn(15), 'Ovulation');
      expect(data.getPhaseOn(16), 'Luteal');
      expect(data.getPhaseOn(28), 'Luteal');
    });

    test('Ovulation phase == the days the ovulation screen highlights', () {
      // Consolidation pin (task 3.1): getPhase used to place Ovulation
      // at days 15-16 while the ovulation screen marked 14-15 -- two
      // different answers from two copies of the same formula.
      expect(data.getPhaseOn(data.ovulationDay), 'Ovulation');
      expect(data.getPhaseOn(data.ovulationDay + 1), 'Ovulation');
      expect(data.getPhaseOn(data.ovulationDay + 2), 'Luteal');
    });

    test('daysUntilOvulationOn counts down to ovulation, then wraps', () {
      // Oct 18 start -> day 1. Ovulation day 14 falls on Oct 31.
      expect(data.daysUntilOvulationOn(DateTime(2026, 10, 18)), 13);
      expect(data.daysUntilOvulationOn(DateTime(2026, 10, 31)), 0);
      // Oct 31 -> Nov 1 crosses the US fall-back; UTC-anchored math
      // keeps the day count exact.
      expect(data.daysUntilOvulationOn(DateTime(2026, 11, 1)), 27);
      expect(data.daysUntilOvulationOn(DateTime(2026, 11, 2)), 26);
    });
  });

  group('late-period math (task 3.3)', () {
    final data = CycleData(
      lastPeriodStart: DateTime(2026, 10, 18),
      cycleLength: 28,
    );

    test('daysSinceLastPeriodStartOn counts unwrapped days', () {
      expect(data.daysSinceLastPeriodStartOn(DateTime(2026, 11, 14)), 27);
      // Well past the cycle length -- that is the point: the cycle-day
      // math wraps, this does not.
      expect(data.daysSinceLastPeriodStartOn(DateTime(2026, 11, 26)), 39);
    });

    test('daysLateOn is 0 before and on the due day, then counts up', () {
      // Due day = 28 days after the start = Nov 15.
      expect(data.daysLateOn(DateTime(2026, 11, 14)), 0);
      expect(data.daysLateOn(DateTime(2026, 11, 15)), 0);
      expect(data.daysLateOn(DateTime(2026, 11, 16)), 1);
      expect(data.daysLateOn(DateTime(2026, 11, 26)), 11);
    });
  });
}
