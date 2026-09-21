import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'project_field.dart';

/// Lines each project up with WorkingHours and Diarium: what it is called
/// there, who it is for, what it is tagged with, and what colour it is.
class ProjectMapping extends StatelessWidget {
  /// Creates the section.
  const ProjectMapping({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = {
      for (final rule in state.config.rules) rule.project,
      for (final link in state.config.links) link.name,
    }.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Mapping', style: theme.textTheme.titleLarge),
            const Spacer(),
            TextButton.icon(
              onPressed: projects.isEmpty
                  ? null
                  : () => _pushColors(context),
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: const Text('Push colours to WorkingHours'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'A project can be called one thing here and another in each app. '
          'Renaming asks which of them should follow.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              if (projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Add a rule first; its project shows up here.'),
                ),
              for (final project in projects)
                ListTile(
                  leading: _Swatch(
                    color: state.colorFor(project, theme.brightness),
                    onTap: () => _pickColour(context, project),
                  ),
                  title: Text(project),
                  subtitle: Text(_describe(state.config.linkFor(project), project)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _rename(context, project),
                        child: const Text('Rename'),
                      ),
                      IconButton(
                        tooltip: 'Map to the apps',
                        icon: const Icon(Icons.link, size: 18),
                        onPressed: () => _editLink(context, project),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _describe(ProjectLink? link, String project) {
    final parts = <String>[
      'WorkingHours: ${link?.workingHoursProject ?? project}',
      if (link?.customer != null) 'customer: ${link!.customer}',
      if (link != null && link.workingHoursTags.isNotEmpty)
        'tags: ${link.workingHoursTags.join(', ')}',
      if (link?.diariumTag != null) 'Diarium: ${link!.diariumTag}',
    ];
    return parts.join('  ·  ');
  }

  Future<void> _pushColors(BuildContext context) async {
    final report = await state.pushColors();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          report.refusal ??
              (report.notes.isEmpty
                  ? 'No colours to push yet.'
                  : report.notes.join('\n')),
        ),
      ),
    );
  }

  Future<void> _pickColour(BuildContext context, String project) async {
    final chosen = await showDialog<Color>(
      context: context,
      builder: (context) => _ColourDialog(
        current: state.colorFor(project, Theme.of(context).brightness),
      ),
    );
    if (chosen == null) return;
    final link = state.config.linkFor(project) ?? ProjectLink(name: project);
    await state.saveLink(link.copyWith(color: formatArgb(chosen)));
  }

  Future<void> _editLink(BuildContext context, String project) async {
    final edited = await showDialog<ProjectLink>(
      context: context,
      builder: (context) => _LinkDialog(
        link: state.config.linkFor(project) ?? ProjectLink(name: project),
        catalog: state.catalog,
      ),
    );
    if (edited == null) return;
    await state.saveLink(edited);
  }

  Future<void> _rename(BuildContext context, String project) async {
    final result = await showDialog<_RenameRequest>(
      context: context,
      builder: (context) => _RenameDialog(project: project),
    );
    if (result == null) return;
    final outcome = await state.rename(
      project,
      result.name,
      inWorkingHours: result.inWorkingHours,
      inDiarium: result.inDiarium,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.refusal ?? outcome.notes.join('\n')),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Colour',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    ),
  );
}

class _ColourDialog extends StatefulWidget {
  const _ColourDialog({required this.current});

  final Color current;

  @override
  State<_ColourDialog> createState() => _ColourDialogState();
}

class _ColourDialogState extends State<_ColourDialog> {
  late final TextEditingController _hex = TextEditingController(
    text: formatArgb(widget.current),
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? darkSeries
        : lightSeries;
    return AlertDialog(
      title: const Text('Project colour'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final colour in palette)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(colour),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colour,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hex,
              decoration: const InputDecoration(
                labelText: 'Hex',
                helperText: '#AARRGGBB, the way WorkingHours writes it',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parsed = parseArgb(_hex.text);
            if (parsed != null) Navigator.of(context).pop(parsed);
          },
          child: const Text('Use'),
        ),
      ],
    );
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.link, required this.catalog});

  final ProjectLink link;
  final Catalog catalog;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _workingHours = TextEditingController(
    text: widget.link.workingHoursProject,
  );
  late final TextEditingController _customer = TextEditingController(
    text: widget.link.customer ?? '',
  );
  late final TextEditingController _diarium = TextEditingController(
    text: widget.link.diariumTag ?? '',
  );
  late final Set<String> _tags = {...widget.link.workingHoursTags};

  @override
  void dispose() {
    _workingHours.dispose();
    _customer.dispose();
    _diarium.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = {
      ...widget.catalog.tags.where((t) => !t.hidden).map((t) => t.value),
      ..._tags,
    }.toList()..sort();

    return AlertDialog(
      title: Text(widget.link.name),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProjectField(
                controller: _workingHours,
                options: widget.catalog.projects.map((p) => p.name).toList(),
                label: 'WorkingHours project',
                hint: 'the project this is filed under',
              ),
              const SizedBox(height: 16),
              ProjectField(
                controller: _customer,
                options: widget.catalog.customers,
                label: 'Customer',
                hint: 'tag WorkingHours puts on the project',
              ),
              const SizedBox(height: 16),
              ProjectField(
                controller: _diarium,
                options: widget.catalog.diariumTags
                    .map((t) => t.value)
                    .toList(),
                label: 'Diarium tag',
                hint: 'tag on the daily journal entry',
              ),
              const SizedBox(height: 18),
              Text('Work unit tags', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in tags)
                    FilterChip(
                      label: Text(tag),
                      selected: _tags.contains(tag),
                      onSelected: (on) => setState(
                        () => on ? _tags.add(tag) : _tags.remove(tag),
                      ),
                    ),
                  if (tags.isEmpty)
                    Text(
                      'WorkingHours has no tags yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ProjectLink(
              name: widget.link.name,
              workingHours: _workingHours.text.trim().isEmpty ||
                      _workingHours.text.trim() == widget.link.name
                  ? null
                  : _workingHours.text.trim(),
              customer: _blank(_customer.text),
              workingHoursTags: _tags.toList()..sort(),
              diariumTag: _blank(_diarium.text),
              color: widget.link.color,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  static String? _blank(String value) =>
      value.trim().isEmpty ? null : value.trim();
}

class _RenameRequest {
  const _RenameRequest(this.name, this.inWorkingHours, this.inDiarium);

  final String name;
  final bool inWorkingHours;
  final bool inDiarium;
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.project});

  final String project;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.project,
  );
  bool _inWorkingHours = true;
  bool _inDiarium = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename project'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'New name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _inWorkingHours,
            onChanged: (value) =>
                setState(() => _inWorkingHours = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Rename the WorkingHours project too'),
          ),
          CheckboxListTile(
            value: _inDiarium,
            onChanged: (value) => setState(() => _inDiarium = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Rename the Diarium tag too'),
          ),
          Text(
            'Whatever is left unticked keeps its old name, and the mapping '
            'remembers that they are the same project.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _RenameRequest(_name.text.trim(), _inWorkingHours, _inDiarium),
        ),
        child: const Text('Rename'),
      ),
    ],
  );
}
