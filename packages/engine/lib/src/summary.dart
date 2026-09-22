import 'package:path/path.dart' as p;

import 'activity.dart';
import 'periods.dart';
import 'tracking.dart';

/// What the rows of a breakdown are counted by.
enum Grouping {
  /// One row per project.
  project('Project'),

  /// One row per company, as the ledger files them.
  company('Company'),

  /// One row per directory worked in.
  repository('Repository'),

  /// One row per day.
  day('Day'),

  /// One row per week, Monday to Sunday.
  week('Week'),

  /// One row per calendar month.
  month('Month');

  const Grouping(this.label);

  /// Name on the control.
  final String label;
}

/// What one row of a breakdown holds.
class SummaryRow {
  /// Creates a row.
  const SummaryRow({
    required this.label,
    required this.time,
    required this.tokens,
    required this.blocks,
    required this.sessions,
    this.sortsBy,
  });

  /// What the row is called.
  final String label;

  /// Time it holds.
  final Duration time;

  /// Tokens the exchanges in it reported.
  final TokenUsage tokens;

  /// How many blocks it covers.
  final int blocks;

  /// How many sessions fed those blocks.
  final int sessions;

  /// What to order the row by when the label is not the natural order, which is
  /// what keeps days and months in calendar order rather than alphabetical.
  final Comparable<Object>? sortsBy;

  /// Tokens per hour, for comparing how heavy the work was rather than how long.
  double get tokensPerHour =>
      time.inMinutes == 0 ? 0 : tokens.total / (time.inMinutes / 60);

  /// JSON form.
  Map<String, Object?> toJson() => {
    'label': label,
    'hours': double.parse((time.inMinutes / 60).toStringAsFixed(2)),
    'tokens': tokens.toJson(),
    'blocks': blocks,
    'sessions': sessions,
  };
}

/// Groups [blocks] into rows of time and tokens.
///
/// Excluded blocks are left out, since they are the ones struck off on purpose,
/// and unmapped blocks are kept under their own name: hours going nowhere are
/// exactly what a breakdown should show.
List<SummaryRow> summarise(Iterable<TrackedBlock> blocks, Grouping by) {
  final rows = <String, _Bucket>{};
  for (final tracked in blocks) {
    if (tracked.excluded) continue;
    final (label, sort) = _keyOf(tracked, by);
    final bucket = rows.putIfAbsent(label, () => _Bucket(sort));
    bucket.time += tracked.block.duration;
    bucket.tokens += tracked.block.tokens;
    bucket.blocks++;
    bucket.sessions += tracked.block.sessions;
  }
  final result = [
    for (final entry in rows.entries)
      SummaryRow(
        label: entry.key,
        time: entry.value.time,
        tokens: entry.value.tokens,
        blocks: entry.value.blocks,
        sessions: entry.value.sessions,
        sortsBy: entry.value.sort,
      ),
  ];
  // Calendar groupings read in their own order; the rest by how much time.
  final chronological =
      by == Grouping.day || by == Grouping.week || by == Grouping.month;
  result.sort(
    chronological
        ? (a, b) => a.sortsBy!.compareTo(b.sortsBy!)
        : (a, b) => b.time.compareTo(a.time),
  );
  return result;
}

(String, Comparable<Object>?) _keyOf(TrackedBlock block, Grouping by) {
  switch (by) {
    case Grouping.project:
      return (block.project ?? unmappedLabel, null);
    case Grouping.company:
      final company = block.company;
      if (company != null) return (company, null);
      return (block.project == null ? unmappedLabel : 'No company', null);
    case Grouping.repository:
      return (p.basename(block.block.directory), null);
    case Grouping.day:
      final day = block.day;
      return ('${_weekday(day)} ${day.day} ${_month(day)}', day);
    case Grouping.week:
      final monday = block.day.subtract(
        Duration(days: block.day.weekday - 1),
      );
      return ('Week of ${monday.day} ${_month(monday)}', monday);
    case Grouping.month:
      final month = DateTime(block.day.year, block.day.month);
      return ('${_month(month)} ${month.year}', month);
  }
}

class _Bucket {
  _Bucket(this.sort);

  final Comparable<Object>? sort;
  Duration time = Duration.zero;
  TokenUsage tokens = TokenUsage.zero;
  int blocks = 0;
  int sessions = 0;
}

String _weekday(DateTime at) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];

String _month(DateTime at) => const [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][at.month - 1];
