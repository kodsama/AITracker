import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'activity.dart';
import 'config.dart';
import 'log.dart';

/// Which reading of overlapping sessions a set of blocks is.
enum BlockMode {
  /// A minute belongs to one project.
  wallClock('wall'),

  /// Each project on its own timeline.
  perProject('project');

  const BlockMode(this.key);

  /// How the mode is written in the archive.
  final String key;
}

/// What the archive holds, for showing in the app.
class HistorySummary {
  /// Creates a summary.
  const HistorySummary({
    required this.events,
    required this.files,
    required this.bytes,
    this.first,
    this.last,
  });

  /// Events kept.
  final int events;

  /// Transcripts read at least once, whether or not they still exist.
  final int files;

  /// Size of the archive on disk.
  final int bytes;

  /// When the earliest event happened.
  final DateTime? first;

  /// When the latest one did.
  final DateTime? last;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'events': events,
    'files': files,
    'bytes': bytes,
    if (first != null) 'first': first!.toIso8601String(),
    if (last != null) 'last': last!.toIso8601String(),
  };
}

/// The durable record of what the assistants did.
///
/// Transcripts are pruned after about a month, so anything derived from them
/// alone lasts about a month. The archive keeps the events themselves, read
/// once and never thrown away, and everything else is computed from it: the
/// hours, the tokens, the graphs, and the unmapped time that no timesheet would
/// have caught.
///
/// Events rather than blocks, because the idle gap is a setting. Keeping what
/// actually happened means changing that setting applies to the whole history
/// instead of leaving a seam in it.
class HistoryStore {
  HistoryStore._(this._db, this.path);

  final Database _db;

  /// Where the archive lives.
  final String path;

  /// Schema this build writes.
  static const int schemaVersion = 1;

  /// How much of a transcript is held in memory at once.
  static const int _chunkBytes = 1 << 22;

  /// The archive beside the configuration.
  static String defaultPath() => besideConfig(null);

  /// The archive that belongs with [configPath].
  ///
  /// Everything that reads a configuration from somewhere else, which in
  /// practice means every test, gets the archive that goes with it rather than
  /// the real one.
  static String besideConfig(String? configPath) => p.join(
    p.dirname(configPath ?? AiTrackerConfig.defaultPath()),
    'history.db',
  );

  /// Opens the archive, creating it on first use.
  static HistoryStore open([String? at]) {
    final file = at ?? defaultPath();
    Directory(p.dirname(file)).createSync(recursive: true);
    final db = sqlite3.open(file);
    // Several front ends read this at once, so readers must not block on the
    // writer, and a writer must wait its turn rather than fail.
    db.execute('pragma journal_mode = wal');
    db.execute('pragma busy_timeout = 5000');
    db.execute('pragma synchronous = normal');
    _migrate(db);
    return HistoryStore._(db, file);
  }

  static void _migrate(Database db) {
    final version = db.select('pragma user_version').first.values.first as int;
    if (version >= schemaVersion) return;
    db.execute('''
      create table if not exists files (
        id integer primary key autoincrement,
        path text not null unique,
        size integer not null,
        modified integer not null,
        offset integer not null,
        head text not null,
        format text not null,
        directory text not null
      );
      create table if not exists events (
        file_id integer not null,
        at integer not null,
        directory text not null,
        session text not null,
        input integer not null,
        output integer not null,
        cache_write integer not null,
        cache_read integer not null
      );
      create index if not exists events_at on events (at);
      create index if not exists events_file on events (file_id);
      create table if not exists blocks (
        params text not null,
        mode text not null,
        day integer not null,
        directory text not null,
        start integer not null,
        finish integer not null,
        sessions integer not null,
        input integer not null,
        output integer not null,
        cache_write integer not null,
        cache_read integer not null,
        primary key (params, mode, day, directory, start)
      );
      create index if not exists blocks_day on blocks (params, mode, day);
      create table if not exists days (
        params text not null,
        mode text not null,
        day integer not null,
        primary key (params, mode, day)
      );
    ''');
    db.execute('pragma user_version = $schemaVersion');
    Log.info('archive created at schema $schemaVersion');
  }

