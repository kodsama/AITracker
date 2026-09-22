import 'dart:math' as math;

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

/// A calendar of the period, a month to a block, each day painted in the colour
/// of the project that took most of it and shaded by how much of it there was.
///
/// Colour carries identity and shade carries magnitude, so the legend and the
/// line under the grid both name the project: a cell is never the only thing
/// saying which project it was.
class CalendarHeatmap extends StatefulWidget {
  /// Creates the calendar.
  const CalendarHeatmap({
    required this.days,
    required this.period,
    required this.colorOf,
    this.onDayTapped,
    super.key,
  });

  /// Day to project to time.
  final Map<DateTime, Map<String, Duration>> days;

  /// Window to draw. Whole months are shown, with the days outside the window
  /// dimmed, so a week in the middle of a month still reads as a week.
  final Period period;

  /// Colour for a project.
  final Color Function(String project) colorOf;

  /// Called when a day is clicked, which opens it.
  final ValueChanged<DateTime>? onDayTapped;

  /// Space between day cells.
  static const double gap = 4;

  /// Width kept for the weekday column inside a month block.
  static const double labelWidth = 34;

  /// Below this a day cell is unreadable, so fewer months go across instead.
  static const double minCell = 19;

  /// Above this a cell stops looking like a calendar and starts looking like a
  /// wall.
  static const double maxCell = 46;

  /// The size a day wants to be. The number of months across the card is
  /// worked out from this, then the cells grow to use what is left over.
  static const double idealCell = 30;

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

class _CalendarHeatmapState extends State<CalendarHeatmap> {
  DateTime? _hovered;

  /// Every month the period touches.
  List<DateTime> get _months {
    final months = <DateTime>[];
    var at = DateTime(widget.period.start.year, widget.period.start.month);
    final last = DateTime(widget.period.end.year, widget.period.end.month);
    while (!at.isAfter(last)) {
      // A period ending exactly at midnight on the first does not reach into
      // that month.
      if (at == last && widget.period.end == last) break;
      months.add(at);
      at = DateTime(at.year, at.month + 1);
    }
    if (months.isEmpty) {
      months.add(DateTime(widget.period.start.year, widget.period.start.month));
    }
    return months;
  }

  /// [months] padded with the months either side until [wanted] blocks are
  /// filled.
  ///
  /// A single week or month would otherwise sit in the corner of a wide card.
  /// The months around it cost nothing to draw, read as context, and are dimmed
  /// because they fall outside the window.
  static List<DateTime> _pad(List<DateTime> months, int wanted) {
    final padded = [...months];
    var after = true;
    while (padded.length < wanted) {
      if (after) {
        final last = padded.last;
        padded.add(DateTime(last.year, last.month + 1));
      } else {
        final first = padded.first;
        padded.insert(0, DateTime(first.year, first.month - 1));
      }
      after = !after;
    }
    return padded;
  }

  @override
  Widget build(BuildContext context) {
    final months = _months;
    final busiest = widget.days.values.fold<Duration>(
      Duration.zero,
      (most, row) => bucketTotal(row) > most ? bucketTotal(row) : most,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final (columns, cell) = _fit(constraints.maxWidth, months.length);
        final blocks = _pad(months, columns);
        final blockWidth =
            CalendarHeatmap.labelWidth + 7 * (cell + CalendarHeatmap.gap);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: math.max(
                0,
                (constraints.maxWidth - columns * blockWidth) /
                    math.max(columns - 1, 1),
              ),
              runSpacing: 20,
              children: [
                for (final month in blocks)
                  SizedBox(
                    width: blockWidth,
                    child: _Month(
                      month: month,
                      cell: cell,
                      days: widget.days,
                      period: widget.period,
                      busiest: busiest,
                      hovered: _hovered,
                      colorOf: widget.colorOf,
                      onHover: (day) => setState(() => _hovered = day),
                      onTapped: widget.onDayTapped,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _Readout(
              day: _hovered,
              row: _hovered == null
                  ? const {}
                  : widget.days[_hovered!] ?? const {},
              colorOf: widget.colorOf,
            ),
          ],
        );
      },
    );
  }

  /// How many months go across, and how big a day is, for the width on offer.
  ///
  /// The card is filled first: as many months as fit at a comfortable day size,
  /// up to four across. Then the cells grow into whatever width is left, so
  /// nothing sits in the corner of a wide window.
  static (int, double) _fit(double width, int months) {
    final ideal =
        CalendarHeatmap.labelWidth +
        7 * (CalendarHeatmap.idealCell + CalendarHeatmap.gap);
    final fits = math.max(1, (width / ideal).floor());
    // A long period keeps its own months; a short one is padded out to fill.
    final columns = months > fits
        ? _rowsFor(months, fits)
        : math.min(fits, 4);
    final cell =
        (width / columns - CalendarHeatmap.labelWidth) / 7 -
        CalendarHeatmap.gap;
    return (
      columns,
      cell.clamp(CalendarHeatmap.minCell, CalendarHeatmap.maxCell),
    );
  }

