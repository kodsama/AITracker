import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../config.dart';
import '../mac_apps.dart';
import '../ticks.dart';
import '../tracking.dart';
import 'report.dart';

/// Writes a daily summary of AI hours into the Diarium journal.
///
/// Diarium keys an entry by its timestamp, so the day's entry is stamped at a
/// fixed time and carries a marker: a later run rewrites its own entry instead
/// of stacking duplicates, and never touches one the user wrote.
class DiariumSink {
  /// Creates the sink.
  const DiariumSink({required this.config, this.app = MacApp.diarium});

  /// Database path, heading and entry time.
  final DiariumSinkConfig config;

  /// The app that owns the store.
  final MacApp app;

  /// Marks the entries this tool owns.
  static const String marker = '<!-- aitracking -->';

  /// Resolved path of the store.
  String get databasePath => AiTrackingConfig.resolveHome(config.databasePath);

  /// Writes one entry per day covered by [blocks], or previews the write.
  SyncReport sync(
    List<TrackedBlock> blocks, {
    bool dryRun = true,
    bool quitApp = false,
  }) {
    final file = File(databasePath);
    if (!file.existsSync()) {
      return SyncReport(
        sink: 'diarium',
        applied: false,
        refusal: 'no Diarium database at $databasePath',
      );
    }

    final billable = blocks.where((b) => b.billable).toList();
    final byDay = <DateTime, List<TrackedBlock>>{};
    for (final block in billable) {
      byDay.putIfAbsent(block.day, () => []).add(block);
    }
    if (byDay.isEmpty) {
      return SyncReport(sink: 'diarium', applied: !dryRun);
    }

    var relaunch = false;
    if (!dryRun && app.isRunning) {
      if (!quitApp) {
        return SyncReport(
          sink: 'diarium',
          applied: false,
          refusal:
              'Diarium is running; it would overwrite the entry from its own '
              'memory. Quit it, or sync with quit_app enabled.',
        );
      }
      if (!app.quit()) {
        return SyncReport(
          sink: 'diarium',
          applied: false,
          refusal: 'Diarium did not quit within 20s',
        );
      }
      relaunch = true;
    }

    final db = sqlite3.open(
      databasePath,
      mode: dryRun ? OpenMode.readOnly : OpenMode.readWrite,
    );
    final notes = <String>[];
    try {
      String? backup;
      for (final day in byDay.keys.toList()..sort()) {
        final id = _entryId(day, db);
        if (id == null) {
          notes.add('no free slot for ${_isoDay(day)}, left alone');
          continue;
        }
        final exists = db
            .select('select DiaryEntryId from Entries where DiaryEntryId = ?', [id])
            .isNotEmpty;
        final verb = exists ? 'update' : 'create';
        if (dryRun) {
          notes.add('would $verb the ${_isoDay(day)} entry');
          continue;
        }
        backup ??= _backup(file);
        final text = _body(byDay[day]!);
        if (exists) {
          db.execute('update Entries set Heading = ?, Text = ? where DiaryEntryId = ?', [
            config.heading,
            text,
            id,
          ]);
        } else {
          db.execute(
            'insert into Entries '
            '(DiaryEntryId, Heading, Text, Rating, Latitude, Longitude) '
            'values (?, ?, ?, 0, 0.0, 0.0)',
            [id, config.heading, text],
          );
        }
        notes.add('${verb}d the ${_isoDay(day)} entry');
      }
      if (relaunch) app.launch();
      return SyncReport(
        sink: 'diarium',
        applied: !dryRun,
        written: billable,
        notes: notes,
        backup: backup,
      );
    } finally {
      db.close();
    }
  }

  /// Tick id for the day's entry: the configured time, stepped forward a minute
  /// at a time past entries the user owns. Null when ten minutes are all taken.
  int? _entryId(DateTime day, Database db) {
    final parts = config.entryTimeOfDay.split(':');
    final hour = int.tryParse(parts.first) ?? 23;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 55 : 55;
    for (var step = 0; step < 10; step++) {
      final at = DateTime(day.year, day.month, day.day, hour, minute + step);
      final id = toTicks(at);
      final rows = db.select('select Text from Entries where DiaryEntryId = ?', [id]);
      if (rows.isEmpty) return id;
      if ('${rows.first['Text'] ?? ''}'.contains(marker)) return id;
    }
    return null;
  }

  String _body(List<TrackedBlock> blocks) {
    final totals = totalsByProject(blocks);
    final names = totals.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final name in names) {
      buffer.write('<p>$name: ${formatDuration(totals[name]!)}</p>');
    }
    final total = totals.values.fold(Duration.zero, (a, b) => a + b);
    buffer.write('<p>Total: ${formatDuration(total)}</p>');
    buffer.write(marker);
    return buffer.toString();
  }

  static String _isoDay(DateTime day) =>
      day.toIso8601String().substring(0, 10);

  String _backup(File file) {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp('[^0-9]'), '')
        .substring(0, 14);
    final path = '${file.parent.path}/Diarium_backup_aitracking_$stamp.sqlite';
    file.copySync(path);
    return path;
  }
}
