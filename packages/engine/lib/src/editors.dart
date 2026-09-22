import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'activity.dart';
import 'log.dart';

/// An editor that keeps its history in a VS Code state database.
///
/// Neither writes a transcript. Both keep everything in the `state.vscdb` that
/// VS Code uses for workbench state, so the history comes out of SQLite rather
/// than off the end of a file, and the reading is particular to each.
enum EditorStore {
  /// Cursor: one row per chat turn in `cursorDiskKV`, the conversation it
  /// belongs to in another, and the folder on the conversation.
  cursor,

  /// Antigravity and Antigravity IDE: whole conversations in one row, held as
  /// protocol buffers inside base64.
  antigravity;

  /// How the store is written in the archive.
  String get key => name;
}

/// The state databases an editor writes under [home], in the order they are
/// offered.
///
/// Both editors are VS Code forks and keep this file in the same place under
/// their own application support folder, so finding them is naming the folders
/// rather than searching for the file.
List<String> discoverEditorStores(String home) {
  final found = <String>[];
  for (final editor in const ['Cursor', 'Antigravity', 'Antigravity IDE']) {
    final path = p.join(
      home,
      'Library',
      'Application Support',
      editor,
      'User',
      'globalStorage',
      'state.vscdb',
    );
    if (File(path).existsSync()) found.add(path);
  }
  return found;
}

/// Which reader [path] wants, or null when it is not an editor store.
///
/// The folder the database sits in names the editor: the file itself is called
/// `state.vscdb` in every VS Code fork there is.
EditorStore? editorAt(String path) {
  if (p.basename(path) != 'state.vscdb') return null;
  for (final part in p.split(path)) {
    final name = part.toLowerCase();
    if (name == 'cursor') return EditorStore.cursor;
    if (name.startsWith('antigravity')) return EditorStore.antigravity;
  }
  return null;
}

/// Reads what an editor did, keeping only what happened after [after].
///
/// The database belongs to a running editor, so it is opened read-only and
/// left alone; a store that cannot be opened is reported and skipped rather
/// than failing the scan.
List<ActivityEvent> readEditorStore(
  String path,
  EditorStore store, {
  DateTime? after,
}) {
  final Database db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
  } on SqliteException catch (error) {
    Log.error('could not open $path', error);
    return const [];
  }
  try {
    return switch (store) {
      EditorStore.cursor => _readCursor(db, after),
      EditorStore.antigravity => _readAntigravity(db, after),
    };
  } on SqliteException catch (error) {
    Log.error('could not read $path', error);
    return const [];
  } finally {
    db.close();
  }
}

/// Cursor keys everything on a conversation id, and the rows are one flat
/// table, so a conversation's turns are the keys between `bubbleId:<id>:` and
/// the next character after the colon.
///
/// The fields wanted are pulled out in SQL rather than by decoding each row
/// here: a turn holds the whole message and every file it touched, and there
/// are hundreds of thousands of them.
List<ActivityEvent> _readCursor(Database db, DateTime? after) {
  final events = <ActivityEvent>[];
  final turns = db.prepare(
    "select json_extract(value, '\$.createdAt') as at, "
    "json_extract(value, '\$.tokenCount.inputTokens') as input, "
    "json_extract(value, '\$.tokenCount.outputTokens') as output "
    'from cursorDiskKV where key >= ? and key < ?',
  );
  var placed = 0;
  var unplaced = 0;

  try {
    for (final row in db.select(
      'select key, '
      "coalesce(json_extract(value, '\$.workspaceIdentifier.uri.fsPath'), "
      "json_extract(value, '\$.workspaceIdentifier.uri.path')) as directory, "
      "coalesce(json_extract(value, '\$.lastUpdatedAt'), "
      "json_extract(value, '\$.createdAt')) as touched "
      'from cursorDiskKV '
      "where key >= 'composerData:' and key < 'composerData;'",
    )) {
      final directory = row['directory'];
      if (directory is! String || directory.isEmpty) {
        unplaced++;
        continue;
      }
      placed++;

      // A conversation nobody has touched since the last read has nothing new
      // in it, and reading a conversation means reading every turn of it.
      final touched = _millis(row['touched']);
      if (after != null && touched != null && touched.isBefore(after)) continue;

      final id = '${row['key']}'.split(':').last;
      for (final turn in turns.select(['bubbleId:$id:', 'bubbleId:$id;'])) {
        final at = _isoOrMillis(turn['at']);
        if (at == null || (after != null && !at.isAfter(after))) continue;
        final input = turn['input'];
        final output = turn['output'];
        events.add(
          ActivityEvent(
            time: at.toLocal(),
            directory: directory,
            sessionId: id,
            tokens: TokenUsage(
              input: input is int ? input : 0,
              output: output is int ? output : 0,
            ),
          ),
        );
      }
    }
  } finally {
    turns.close();
  }

  if (unplaced > 0) {
    // Only conversations from Cursor 2026.4 onwards name their folder. The
    // older ones name it nowhere in the database, and guessing it from the
    // files they mention puts hours against the wrong project.
    Log.info(
      'Cursor: $placed conversations name their folder, $unplaced do not and '
      'were left out',
    );
  }
  return events;
}

