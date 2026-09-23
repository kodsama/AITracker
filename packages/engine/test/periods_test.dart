import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

TrackedBlock block(
  String day, {
  String? project,
  int hours = 1,
  int tokens = 0,
}) => TrackedBlock(
  block: WorkBlock(
    directory: '/repo',
    start: DateTime.parse('${day}T09:00:00'),
    end: DateTime.parse('${day}T09:00:00').add(Duration(hours: hours)),
    tokens: TokenUsage(input: tokens),
  ),
  project: project,
  description: 'AI: repo',
);

void main() {
  // A test run has no business writing to the user's log.
  Log.enabled = false;

  // A Wednesday, in the third quarter, second semester.
  final now = DateTime(2026, 9, 16, 14, 30);

  group('periodFor', () {
    Period at(PeriodKind kind) => periodFor(kind, now: now);

    test('a day runs midnight to midnight', () {
      expect(at(PeriodKind.today).start, DateTime(2026, 9, 16));
      expect(at(PeriodKind.today).end, DateTime(2026, 9, 17));
      expect(at(PeriodKind.yesterday).start, DateTime(2026, 9, 15));
      expect(at(PeriodKind.yesterday).end, DateTime(2026, 9, 16));
    });

    test('weeks run Monday to Sunday', () {
      expect(at(PeriodKind.thisWeek).start, DateTime(2026, 9, 14));
      expect(at(PeriodKind.thisWeek).end, DateTime(2026, 9, 21));
      expect(at(PeriodKind.lastWeek).start, DateTime(2026, 9, 7));
      expect(at(PeriodKind.lastWeek).end, DateTime(2026, 9, 14));
    });

    test('months, and the pair of them', () {
      expect(at(PeriodKind.thisMonth).start, DateTime(2026, 9));
      expect(at(PeriodKind.lastMonth).start, DateTime(2026, 8));
      expect(at(PeriodKind.lastMonth).end, DateTime(2026, 9));
      expect(at(PeriodKind.lastTwoMonths).start, DateTime(2026, 8));
      expect(at(PeriodKind.lastTwoMonths).end, DateTime(2026, 10));
    });

    test('quarters snap to January, April, July, October', () {
      expect(at(PeriodKind.thisQuarter).start, DateTime(2026, 7));
      expect(at(PeriodKind.thisQuarter).end, DateTime(2026, 10));
      expect(at(PeriodKind.lastQuarter).start, DateTime(2026, 4));
      expect(at(PeriodKind.lastQuarter).end, DateTime(2026, 7));

      final january = periodFor(PeriodKind.thisQuarter, now: DateTime(2026, 2, 3));
      expect(january.start, DateTime(2026));
      expect(january.end, DateTime(2026, 4));
    });

    test('semesters split the year in half, and the year is the year', () {
      expect(at(PeriodKind.thisSemester).start, DateTime(2026, 7));
      expect(at(PeriodKind.thisSemester).end, DateTime(2027));
      expect(
        periodFor(PeriodKind.thisSemester, now: DateTime(2026, 3, 1)).end,
        DateTime(2026, 7),
      );
      expect(at(PeriodKind.thisYear).start, DateTime(2026));
      expect(at(PeriodKind.thisYear).end, DateTime(2027));
    });

    test('a custom range covers both end days in full', () {
      final period = periodFor(
        PeriodKind.custom,
        now: now,
        start: DateTime(2026, 9, 1, 13),
        end: DateTime(2026, 9, 3, 8),
      );

      expect(period.start, DateTime(2026, 9));
      expect(period.end, DateTime(2026, 9, 4));
      expect(period.days, 3);
      expect(period.contains(DateTime(2026, 9, 3, 23)), isTrue);
      expect(period.contains(DateTime(2026, 9, 4)), isFalse);
    });
  });

  group('shiftPeriod', () {
    test('a month window lands on whole months', () {
      final back = shiftPeriod(
        PeriodKind.thisMonth,
        periodFor(PeriodKind.thisMonth, now: now),
        -1,
      );

      expect(back.start, DateTime(2026, 8));
      expect(back.end, DateTime(2026, 9));
      expect(back.label, 'August 2026');
    });

    test('a week window moves seven days at a time', () {
      final back = shiftPeriod(
        PeriodKind.thisWeek,
        periodFor(PeriodKind.thisWeek, now: now),
        -2,
      );

      expect(back.start, DateTime(2026, 8, 31));
      expect(back.end, DateTime(2026, 9, 7));
      expect(back.label, '31 Aug to 6 Sep');
    });

    test('a day window keeps its name as a date', () {
      final forward = shiftPeriod(
        PeriodKind.today,
        periodFor(PeriodKind.today, now: now),
        1,
      );

      expect(forward.start, DateTime(2026, 9, 17));
      expect(forward.label, 'Thu 17 Sep 2026');
    });

    test('quarters, semesters and years move by their own length', () {
      expect(
        shiftPeriod(
          PeriodKind.thisQuarter,
          periodFor(PeriodKind.thisQuarter, now: now),
          -1,
        ).start,
        DateTime(2026, 4),
      );
      expect(
        shiftPeriod(
          PeriodKind.thisSemester,
          periodFor(PeriodKind.thisSemester, now: now),
          -1,
        ).start,
        DateTime(2026),
      );
      final lastYear = shiftPeriod(
        PeriodKind.thisYear,
        periodFor(PeriodKind.thisYear, now: now),
        -1,
      );
      expect(lastYear.start, DateTime(2025));
      expect(lastYear.label, '2025');
    });

    test('a custom range moves by the days it covers', () {
      final custom = periodFor(
        PeriodKind.custom,
        now: now,
        start: DateTime(2026, 9, 10),
        end: DateTime(2026, 9, 12),
      );

      final back = shiftPeriod(PeriodKind.custom, custom, -1);

      expect(back.start, DateTime(2026, 9, 7));
      expect(back.end, DateTime(2026, 9, 10));
    });

    test('no step is the window it was given', () {
      final window = periodFor(PeriodKind.thisMonth, now: now);
      expect(shiftPeriod(PeriodKind.thisMonth, window, 0), same(window));
    });
  });

  group('bucketFor', () {
    Period span(int days) => Period(
      label: 'x',
      start: DateTime(2026, 9),
      end: DateTime(2026, 9).add(Duration(days: days)),
    );

    test('widens the bar as the window grows', () {
      expect(bucketFor(span(1)), Bucket.day);
      expect(bucketFor(span(16)), Bucket.day);
      expect(bucketFor(span(17)), Bucket.week);
      expect(bucketFor(span(120)), Bucket.week);
      expect(bucketFor(span(121)), Bucket.month);
    });
  });

  group('bucketAmounts', () {
    const hour = 3600.0;

    test('keeps an empty bucket so a gap stays visible', () {
      final period = periodFor(PeriodKind.thisWeek, now: now);
      final totals = bucketAmounts(
        [block('2026-09-14', project: 'A - a')],
        period,
        secondsWorked,
      );

      expect(totals, hasLength(7));
      expect(totals[DateTime(2026, 9, 14)], {'A - a': hour});
      expect(totals[DateTime(2026, 9, 15)], isEmpty);
    });

    test('stacks the projects inside one bucket', () {
      final period = periodFor(PeriodKind.thisWeek, now: now);
      final totals = bucketAmounts([
        block('2026-09-14', project: 'A - a'),
        block('2026-09-14', project: 'B - b', hours: 2),
        block('2026-09-14'),
      ], period, secondsWorked);

      expect(totals[DateTime(2026, 9, 14)], {
        'A - a': hour,
        'B - b': 2 * hour,
        unmappedLabel: hour,
      });
    });

    test('measures tokens as readily as time', () {
      final period = periodFor(PeriodKind.thisWeek, now: now);
      final totals = bucketAmounts([
        block('2026-09-14', project: 'A - a', tokens: 500),
        block('2026-09-14', project: 'A - a', tokens: 250),
      ], period, tokensUsed);

      expect(totals[DateTime(2026, 9, 14)], {'A - a': 750.0});
      expect(rowTotal(totals[DateTime(2026, 9, 14)]!), 750);
      expect(rowTotal(const {}), 0);
    });

    test('groups by week and by month for longer windows', () {
      final quarter = periodFor(PeriodKind.thisQuarter, now: now);
      final weeks = bucketAmounts([
        block('2026-09-14', project: 'A - a'),
        block('2026-09-16', project: 'A - a'),
      ], quarter, secondsWorked);
      expect(weeks[DateTime(2026, 9, 14)], {'A - a': 2 * hour});

      final year = periodFor(PeriodKind.thisYear, now: now);
      final months = bucketAmounts([
        block('2026-09-14', project: 'A - a'),
        block('2026-09-30', project: 'A - a'),
      ], year, secondsWorked);
      expect(months, hasLength(12));
      expect(months[DateTime(2026, 9)], {'A - a': 2 * hour});
    });

    test('leaves out what falls outside the window', () {
      final period = periodFor(PeriodKind.today, now: now);
      final totals = bucketAmounts(
        [block('2026-09-15', project: 'A - a')],
        period,
        secondsWorked,
      );

      expect(rowTotal(totals.values.single), 0);
    });
  });

  group('calendar', () {
    test('totals a day and names the project that owned it', () {
      final blocks = [
        block('2026-09-14', project: 'A - a'),
        block('2026-09-14', project: 'B - b', hours: 3),
      ];

      // What the timesheet is written from, in hours.
      expect(
        bucketTotal(dailyTotals(blocks)[DateTime(2026, 9, 14)]!),
        const Duration(hours: 4),
      );
      // And what the calendar shades by, in whatever it is measuring.
      final amounts = dailyAmounts(blocks, secondsWorked);
      expect(dominantProject(amounts[DateTime(2026, 9, 14)]!), 'B - b');
      expect(dominantProject(const {}), isNull);
    });

    test('the same days measured in tokens', () {
      final totals = dailyAmounts([
        block('2026-09-14', project: 'A - a', tokens: 900),
        block('2026-09-15', project: 'A - a', tokens: 100),
      ], tokensUsed);

      expect(totals[DateTime(2026, 9, 14)], {'A - a': 900.0});
      expect(totals[DateTime(2026, 9, 15)], {'A - a': 100.0});
    });
  });
}
