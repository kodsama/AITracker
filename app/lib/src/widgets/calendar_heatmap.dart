import 'dart:math' as math;

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

/// A day-by-day calendar, each day painted in the colour of the project that
/// took most of it, and shaded by how much of it there was.
///
/// Colour carries identity and shade carries magnitude, so the legend and the
/// hover card both name the project: the cell is never the only thing saying
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

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

class _CalendarHeatmapState extends State<CalendarHeatmap> {
  DateTime? _hovered;

  static const double cell = 15;
  static const double gap = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = widget.period.start.subtract(
      Duration(days: widget.period.start.weekday - 1),
    );
    final weeks = <List<DateTime>>[];
    for (var at = start; at.isBefore(widget.period.end); ) {
      final week = <DateTime>[];
      for (var day = 0; day < 7; day++) {
        week.add(DateTime(at.year, at.month, at.day + day));
      }
      weeks.add(week);
      at = DateTime(at.year, at.month, at.day + 7);
    }
    final busiest = widget.days.values.fold<Duration>(
      Duration.zero,
      (most, row) => bucketTotal(row) > most ? bucketTotal(row) : most,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(height: 18),
                  for (final day in ['Mon', '', 'Wed', '', 'Fri', '', 'Sun'])
                    SizedBox(
                      height: cell + gap,
                      width: 34,
                      child: Text(
                        day,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
                      height: 18,
                      width: cell + gap,
                      child: week.first.day <= 7
                          ? Text(
                              _month(week.first),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
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
                        colorOf: widget.colorOf,
                        onHover: (over) =>
                            setState(() => _hovered = over ? day : null),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Readout(
          day: _hovered,
          row: _hovered == null ? const {} : widget.days[_hovered!] ?? const {},
          colorOf: widget.colorOf,
        ),
      ],
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
    required this.colorOf,
    required this.onHover,
  });

  final DateTime day;
  final Map<String, Duration> row;
  final Duration busiest;
  final bool inPeriod;
  final bool hovered;
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
          right: _CalendarHeatmapState.gap,
          bottom: _CalendarHeatmapState.gap,
        ),
        child: Container(
          width: _CalendarHeatmapState.cell,
          height: _CalendarHeatmapState.cell,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(3),
            border: hovered
                ? Border.all(color: theme.colorScheme.onSurface, width: 1.5)
                : null,
          ),
        ),
      ),
    );
  }
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
