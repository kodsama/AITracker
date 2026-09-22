import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'config.dart';
import 'log.dart';
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

/// Renames a project, and carries the new name into WorkingHours if asked.
///
/// The rules, the mapping and the hand edits always move together, because they
/// key on the project name and would otherwise be orphaned. The ledger only
/// moves when [inWorkingHours] says so, which is how a name can differ on
/// purpose between the two: rename here and leave the ledger alone, and the
/// mapping keeps pointing at the old ledger name.
RenameResult renameProject(
  AiTrackerConfig config, {
  required String from,
  required String to,
  bool inWorkingHours = false,
  bool dryRun = true,
  bool quitApps = false,
  OverrideStore? overrides,
  MacApp workingHoursApp = MacApp.workingHours,
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
  final notes = <String>[];

  final whPath = AiTrackerConfig.resolveHome(config.workingHours.databasePath);

  final relaunch = <MacApp>[];
  if (inWorkingHours && !dryRun) {
    if (!File(whPath).existsSync()) {
      return RenameResult(
        config: config,
        applied: false,
        refusal: 'no WorkingHours database at $whPath',
      );
    }
    if (workingHoursApp.owns(whPath) && workingHoursApp.isRunning) {
      if (!quitApps) {
        return RenameResult(
          config: config,
          applied: false,
          refusal:
              'WorkingHours is running; quit it, or rename with quit_app '
              'enabled',
        );
      }
      if (!workingHoursApp.quit()) {
        return RenameResult(
          config: config,
          applied: false,
          refusal: 'WorkingHours did not quit within 20s',
        );
      }
      relaunch.add(workingHoursApp);
    }
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
          company: link.company,
          workingHoursTags: link.workingHoursTags,
          calendarLabel: link.calendarLabel,
          color: link.color,
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
  for (final app in relaunch) {
    app.launch();
  }

  for (final note in notes) {
    Log.info('rename: $note');
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
