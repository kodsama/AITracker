import 'package:aitracking_engine/aitracking_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Shows what each sink would do, then writes it if the user says so.
///
/// Nothing is written until the button in this dialog is pressed: the first
/// pass is always a preview, because these stores hold real timesheets.
class SyncDialog extends StatefulWidget {
  /// Creates the dialog.
  const SyncDialog({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  State<SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<SyncDialog> {
  List<SyncReport>? _reports;
  bool _applied = false;
  bool _quitApps = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run(apply: false);
  }

  Future<void> _run({required bool apply}) async {
    setState(() => _busy = true);
    final reports = await widget.state.sync(apply: apply, quitApps: _quitApps);
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _applied = apply;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = _reports;
    return AlertDialog(
      title: Text(_applied ? 'Filed' : 'Ready to file'),
      content: SizedBox(
        width: 560,
        child: reports == null
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reports.isEmpty)
                    const Text('No sink is switched on. See Settings.')
                  else
                    for (final report in reports) _ReportTile(report: report),
                  if (!_applied && reports.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _quitApps,
                      onChanged: (value) =>
                          setState(() => _quitApps = value ?? true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Close the apps for the write'),
                      subtitle: Text(
                        'WorkingHours and Diarium hold their database open and '
                        'would overwrite new rows from memory. They are started '
                        'again afterwards.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(_applied ? 'Done' : 'Cancel'),
        ),
        if (!_applied)
          FilledButton(
            onPressed: _busy || (reports?.isEmpty ?? true)
                ? null
                : () => _run(apply: true),
            child: const Text('Write'),
          ),
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final SyncReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refused = report.refusal != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            refused ? Icons.error_outline : Icons.check_circle_outline,
            color: refused ? theme.colorScheme.error : theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name(report.sink), style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  refused
                      ? report.refusal!
                      : '${report.written.length} blocks, '
                            '${formatDuration(report.total)}'
                            '${report.skipped.isEmpty ? '' : ', ${report.skipped.length} already logged'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: refused
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final note in report.notes)
                  Text(note, style: theme.textTheme.bodySmall),
                for (final output in report.outputs)
                  Text(output, style: theme.textTheme.bodySmall),
                if (report.backup != null)
                  Text(
                    'backup: ${report.backup}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _name(String sink) => switch (sink) {
    'workinghours' => 'WorkingHours',
    'diarium' => 'Diarium',
    _ => 'CSV and Excel',
  };
}