  /// Reads whatever is new in [sources] into the archive.
  ///
  /// A transcript is append-only while its session runs, so only the bytes past
  /// the last complete line already read are parsed. A file that shrank or
  /// whose first line changed is read again from the start, since it is no
  /// longer the file it was.
  ///
  /// Returns how many events were added.
  int ingest(List<String> sources) {
    final started = DateTime.now();
    var added = 0;
    var touched = 0;
    final days = <int>{};

    for (final source in sources) {
      final dir = Directory(source);
      if (!dir.existsSync()) {
        Log.warn('transcript folder is not there: $source');
        continue;
      }
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (p.extension(file.path) != '.jsonl') continue;
        // A transaction per file rather than one around the lot: a first run
        // over months of history is a long job, and a file already read should
        // stay read whatever happens to the next one.
        _db.execute('begin');
        final int? events;
        try {
          events = _ingestFile(file, days);
          _db.execute('commit');
        } on Object catch (error) {
          _db.execute('rollback');
          Log.error('could not read ${file.path}', error);
          continue;
        }
        if (events == null) continue;
        touched++;
        added += events;
      }
    }

    if (days.isNotEmpty) {
      _db.execute('begin');
      for (final day in days) {
        _db.execute('delete from blocks where day = ?', [day]);
        _db.execute('delete from days where day = ?', [day]);
      }
      _db.execute('commit');
    }

