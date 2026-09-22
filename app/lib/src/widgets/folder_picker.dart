import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Asks for a folder, by typing a path or by walking the disk.
///
/// The system panel hides dotfolders unless you know the keystroke, and every
/// transcript folder is one, so this browser lists them like any other.
///
/// An editor keeps its history in a file rather than a folder, so a typed path
/// to one of those is taken as it is.
Future<String?> showFolderPicker(
  BuildContext context, {
  String? initial,
}) => showDialog<String>(
  context: context,
  builder: (context) => _FolderPicker(initial: initial),
);

class _FolderPicker extends StatefulWidget {
  const _FolderPicker({this.initial});

  final String? initial;

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late String _current = _startingPoint();
  late final TextEditingController _path = TextEditingController(text: _current);
  String? _error;

  String _startingPoint() {
    final initial = widget.initial;
    if (initial != null && Directory(initial).existsSync()) return initial;
    if (initial != null) {
      final parent = p.dirname(initial);
      if (Directory(parent).existsSync()) return parent;
    }
    return _home;
  }

  static String get _home =>
      Platform.environment['HOME'] ?? Directory.current.path;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  List<Directory> get _children {
    try {
      final entries = Directory(_current)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList();
      entries.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
      return entries;
    } on FileSystemException {
      return const [];
    }
  }

  void _goTo(String path) {
    setState(() {
      _current = path;
      _path.text = path;
      _error = null;
    });
  }

  void _typed(String value) {
    final path = value.trim().replaceFirst(RegExp('^~'), _home);
    if (Directory(path).existsSync()) {
      _goTo(path);
    } else if (editorAt(path) != null && File(path).existsSync()) {
      Navigator.of(context).pop(path);
    } else {
      setState(() => _error = 'No folder at that path');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = _children;

    return AlertDialog(
      title: const Text('Choose a folder'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _path,
              decoration: InputDecoration(
                labelText: 'Path',
                errorText: _error,
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: IconButton(
                  tooltip: 'Up',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: p.dirname(_current) == _current
                      ? null
                      : () => _goTo(p.dirname(_current)),
                ),
                suffixIcon: IconButton(
                  tooltip: 'Home',
                  icon: const Icon(Icons.home_outlined, size: 18),
                  onPressed: () => _goTo(_home),
                ),
              ),
              onSubmitted: _typed,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: children.isEmpty
                    ? Center(
                        child: Text(
                          'No folders in here.',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        itemCount: children.length,
                        itemBuilder: (context, index) {
                          final name = p.basename(children[index].path);
                          final hidden = name.startsWith('.');
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              hidden
                                  ? Icons.folder_off_outlined
                                  : Icons.folder_outlined,
                              size: 20,
                              color: hidden
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                            title: Text(
                              name,
                              style: hidden
                                  ? TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    )
                                  : null,
                            ),
                            onTap: () => _goTo(children[index].path),
                          );
                        },
                      ),
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
          onPressed: () => Navigator.of(context).pop(_path.text.trim()),
          child: const Text('Use this folder'),
        ),
      ],
    );
  }
}
