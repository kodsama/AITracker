import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'period_picker.dart';

/// The top of the Hours screen: how much time, over what window, and the button
/// that files it.
class SummaryHeader extends StatelessWidget {
  /// Creates the header.
  const SummaryHeader({required this.state, required this.onSync, super.key});

  /// App state.
  final AppState state;

  /// Called when the sync button is pressed.
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = state.byProject.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final longest = totals.isEmpty ? Duration.zero : totals.first.value;
    final tokens = state.tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatDuration(state.total),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.mode == CountMode.perProject
                        ? 'across projects, ${formatDuration(state.wallClock)} '
                              'on the clock'
                        : 'with an AI assistant',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.only(right: 4, bottom: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          PeriodPicker(state: state),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 24,
                  runSpacing: 6,
                  children: [
                    _Figure(
                      label: 'On the clock',
                      value: formatDuration(state.wallClock),
                      help:
                          'A minute counts once, however many sessions were in it',
                    ),
                    _Figure(
                      label: 'Across projects',
                      value: formatDuration(state.total),
                      help: 'Parallel sessions counted for each project',
                    ),
                    if (!tokens.isEmpty) ...[
                      _Figure(
                        label: 'Tokens',
                        value: _compact(tokens.total),
                        help: 'Everything that passed through, cache included',
                      ),
                      _Figure(
                        label: 'Not cached',
                        value: _compact(tokens.fresh),
                        help: 'Input, output and cache writes',
                      ),
                    ],
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: state.blocks.isEmpty ? null : onSync,
                icon: const Icon(Icons.sync, size: 20),
                label: const Text('Sync…'),
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

/// `1.2M`, because a token count in full is unreadable at a glance.
String _compact(int count) {
  if (count >= 1000000000) return '${(count / 1000000000).toStringAsFixed(1)}B';
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
  return '$count';
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
