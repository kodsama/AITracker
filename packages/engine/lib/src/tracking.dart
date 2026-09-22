import 'package:path/path.dart' as p;

import 'activity.dart';
import 'config.dart';
import 'history.dart';
import 'overrides.dart';

/// A work block with the project it bills to and the hand edits applied.
class TrackedBlock {
  /// Creates a tracked block.
  const TrackedBlock({
    required this.block,
    required this.project,
    required this.description,
    this.excluded = false,
  });

  /// The measured stretch of work.
  final WorkBlock block;

  /// Project name for the sinks, null when no rule matched.
  final String? project;

  /// Description written on the work unit.
  final String description;

  /// Whether a hand edit struck this block out.
  final bool excluded;

  /// Stable identity, as the override store keys it.
  String get key => OverrideStore.keyFor(block.directory, block.start);

  /// Folder name of the directory worked in.
  String get repo => p.basename(block.directory);

  /// Part of [project] before the separator, for projects named
  /// `Company - Project`.
  String? get company {
    final name = project;
    if (name == null) return null;
    final company = splitProjectName(name).company;
    return company.isEmpty ? null : company;
  }

  /// Local midnight of the day the block starts on.
  DateTime get day =>
      DateTime(block.start.year, block.start.month, block.start.day);

  /// Whether the block is ready to be written: mapped and not struck out.
  bool get billable => project != null && !excluded;
}

/// Reads the archive and resolves it into billable blocks.
class AiTracker {
  /// Creates a facade over [config] and the hand edits in [overrides].
  ///
  /// [history] is the archive to read; without one it is opened and closed
  /// around each call, which suits a command that runs once. Anything asking
  /// repeatedly should hold one open and pass it.
  AiTracker({
    required this.config,
    OverrideStore? overrides,
    this.history,
    this.historyPath,
  }) : overrides = overrides ?? OverrideStore();

  /// Sources, thresholds, rules and sink settings.
  final AiTrackerConfig config;

  /// Hand edits applied on top of the measurement.
  final OverrideStore overrides;

  /// An archive already open, if the caller keeps one.
  final HistoryStore? history;

  /// Where to open the archive when none was passed.
  final String? historyPath;

  /// Blocks between [since] and [until], oldest first.
  ///
  /// The transcripts are read into the archive first, so a window that reaches
  /// past what the assistant still keeps on disk is answered from what was
  /// archived when it was there.
  List<TrackedBlock> blocks({
    DateTime? since,
    DateTime? until,
    BlockMode mode = BlockMode.wallClock,
  }) {
    final store = history ?? HistoryStore.open(historyPath);
    try {
      store.ingest(config.sources);
      return [
        for (final block in store.blocks(
          from: since ?? DateTime(2000),
          to: until ?? DateTime.now().add(const Duration(days: 1)),
          idleGap: config.idleGap,
          minBlock: config.minBlock,
          mode: mode,
        ))
          resolve(block),
      ];
    } finally {
      if (history == null) store.close();
    }
  }

  /// Applies rules and hand edits to one measured [block].
  TrackedBlock resolve(WorkBlock block) {
    final override = overrides[OverrideStore.keyFor(
      block.directory,
      block.start,
    )];
    final edited = override == null
        ? block
        : block.copyWith(start: override.start, end: override.end);
    final project = override?.project ?? config.projectFor(block.directory);
    return TrackedBlock(
      block: edited,
      project: project,
      description:
          override?.description ??
          _describe(edited, project, config.workingHours.descriptionTemplate),
      excluded: override?.excluded ?? false,
    );
  }

  static String _describe(WorkBlock block, String? project, String template) {
    final name = project ?? '';
    return template
        .replaceAll('{repo}', p.basename(block.directory))
        .replaceAll('{project}', name)
        .replaceAll('{company}', splitProjectName(name).company)
        .replaceAll('{sessions}', '${block.sessions}');
  }
}

/// Total time per project, billable blocks only.
Map<String, Duration> totalsByProject(Iterable<TrackedBlock> blocks) {
  final totals = <String, Duration>{};
  for (final tracked in blocks.where((b) => b.billable)) {
    totals[tracked.project!] =
        (totals[tracked.project!] ?? Duration.zero) + tracked.block.duration;
  }
  return totals;
}

/// Total time per day, billable blocks only.
Map<DateTime, Duration> totalsByDay(Iterable<TrackedBlock> blocks) {
  final totals = <DateTime, Duration>{};
  for (final tracked in blocks.where((b) => b.billable)) {
    totals[tracked.day] =
        (totals[tracked.day] ?? Duration.zero) + tracked.block.duration;
  }
  return totals;
}

/// Directories no rule covers, with how much time each holds.
///
/// This is what turns an unmapped repository into a one-line fix instead of
/// silently missing hours.
Map<String, Duration> unmapped(Iterable<TrackedBlock> blocks) {
  final totals = <String, Duration>{};
  for (final tracked in blocks.where((b) => b.project == null)) {
    totals[tracked.block.directory] =
        (totals[tracked.block.directory] ?? Duration.zero) +
        tracked.block.duration;
  }
  return totals;
}

/// `7h 20m`, the shape a timesheet reads best.
String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}
