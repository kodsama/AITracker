import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'period_picker.dart';

/// The top of the Hours screen: how much time, over what window, and the button
/// that files it.
class SummaryHeader extends StatelessWidget {
  /// Creates the header.
  const SummaryHeader({required this.state, required this.onExport, super.key});

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
                    'with an AI assistant',
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
                  padding: EdgeInsets.only(right: 16, bottom: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              FilledButton.icon(
                onPressed: state.blocks.isEmpty ? null : onExport,
                icon: const Icon(Icons.upload_rounded, size: 20),
                label: const Text('Export…'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PeriodPicker(state: state),
          if (totals.isNotEmpty) ...[
            const SizedBox(height: 20),
            for (final entry in totals.take(6))
              _ProjectBar(
                name: entry.key,
                time: entry.value,
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

class _ProjectBar extends StatelessWidget {
  const _ProjectBar({
    required this.name,
    required this.time,
    required this.share,
  });

  final String name;
  final Duration time;
  final double share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 10,
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
