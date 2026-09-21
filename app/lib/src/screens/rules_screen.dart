import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../state/app_state.dart';
import '../widgets/project_field.dart';
import '../widgets/project_mapping.dart';

/// Where directories become projects, and where the unmapped ones get fixed.
class RulesScreen extends StatelessWidget {
  /// Creates the screen.
  const RulesScreen({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = state.config.rules;
    final strays = state.strays.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      children: [
        Row(
          children: [
            Text('Projects', style: theme.textTheme.headlineSmall),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () => _edit(context, null, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add rule'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'The first rule whose text appears in a session directory wins. '
          'Slashes and hyphens are interchangeable.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              if (rules.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No rules yet. Every hour is unmapped.'),
                ),
              for (var i = 0; i < rules.length; i++)
                ListTile(
                  leading: Text(
                    '${i + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(rules[i].project),
                  subtitle: Text('directory contains "${rules[i].match}"'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        onPressed: i == 0 ? null : () => _move(i, -1),
                        icon: const Icon(Icons.arrow_upward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        onPressed: i == rules.length - 1
                            ? null
                            : () => _move(i, 1),
                        icon: const Icon(Icons.arrow_downward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => _edit(context, i, rules[i]),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _delete(i),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        ProjectMapping(state: state),
        if (strays.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Unmapped', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Directories with hours in the current window and no rule.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final stray in strays)
                  ListTile(
                    title: Text(p.basename(stray.key)),
                    subtitle: Text(stray.key),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatDuration(stray.value)),
                        const SizedBox(width: 12),
                        FilledButton.tonal(
                          onPressed: () => _edit(
                            context,
                            null,
                            ProjectRule(
                              match: p.basename(stray.key),
                              project: '',
                            ),
                          ),
                          child: const Text('Map it'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _move(int index, int delta) {
    final rules = [...state.config.rules];
    final rule = rules.removeAt(index);
    rules.insert(index + delta, rule);
    state.save(state.config.copyWith(rules: rules));
  }

  void _delete(int index) {
    final rules = [...state.config.rules]..removeAt(index);
    state.save(state.config.copyWith(rules: rules));
  }

  Future<void> _edit(
    BuildContext context,
    int? index,
    ProjectRule? rule,
  ) async {
    final edited = await showDialog<ProjectRule>(
      context: context,
      builder: (context) => _RuleDialog(rule: rule, projects: state.knownProjects),
    );
    if (edited == null) return;
    final rules = [...state.config.rules];
    if (index == null) {
      rules.add(edited);
    } else {
      rules[index] = edited;
    }
    await state.save(state.config.copyWith(rules: rules));
  }
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.projects, this.rule});

  final ProjectRule? rule;

  /// Projects to suggest: what the ledger holds and what is already mapped.
  final List<String> projects;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final TextEditingController _match = TextEditingController(
    text: widget.rule?.match ?? '',
  );
  late final TextEditingController _project = TextEditingController(
    text: widget.rule?.project ?? '',
  );

  @override
  void dispose() {
    _match.dispose();
    _project.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.rule == null ? 'New rule' : 'Edit rule'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _match,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Directory contains',
              hintText: 'byte-buddies/idbuddy',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ProjectField(
            controller: _project,
            options: widget.projects,
            hint: 'Byte Buddies - idbuddy',
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
          if (_match.text.isEmpty || _project.text.isEmpty) return;
          Navigator.of(context).pop(
            ProjectRule(match: _match.text, project: _project.text),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}
