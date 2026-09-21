import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// The blocks themselves, one row each, selectable for a batch edit.
class BlockList extends StatelessWidget {
  /// Creates the list.
  const BlockList({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.blocks.isEmpty && !state.loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text(
            'No assistant activity in this window.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
      itemCount: state.blocks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final block = state.blocks[index];
        final previous = index == 0 ? null : state.blocks[index - 1];
        final newDay = previous == null || previous.day != block.day;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (newDay)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 8 : 24, bottom: 8),
                child: Row(
                  children: [
                    Text(
                      _dayLabel(block.day),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => state.selectDay(block.day),
                      child: const Text('Select day'),
                    ),
                    TextButton(
                      onPressed: () => state.selectWeek(block.day),
                      child: const Text('Select week'),
                    ),
                  ],
                ),
              ),
            _BlockRow(state: state, block: block),
          ],
        );
      },
    );
  }

  static String _dayLabel(DateTime day) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[day.weekday - 1]} ${day.day} ${months[day.month - 1]} ${day.year}';
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({required this.state, required this.block});

  final AppState state;
  final TrackedBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = state.selected.contains(block.key);
    final edited = state.blocks.isNotEmpty &&
        (block.excluded || _isEdited(state, block));

    return InkWell(
      onTap: () => state.toggle(block.key),
      child: Opacity(
        opacity: block.excluded ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => state.toggle(block.key),
              ),
              SizedBox(
                width: 112,
                child: Text(
                  '${_clock(block.block.start)} - ${_clock(block.block.end)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 68,
                child: Text(
                  formatDuration(block.block.duration),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: block.project == null
                    ? Chip(
                        label: const Text('unmapped'),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                        backgroundColor: theme.colorScheme.errorContainer
                            .withValues(alpha: 0.35),
                      )
                    : Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: state.colorFor(
                                block.project!,
                                theme.brightness,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              block.project!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  block.description,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (block.excluded)
                Tooltip(
                  message: 'Left out of every sink',
                  child: Icon(
                    Icons.block,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else if (edited)
                Tooltip(
                  message: 'Edited by hand',
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: Text(
                  '${block.block.sessions} ${block.block.sessions == 1 ? 'session' : 'sessions'}',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isEdited(AppState state, TrackedBlock block) =>
      state.overrideFor(block.key) != null;

  static String _clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
