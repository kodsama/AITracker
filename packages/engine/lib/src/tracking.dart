import 'package:path/path.dart' as p;

import 'activity.dart';
import 'config.dart';
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
    if (name == null || !name.contains(' - ')) return null;
    return name.split(' - ').first.trim();
  }

  /// Local midnight of the day the block starts on.
  DateTime get day =>
      DateTime(block.start.year, block.start.month, block.start.day);

  /// Whether the block is ready to be written: mapped and not struck out.
  bool get billable => project != null && !excluded;
}

/// Reads transcripts and resolves them into billable blocks.
class AiTracking {
  /// Creates a facade over [config] and the hand edits in [overrides].
  AiTracking({required this.config, OverrideStore? overrides})
    : overrides = overrides ?? OverrideStore();

  /// Sources, thresholds, rules and sink settings.
  final AiTrackingConfig config;

  /// Hand edits applied on top of the measurement.
  final OverrideStore overrides;

  /// Blocks between [since] and [until], oldest first.
  List<TrackedBlock> blocks({DateTime? since, DateTime? until}) {
    final events = TranscriptScanner(config.sources).scan(since: since);
    final measured = buildBlocks(
      events,
      idleGap: config.idleGap,
      minBlock: config.minBlock,
    );
    final result = <TrackedBlock>[];
    for (final block in measured) {
      if (until != null && !block.start.isBefore(until)) continue;
      result.add(resolve(block));
    }
    return result;
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
        .replaceAll('{company}', name.contains(' - ') ? name.split(' - ').first : '')
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
