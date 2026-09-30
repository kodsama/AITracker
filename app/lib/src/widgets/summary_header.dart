import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../measures.dart';
import '../state/app_state.dart';
import 'period_picker.dart';

/// The top of the Hours screen: how much time, over what window, the button
/// that rereads the transcripts and the button that files what they hold.
class SummaryHeader extends StatelessWidget {
  /// Creates the header.
  const SummaryHeader({
    required this.state,
    required this.onExport,
    super.key,
  });

  /// App state.
  final AppState state;

  /// Called when the export button is pressed.
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = state.byProject.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final longest = totals.isEmpty ? Duration.zero : totals.first.value;
    final tokens = state.tokens;
    final models = state.models;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // The total never gives up room. The words beside it go first,
              // then the button shrinks to its icon.
              final roomForWords = constraints.maxWidth > 760;
              final roomForLabel = constraints.maxWidth > 560;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatDuration(state.total),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1,
                    ),
                  ),
                  if (roomForWords) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          state.mode == CountMode.perProject
                              ? 'across projects, '
                                    '${formatDuration(state.wallClock)} on the clock'
                              : 'with an AI assistant',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (state.loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 10),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          if (state.reading && roomForWords) ...[
                            const SizedBox(width: 8),
                            Text(
                              'reading transcripts',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  // Sync is greyed while a scan runs: pressing it then would
                  // only start the same read over.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, right: 8),
                    child: roomForLabel
                        ? FilledButton.tonalIcon(
                            onPressed: state.loading ? null : state.refresh,
                            icon: const Icon(Icons.sync, size: 20),
                            label: const Text('Sync'),
                          )
                        : IconButton.filledTonal(
                            tooltip: 'Sync',
                            onPressed: state.loading ? null : state.refresh,
                            icon: const Icon(Icons.sync),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: roomForLabel
                        ? FilledButton.icon(
                            onPressed: state.blocks.isEmpty ? null : onExport,
                            icon: const Icon(Icons.upload, size: 20),
                            label: const Text('Export…'),
                          )
                        : IconButton.filled(
                            tooltip: 'Export',
                            onPressed: state.blocks.isEmpty ? null : onExport,
                            icon: const Icon(Icons.upload),
                          ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          PeriodPicker(state: state),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              _Figure(
                label: 'On the clock',
                value: formatDuration(state.wallClock),
                help: 'A minute counts once, however many sessions were in it',
              ),
              _Figure(
                label: 'Across projects',
                value: formatDuration(state.total),
                help: 'Parallel sessions counted for each project',
              ),
              if (!tokens.isEmpty) ...[
                _Figure(
                  label: 'Tokens',
                  value: compactCount(tokens.total),
                  help: 'Everything that passed through, cache included',
                ),
                _Figure(
                  label: 'Not cached',
                  value: compactCount(tokens.fresh),
                  help: 'Input, output and cache writes',
                ),
              ],
              if (models.isNotEmpty)
                _Figure(
                  label: models.length == 1 ? 'Model' : 'Models',
                  value: _shortModel(models.first.key),
                  help: _whichModels(models),
                ),
            ],
          ),
          if (totals.isNotEmpty) ...[
            const SizedBox(height: 20),
            for (final entry in totals.take(6))
              _ProjectBar(
                name: entry.key,
                time: entry.value,
                colour: state.colorFor(entry.key, theme.brightness),
                share: longest.inSeconds == 0
                    ? 0
                    : entry.value.inSeconds / longest.inSeconds,
              ),
          ],
        ],
      ),
    );
  }
}

/// One number with its name, for the row of figures under the picker.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.help,
  });

  final String label;
  final String value;
  final String help;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: help,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectBar extends StatelessWidget {
  const _ProjectBar({
    required this.name,
    required this.time,
    required this.colour,
    required this.share,
  });

  final String name;
  final Duration time;
  final Color colour;
  final double share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          SizedBox(
            width: 190,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 10,
                color: colour,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              formatDuration(time),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `opus-5` out of `claude-opus-5`: the vendor is not the news on a stat.
String _shortModel(String model) {
  const prefixes = ['claude-', 'gpt-', 'gemini-', 'cursor-'];
  for (final prefix in prefixes) {
    if (model.startsWith(prefix)) return model.substring(prefix.length);
  }
  return model;
}

/// Every model in the window with its share, for the tooltip.
String _whichModels(List<MapEntry<String, int>> models) {
  final turns = models.fold<int>(0, (sum, entry) => sum + entry.value);
  return [
    for (final model in models)
      '${model.key}  ${(100 * model.value / turns).round()}%',
  ].join('\n');
}
