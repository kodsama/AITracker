import 'package:flutter/material.dart';

/// A text field that suggests what already exists, and lets you type something
/// that does not.
///
/// The options are the projects WorkingHours holds plus the ones already in
/// play here, so a rule points at a real project rather than a near-miss of its
/// name. Anything typed that matches nothing is offered as a new project, which
/// the sinks create on the next write.
class ProjectField extends StatefulWidget {
  /// Creates the field over [controller], whose text is the value.
  const ProjectField({
    required this.controller,
    required this.options,
    this.label = 'Project',
    this.hint,
    this.autofocus = false,
    this.onSubmitted,
    super.key,
  });

  /// Holds the chosen or typed value.
  final TextEditingController controller;

  /// What to suggest, in the order to suggest it.
  final List<String> options;

  /// Label above the field.
  final String label;

  /// Placeholder when it is empty.
  final String? hint;

  /// Whether to take focus when it appears.
  final bool autofocus;

  /// Called when the field is submitted or an option is picked.
  final ValueChanged<String>? onSubmitted;

  @override
  State<ProjectField> createState() => _ProjectFieldState();
}

class _ProjectFieldState extends State<ProjectField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Nudges the controller so the options list reopens on a bare tap, without
  /// changing what was typed.
  void _reopen() {
    final text = widget.controller.text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// The suggestion list: what matches, with "create this one" in front when
  /// the typed name is not one of the options.
  ///
  /// The create entry is a real option rather than a decoration on an empty
  /// list, because an autocomplete with no options shows no list at all.
  List<_Suggestion> _suggestions(String query) {
    final needle = query.trim();
    final matches = [
      for (final option in _matches(needle)) _Suggestion(option),
    ];
    final exact = widget.options.any(
      (option) => option.toLowerCase() == needle.toLowerCase(),
    );
    return [
      if (needle.isNotEmpty && !exact) _Suggestion(needle, create: true),
      ...matches,
    ];
  }

  List<String> _matches(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return widget.options;
    final starts = <String>[];
    final contains = <String>[];
    for (final option in widget.options) {
      final haystack = option.toLowerCase();
      if (haystack.startsWith(needle)) {
        starts.add(option);
      } else if (haystack.contains(needle)) {
        contains.add(option);
      }
    }
    return [...starts, ...contains];
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<_Suggestion>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (suggestion) => suggestion.value,
      optionsBuilder: (value) => _suggestions(value.text),
      onSelected: (suggestion) => widget.onSubmitted?.call(suggestion.value),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: widget.autofocus,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Show all',
                icon: const Icon(Icons.arrow_drop_down),
                onPressed: () {
                  focusNode.requestFocus();
                  _reopen();
                },
              ),
            ),
            onTap: _reopen,
            onSubmitted: (value) {
              onSubmitted();
              widget.onSubmitted?.call(value);
            },
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    dense: true,
                    leading: option.create ? const Icon(Icons.add, size: 18) : null,
                    title: Text(
                      option.create ? 'Create "${option.value}"' : option.value,
                    ),
                    subtitle: option.create ? const Text('New project') : null,
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of the dropdown: something that exists, or the name just typed.
class _Suggestion {
  const _Suggestion(this.value, {this.create = false});

  final String value;
  final bool create;
}
