import 'package:aitracking_engine/aitracking_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Sources, thresholds, sinks and the MCP endpoint.
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
                onChanged: (value) => state.save(
                  config.copyWith(idleGap: Duration(minutes: value.round())),
                ),
              ),
              _Slider(
                label: 'Shortest block',
                help: 'Anything briefer is noise, not work.',
                value: config.minBlock.inMinutes.toDouble(),
                min: 1,
                max: 30,
                onChanged: (value) => state.save(
                  config.copyWith(minBlock: Duration(minutes: value.round())),
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'Transcripts',
          subtitle: 'Read-only. These are the folders the assistant writes to.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final source in config.sources)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined, size: 20),
                  title: Text(source),
                ),
              if (config.sources.isEmpty)
                const ListTile(
                  dense: true,
                  title: Text('No transcript folder found.'),
                ),
            ],
          ),
        ),

        _Section(
          title: 'WorkingHours',
          child: Column(
            children: [
              SwitchListTile(
                value: config.workingHours.enabled,
                onChanged: (value) => state.save(
                  config.copyWith(
                    workingHours: WorkingHoursSinkConfig(
                      enabled: value,
                      databasePath: config.workingHours.databasePath,
                      descriptionTemplate:
                          config.workingHours.descriptionTemplate,
                      color: config.workingHours.color,
                    ),
                  ),
                ),
                title: const Text('File work units'),
                subtitle: Text(
                  AiTrackingConfig.resolveHome(config.workingHours.databasePath),
                ),
              ),
              _Field(
                label: 'Description',
                help: 'Placeholders: {repo} {project} {company} {sessions}',
                value: config.workingHours.descriptionTemplate,
                onSubmitted: (value) => state.save(
                  config.copyWith(
                    workingHours: WorkingHoursSinkConfig(
                      enabled: config.workingHours.enabled,
                      databasePath: config.workingHours.databasePath,
                      descriptionTemplate: value,
                      color: config.workingHours.color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        _Section(
          title: 'Diarium',
          child: Column(
            children: [
              SwitchListTile(
                value: config.diarium.enabled,
                onChanged: (value) => state.save(
                  config.copyWith(
                    diarium: DiariumSinkConfig(
                      enabled: value,
                      databasePath: config.diarium.databasePath,
                      heading: config.diarium.heading,
                      entryTimeOfDay: config.diarium.entryTimeOfDay,
                    ),
                  ),
                ),
                title: const Text('Write a daily journal entry'),
                subtitle: Text(
                  'One entry a day at ${config.diarium.entryTimeOfDay}, '
                  'headed "${config.diarium.heading}", rewritten in place.',
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
                  config.copyWith(
                    tabular: TabularSinkConfig(
                      enabled: value,
                      csvPath: config.tabular.csvPath,
                      xlsxPath: config.tabular.xlsxPath,
                    ),
                  ),
                ),
                title: const Text('Export CSV and Excel'),
                subtitle: Text(
                  '${AiTrackingConfig.resolveHome(config.tabular.csvPath)}\n'
                  '${AiTrackingConfig.resolveHome(config.tabular.xlsxPath)}',
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
              'aitracking_mcp binary.',
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
            ],
          ),
        ),

        const SizedBox(height: 12),
        Text(
          'Configuration: ${state.configPath ?? AiTrackingConfig.defaultPath()}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.help,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String help;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text('$label: ${value.round()} min'),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(help, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          // A value typed into the configuration file by hand can sit outside
          // the slider's range; show it at the end of the track rather than
          // throwing the screen away.
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min).round(),
          label: '${value.round()} min',
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.help,
  });

  final String label;
  final String value;
  final String? help;
  final ValueChanged<String> onSubmitted;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

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
      ),
      onSubmitted: widget.onSubmitted,
    ),
  );
}