/// Antigravity keeps one row per sync key holding every conversation, each one
/// a protocol buffer inside base64, and the steps inside carry the times.
List<ActivityEvent> _readAntigravity(Database db, DateTime? after) {
  final events = <ActivityEvent>[];
  var read = 0;
  var unplaced = 0;

  for (final row in db.select(
    "select value from ItemTable where key like '%trajectorySummaries'",
  )) {
    final value = row['value'];
    if (value is! String) continue;
    final outer = _base64(value);
    if (outer == null) continue;

    final List<_Field> entries;
    try {
      entries = _fields(outer).where((f) => f.number == 1).toList();
    } on FormatException catch (error) {
      Log.warn('Antigravity: a stored row would not decode ($error)');
      continue;
    }
    for (final entry in entries) {
      final bytes = entry.bytes;
      if (bytes == null) continue;
      final id = _fields(bytes)
          .where((f) => f.number == 1)
          .map((f) => f.text)
          .firstWhere((t) => t != null, orElse: () => null);
      final held = _fields(bytes)
          .where((f) => f.number == 2)
          .map((f) => f.bytes)
          .firstWhere((b) => b != null, orElse: () => null);
      if (held == null) continue;
      final encoded = _fields(held)
          .where((f) => f.number == 1)
          .map((f) => f.text)
          .firstWhere((t) => t != null, orElse: () => null);
      if (encoded == null) continue;
      final body = _base64(encoded);
      if (body == null) continue;

      read++;
      // One conversation that will not decode is one conversation, not the end
      // of the read: the schema is Google's and it moves between releases.
      final List<ActivityEvent>? conversation;
      try {
        conversation = _antigravityConversation(body, id ?? '$read');
      } on FormatException catch (error) {
        Log.warn('Antigravity: a conversation would not decode ($error)');
        continue;
      }
      if (conversation == null) {
        unplaced++;
        continue;
      }
      for (final event in conversation) {
        if (after != null && !event.time.isAfter(after)) continue;
        events.add(event);
      }
    }
  }

  if (read > 0) {
    Log.info(
      'Antigravity: read $read conversations'
      '${unplaced > 0 ? ', $unplaced name no folder and were left out' : ''}',
    );
  }
  return events;
}

/// One Antigravity conversation as the moments it happened.
///
/// Field 9 holds the folder and fields 3, 7 and 10 the conversation's own
/// times; the steps are nested deeper and move between releases, so their
/// times are found by shape instead: a submessage of exactly two numbers that
/// reads as seconds and nanoseconds is what protobuf timestamps are, and one
/// outside the conversation's own span is not one of its steps and is dropped.
List<ActivityEvent>? _antigravityConversation(Uint8List body, String id) {
  final parts = <int, List<_Field>>{};
  for (final field in _fields(body)) {
    parts.putIfAbsent(field.number, () => []).add(field);
  }

  final folder = _antigravityFolder(parts[9]);
  if (folder == null) return null;

  final own = <DateTime>[];
  for (final number in const [3, 7, 10]) {
    final at = _timestamp(parts[number]?.first.bytes);
    if (at != null) own.add(at);
  }
  if (own.isEmpty) return null;
  own.sort();
  final start = own.first;
  final end = own.last;

  final times = {...own};
  for (final number in const [12, 14]) {
    for (final step in parts[number] ?? const <_Field>[]) {
      final bytes = step.bytes;
      if (bytes == null) continue;
      for (final at in _timestampsIn(bytes)) {
        if (at.isBefore(start) || at.isAfter(end)) continue;
        times.add(at);
      }
    }
  }

  return [
    for (final at in times)
      ActivityEvent(time: at.toLocal(), directory: folder, sessionId: id),
  ];
}

