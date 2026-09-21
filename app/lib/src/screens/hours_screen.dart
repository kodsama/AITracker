import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../widgets/batch_bar.dart';
import '../widgets/block_list.dart';
import '../widgets/summary_header.dart';
import '../widgets/export_dialog.dart';

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
          onExport: () => showDialog<void>(
            context: context,
            builder: (context) => ExportDialog(state: state),
          ),
        ),
        if (strays.isNotEmpty) _UnmappedBanner(strays: strays),
        if (state.selected.isNotEmpty) BatchBar(state: state),
        const SizedBox(height: 4),
        Expanded(child: BlockList(state: state)),
      ],
    );
  }
}

class _UnmappedBanner extends StatelessWidget {
  const _UnmappedBanner({required this.strays});

  final Map<String, Duration> strays;

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
        ],
      ),
    );
  }
}
