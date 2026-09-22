import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/breakdown.dart';
import '../widgets/calendar_heatmap.dart';
import '../widgets/period_picker.dart';
import '../widgets/stacked_bars.dart';

/// The same hours, drawn: stacked bars over the period, then a calendar of the
/// days themselves.
class GraphsScreen extends StatelessWidget {
  /// Creates the screen.
  const GraphsScreen({required this.state, required this.onOpenDay, super.key});

  /// App state.
  final AppState state;

  /// Called when a day in the calendar is clicked.
  final ValueChanged<DateTime> onOpenDay;

  /// Projects charted individually before the rest fold into one slice. The
  /// palette holds eight hues and folding beats inventing a ninth.
  static const int maxSeries = 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final period = state.period;
    final blocks = state.blocks.where((b) => !b.excluded).toList();

    final totals = <String, Duration>{};
    for (final block in blocks) {
      final name = block.project ?? unmappedLabel;
      totals[name] = (totals[name] ?? Duration.zero) + block.block.duration;
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final charted = ranked.take(maxSeries).map((e) => e.key).toList();
    final folded = ranked.length > maxSeries;

    String slot(String project) =>
        charted.contains(project) ? project : otherLabel;
    Color colourOf(String project) => project == otherLabel
        ? otherSeriesColor(context)
        : state.colorFor(project, brightness);

    Map<DateTime, Map<String, Duration>> fold(
      Map<DateTime, Map<String, Duration>> source,
    ) => {
      for (final entry in source.entries)
        entry.key: {
          for (final project in entry.value.entries)
            slot(project.key): (entry.value.entries
                .where((e) => slot(e.key) == slot(project.key))
                .fold(Duration.zero, (sum, e) => sum + e.value)),
        },
    };

    final buckets = fold(bucketBlocks(blocks, period));
    final calendar = fold(dailyTotals(blocks));
    final series = [...charted, if (folded) otherLabel];

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Graphs', style: theme.textTheme.headlineSmall),
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                '${state.periodStep == 0 ? period.label.toLowerCase() : period.label}, '
                '${formatDuration(state.total)}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PeriodPicker(state: state),
        const SizedBox(height: 24),

        if (series.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'Nothing in this window yet.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else ...[
          _Legend(series: series, colourOf: colourOf, totals: totals, slot: slot),
          const SizedBox(height: 16),
          _Panel(
            title: switch (bucketFor(period)) {
              Bucket.day => 'By day',
              Bucket.week => 'By week',
              Bucket.month => 'By month',
            },
            child: StackedBars(
              buckets: buckets,
              width: bucketFor(period),
              series: series,
              colorOf: colourOf,
            ),
          ),
          const SizedBox(height: 20),
          _Panel(
            title: 'Breakdown',
            subtitle: 'Time and tokens together, grouped how you like and '
                'sorted by any column.',
            child: Breakdown(state: state),
          ),
          const SizedBox(height: 20),
          _Panel(
            title: 'Calendar',
            subtitle: 'Each day in the colour of the project that took most of '
                'it, darker the longer it ran.',
            child: CalendarHeatmap(
              days: calendar,
              period: period,
              colorOf: colourOf,
              onDayTapped: onOpenDay,
            ),
          ),
        ],
      ],
    );
  }

  /// What everything past the charted projects is called.
  static const String otherLabel = 'Other';

  /// Grey for the folded slice and for unmapped time.
  static Color otherSeriesColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.series,
    required this.colourOf,
    required this.totals,
    required this.slot,
  });

  final List<String> series;
  final Color Function(String) colourOf;
  final Map<String, Duration> totals;
  final String Function(String) slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folded = <String, Duration>{};
    for (final entry in totals.entries) {
      final name = slot(entry.key);
      folded[name] = (folded[name] ?? Duration.zero) + entry.value;
    }

    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        for (final name in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colourOf(name),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(name, style: theme.textTheme.bodyMedium),
              const SizedBox(width: 6),
              Text(
                formatDuration(folded[name] ?? Duration.zero),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
