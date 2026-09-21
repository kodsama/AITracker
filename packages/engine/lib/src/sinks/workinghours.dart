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
    this.links = const [],
    this.minBlock = const Duration(minutes: 5),
    this.app = MacApp.workingHours,
  });

  /// Database path, description template and colour.
  final WorkingHoursSinkConfig config;

  /// How each project is named and tagged in this ledger.
  final List<ProjectLink> links;

  /// Remainders shorter than this, after cutting out time already logged, are
  /// dropped instead of written.
  final Duration minBlock;

  /// The app that owns the store.
  final MacApp app;

  /// Resolved path of the store.
  String get databasePath => AiTrackerConfig.resolveHome(config.databasePath);

  /// Whether the file being written is the one the app keeps open.
  ///
  /// The quit dance exists because WorkingHours holds its own store in memory
  /// and writes it back. A database somewhere outside its container is nobody's
  /// live store, so it is written straight away.
  bool get appOwnsStore =>
      ownsStore(databasePath, WorkingHoursSinkConfig.defaultDatabasePath);

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
    if (!dryRun && appOwnsStore && app.isRunning) {
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
          if (!projects.containsKey(_ledgerName(block))) _ledgerName(block),
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
        final link = links.where((l) => l.workingHoursProject == name).firstOrNull;
        projects[name] = _createProject(db, name, link?.company, link?.color);
        notes.add(
          'created project "$name"'
          '${link?.company == null ? '' : ' for ${link!.company}'}',
        );
      }
      for (final block in candidates) {
        final start = toTicks(block.block.start);
        final end = toTicks(block.block.end);
        db.execute(
          'insert into WorkUnits '
          '(ProjectId, Duration, End, Description, Details, Start) '
          'values (?, ?, ?, ?, ?, ?)',
          [
            projects[_ledgerName(block)],
            end - start,
            end,
            block.description,
            marker,
            start,
          ],
        );
        final unit = db.lastInsertRowId;
        for (final tag in _link(block)?.workingHoursTags ?? const <String>[]) {
          db.execute('insert into WorkUnitTags (WorkUnitId, TagId) values (?, ?)', [
            unit,
            tagId(db, tag, config.color),
          ]);
        }
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

  /// Pushes each linked project's colour into the ledger, so the two apps draw
  /// the same project the same way.
  SyncReport applyColors({
    bool dryRun = true,
    bool quitApp = false,
    Set<String>? only,
  }) {
    final file = File(databasePath);
    if (!file.existsSync()) {
      return SyncReport(
        sink: 'workinghours',
        applied: false,
        refusal: 'no WorkingHours database at $databasePath',
      );
    }
    final coloured = [
      for (final link in links)
        if (link.color != null &&
            link.color!.isNotEmpty &&
            (only == null || only.contains(link.name)))
          link,
    ];
    if (coloured.isEmpty) {
      return SyncReport(sink: 'workinghours', applied: !dryRun);
    }

    var relaunch = false;
    if (!dryRun && appOwnsStore && app.isRunning) {
      if (!quitApp) {
        return SyncReport(
          sink: 'workinghours',
          applied: false,
          refusal: 'WorkingHours is running; quit it, or sync with quit_app',
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
    final notes = <String>[];
    try {
      String? backup;
      for (final link in coloured) {
        final current = db.select(
          'select Color from Projects where Name = ?',
          [link.workingHoursProject],
        );
        if (current.isEmpty) {
          notes.add('no project "${link.workingHoursProject}" to colour');
          continue;
        }
        if ('${current.first['Color']}'.toUpperCase() ==
            link.color!.toUpperCase()) {
          continue;
        }
        if (dryRun) {
          notes.add(
            'would colour "${link.workingHoursProject}" '
            '${current.first['Color']} -> ${link.color}',
          );
          continue;
        }
        backup ??= _backup(file);
        db.execute('update Projects set Color = ? where Name = ?', [
          link.color,
          link.workingHoursProject,
        ]);
        notes.add('coloured "${link.workingHoursProject}" ${link.color}');
      }
      if (relaunch) app.launch();
      return SyncReport(
        sink: 'workinghours',
        applied: !dryRun,
        notes: notes,
        backup: backup,
      );
    } finally {
      db.close();
    }
  }

  /// Written into each row's `Details` so a later run, or a human, can tell
  /// which units this tool owns.
  static const String marker = 'aitracker';

  /// The link for [block], if its project has been mapped.
  ProjectLink? _link(TrackedBlock block) =>
      links.where((link) => link.name == block.project).firstOrNull;

  /// The name this block is filed under in the ledger, which is the mapped one
  /// when the project has a link.
  String _ledgerName(TrackedBlock block) =>
      _link(block)?.workingHoursProject ?? block.project!;

  Map<String, int> _projectIds(Database db) => {
    for (final row in db.select('select ProjectId, Name from Projects'))
      row['Name']! as String: row['ProjectId']! as int,
  };

  int _createProject(
    Database db,
    String name,
    String? company,
    String? color,
  ) {
    final sort = db.select('select coalesce(max(SortIndex), 0) + 1 as next from Projects');
    db.execute(
      'insert into Projects '
      '(Name, Icon, Color, HourlyRate, Currency, Details, SortIndex, Hidden, IsLumpSum) '
      'values (?, null, ?, 0.0, ?, ?, ?, 0, 0)',
      [
        name,
        color ?? config.color,
        _currency(db),
        marker,
        sort.first['next'],
      ],
    );
    final project = db.lastInsertRowId;
    if (company != null && company.isNotEmpty) {
      db.execute('insert into ProjectTags (ProjectId, TagId) values (?, ?)', [
        project,
        tagId(db, company, config.color),
      ]);
    }
    return project;
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

  /// Id of the tag with [value], created with [color] when the ledger has no
  /// such tag yet.
  static int tagId(Database db, String value, String color) {
    final existing = db.select('select TagId from Tags where Value = ?', [value]);
    if (existing.isNotEmpty) return existing.first['TagId']! as int;
    final sort = db.select('select coalesce(max(SortIndex), 0) + 1 as next from Tags');
    db.execute(
      'insert into Tags '
      '(Value, Type, SortIndex, AutoAssign, Details, Icon, Color, AdjustmentValue, Hidden) '
      'values (?, 0, ?, 0, ?, null, ?, 0.0, 0)',
      [value, sort.first['next'], marker, color],
    );
    return db.lastInsertRowId;
  }

  String _backup(File file) {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp('[^0-9]'), '')
        .substring(0, 14);
    final path = '${file.parent.path}/WorkingHours_backup_aitracker_$stamp.sqlite';
    file.copySync(path);
    return path;
  }
}