  /// With more months than fit across, spread them evenly over the rows they
  /// need, so twelve months read as three rows of four rather than two rows and
  /// a stub.
  static int _rowsFor(int months, int fits) {
    final rows = (months / fits).ceil();
    return (months / rows).ceil();
  }
}

class _Month extends StatelessWidget {
  const _Month({
    required this.month,
    required this.cell,
    required this.days,
    required this.period,
    required this.busiest,
    required this.hovered,
    required this.colorOf,
    required this.onHover,
    required this.onTapped,
  });

  final DateTime month;
  final double cell;
  final Map<DateTime, Map<String, Duration>> days;
  final Period period;
  final Duration busiest;
  final DateTime? hovered;
  final Color Function(String) colorOf;
  final ValueChanged<DateTime?> onHover;
  final ValueChanged<DateTime>? onTapped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = DateTime(month.year, month.month);
    final length = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final rows = ((leading + length) / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: CalendarHeatmap.labelWidth, bottom: 6),
          child: Text(
            '${_monthName(month)} ${month.year}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              SizedBox(
                width: CalendarHeatmap.labelWidth,
                height: cell + CalendarHeatmap.gap,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      _weekOf(first, leading, row),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              for (var column = 0; column < 7; column++)
                _cellAt(row * 7 + column - leading + 1),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(left: CalendarHeatmap.labelWidth, top: 2),
          child: Row(
            children: [
              for (final day in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                SizedBox(
                  width: cell + CalendarHeatmap.gap,
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cellAt(int dayOfMonth) {
    final length = DateTime(month.year, month.month + 1, 0).day;
    if (dayOfMonth < 1 || dayOfMonth > length) {
      return SizedBox(
        width: cell + CalendarHeatmap.gap,
        height: cell + CalendarHeatmap.gap,
      );
    }
    final day = DateTime(month.year, month.month, dayOfMonth);
    return _Cell(
      // A day appears once per calendar, and the months either side of the
      // window repeat nothing, so the date is its identity.
      key: Key('day-${_iso(day)}'),
      day: day,
      row: days[day] ?? const {},
      busiest: busiest,
      inPeriod: period.contains(day),
      hovered: hovered == day,
      size: cell,
      colorOf: colorOf,
      onHover: (over) => onHover(over ? day : null),
      onTapped: onTapped == null ? null : () => onTapped!(day),
    );
  }

  /// The week number, which is the one thing a week column loses when the grid
  /// becomes a month.
  static String _weekOf(DateTime first, int leading, int row) {
    final monday = first.subtract(Duration(days: leading - row * 7));
    final thursday = monday.add(const Duration(days: 3));
    final week =
        ((thursday.difference(DateTime(thursday.year)).inDays) / 7).floor() + 1;
    return 'w$week';
  }
}

/// `2026-09-22`.
String _iso(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.row,
    required this.busiest,
    required this.inPeriod,
    required this.hovered,
    required this.size,
    required this.colorOf,
    required this.onHover,
    required this.onTapped,
    super.key,
  });

  final DateTime day;
  final Map<String, Duration> row;
  final Duration busiest;
  final bool inPeriod;
  final bool hovered;
  final double size;
  final Color Function(String) colorOf;
  final ValueChanged<bool> onHover;
  final VoidCallback? onTapped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worked = bucketTotal(row);
    final project = dominantProject(row);
    final share = busiest.inMinutes == 0
        ? 0.0
        : worked.inMinutes / busiest.inMinutes;
    final colour = project == null
        ? theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: inPeriod ? 1 : 0.35,
          )
        : colorOf(project).withValues(
            alpha: (0.28 + 0.72 * math.min(share, 1)) * (inPeriod ? 1 : 0.35),
          );

    return MouseRegion(
      cursor: onTapped == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTapped,
        child: Padding(
        padding: const EdgeInsets.only(
          right: CalendarHeatmap.gap,
          bottom: CalendarHeatmap.gap,
        ),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(6),
            border: hovered
                ? Border.all(color: theme.colorScheme.onSurface, width: 1.5)
                : null,
          ),
          child: Text(
            '${day.day}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: project == null
                  ? theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: inPeriod ? 0.7 : 0.3,
                    )
                  : _inkOn(colour),
            ),
          ),
          ),
        ),
      ),
    );
  }

  /// Black or white, whichever the filled cell can carry.
  static Color _inkOn(Color background) =>
      background.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.day,
    required this.row,
    required this.colorOf,
  });

  final DateTime? day;
  final Map<String, Duration> row;
  final Color Function(String) colorOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (day == null) {
      return Text(
        'Hover a day to see what it held, click it to open it.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final entries = row.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${_weekdayName(day!)} ${day!.day} ${_monthName(day!)} ${day!.year}',
          style: theme.textTheme.labelLarge,
        ),
        if (entries.isEmpty)
          Text('nothing', style: theme.textTheme.bodySmall)
        else
          for (final entry in entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colorOf(entry.key),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${entry.key} ${formatDuration(entry.value)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
      ],
    );
  }
}

String _weekdayName(DateTime at) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];

String _monthName(DateTime at) => const [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
][at.month - 1];
