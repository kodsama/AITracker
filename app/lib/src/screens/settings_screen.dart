import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../state/app_state.dart';
import '../widgets/folder_picker.dart';

/// Sources, thresholds, where each export goes, and the MCP endpoint.
class SettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const SettingsScreen({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = state.config;

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      children: [
        Text('Settings', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 20),

        _Section(
          title: 'Measurement',
          child: Column(
            children: [
              _Slider(
                label: 'Idle gap',
                help: 'Silence longer than this ends a block.',
                value: config.idleGap.inMinutes.toDouble(),
                min: 2,
                max: 60,
                onSettled: (value) => state.save(
                  config.copyWith(idleGap: Duration(minutes: value.round())),
                ),
              ),
              _Slider(
                label: 'Shortest block',
                help: 'Anything briefer is noise, not work.',
                value: config.minBlock.inMinutes.toDouble(),
                min: 1,
                max: 30,
                onSettled: (value) => state.save(
                  config.copyWith(minBlock: Duration(minutes: value.round())),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overlapping sessions', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<CountMode>(
                      segments: [
                        for (final mode in CountMode.values)
                          ButtonSegment(value: mode, label: Text(mode.label)),
                      ],
                      selected: {state.mode},
                      onSelectionChanged: (chosen) =>
                          state.setMode(chosen.first),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${state.mode.help}. Exports always use wall clock: a '
                      'timesheet cannot hold the same minute twice.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'Transcripts',
          subtitle: 'The folders an assistant writes its sessions to. Claude '
              'Code and the Gemini and Antigravity CLIs are read.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final source in config.sources)
                ListTile(
                  dense: true,
                  leading: Icon(
                    Directory(source).existsSync()
                        ? Icons.folder_outlined
                        : Icons.folder_off_outlined,
                    size: 20,
                    color: Directory(source).existsSync()
                        ? null
                        : theme.colorScheme.error,
                  ),
                  title: Text(source),
                  subtitle: Directory(source).existsSync()
                      ? null
                      : const Text('Not there any more'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _editSource(context, state, source),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => state.save(
                          config.copyWith(
                            sources: [
                              for (final other in config.sources)
                                if (other != source) other,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (config.sources.isEmpty)
                const ListTile(
                  dense: true,
                  title: Text('No transcript folder yet. Add one.'),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _editSource(context, state, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add folder'),
                  ),
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'WorkingHours',
          subtitle: 'Work units, one per block of attention.',
          child: Column(
            children: [
              SwitchListTile(
                value: config.workingHours.enabled,
                onChanged: (value) => state.save(
                  config.copyWith(
                    workingHours: _workingHours(config, enabled: value),
                  ),
                ),
                title: const Text('Export to WorkingHours'),
              ),
              SwitchListTile(
                value: config.workingHours.automatic,
                onChanged: config.workingHours.enabled
                    ? (value) => state.save(
                        config.copyWith(
                          workingHours: _workingHours(config, automatic: value),
                        ),
                      )
                    : null,
                title: const Text('Keep it up to date by itself'),
                subtitle: const Text(
                  'Files new blocks after each scan. Skipped while '
                  'WorkingHours is open, since it would be overwritten.',
                ),
              ),
              _PathField(
                label: 'Database',
                value: AiTrackerConfig.resolveHome(
                  config.workingHours.databasePath,
                ),
                onPicked: (value) => state.save(
                  config.copyWith(
                    workingHours: _workingHours(config, databasePath: value),
                  ),
                ),
              ),
              _Field(
                label: 'Description',
                help: 'Placeholders: {repo} {project} {company} {sessions}',
                value: config.workingHours.descriptionTemplate,
                onSubmitted: (value) => state.save(
                  config.copyWith(
                    workingHours: _workingHours(
                      config,
                      descriptionTemplate: value,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'Calendar, which is how Diarium sees it',
          subtitle: 'One all-day event per worked day, in a calendar of its '
              'own. Diarium reads system calendars as a source, so switch this '
              'calendar on in Diarium and the hours show up there beside '
              'WorkingHours. Nothing is ever written into Diarium itself.',
          child: Column(
            children: [
              SwitchListTile(
                value: config.calendar.enabled,
                onChanged: (value) => state.save(
                  config.copyWith(calendar: _calendar(config, enabled: value)),
                ),
                title: const Text('Publish the calendar'),
                subtitle: Text(_helperState()),
              ),
              SwitchListTile(
                value: config.calendar.automatic,
                onChanged: config.calendar.enabled
                    ? (value) => state.save(
                        config.copyWith(
                          calendar: _calendar(config, automatic: value),
                        ),
                      )
                    : null,
                title: const Text('Keep it up to date by itself'),
              ),
              _Field(
                label: 'Calendar name',
                value: config.calendar.calendarName,
                onSubmitted: (value) => state.save(
                  config.copyWith(calendar: _calendar(config, name: value)),
                ),
              ),
              _Field(
                label: 'Event title',
                help: '{hours} is the day\'s total',
                value: config.calendar.titleTemplate,
                onSubmitted: (value) => state.save(
                  config.copyWith(calendar: _calendar(config, title: value)),
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'Spreadsheets',
          child: Column(
            children: [
              SwitchListTile(
                value: config.tabular.enabled,
                onChanged: (value) => state.save(
                  config.copyWith(tabular: _tabular(config, enabled: value)),
                ),
                title: const Text('Export CSV and Excel'),
              ),
              SwitchListTile(
                value: config.tabular.automatic,
                onChanged: config.tabular.enabled
                    ? (value) => state.save(
                        config.copyWith(
                          tabular: _tabular(config, automatic: value),
                        ),
                      )
                    : null,
                title: const Text('Rewrite them by themselves'),
              ),
              _PathField(
                label: 'CSV',
                value: AiTrackerConfig.resolveHome(config.tabular.csvPath),
                onPicked: (value) => state.save(
                  config.copyWith(tabular: _tabular(config, csv: value)),
                ),
              ),
              _PathField(
                label: 'Excel',
                value: AiTrackerConfig.resolveHome(config.tabular.xlsxPath),
                onPicked: (value) => state.save(
                  config.copyWith(tabular: _tabular(config, xlsx: value)),
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'MCP',
          subtitle:
              'Serve the engine to an assistant over JSON-RPC while this app '
              'is open. The same tools are available over stdio through the '
              'aitracker_mcp binary, which needs no key.',
          child: Column(
            children: [
              SwitchListTile(
                value: config.mcpEnabled,
                onChanged: (value) =>
                    state.save(config.copyWith(mcpEnabled: value)),
                title: const Text('Listen on localhost'),
                subtitle: Text(
                  state.mcpPort == null
                      ? 'Off'
                      : 'Listening on 127.0.0.1:${state.mcpPort}',
                ),
              ),
              _Field(
                label: 'Port',
                value: '${config.mcpPort}',
                onSubmitted: (value) {
                  final port = int.tryParse(value);
                  if (port != null) state.save(config.copyWith(mcpPort: port));
                },
              ),
              ListTile(
                title: const Text('Key'),
                isThreeLine: true,
                subtitle: Text(
                  'A client on the socket presents this as '
                  'initialize.params.api_key. Anything on this machine can '
                  'reach the port, so it is not optional.\n${state.mcpToken}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: state.mcpToken),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Key copied')),
                        );
                      },
                    ),
                    TextButton(
                      onPressed: state.regenerateMcpToken,
                      child: const Text('Regenerate'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'History',
          subtitle: 'The transcripts are read once into an archive here and '
              'never dropped, so the hours, the tokens and the unmapped time '
              'stay after an assistant prunes its own logs.',
          child: _Archive(state: state),
        ),

        _Section(
          title: 'Log',
          subtitle: 'Every scan, export, refusal and rename, shared by the app, '
              'the command line and the MCP server.',
          child: _LogView(path: Log.path()),
        ),

        const SizedBox(height: 12),
        Text(
          'Configuration: ${state.configPath ?? AiTrackerConfig.defaultPath()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _helperState() {
    const sink = CalendarSink(config: CalendarSinkConfig());
    return sink.helper == null
        ? 'The EventKit helper is not built yet: run '
              'tool/build-calendar-helper.sh'
        : 'Publishing through ${sink.helper}';
  }

  static WorkingHoursSinkConfig _workingHours(
    AiTrackerConfig config, {
    bool? enabled,
    bool? automatic,
    String? databasePath,
    String? descriptionTemplate,
  }) => WorkingHoursSinkConfig(
    enabled: enabled ?? config.workingHours.enabled,
    automatic: automatic ?? config.workingHours.automatic,
    databasePath: databasePath ?? config.workingHours.databasePath,
    descriptionTemplate:
        descriptionTemplate ?? config.workingHours.descriptionTemplate,
    color: config.workingHours.color,
  );

  static CalendarSinkConfig _calendar(
    AiTrackerConfig config, {
    bool? enabled,
    bool? automatic,
    String? name,
    String? title,
  }) => CalendarSinkConfig(
    enabled: enabled ?? config.calendar.enabled,
    automatic: automatic ?? config.calendar.automatic,
    calendarName: name ?? config.calendar.calendarName,
    titleTemplate: title ?? config.calendar.titleTemplate,
  );

  static TabularSinkConfig _tabular(
    AiTrackerConfig config, {
    bool? enabled,
    bool? automatic,
    String? csv,
    String? xlsx,
  }) => TabularSinkConfig(
    enabled: enabled ?? config.tabular.enabled,
    automatic: automatic ?? config.tabular.automatic,
    csvPath: csv ?? config.tabular.csvPath,
    xlsxPath: xlsx ?? config.tabular.xlsxPath,
  );
}

/// Adds a transcript folder, or points an existing one somewhere else.
Future<void> _editSource(
  BuildContext context,
  AppState state,
  String? existing,
) async {
  final chosen = await showFolderPicker(context, initial: existing);
  if (chosen == null || chosen.isEmpty) return;
  final sources = [
    for (final source in state.config.sources)
      if (source == existing) chosen else source,
    if (existing == null) chosen,
  ];
  await state.save(state.config.copyWith(sources: sources.toSet().toList()));
}

/// What the archive holds, and where it is.
class _Archive extends StatefulWidget {
  const _Archive({required this.state});

  final AppState state;

  @override
  State<_Archive> createState() => _ArchiveState();
}

class _ArchiveState extends State<_Archive> {
  late HistorySummary _summary = widget.state.archive();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = _summary.first;
    final last = _summary.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(
            _summary.events == 0
                ? 'Nothing archived yet'
                : '${_thousands(_summary.events)} events from '
                      '${_summary.files} transcripts',
          ),
          subtitle: Text(
            first == null || last == null
                ? widget.state.historyPath
                : '${_day(first)} to ${_day(last)}, '
                      '${(_summary.bytes / 1024 / 1024).toStringAsFixed(1)} MB\n'
                      '${widget.state.historyPath}',
            style: theme.textTheme.bodySmall,
          ),
          isThreeLine: first != null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () =>
                    setState(() => _summary = widget.state.archive()),
              ),
              IconButton(
                tooltip: 'Show in Finder',
                icon: const Icon(Icons.folder_open, size: 18),
                onPressed: () => Process.runSync('/usr/bin/open', [
                  '-R',
                  widget.state.historyPath,
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _day(DateTime at) =>
      '${at.day}/${at.month}/${at.year}';

  static String _thousands(int count) {
    final digits = '$count';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// The tail of the log, with a way to open the whole thing.
class _LogView extends StatefulWidget {
  const _LogView({required this.path});

  final String path;

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  List<String> _lines = Log.tail(40);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.path, style: theme.textTheme.bodySmall),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () => setState(() => _lines = Log.tail(40)),
              ),
              IconButton(
                tooltip: 'Show in Finder',
                icon: const Icon(Icons.folder_open, size: 18),
                onPressed: () =>
                    Process.runSync('/usr/bin/open', ['-R', widget.path]),
              ),
              TextButton(
                onPressed: () {
                  Log.clear();
                  setState(() => _lines = const []);
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        Container(
          height: 220,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: _lines.isEmpty
              ? Text('Nothing logged yet.', style: theme.textTheme.bodySmall)
              : ListView.builder(
                  reverse: true,
                  itemCount: _lines.length,
                  itemBuilder: (context, index) => SelectableText(
                    _lines[_lines.length - 1 - index],
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'Menlo',
                      fontSize: 11,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
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
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// A slider that only commits when the thumb is let go.
///
/// Saving means rewriting the configuration and rescanning every transcript,
/// which is far too much to do on each pixel of a drag, so the value is local
/// until the gesture ends.
class _Slider extends StatefulWidget {
  const _Slider({
    required this.label,
    required this.help,
    required this.value,
    required this.min,
    required this.max,
    required this.onSettled,
  });

  final String label;
  final String help;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onSettled;

  @override
  State<_Slider> createState() => _SliderState();
}

class _SliderState extends State<_Slider> {
  double? _dragging;

  @override
  void didUpdateWidget(_Slider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _dragging = null;
  }

  @override
  Widget build(BuildContext context) {
    // A value typed into the configuration file by hand can sit outside the
    // slider's range; show it at the end of the track rather than throwing the
    // screen away.
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    return ListTile(
      title: Text('${widget.label}: ${value.round()} min'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.help, style: Theme.of(context).textTheme.bodySmall),
          Slider(
            value: value,
            min: widget.min,
            max: widget.max,
            divisions: (widget.max - widget.min).round(),
            label: '${value.round()} min',
            onChanged: (next) => setState(() => _dragging = next),
            onChangeEnd: widget.onSettled,
          ),
        ],
      ),
    );
  }
}

/// A file path with a folder button: type it, or go and find it.
class _PathField extends StatelessWidget {
  const _PathField({
    required this.label,
    required this.value,
    required this.onPicked,
  });

  final String label;
  final String value;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) => _Field(
    label: label,
    value: value,
    onSubmitted: onPicked,
    trailing: IconButton(
      tooltip: 'Browse',
      icon: const Icon(Icons.folder_open, size: 18),
      onPressed: () async {
        final folder = await showFolderPicker(
          context,
          initial: p.dirname(value),
        );
        if (folder == null || folder.isEmpty) return;
        onPicked(p.join(folder, p.basename(value)));
      },
    ),
  );
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.help,
    this.trailing,
  });

  final String label;
  final String value;
  final String? help;
  final Widget? trailing;
  final ValueChanged<String> onSubmitted;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_Field old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    child: TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.help,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: widget.trailing,
      ),
      onSubmitted: widget.onSubmitted,
    ),
  );
}
