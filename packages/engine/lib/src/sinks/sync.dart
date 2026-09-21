import '../config.dart';
import '../log.dart';
import '../tracking.dart';
import 'calendar.dart';
import 'report.dart';
import 'tabular.dart';
import 'workinghours.dart';

/// Every sink this build knows how to write, in the order a run touches them.
const List<String> kSinkNames = ['workinghours', 'calendar', 'tabular'];

/// Runs every enabled sink over the same blocks in one pass.
///
/// The targets are independent, so exporting to all of them is one operation
/// rather than three runs of one: WorkingHours closes and reopens its own app
/// as needed, and a refusal from one leaves the others' reports intact.
///
/// [only] narrows the run to the named sinks; an empty set means all of them.
/// Nothing is written unless [dryRun] is false.
List<SyncReport> syncAll(
  AiTrackerConfig config,
  List<TrackedBlock> blocks, {
  bool dryRun = true,
  bool quitApps = false,
  Set<String> only = const {},
}) {
  bool wanted(String sink) =>
      (only.isEmpty || only.contains(sink)) && _enabled(config, sink);

  Log.info(
    '${dryRun ? 'preview' : 'export'} of ${blocks.length} blocks to '
    '${only.isEmpty ? kSinkNames.where((s) => _enabled(config, s)).join(', ') : only.join(', ')}',
  );
  return [
    if (wanted('workinghours'))
      _logged(
        WorkingHoursSink(
          config: config.workingHours,
          links: config.links,
          minBlock: config.minBlock,
        ).sync(blocks, dryRun: dryRun, quitApp: quitApps),
      ),
    if (wanted('calendar'))
      _logged(
        CalendarSink(
          config: config.calendar,
          links: config.links,
        ).sync(blocks, dryRun: dryRun),
      ),
    if (wanted('tabular'))
      _logged(TabularSink(config: config.tabular).sync(blocks, dryRun: dryRun)),
  ];
}

/// Records what a sink reported, so the log holds the same story the dialog
/// showed.
SyncReport _logged(SyncReport report) {
  if (report.refusal != null) {
    Log.warn('${report.sink}: refused, ${report.refusal}');
  } else {
    Log.info(
      '${report.sink}: ${report.applied ? 'wrote' : 'would write'} '
      '${report.written.length} blocks'
      '${report.skipped.isEmpty ? '' : ', skipped ${report.skipped.length}'}'
      '${report.notes.isEmpty ? '' : ' (${report.notes.join('; ')})'}',
    );
  }
  return report;
}

bool _enabled(AiTrackerConfig config, String sink) => switch (sink) {
  'workinghours' => config.workingHours.enabled,
  'calendar' => config.calendar.enabled,
  'tabular' => config.tabular.enabled,
  _ => false,
};