    if (touched > 0) {
      Log.info(
        'archived $added events from $touched transcripts in '
        '${DateTime.now().difference(started).inMilliseconds}ms',
      );
    }
    return added;
  }

  /// Reads one file, returning how many events it added, or null when there was
  /// nothing new in it.
  int? _ingestFile(File file, Set<int> days) {
    final stat = file.statSync();
    final held = _db.select('select * from files where path = ?', [file.path]);
    final known = held.isEmpty ? null : held.first;
    final modified = stat.modified.millisecondsSinceEpoch;
    if (known != null &&
        known['size'] == stat.size &&
        known['modified'] == modified) {
      return null;
    }

    final handle = file.openSync();
    try {
      final head = _headOf(handle);
      var offset = 0;
      var id = known?['id'] as int?;
      final rewritten =
          known != null && (stat.size < (known['size']! as int) || known['head'] != head);
      if (known != null && !rewritten) {
        offset = known['offset']! as int;
      }
      if (rewritten && id != null) {
        _db.execute('delete from events where file_id = ?', [id]);
        Log.info('transcript was rewritten, reading it again: ${file.path}');
      }
      if (offset >= stat.size) return null;

      var format = known == null || rewritten
          ? TranscriptFormat.unknown
          : TranscriptFormat.values.firstWhere(
              (f) => f.name == known['format'],
              orElse: () => TranscriptFormat.unknown,
            );
      var directory = rewritten ? '' : '${known?['directory'] ?? ''}';
      final session = p.basenameWithoutExtension(file.path);
      final events = <ActivityEvent>[];

      // Read in chunks rather than whole: a long session runs to tens of
      // megabytes, and holding one as bytes, then as a copy, then as a string,
      // then as a list of lines is what made the first run take minutes.
      var position = offset;
      var consumed = offset;
      var pending = Uint8List(0);
      while (position < stat.size) {
        handle.setPositionSync(position);
        final data = handle.readSync(
          math.min(_chunkBytes, stat.size - position),
        );
        if (data.isEmpty) break;
        position += data.length;
        var from = 0;
        for (var i = 0; i < data.length; i++) {
          if (data[i] != 10) continue;
          final line = pending.isEmpty
              ? utf8.decode(
                  Uint8List.sublistView(data, from, i),
                  allowMalformed: true,
                )
              : utf8.decode(
                  Uint8List.fromList([...pending, ...data.sublist(from, i)]),
                  allowMalformed: true,
                );
          pending = Uint8List(0);
          from = i + 1;
          consumed = position - (data.length - from);
          if (line.trim().isEmpty) continue;
          if (format == TranscriptFormat.unknown) format = formatOf(line);
          if (directory.isEmpty) directory = directoryIn(line, format) ?? '';
          final event = parseTranscriptLine(
            line,
            format,
            directory: directory.isEmpty ? _folderOf(file) : directory,
            session: session,
          );
          if (event == null) continue;
          events.add(event);
          // The days these events land in have to be worked out again.
          days.add(_dayOf(event.time.millisecondsSinceEpoch));
        }
        pending = Uint8List.fromList([...pending, ...data.sublist(from)]);
      }
      if (consumed == offset) return null;

      if (id == null) {
        _db.execute(
          'insert into files (path, size, modified, offset, head, format, '
          'directory) values (?, ?, ?, ?, ?, ?, ?)',
          [
            file.path,
            stat.size,
            modified,
            consumed,
            head,
            format.name,
            directory,
          ],
        );
        id = _db.lastInsertRowId;
      } else {
        _db.execute(
          'update files set size = ?, modified = ?, offset = ?, head = ?, '
          'format = ?, directory = ? where id = ?',
          [
            stat.size,
            modified,
            consumed,
            head,
            format.name,
            directory,
            id,
          ],
        );
      }

      final insert = _db.prepare(
        'insert into events (file_id, at, directory, session, input, output, '
        'cache_write, cache_read) values (?, ?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final event in events) {
          insert.execute([
            id,
            event.time.millisecondsSinceEpoch,
            event.directory,
            event.sessionId,
            event.tokens.input,
            event.tokens.output,
            event.tokens.cacheWrite,
            event.tokens.cacheRead,
          ]);
        }
      } finally {
        insert.close();
      }
      return events.length;
    } finally {
      handle.closeSync();
    }
  }

  /// Events between [from] and [to], oldest first.
  List<ActivityEvent> events({DateTime? from, DateTime? to}) => [
    for (final row in _db.select(
      'select at, directory, session, input, output, cache_write, cache_read '
      'from events where at >= ? and at < ? order by at',
      [
        from?.millisecondsSinceEpoch ?? 0,
        to?.millisecondsSinceEpoch ?? 1 << 62,
      ],
    ))
      ActivityEvent(
        time: DateTime.fromMillisecondsSinceEpoch(row['at']! as int),
        directory: row['directory']! as String,
        sessionId: row['session']! as String,
        tokens: TokenUsage(
          input: row['input']! as int,
          output: row['output']! as int,
          cacheWrite: row['cache_write']! as int,
          cacheRead: row['cache_read']! as int,
        ),
      ),
  ];

  /// Blocks between [from] and [to], computed from the archive and kept.
  ///
  /// A day is worked out once per set of thresholds and stored, so looking at a
  /// year reads a few thousand rows rather than a million events. Changing the
  /// idle gap gives a new set and the days are worked out again, which is what
  /// keeps the whole history consistent with the current settings.
  List<WorkBlock> blocks({
    required DateTime from,
    required DateTime to,
    required Duration idleGap,
    required Duration minBlock,
    BlockMode mode = BlockMode.wallClock,
  }) {
    final params = 'gap=${idleGap.inMinutes};min=${minBlock.inMinutes}';
    for (
      var day = DateTime(from.year, from.month, from.day);
      day.isBefore(to);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      _ensureDay(day, params, idleGap, minBlock, mode);
    }
    return [
      for (final row in _db.select(
        'select directory, start, finish, sessions, input, output, '
        'cache_write, cache_read from blocks '
        'where params = ? and mode = ? and start >= ? and start < ? '
        'order by start',
        [
          params,
          mode.key,
          from.millisecondsSinceEpoch,
          to.millisecondsSinceEpoch,
        ],
      ))
        WorkBlock(
          directory: row['directory']! as String,
          start: DateTime.fromMillisecondsSinceEpoch(row['start']! as int),
          end: DateTime.fromMillisecondsSinceEpoch(row['finish']! as int),
          sessions: row['sessions']! as int,
          tokens: TokenUsage(
            input: row['input']! as int,
            output: row['output']! as int,
            cacheWrite: row['cache_write']! as int,
            cacheRead: row['cache_read']! as int,
          ),
        ),
    ];
  }

  void _ensureDay(
    DateTime day,
    String params,
    Duration idleGap,
    Duration minBlock,
    BlockMode mode,
  ) {
    final key = day.millisecondsSinceEpoch;
    final known = _db.select(
      'select 1 from days where params = ? and mode = ? and day = ?',
      [params, mode.key, key],
    );
    if (known.isNotEmpty) return;

    // A day is read with its neighbours, so a stretch of work that runs over
    // midnight is joined up before it is split at it.
    final next = DateTime(day.year, day.month, day.day + 1);
    final around = events(
      from: day.subtract(const Duration(days: 1)),
      to: next.add(const Duration(days: 1)),
    );
    final built = mode == BlockMode.perProject
        ? buildProjectBlocks(around, idleGap: idleGap, minBlock: minBlock)
        : buildBlocks(around, idleGap: idleGap, minBlock: minBlock);

    final insert = _db.prepare(
      'insert or replace into blocks (params, mode, day, directory, start, '
      'finish, sessions, input, output, cache_write, cache_read) '
      'values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );
    try {
      for (final block in built) {
        if (block.start.isBefore(day) || !block.start.isBefore(next)) continue;
        insert.execute([
          params,
          mode.key,
          key,
          block.directory,
          block.start.millisecondsSinceEpoch,
          block.end.millisecondsSinceEpoch,
          block.sessions,
          block.tokens.input,
          block.tokens.output,
          block.tokens.cacheWrite,
          block.tokens.cacheRead,
        ]);
      }
    } finally {
      insert.close();
    }
    _db.execute('insert or replace into days (params, mode, day) values (?, ?, ?)', [
      params,
      mode.key,
      key,
    ]);
  }

  /// What the archive holds.
  HistorySummary summary() {
    final counts = _db
        .select('select count(*) as n, min(at) as a, max(at) as b from events')
        .first;
    final files = _db.select('select count(*) as n from files').first;
    final at = counts['a'] as int?;
    final to = counts['b'] as int?;
    return HistorySummary(
      events: counts['n']! as int,
      files: files['n']! as int,
      bytes: File(path).existsSync() ? File(path).lengthSync() : 0,
      first: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      last: to == null ? null : DateTime.fromMillisecondsSinceEpoch(to),
    );
  }

  /// Throws away the computed blocks, keeping the events.
  ///
  /// Nothing needs this in normal use: a day is recomputed when its events
  /// change or the thresholds do. It is here for when the block building itself
  /// changes under the same thresholds.
  void forgetComputed() {
    _db
      ..execute('delete from blocks')
      ..execute('delete from days');
    Log.info('archive dropped its computed blocks');
  }

  /// Closes the archive.
  void close() => _db.close();

  static int _dayOf(int millis) {
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime(at.year, at.month, at.day).millisecondsSinceEpoch;
  }

  /// The first line, capped, as a fingerprint of the file.
  ///
  /// It has to be the first line rather than the first so many bytes: a
  /// transcript grows by appending, and a fingerprint that grows with it would
  /// make every append look like a different file.
  static String _headOf(RandomAccessFile handle) {
    handle.setPositionSync(0);
    final bytes = handle.readSync(200);
    final line = bytes.indexOf(10);
    return utf8.decode(
      line < 0 ? bytes : bytes.sublist(0, line),
      allowMalformed: true,
    );
  }

  static String _folderOf(File file) {
    final parts = p.split(file.parent.path);
    final index = parts.lastIndexOf('projects');
    if (index >= 0 && index + 1 < parts.length) return parts[index + 1];
    return file.parent.path;
  }
}
