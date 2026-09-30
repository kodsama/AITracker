import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Both directions of an export in one place: what each target would be
/// given, and what WorkingHours has had done to it since.
///
/// Hours are measured from the transcripts, so out is the busy direction. The
/// way back matters all the same: a unit moved to another project, renamed or
/// trimmed in the ledger is a correction, and it would be lost on the next scan
/// if it were not read back.
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
  List<UnitDifference> _incoming = const [];
  final Set<String> _taking = {};
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
    _incoming = widget.state.readBackFromLedger();
    _taking.addAll(_incoming.map((d) => d.block.key));
    _preview();
  }

  bool _enabled(String sink) => switch (sink) {
    'workinghours' => widget.state.config.workingHours.enabled,
    'calendar' => widget.state.config.calendar.enabled,
    _ => widget.state.config.tabular.enabled,
  };

  Future<void> _preview() async {
    // An empty set means "all of them" to the engine, which is the opposite of
    // what an empty tick list means here.
    if (_targets.isEmpty) {
      setState(() {
        _reports = const [];
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    final reports = await widget.state.export(apply: false, only: _targets);
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _busy = false;
    });
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    // What came back is adopted first, so what goes out carries it.
    await widget.state.adoptFromLedger(
      _incoming.where((d) => _taking.contains(d.block.key)),
    );
    final reports = await widget.state.export(
      apply: true,
      quitApps: _quitApps,
      only: _targets,
    );
    if (!mounted) return;
    setState(() {
      _reports = reports;
      _incoming = widget.state.readBackFromLedger();
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
      title: Text(_applied ? 'Exported' : 'Export'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Heading(
              icon: Icons.south_west,
              text: _incoming.isEmpty
                  ? 'Nothing has been changed in WorkingHours since it was '
                        'last filed.'
                  : 'Changed in WorkingHours since it was filed. Taking one '
                        'keeps it through the next scan.',
            ),
            for (final difference in _incoming)
              CheckboxListTile(
                value: _taking.contains(difference.block.key),
                onChanged: _applied
                    ? null
                    : (on) => setState(() {
                        if (on ?? false) {
                          _taking.add(difference.block.key);
                        } else {
                          _taking.remove(difference.block.key);
                        }
                      }),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '${_day(difference.block.block.start)} '
                  '${difference.block.description}',
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  difference.changes.join('\n'),
                  style: theme.textTheme.bodySmall,
                ),
                isThreeLine: difference.changes.length > 1,
              ),
            const SizedBox(height: 16),
            _Heading(
              icon: Icons.north_east,
              text: 'Filed out of the transcripts.',
            ),
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
            if (!_applied && _targets.contains('workinghours')) ...[
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(_applied ? 'Done' : 'Cancel'),
        ),
        if (!_applied)
          FilledButton(
            onPressed: _busy || (_targets.isEmpty && _taking.isEmpty)
                ? null
                : _apply,
            child: Text(_taking.isEmpty ? 'Write' : 'Take and write'),
          ),
      ],
    );
  }
}

/// A line saying which way the rows under it go.
class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `Mon 21 Sep`, enough to place a row.
String _day(DateTime at) =>
    '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1]} '
    '${at.day} '
    '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][at.month - 1]}';

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
