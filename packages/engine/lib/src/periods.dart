import 'tracking.dart';

/// A named window over the calendar.
class Period {
  /// Creates a period covering `[start, end)`.
  const Period({required this.label, required this.start, required this.end});

  /// What to call it on screen.
  final String label;

  /// First moment, local midnight.
  final DateTime start;

  /// First moment after the period, local midnight.
  final DateTime end;

  /// Whole days covered.
  int get days => end.difference(start).inDays;

  /// Whether [time] falls inside.
  bool contains(DateTime time) => !time.isBefore(start) && time.isBefore(end);
}

/// The ranges the graphs offer, in the order they are listed.
enum PeriodKind {
  /// Since midnight.
  today('Today'),

  /// The day before.
  yesterday('Yesterday'),

  /// Monday to now.
  thisWeek('This week'),

  /// The Monday before last Sunday.
  lastWeek('Last week'),

  /// Since the first of the month.
  thisMonth('This month'),

  /// The month before.
  lastMonth('Last month'),

  /// This month and the one before.
  lastTwoMonths('Last 2 months'),

  /// Since the quarter began.
  thisQuarter('This quarter'),

  /// The quarter before.
  lastQuarter('Last quarter'),

  /// Since January or July.
  thisSemester('This semester'),

  /// Since January.
  thisYear('This year'),

  /// Whatever two dates were picked.
  custom('Custom');

  const PeriodKind(this.label);

  /// Name shown on the chip.
  final String label;
}

/// The window [kind] covers, relative to [now].
///
/// Weeks run Monday to Sunday. A period ends at the midnight after the day it
/// covers, so today is a full day rather than a stub: a chart of "this week"
/// should show the week, not stop mid-afternoon.
Period periodFor(
  PeriodKind kind, {
  DateTime? now,
  DateTime? start,
  DateTime? end,
}) {
  final today = _midnight(now ?? DateTime.now());
  final tomorrow = today.add(const Duration(days: 1));
  final monday = today.subtract(Duration(days: today.weekday - 1));

  return switch (kind) {
    PeriodKind.today => Period(label: kind.label, start: today, end: tomorrow),
    PeriodKind.yesterday => Period(
      label: kind.label,
      start: today.subtract(const Duration(days: 1)),
      end: today,
    ),
    PeriodKind.thisWeek => Period(
      label: kind.label,
      start: monday,
      end: monday.add(const Duration(days: 7)),
    ),
    PeriodKind.lastWeek => Period(
      label: kind.label,
      start: monday.subtract(const Duration(days: 7)),
      end: monday,
    ),
    PeriodKind.thisMonth => Period(
      label: kind.label,
      start: DateTime(today.year, today.month),
      end: DateTime(today.year, today.month + 1),
    ),
    PeriodKind.lastMonth => Period(
      label: kind.label,
      start: DateTime(today.year, today.month - 1),
      end: DateTime(today.year, today.month),
    ),
    PeriodKind.lastTwoMonths => Period(
      label: kind.label,
      start: DateTime(today.year, today.month - 1),
      end: DateTime(today.year, today.month + 1),
    ),
    PeriodKind.thisQuarter => Period(
      label: kind.label,
      start: DateTime(today.year, _quarterMonth(today.month)),
      end: DateTime(today.year, _quarterMonth(today.month) + 3),
    ),
    PeriodKind.lastQuarter => Period(
      label: kind.label,
      start: DateTime(today.year, _quarterMonth(today.month) - 3),
      end: DateTime(today.year, _quarterMonth(today.month)),
    ),
    PeriodKind.thisSemester => Period(
      label: kind.label,
      start: DateTime(today.year, today.month <= 6 ? 1 : 7),
      end: DateTime(today.year, today.month <= 6 ? 7 : 13),
    ),
    PeriodKind.thisYear => Period(
      label: kind.label,
      start: DateTime(today.year),
      end: DateTime(today.year + 1),
    ),
    PeriodKind.custom => Period(
      label: kind.label,
      start: _midnight(start ?? today),
      end: _midnight(end ?? today).add(const Duration(days: 1)),
    ),
  };
}

/// The same window moved [steps] of its own length, forward or back.
///
/// Stepping moves by the unit the window is made of, so a month window lands on
/// whole months and a week window on whole weeks. The label follows the range
/// rather than the name it started with: a month back from "this month" is
/// September, not "this month" again.
Period shiftPeriod(PeriodKind kind, Period period, int steps) {
  if (steps == 0) return period;
  final months = switch (kind) {
    PeriodKind.thisMonth || PeriodKind.lastMonth => 1,
    PeriodKind.lastTwoMonths => 2,
    PeriodKind.thisQuarter || PeriodKind.lastQuarter => 3,
    PeriodKind.thisSemester => 6,
    PeriodKind.thisYear => 12,
    _ => 0,
  };
  final Period shifted;
  if (months > 0) {
    shifted = Period(
      label: '',
      start: DateTime(
        period.start.year,
        period.start.month + months * steps,
        period.start.day,
      ),
      end: DateTime(
        period.end.year,
        period.end.month + months * steps,
        period.end.day,
      ),
    );
  } else {
    final days = Duration(days: period.days * steps);
    shifted = Period(
      label: '',
      start: period.start.add(days),
      end: period.end.add(days),
    );
  }
  return Period(
    label: describePeriod(shifted),
    start: shifted.start,
    end: shifted.end,
  );
}