/// The folder a conversation was held in, from its workspace message.
///
/// A workspace opened over SSH, or on a share that the URI names a host for,
/// is not a folder on this machine, so there is nothing to put the hours
/// against and the conversation is left out.
String? _antigravityFolder(List<_Field>? workspace) {
  final bytes = workspace?.first.bytes;
  if (bytes == null) return null;
  for (final field in _fields(bytes)) {
    final text = field.number == 1 ? field.text : null;
    if (text == null) continue;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'file' || uri.host.isNotEmpty) continue;
    return uri.toFilePath();
  }
  return null;
}

/// Every timestamp inside a message, however deeply nested.
Iterable<DateTime> _timestampsIn(Uint8List bytes, {int depth = 0}) sync* {
  if (depth > 8) return;
  final at = _timestamp(bytes);
  if (at != null) {
    yield at;
    return;
  }
  final List<_Field> fields;
  try {
    fields = _fields(bytes).toList();
  } on FormatException {
    return;
  }
  for (final field in fields) {
    final nested = field.bytes;
    if (nested != null && nested.isNotEmpty) {
      yield* _timestampsIn(nested, depth: depth + 1);
    }
  }
}

/// A message read as a protobuf timestamp, or null when it is not one.
///
/// Seconds are held to this century and nanoseconds to under a second, which
/// is what keeps a pair of unrelated numbers from being read as a time.
DateTime? _timestamp(Uint8List? bytes) {
  if (bytes == null) return null;
  final List<_Field> fields;
  try {
    fields = _fields(bytes).toList();
  } on FormatException {
    return null;
  }
  if (fields.length != 2) return null;
  final seconds = fields[0].number == 1 ? fields[0].integer : null;
  final nanos = fields[1].number == 2 ? fields[1].integer : null;
  if (seconds == null || nanos == null) return null;
  if (seconds < 1600000000 || seconds > 2000000000) return null;
  if (nanos >= 1000000000) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// One field off the wire.
class _Field {
  const _Field(this.number, this.integer, this.bytes);

  final int number;
  final int? integer;
  final Uint8List? bytes;

  /// The field read as text, when it is text at all.
  String? get text {
    final raw = bytes;
    if (raw == null) return null;
    try {
      return utf8.decode(raw);
    } on FormatException {
      return null;
    }
  }
}

/// Walks a protobuf message, which is all this needs of protobuf: the schema
/// is Google's and unpublished, so the fields are taken by number and anything
/// unrecognised is stepped over.
Iterable<_Field> _fields(Uint8List buffer) sync* {
  var i = 0;
  int varint() {
    var value = 0;
    var shift = 0;
    while (true) {
      if (i >= buffer.length) throw const FormatException('truncated varint');
      final byte = buffer[i++];
      value |= (byte & 0x7f) << shift;
      shift += 7;
      if (byte & 0x80 == 0) return value;
      if (shift > 63) throw const FormatException('varint too long');
    }
  }

  while (i < buffer.length) {
    final key = varint();
    final number = key >> 3;
    if (number == 0) throw const FormatException('field 0');
    switch (key & 7) {
      case 0:
        yield _Field(number, varint(), null);
      case 1:
        if (i + 8 > buffer.length) throw const FormatException('truncated i64');
        i += 8;
      case 2:
        final length = varint();
        if (length < 0 || i + length > buffer.length) {
          throw const FormatException('truncated bytes');
        }
        yield _Field(number, null, Uint8List.sublistView(buffer, i, i + length));
        i += length;
      case 5:
        if (i + 4 > buffer.length) throw const FormatException('truncated i32');
        i += 4;
      default:
        throw FormatException('wire type ${key & 7}');
    }
  }
}

Uint8List? _base64(String value) {
  try {
    return base64.decode(value);
  } on FormatException {
    return null;
  }
}

DateTime? _millis(Object? value) =>
    value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

DateTime? _isoOrMillis(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is! String) return null;
  return DateTime.tryParse(value);
}
