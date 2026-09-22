import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../config.dart';
import '../log.dart';
import '../overrides.dart';
import '../ticks.dart';
import '../tracking.dart';
import 'workinghours.dart';

/// What the ledger now says about a block this tool wrote there.
class UnitDifference {
  /// Creates a comparison.
  const UnitDifference({
    required this.block,
    required this.project,
    required this.description,
    required this.start,
    required this.end,
  });

  /// The block as it stands here.
  final TrackedBlock block;

  /// Project the unit sits under in the ledger, mapped back to the name this
  /// tool uses for it.
  final String project;

  /// Description on the unit.
  final String description;

  /// When the unit starts, local time.
  final DateTime start;

  /// When it ends.
  final DateTime end;

  /// Whether the project was changed in the ledger.
  bool get reassigned => project != block.project;

  /// Whether the description was changed.
  bool get renamed => description != block.description;

  /// Whether the unit was retimed. A minute either way is the rounding a person
  /// does when dragging a row, not a change worth reporting.
  bool get retimed =>
      start.difference(block.block.start).abs() > const Duration(minutes: 1) ||
      end.difference(block.block.end).abs() > const Duration(minutes: 1);

  /// Whether anything came back at all.
  bool get differs => reassigned || renamed || retimed;

  /// What changed, in words.
  List<String> get changes => [
    if (reassigned) 'project: ${block.project} to $project',
    if (renamed) 'description: "${block.description}" to "$description"',
    if (retimed)
      'times: ${_clock(block.block.start)}-${_clock(block.block.end)} to '
          '${_clock(start)}-${_clock(end)}',
  ];

  /// The hand edit that adopts the ledger's version.
  BlockOverride get asOverride => BlockOverride(
    project: reassigned ? project : null,
    description: renamed ? description : null,
    start: retimed ? start : null,
    end: retimed ? end : null,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'key': block.key,
    'project': project,
    'description': description,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'changes': changes,
  };

  static String _clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// Reads back what WorkingHours now holds for the units this tool wrote.
///
/// Hours are measured here and filed there, but the ledger is where a person
/// corrects them: moved to another project, renamed, or trimmed. Those
/// corrections would be lost on the next scan, so they are read back and kept
/// as hand edits, which is the same place an edit made in this app lives.
///
/// Only units carrying this tool's marker are read. A meeting logged by hand is
/// somebody else's row and is left alone.
List<UnitDifference> readBack(
  AiTrackerConfig config,
  List<TrackedBlock> blocks,
) {
  final path = AiTrackerConfig.resolveHome(config.workingHours.databasePath);
  if (!File(path).existsSync() || blocks.isEmpty) return const [];

  Database? db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
    final ledger = <({DateTime start, DateTime end, String project, String description})>[
      for (final row in db.select(
        'select u.Start as s, u.End as e, u.Description as d, p.Name as n '
        'from WorkUnits u join Projects p on p.ProjectId = u.ProjectId '
        'where u.Details = ?',
        [WorkingHoursSink.marker],
      ))
        (
          start: fromTicks(row['s']! as int),
          end: fromTicks(row['e']! as int),
          project: '${row['n']}',
          description: '${row['d']}',
        ),
    ];
    if (ledger.isEmpty) return const [];

    // A project may be filed under another name over there; read it back
    // through the same mapping that wrote it.
    String here(String ledgerName) {
      for (final link in config.links) {
        if (link.workingHoursProject == ledgerName) return link.name;
      }
      return ledgerName;
    }

    final differences = <UnitDifference>[];
    for (final block in blocks.where((b) => b.project != null)) {
      final match = _bestMatch(ledger, block);
      if (match == null) continue;
      final difference = UnitDifference(
        block: block,
        project: here(match.project),
        description: match.description,
        start: match.start,
        end: match.end,
      );
      if (difference.differs) differences.add(difference);
    }
    Log.info(
      'read back ${differences.length} changes from '
      '${ledger.length} units this tool wrote',
    );
    return differences;
  } on SqliteException catch (error) {
    Log.error('could not read the ledger back', error);
    return const [];
  } finally {
    db?.close();
  }
}

/// Applies the chosen differences as hand edits.
void adopt(OverrideStore overrides, Iterable<UnitDifference> chosen) {
  for (final difference in chosen) {
    overrides.merge(difference.block.key, difference.asOverride);
    Log.info('adopted the ledger version of ${difference.block.key}');
  }
}

/// The unit that overlaps [block] most, or null when none does.
///
/// Matching on overlap rather than on an exact time means a row someone dragged
/// a few minutes still belongs to the block it came from.
({DateTime start, DateTime end, String project, String description})? _bestMatch(
  List<({DateTime start, DateTime end, String project, String description})> ledger,
  TrackedBlock block,
) {
  ({DateTime start, DateTime end, String project, String description})? best;
  var longest = Duration.zero;
  for (final unit in ledger) {
    final from = unit.start.isAfter(block.block.start)
        ? unit.start
        : block.block.start;
    final to = unit.end.isBefore(block.block.end) ? unit.end : block.block.end;
    final overlap = to.difference(from);
    if (overlap <= longest) continue;
    longest = overlap;
    best = unit;
  }
  return longest > Duration.zero ? best : null;
}
