import 'dart:math' as math;

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

/// A day-by-day calendar, each day painted in the colour of the project that
/// took most of it, and shaded by how much of it there was.
///
/// Colour carries identity and shade carries magnitude, so the legend and the
/// hover line both name the project: a cell is never the only thing saying
/// which project it was.
class CalendarHeatmap extends StatefulWidget {
  /// Creates the calendar.
  const CalendarHeatmap({
    required this.days,
    required this.period,
    required this.colorOf,
    super.key,
  });

  /// Day to project to time.
  final Map<DateTime, Map<String, Duration>> days;

  /// Window to draw, whole weeks either side.
  final Period period;

  /// Colour for a project.
  final Color Function(String project) colorOf;

  /// Space between cells.
  static const double gap = 4;

  /// Width kept for the weekday names.
  static const double labelWidth = 38;

  /// A cell narrower than this is unreadable; one wider stops looking like a
  /// calendar and starts looking like a wall.
  static const double minCell = 13;

  /// Cap on cell size, so a short window does not blow up to fill a wide
  /// window with six enormous squares.
  static const double maxCell = 54;

  /// At this size a cell has room for the day of the month.
  static const double numbersFrom = 24;

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

class _CalendarHeatmapState extends State<CalendarHeatmap> {
  DateTime? _hovered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = widget.period.start.subtract(
      Duration(days: widget.period.start.weekday - 1),
    );
    final weeks = <List<DateTime>>[];
    for (var at = start; at.isBefore(widget.period.end); ) {
      weeks.add([
        for (var day = 0; day < 7; day++)
          DateTime(at.year, at.month, at.day + day),
      ]);
      at = DateTime(at.year, at.month, at.day + 7);
    }
    final busiest = widget.days.values.fold<Duration>(
      Duration.zero,
      (most, row) => bucketTotal(row) > most ? bucketTotal(row) : most,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // The grid takes the width it is given: one column per week, sized to
        // fit, down to a floor that turns on horizontal scrolling instead.
        final available =
            constraints.maxWidth - CalendarHeatmap.labelWidth - 8;
        final cell = math.max(
          CalendarHeatmap.minCell,
          math.min(
            CalendarHeatmap.maxCell,
            available / weeks.length - CalendarHeatmap.gap,
          ),
        );
        final numbers = cell >= CalendarHeatmap.numbersFrom;
        final grid = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(height: cell * 0.5 + 12),
                for (final day in const [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun',
                ])
                  SizedBox(
                    height: cell + CalendarHeatmap.gap,
                    width: CalendarHeatmap.labelWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        cell >= 18 ? day : day.substring(0, 1),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            for (final week in weeks)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: cell * 0.5 + 12,
                    width: cell + CalendarHeatmap.gap,
                    // A month name is wider than one column, so let it run on
                    // over the weeks that follow it.
                    child: week.any((day) => day.day <= 7)
                        ? OverflowBox(
                            maxWidth: 90,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${_month(week.firstWhere((d) => d.day <= 7))} '
                              '${week.firstWhere((d) => d.day <= 7).year}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : null,
                  ),
                  for (final day in week)
                    _Cell(
                      day: day,
                      row: widget.days[day] ?? const {},
                      busiest: busiest,
                      inPeriod: widget.period.contains(day),
                      hovered: _hovered == day,
                      size: cell,
                      showNumber: numbers,
                      colorOf: widget.colorOf,
                      onHover: (over) =>
                          setState(() => _hovered = over ? day : null),
                    ),
                ],
              ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cell > CalendarHeatmap.minCell)
              grid
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: grid,
              ),
            const SizedBox(height: 12),
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
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.day,
    required this.row,
    required this.busiest,
    required this.inPeriod,
    required this.hovered,
    required this.size,
    required this.showNumber,
    required this.colorOf,
    required this.onHover,
  });

  final DateTime day;
  final Map<String, Duration> row;
  final Duration busiest;
  final bool inPeriod;
  final bool hovered;
  final double size;
  final bool showNumber;
  final Color Function(String) colorOf;
  final ValueChanged<bool> onHover;

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
            alpha: inPeriod ? 1 : 0.4,
          )
        : colorOf(project).withValues(alpha: 0.28 + 0.72 * math.min(share, 1));

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
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
            borderRadius: BorderRadius.circular(size < 20 ? 3 : 6),
            border: hovered
                ? Border.all(color: theme.colorScheme.onSurface, width: 1.5)
                : null,
          ),
          child: showNumber
              ? Text(
                  '${day.day}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: project == null
                        ? theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: inPeriod ? 0.7 : 0.35,
                          )
                        : _inkOn(colour),
                  ),
                )
              : null,
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
        'Hover a day to see what it held.',
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
          '${_weekday(day!)} ${day!.day} ${_month(day!)} ${day!.year}',
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

String _weekday(DateTime at) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];

String _month(DateTime at) => const [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][at.month - 1];
