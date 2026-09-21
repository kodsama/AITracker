import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Writes the hours out, after showing exactly what each target would get.
///
/// One direction only, and the dialog says so: the transcripts are the record,
/// so hours go out and never come back. Names and colours are the two-way part,
/// and they live under Projects.
class ExportDialog extends StatefulWidget {
  /// Creates the dialog.
  const ExportDialog({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  List<SyncReport>? _reports;
  Set<String> _targets = {};
  bool _applied = false;
  bool _quitApps = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _targets = {
      for (final sink in kSinkNames)
        if (_enabled(sink)) sink,
    };
    _preview();
  }

  bool _enabled(String sink) => switch (sink) {
    'workinghours' => widget.state.config.workingHours.enabled,
    'calendar' => widget.state.config.calendar.enabled,
    _ => widget.state.config.tabular.enabled,
  };

  Future<void> _preview() async {
    setState(() => _busy = true);
    final reports = await widget.state.export(apply: false, only: _targets);
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _busy = false;
    });
  }

  Future<void> _write() async {
    setState(() => _busy = true);
    final reports = await widget.state.export(
      apply: true,
      quitApps: _quitApps,
      only: _targets,
    );
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _applied = true;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = _reports;
    final enabled = kSinkNames.where(_enabled).toList();

    return AlertDialog(
      title: Text(_applied ? 'Exported' : 'Export hours'),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hours go out only. What comes back the other way is names and '
              'colours, under Projects.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (enabled.isEmpty)
              const Text('No target is switched on. See Settings.')
            else
              for (final sink in enabled)
                CheckboxListTile(
                  value: _targets.contains(sink),
                  onChanged: _applied
                      ? null
                      : (on) {
                          setState(() {
                            if (on ?? false) {
                              _targets.add(sink);
                            } else {
                              _targets.remove(sink);
                            }
                          });
                          _preview();
                        },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(sinkName(sink)),
                  subtitle: _Line(
                    report: reports
                        ?.where((report) => report.sink == sink)
                        .firstOrNull,
                    applied: _applied,
                    busy: _busy,
                  ),
                ),
            if (!_applied &&
                _targets.any((s) => s == 'workinghours')) ...[
              const Divider(),
              CheckboxListTile(
                value: _quitApps,
                onChanged: (value) =>
                    setState(() => _quitApps = value ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Close WorkingHours for the write'),
                subtitle: Text(
                  'It holds its database open and would write its own copy '
                  'back over the new rows. It is started again afterwards.',
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
            onPressed: _busy || _targets.isEmpty ? null : _write,
            child: const Text('Write'),
          ),
      ],
    );
  }
}

/// What a target is called on screen.
String sinkName(String sink) => switch (sink) {
  'workinghours' => 'WorkingHours',
  'calendar' => 'Calendar, which Diarium reads',
  _ => 'CSV and Excel',
};

class _Line extends StatelessWidget {
  const _Line({
    required this.report,
    required this.applied,
    required this.busy,
  });

  final SyncReport? report;
  final bool applied;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (report == null) {
      return Text(
        busy ? 'working it out…' : 'not included',
        style: theme.textTheme.bodySmall,
      );
    }
    if (report!.refusal != null) {
      return Text(
        report!.refusal!,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${applied ? 'wrote' : 'would write'} ${report!.written.length} '
          'blocks, ${formatDuration(report!.total)}'
          '${report!.skipped.isEmpty ? '' : ', ${report!.skipped.length} already logged'}',
          style: theme.textTheme.bodySmall,
        ),
        for (final note in report!.notes)
          Text(note, style: theme.textTheme.bodySmall),
        for (final output in report!.outputs)
          Text(output, style: theme.textTheme.bodySmall),
        if (report!.backup != null)
          Text('backup: ${report!.backup}', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
