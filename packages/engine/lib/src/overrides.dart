import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';

/// A hand edit applied on top of what the transcripts say.
///
/// The UI writes these when a block is reassigned, renamed, retimed or struck
/// out; the engine applies them on every later scan, so a correction survives
/// re-reading the transcripts.
class BlockOverride {
  /// Creates an override.
  const BlockOverride({
    this.project,
    this.description,
    this.excluded = false,
    this.start,
    this.end,
  });

  /// Project to bill instead of the one the rules resolved.
  final String? project;

  /// Description to write instead of the templated one.
  final String? description;

  /// Whether the block is left out of every sink.
  final bool excluded;

  /// Corrected start, local time.
  final DateTime? start;

  /// Corrected end, local time.
  final DateTime? end;

  /// Reads an override from its JSON form.
  factory BlockOverride.fromJson(Map<String, Object?> json) => BlockOverride(
    project: json['project'] as String?,
    description: json['description'] as String?,
    excluded: json['excluded'] as bool? ?? false,
    start: DateTime.tryParse(json['start'] as String? ?? ''),
    end: DateTime.tryParse(json['end'] as String? ?? ''),
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    if (project != null) 'project': project,
    if (description != null) 'description': description,
    if (excluded) 'excluded': true,
    if (start != null) 'start': start!.toIso8601String(),
    if (end != null) 'end': end!.toIso8601String(),
  };

  /// The same edit with the project left to the rules again.
  BlockOverride get withoutProject => BlockOverride(
    description: description,
    excluded: excluded,
    start: start,
    end: end,
  );

  /// Whether this edit changes nothing at all.
  bool get isEmpty => toJson().isEmpty;

  /// A copy with the given fields replaced.
  BlockOverride merge(BlockOverride other) => BlockOverride(
    project: other.project ?? project,
    description: other.description ?? description,
    excluded: other.excluded || excluded,
    start: other.start ?? start,
    end: other.end ?? end,
  );
}

/// The hand edits, keyed by block, persisted next to the configuration.
class OverrideStore {
  /// Creates a store over [entries].
  OverrideStore([Map<String, BlockOverride>? entries])
    : _entries = {...?entries};

  final Map<String, BlockOverride> _entries;

  /// Every override, keyed as [keyFor] builds it.
  Map<String, BlockOverride> get entries => Map.unmodifiable(_entries);

  /// The override for [key], if any.
  BlockOverride? operator [](String key) => _entries[key];

  /// Adds or replaces the override for [key]. A null [override] clears it.
  void set(String key, BlockOverride? override) {
    if (override == null) {
      _entries.remove(key);
    } else {
      _entries[key] = override;
    }
  }

  /// Applies [override] on top of whatever [key] already carries.
  void merge(String key, BlockOverride override) {
    _entries[key] = _entries[key]?.merge(override) ?? override;
  }

  /// Stable identity of a block: where it happened and when it started.
  static String keyFor(String directory, DateTime start) =>
      '$directory|${start.toIso8601String()}';

  /// Where the overrides live, next to the configuration file.
  static String defaultPath() =>
      p.join(p.dirname(AiTrackerConfig.defaultPath()), 'overrides.json');

  /// Loads the store from [path], empty when the file does not exist.
  static OverrideStore load([String? path]) {
    final file = File(path ?? defaultPath());
    if (!file.existsSync()) return OverrideStore();
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return OverrideStore();
    return OverrideStore({
      for (final entry in decoded.cast<String, Object?>().entries)
        entry.key: BlockOverride.fromJson(
          (entry.value! as Map).cast<String, Object?>(),
        ),
    });
  }

  /// Writes the store to [path].
  void save([String? path]) {
    final file = File(path ?? defaultPath());
    file.parent.createSync(recursive: true);
    final json = {
      for (final entry in _entries.entries) entry.key: entry.value.toJson(),
    };
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
  }
}
