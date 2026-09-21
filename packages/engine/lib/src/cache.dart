import 'dart:io';

import 'activity.dart';
import 'log.dart';

/// What one transcript held, and what it looked like when it was read.
class CachedTranscript {
  /// Creates an entry.
  const CachedTranscript({
    required this.modified,
    required this.length,
    required this.events,
  });

  /// When the file was last written.
  final DateTime modified;

  /// How long it was.
  final int length;

  /// What was parsed out of it.
  final List<ActivityEvent> events;

  /// Whether [file] still looks the way it did when this was read.
  ///
  /// A transcript is append-only while a session runs and never rewritten
  /// afterwards, so the size and the modification time together are enough:
  /// anything that changed either one gets read again.
  bool matches(FileStat file) =>
      file.modified == modified && file.size == length;
}

/// Keeps the parsed transcripts between scans.
///
/// A scan reads every file in every source, which on a machine with months of
/// history is a hundred megabytes of JSONL for a second or two of new activity.
/// Holding what was parsed, keyed on how the file looked, turns a rescan into
/// reading the handful of transcripts that moved.
class TranscriptCache {
  /// Creates an empty cache.
  TranscriptCache();

  final Map<String, CachedTranscript> _entries = {};

  /// How many transcripts are held.
  int get length => _entries.length;

  /// Whether [path] has been read already.
  bool holds(String path) => _entries.containsKey(path);

  /// The events of [path], read through [parse] when the file has changed.
  ///
  /// Returns null when the file cannot be looked at, which a caller treats as
  /// nothing to read.
  List<ActivityEvent>? events(
    String path,
    List<ActivityEvent> Function() parse,
  ) {
    final FileStat stat;
    try {
      stat = File(path).statSync();
    } on FileSystemException {
      return null;
    }
    if (stat.type == FileSystemEntityType.notFound) {
      _entries.remove(path);
      return null;
    }
    final held = _entries[path];
    if (held != null && held.matches(stat)) return held.events;
    final parsed = parse();
    _entries[path] = CachedTranscript(
      modified: stat.modified,
      length: stat.size,
      events: parsed,
    );
    return parsed;
  }

  /// Forgets transcripts that are no longer in [paths], so a removed source
  /// does not sit in memory for the rest of the session.
  void keepOnly(Set<String> paths) {
    final gone = _entries.keys.where((path) => !paths.contains(path)).toList();
    for (final path in gone) {
      _entries.remove(path);
    }
    if (gone.isNotEmpty) Log.info('cache dropped ${gone.length} transcripts');
  }

  /// Empties the cache.
  void clear() => _entries.clear();
}
