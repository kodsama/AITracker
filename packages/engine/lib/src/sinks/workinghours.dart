import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../config.dart';
import '../mac_apps.dart';
import '../ticks.dart';
import '../tracking.dart';
import 'report.dart';

/// Writes work blocks into the WorkingHours store.
///
/// WorkingHours has no API: the community answer is to write its SQLite file
/// directly (forum.workinghoursapp.com/d/1832). That file is the app's live
/// store and is whole-file synced to the cloud, so this sink only writes while
/// the app is closed and no timer is running, and copies the database first.
class WorkingHoursSink {
  /// Creates the sink.
  const WorkingHoursSink({
    required this.config,
    this.minBlock = const Duration(minutes: 5),
    this.app = MacApp.workingHours,
  });

  /// Database path, description template and colour.
  final WorkingHoursSinkConfig config;

  /// Remainders shorter than this, after cutting out time already logged, are
  /// dropped instead of written.
  final Duration minBlock;

  /// The app that owns the store.
  final MacApp app;

  /// Resolved path of the store.
  String get databasePath => AiTrackingConfig.resolveHome(config.databasePath);

  /// Writes [blocks], or previews the write when [dryRun] is set.
  ///
  /// With [quitApp] the sink closes WorkingHours first and starts it again
  /// afterwards, which is what a scheduled run needs; without it, a running app
  /// is a refusal.
  SyncReport sync(
    List<TrackedBlock> blocks, {
    bool dryRun = true,
    bool quitApp = false,
  }) {
    final file = File(databasePath);
    if (!file.existsSync()) {
      return SyncReport(
        sink: 'workinghours',
        applied: false,
        refusal: 'no WorkingHours database at $databasePath',
      );
    }

    var relaunch = false;
    if (!dryRun && app.isRunning) {
      if (!quitApp) {
        return SyncReport(
          sink: 'workinghours',
          applied: false,
          refusal:
              'WorkingHours is running; it would overwrite the rows from its '
              'own memory. Quit it, or sync with quit_app enabled.',
        );
      }
      if (!app.quit()) {
        return SyncReport(
          sink: 'workinghours',
          applied: false,
          refusal: 'WorkingHours did not quit within 20s',
        );
      }
      relaunch = true;
    }

    final db = sqlite3.open(
      databasePath,
      mode: dryRun ? OpenMode.readOnly : OpenMode.readWrite,
    );
    try {
      final running = db.select(
        "select Value from Settings where SettingId = 'WatchStarted'",
      );
      if (running.isNotEmpty && '${running.first['Value'] ?? ''}'.isNotEmpty) {
        return SyncReport(
          sink: 'workinghours',
          applied: false,
          refusal: 'a WorkingHours timer is running; stop it and run again',
        );
      }

      final busy = <TimeRange>[
        for (final row in db.select('select Start, End from WorkUnits'))
          (start: fromTicks(row['Start']! as int), end: fromTicks(row['End']! as int)),
      ];

      final candidates = <TrackedBlock>[];
      final skipped = <TrackedBlock>[];
      for (final block in blocks.where((b) => b.billable)) {
        final pieces = subtractBusy(block, busy, minBlock);
        if (pieces.isEmpty) {
          skipped.add(block);
        } else {
          candidates.addAll(pieces);
        }
      }

      final notes = <String>[];
      final projects = _projectIds(db);
      final missing = {
        for (final block in candidates)
          if (!projects.containsKey(block.project)) block.project!,
      };
      if (dryRun) {
        for (final name in missing) {
          notes.add('would create project "$name"');
        }
        return SyncReport(
          sink: 'workinghours',
          applied: false,
          written: candidates,
          skipped: skipped,
          notes: notes,
        );
      }

      final backup = candidates.isEmpty ? null : _backup(file);
      for (final name in missing) {
        projects[name] = _createProject(db, name);
        notes.add('created project "$name"');
      }
      for (final block in candidates) {
        final start = toTicks(block.block.start);
        final end = toTicks(block.block.end);
        db.execute(
          'insert into WorkUnits '
          '(ProjectId, Duration, End, Description, Details, Start) '
          'values (?, ?, ?, ?, ?, ?)',
          [projects[block.project], end - start, end, block.description, marker, start],
        );
      }
      if (relaunch) app.launch();
      return SyncReport(
        sink: 'workinghours',
        applied: true,
        written: candidates,
        skipped: skipped,
        notes: notes,
        backup: backup,
      );
    } finally {
      db.close();
    }
  }

  /// Written into each row's `Details` so a later run, or a human, can tell
  /// which units this tool owns.
  static const String marker = 'aitracking';

  Map<String, int> _projectIds(Database db) => {
    for (final row in db.select('select ProjectId, Name from Projects'))
      row['Name']! as String: row['ProjectId']! as int,
  };

  int _createProject(Database db, String name) {
    final sort = db.select('select coalesce(max(SortIndex), 0) + 1 as next from Projects');
    db.execute(
      'insert into Projects '
      '(Name, Icon, Color, HourlyRate, Currency, Details, SortIndex, Hidden, IsLumpSum) '
      'values (?, null, ?, 0.0, ?, ?, ?, 0, 0)',
      [name, config.color, _currency(db), marker, sort.first['next']],
    );
    return db.lastInsertRowId;
  }

  /// The currency the other projects use, so a new one matches the ledger.
  String _currency(Database db) {
    final rows = db.select(
      'select Currency, count(*) as n from Projects '
      'group by Currency order by n desc limit 1',
    );
    if (rows.isEmpty) return '';
    return '${rows.first['Currency'] ?? ''}';
  }

  String _backup(File file) {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp('[^0-9]'), '')
        .substring(0, 14);
    final path = '${file.parent.path}/WorkingHours_backup_aitracking_$stamp.sqlite';
    file.copySync(path);
    return path;
  }
}
