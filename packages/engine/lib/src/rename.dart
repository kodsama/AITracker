import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'config.dart';
import 'mac_apps.dart';
import 'overrides.dart';

/// What a rename changed, or would change.
class RenameResult {
  /// Creates a result.
  const RenameResult({
    required this.config,
    required this.applied,
    this.refusal,
    this.notes = const [],
  });

  /// The configuration after the rename. The caller saves it.
  final AiTrackerConfig config;

  /// Whether anything was written.
  final bool applied;

  /// Why nothing was written, when a guard stopped the run.
  final String? refusal;

  /// What moved, one line each.
  final List<String> notes;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'applied': applied,
    if (refusal != null) 'refusal': refusal,
    'notes': notes,
  };
}

/// Renames a project, and carries the new name into the apps that were asked
/// for.
///
/// The rules, the mapping and the hand edits always move together, because they
/// key on the project name and would otherwise be orphaned. WorkingHours and
/// Diarium only move when [inWorkingHours] and [inDiarium] say so, which is how
/// a name can differ on purpose between the three: rename here and leave the
/// ledger alone, and the mapping keeps pointing at the old ledger name.
RenameResult renameProject(
  AiTrackerConfig config, {
  required String from,
  required String to,
  bool inWorkingHours = false,
  bool inDiarium = false,
  bool dryRun = true,
  bool quitApps = false,
  OverrideStore? overrides,
  MacApp workingHoursApp = MacApp.workingHours,
  MacApp diariumApp = MacApp.diarium,
}) {
  if (from == to || to.trim().isEmpty) {
    return RenameResult(
      config: config,
      applied: false,
      refusal: 'nothing to rename',
    );
  }

  final link = config.linkFor(from);
  final ledgerName = link?.workingHoursProject ?? from;
  final journalTag = link?.diariumTag;
  final notes = <String>[];

  final whPath = AiTrackerConfig.resolveHome(config.workingHours.databasePath);
  final diariumPath = AiTrackerConfig.resolveHome(config.diarium.databasePath);

  final relaunch = <MacApp>[];
  for (final (wanted, path, app, name, live) in [
    (
      inWorkingHours,
      whPath,
      workingHoursApp,
      'WorkingHours',
      WorkingHoursSinkConfig.defaultDatabasePath,
    ),
    (
      inDiarium,
      diariumPath,
      diariumApp,
      'Diarium',
      DiariumSinkConfig.defaultDatabasePath,
    ),
  ]) {
    if (!wanted || dryRun) continue;
    if (!File(path).existsSync()) {
      return RenameResult(
        config: config,
        applied: false,
        refusal: 'no $name database at $path',
      );
    }
    if (!ownsStore(path, live) || !app.isRunning) continue;
    if (!quitApps) {
      return RenameResult(
        config: config,
        applied: false,
        refusal: '$name is running; quit it, or rename with quit_app enabled',
      );
    }
    if (!app.quit()) {
      return RenameResult(
        config: config,
        applied: false,
        refusal: '$name did not quit within 20s',
      );
    }
    relaunch.add(app);
  }

  // The configuration moves whatever the stores do: a rule or a hand edit still
  // naming the old project would quietly stop matching.
  final rules = [
    for (final rule in config.rules)
      rule.project == from ? ProjectRule(match: rule.match, project: to) : rule,
  ];
  final links = [
    for (final link in config.links)
      if (link.name == from)
        ProjectLink(
          name: to,
          workingHours: inWorkingHours ? null : link.workingHours ?? from,
          customer: link.customer,
          workingHoursTags: link.workingHoursTags,
          diariumTag: inDiarium ? to : link.diariumTag,
        )
      else
        link,
  ];
  if (link == null && !inWorkingHours && _ledgerHasProject(whPath, from)) {
    // The ledger keeps the old name, so write down that they are the same
    // project rather than letting the next sync create a second one.
    links.add(ProjectLink(name: to, workingHours: from));
  }
  notes.add('renamed "$from" to "$to" here');

  if (overrides != null) {
    for (final entry in overrides.entries.entries) {
      if (entry.value.project != from) continue;
      overrides.set(
        entry.key,
        BlockOverride(
          project: to,
          description: entry.value.description,
          excluded: entry.value.excluded,
          start: entry.value.start,
          end: entry.value.end,
        ),
      );
    }
  }

  if (inWorkingHours) {
    notes.add(
      dryRun
          ? 'would rename the WorkingHours project "$ledgerName"'
          : _renameRow(
              whPath,
              'update Projects set Name = ? where Name = ?',
              [to, ledgerName],
              'WorkingHours project "$ledgerName"',
            ),
    );
  }
  if (inDiarium && journalTag != null) {
    notes.add(
      dryRun
          ? 'would rename the Diarium tag "$journalTag"'
          : _renameRow(
              diariumPath,
              'update Tags set Value = ? where Value = ?',
              [to, journalTag],
              'Diarium tag "$journalTag"',
            ),
    );
  }

  for (final app in relaunch) {
    app.launch();
  }

  return RenameResult(
    config: config.copyWith(rules: rules, links: links),
    applied: !dryRun,
    notes: notes,
  );
}

/// Whether the ledger already holds a project under [name].
bool _ledgerHasProject(String path, String name) {
  if (!File(path).existsSync()) return false;
  Database? db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
    return db
        .select('select 1 from Projects where Name = ?', [name])
        .isNotEmpty;
  } on SqliteException {
    return false;
  } finally {
    db?.close();
  }
}

String _renameRow(
  String path,
  String sql,
  List<Object?> params,
  String what,
) {
  final db = sqlite3.open(path);
  try {
    db.execute(sql, params);
    return db.updatedRows == 0 ? 'no $what to rename' : 'renamed the $what';
  } finally {
    db.close();
  }
}
