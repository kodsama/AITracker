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
              onPressed: projects.isEmpty ? null : () => _colours(context),
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: const Text('Colours…'),
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
      if (link?.company != null) 'company: ${link!.company}',
      if (link != null && link.workingHoursTags.isNotEmpty)
        'tags: ${link.workingHoursTags.join(', ')}',
      if (link?.calendarLabel != null) 'Diarium: ${link!.calendarLabel}',
    ];
    return parts.join('  ·  ');
  }

  Future<void> _colours(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ColourSyncDialog(state: state),
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
        companies: state.knownCompanies,
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
  const _LinkDialog({
    required this.link,
    required this.catalog,
    required this.companies,
  });

  final ProjectLink link;
  final Catalog catalog;

  /// Companies the ledger knows.
  final List<String> companies;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _workingHours = TextEditingController(
    text: widget.link.workingHoursProject,
  );
  late final TextEditingController _customer = TextEditingController(
    text: widget.link.company ?? '',
  );
  late final TextEditingController _diarium = TextEditingController(
    text: widget.link.calendarLabel ?? '',
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
                options: widget.companies,
                label: 'Customer',
                hint: 'tag WorkingHours puts on the project',
              ),
              const SizedBox(height: 16),
              ProjectField(
                controller: _diarium,
                options: const [],
                label: 'Calendar label',
                hint: 'what this project is called in the calendar, and so in '
                    'Diarium',
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
              company: _blank(_customer.text),
              workingHoursTags: _tags.toList()..sort(),
              calendarLabel: _blank(_diarium.text),
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
  const _RenameRequest(this.name, this.inWorkingHours);

  final String name;
  final bool inWorkingHours;
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
          Text(
            'Left unticked, the ledger keeps its old name and the mapping '
            'remembers that they are the same project. The calendar picks the '
            'new name up on the next export.',
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
          _RenameRequest(_name.text.trim(), _inWorkingHours),
        ),
        child: const Text('Rename'),
      ),
    ],
  );
}

/// Compares each project's colour with the ledger's and lets each one go
/// either way.
///
/// Colour is the one thing both sides own, so this is the only place the flow
/// runs in both directions: everything else about a project is decided here and
/// written out.
class _ColourSyncDialog extends StatefulWidget {
  const _ColourSyncDialog({required this.state});

  final AppState state;

  @override
  State<_ColourSyncDialog> createState() => _ColourSyncDialogState();
}

enum _Direction { skip, export, import }

class _ColourSyncDialogState extends State<_ColourSyncDialog> {
  late List<ColourDifference> _differences = widget.state
      .colourDifferences()
      .where((d) => d.differs)
      .toList();
  final Map<String, _Direction> _choices = {};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Colours'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _differences.isEmpty
                  ? 'Every project is the same colour on both sides.'
                  : 'Send a colour to WorkingHours, or take the one it already '
                        'uses.',
              style: theme.textTheme.bodyMedium,
            ),
            if (_differences.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _all(_Direction.export),
                    child: const Text('Export all'),
                  ),
                  TextButton(
                    onPressed: () => _all(_Direction.import),
                    child: const Text('Import all'),
                  ),
                  TextButton(
                    onPressed: () => _all(_Direction.skip),
                    child: const Text('None'),
                  ),
                ],
              ),
              const Divider(),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final difference in _differences)
                      ListTile(
                        dense: true,
                        title: Text(difference.project),
                        subtitle: Text(
                          difference.inLedger
                              ? 'here ${difference.here ?? 'none'} · '
                                    'WorkingHours ${difference.there}'
                              : 'not in WorkingHours yet',
                          style: theme.textTheme.bodySmall,
                        ),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Dot(colour: parseArgb(difference.here)),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.compare_arrows,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            _Dot(colour: parseArgb(difference.there)),
                          ],
                        ),
                        trailing: SegmentedButton<_Direction>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: [
                            const ButtonSegment(
                              value: _Direction.skip,
                              label: Text('Skip'),
                            ),
                            ButtonSegment(
                              value: _Direction.export,
                              label: const Text('Export'),
                              enabled: difference.here != null,
                            ),
                            ButtonSegment(
                              value: _Direction.import,
                              label: const Text('Import'),
                              enabled: difference.inLedger,
                            ),
                          ],
                          selected: {
                            _choices[difference.project] ?? _Direction.skip,
                          },
                          onSelectionChanged: (chosen) => setState(
                            () => _choices[difference.project] = chosen.first,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_differences.isNotEmpty)
          FilledButton(
            onPressed: _busy || _choices.values.every((d) => d == _Direction.skip)
                ? null
                : _apply,
            child: const Text('Apply'),
          ),
      ],
    );
  }

  void _all(_Direction direction) => setState(() {
    for (final difference in _differences) {
      final allowed = switch (direction) {
        _Direction.export => difference.here != null,
        _Direction.import => difference.inLedger,
        _Direction.skip => true,
      };
      _choices[difference.project] = allowed ? direction : _Direction.skip;
    }
  });

  Future<void> _apply() async {
    setState(() => _busy = true);
    final toImport = {
      for (final entry in _choices.entries)
        if (entry.value == _Direction.import) entry.key,
    };
    final toExport = {
      for (final entry in _choices.entries)
        if (entry.value == _Direction.export) entry.key,
    };
    String? trouble;
    if (toImport.isNotEmpty) await widget.state.importColors(toImport);
    if (toExport.isNotEmpty) {
      final report = await widget.state.exportColors(toExport);
      trouble = report.refusal;
    }
    if (!mounted) return;
    setState(() {
      _differences = widget.state
          .colourDifferences()
          .where((d) => d.differs)
          .toList();
      _choices.clear();
      _busy = false;
    });
    if (trouble == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(trouble)));
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.colour});

  final Color? colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: colour ?? Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
}
