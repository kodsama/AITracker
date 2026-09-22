import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/batch_bar.dart';
import '../widgets/block_list.dart';
import '../widgets/summary_header.dart';
import '../widgets/sync_dialog.dart';

/// The main screen: what the transcripts say, and the button that files it.
class HoursScreen extends StatelessWidget {
  /// Creates the screen.
  const HoursScreen({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final strays = state.strays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SummaryHeader(
          state: state,
          onSync: () => showDialog<void>(
            context: context,
            builder: (context) => SyncDialog(state: state),
          ),
        ),
        if (state.trouble != null) _Trouble(message: state.trouble!),
        if (strays.isNotEmpty)
          _UnmappedBanner(
            strays: strays,
            onShow: () => state.setFilter(BlockFilter.unmapped),
          ),
        _SearchRow(state: state),
        if (state.selected.isNotEmpty) BatchBar(state: state),
        const SizedBox(height: 4),
        Expanded(child: BlockList(state: state)),
      ],
    );
  }
}

/// The search box and the selection shortcuts.
///
/// The controller lives with the widget: rebuilding one on every keystroke,
/// which a filtered list causes plenty of, throws the caret back to the start.
class _SearchRow extends StatefulWidget {
  const _SearchRow({required this.state});

  final AppState state;

  @override
  State<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends State<_SearchRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.query,
  );

  @override
  void didUpdateWidget(_SearchRow old) {
    super.didUpdateWidget(old);
    if (widget.state.query != _controller.text) {
      _controller.text = widget.state.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final all = state.blocks.isNotEmpty &&
        state.selected.length == state.blocks.length;
    final counts = state.filterCounts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 4),
      child: Row(
        children: [
          SegmentedButton<BlockFilter>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final filter in BlockFilter.values)
                ButtonSegment(
                  value: filter,
                  label: Text('${filter.label} ${counts[filter]}'),
                ),
            ],
            selected: {state.filter},
            onSelectionChanged: (chosen) => state.setFilter(chosen.first),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Search the description, project or folder',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: state.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _controller.clear();
                          state.setQuery('');
                        },
                      ),
              ),
              onChanged: state.setQuery,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${state.blocks.length} blocks',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: state.blocks.isEmpty ? null : state.toggleAll,
            child: Text(all ? 'Select none' : 'Select all'),
          ),
        ],
      ),
    );
  }
}

/// Whatever went wrong last, said out loud rather than swallowed.
class _Trouble extends StatelessWidget {
  const _Trouble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 8, 28, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnmappedBanner extends StatelessWidget {
  const _UnmappedBanner({required this.strays, required this.onShow});

  final Map<String, Duration> strays;

  /// Narrows the list to the blocks going nowhere.
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = strays.values.fold(Duration.zero, (sum, d) => sum + d);
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 8, 28, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.help_outline, size: 20, color: theme.colorScheme.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${formatDuration(total)} in ${strays.length} '
              '${strays.length == 1 ? 'directory' : 'directories'} no rule covers. '
              'These hours go nowhere until you map them under Projects.',
            ),
          ),
          TextButton(onPressed: onShow, child: const Text('Show them')),
        ],
      ),
    );
  }
}