/// What a range is called once it is no longer the named one: a single day by
/// its date, a whole month or year by its name, anything else by its ends.
String describePeriod(Period period) {
  final last = period.end.subtract(const Duration(days: 1));
  if (period.days == 1) {
    return '${_weekday(period.start)} ${period.start.day} '
        '${_month(period.start)} ${period.start.year}';
  }
  if (period.start == DateTime(period.start.year, period.start.month) &&
      period.end == DateTime(period.start.year, period.start.month + 1)) {
    return '${_monthInFull(period.start)} ${period.start.year}';
  }
  if (period.start == DateTime(period.start.year) &&
      period.end == DateTime(period.start.year + 1)) {
    return '${period.start.year}';
  }
  return '${period.start.day} ${_month(period.start)} to '
      '${last.day} ${_month(last)}'
      '${last.year == period.start.year ? '' : ' ${last.year}'}';
}

String _weekday(DateTime at) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];

String _month(DateTime at) => const [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][at.month - 1];

/// A month on its own is read out in full; a month at the end of a range is
/// read short, where it sits beside a day number.
String _monthInFull(DateTime at) => const [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
][at.month - 1];

/// How wide one bar is.
enum Bucket {
  /// One bar per day.
  day,

  /// One bar per week, Monday to Sunday.
  week,

  /// One bar per calendar month.
  month,
}

/// The bar width that keeps a period readable: days up to a fortnight, weeks up
/// to about four months, months beyond that.
Bucket bucketFor(Period period) {
  if (period.days <= 16) return Bucket.day;
  if (period.days <= 120) return Bucket.week;
  return Bucket.month;
}

/// How much of a measure a block is worth.
typedef BlockAmount = double Function(TrackedBlock block);

/// A block as seconds of work.
double secondsWorked(TrackedBlock block) =>
    block.block.duration.inSeconds.toDouble();

/// A block as tokens, everything that passed through it, cache included.
double tokensUsed(TrackedBlock block) => block.block.tokens.total.toDouble();

/// How much of [amount] per bucket per project, oldest bucket first.
///
/// Every bucket in the period is present even when nothing was worked, so a
/// chart shows the gaps instead of closing them up.
Map<DateTime, Map<String, double>> bucketAmounts(
  Iterable<TrackedBlock> blocks,
  Period period,
  BlockAmount amount, {
  Bucket? bucket,
}) {
  final width = bucket ?? bucketFor(period);
  final totals = <DateTime, Map<String, double>>{};
  for (var at = _bucketStart(period.start, width);
      at.isBefore(period.end);
      at = _nextBucket(at, width)) {
    totals[at] = <String, double>{};
  }
  for (final block in blocks) {
    if (!period.contains(block.block.start)) continue;
    final at = _bucketStart(block.block.start, width);
    final row = totals.putIfAbsent(at, () => <String, double>{});
    final name = block.project ?? unmappedLabel;
    row[name] = (row[name] ?? 0) + amount(block);
  }
  return totals;
}

/// How much of [amount] per day per project, for the calendar.
Map<DateTime, Map<String, double>> dailyAmounts(
  Iterable<TrackedBlock> blocks,
  BlockAmount amount,
) {
  final totals = <DateTime, Map<String, double>>{};
  for (final block in blocks) {
    final row = totals.putIfAbsent(block.day, () => <String, double>{});
    final name = block.project ?? unmappedLabel;
    row[name] = (row[name] ?? 0) + amount(block);
  }
  return totals;
}

/// Everything in a row added up.
double rowTotal(Map<String, double> row) =>
    row.values.fold(0, (sum, value) => sum + value);

/// Time per day per project, which is what a timesheet is written from.
Map<DateTime, Map<String, Duration>> dailyTotals(
  Iterable<TrackedBlock> blocks,
) => {
  for (final day in dailyAmounts(blocks, secondsWorked).entries)
    day.key: {
      for (final project in day.value.entries)
        project.key: Duration(seconds: project.value.round()),
    },
};

/// What a block with no project is called in a chart.
const String unmappedLabel = 'Unmapped';

/// The project with the most time in [row], null when it is empty.
String? dominantProject(Map<String, double> row) {
  String? best;
  var most = 0.0;
  for (final entry in row.entries) {
    if (entry.value <= most) continue;
    most = entry.value;
    best = entry.key;
  }
  return best;
}

/// Total of one bucket.
Duration bucketTotal(Map<String, Duration> row) =>
    row.values.fold(Duration.zero, (sum, d) => sum + d);

DateTime _midnight(DateTime time) =>
    DateTime(time.year, time.month, time.day);

int _quarterMonth(int month) => month - ((month - 1) % 3);

DateTime _bucketStart(DateTime time, Bucket bucket) => switch (bucket) {
  Bucket.day => _midnight(time),
  Bucket.week => _midnight(time).subtract(Duration(days: time.weekday - 1)),
  Bucket.month => DateTime(time.year, time.month),
};

DateTime _nextBucket(DateTime at, Bucket bucket) => switch (bucket) {
  Bucket.day => at.add(const Duration(days: 1)),
  Bucket.week => at.add(const Duration(days: 7)),
  Bucket.month => DateTime(at.year, at.month + 1),
};
