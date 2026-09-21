import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'project_field.dart';

/// Appears once something is selected: reassign, rename or strike out the lot.
class BatchBar extends StatelessWidget {
  /// Creates the bar.
  const BatchBar({required this.state, super.key});

  /// App state.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = state.selected.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 4, 28, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 20),
          _Action(
            icon: Icons.drive_file_move_outlined,
            label: 'Assign project',
            onPressed: () => _assign(context),
          ),
          _Action(
            icon: Icons.edit_outlined,
            label: 'Rename',
            onPressed: () => _rename(context),
          ),
          _Action(
            icon: Icons.block,
            label: 'Exclude',
            onPressed: () =>
                state.editSelected(const BlockOverride(excluded: true)),
          ),
          _Action(
            icon: Icons.restart_alt,
            label: 'Clear edits',
            onPressed: state.clearSelectedEdits,
          ),
          const Spacer(),
          TextButton(onPressed: state.toggleAll, child: const Text('Select all')),
        ],
      ),
    );
  }

  Future<void> _assign(BuildContext context) async {
    final known = state.knownProjects;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => _PickerDialog(
        title: 'Assign project',
        options: known,
        hint: 'Company - Project',
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    await state.editSelected(BlockOverride(project: chosen));
  }

  Future<void> _rename(BuildContext context) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => const _PickerDialog(
        title: 'Description',
        options: [],
        hint: 'What this time was',
      ),
    );
    if (chosen == null || chosen.isEmpty) return;
    await state.editSelected(BlockOverride(description: chosen));
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    ),
  );
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({
    required this.title,
    required this.options,
    required this.hint,
  });

  final String title;
  final List<String> options;
  final String hint;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.options.isEmpty)
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.hint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            )
          else
            ProjectField(
              controller: _controller,
              options: widget.options,
              autofocus: true,
              hint: widget.hint,
              onSubmitted: (value) => Navigator.of(context).pop(value),
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
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Apply'),
      ),
    ],
  );
}
