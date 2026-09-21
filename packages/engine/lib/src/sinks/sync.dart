import '../config.dart';
import '../tracking.dart';
import 'diarium.dart';
import 'report.dart';
import 'tabular.dart';
import 'workinghours.dart';

/// Every sink this build knows how to write, in the order a run touches them.
const List<String> kSinkNames = ['workinghours', 'diarium', 'tabular'];

/// Runs every enabled sink over the same blocks in one pass.
///
/// WorkingHours and Diarium are independent stores, so filing to both is one
/// operation rather than two runs of one: each closes and reopens its own app
/// as needed, and a refusal from one leaves the other's report intact.
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

  return [
    if (wanted('workinghours'))
      WorkingHoursSink(
        config: config.workingHours,
        links: config.links,
        minBlock: config.minBlock,
      ).sync(blocks, dryRun: dryRun, quitApp: quitApps),
    if (wanted('diarium'))
      DiariumSink(
        config: config.diarium,
        links: config.links,
      ).sync(blocks, dryRun: dryRun, quitApp: quitApps),
    if (wanted('tabular'))
      TabularSink(config: config.tabular).sync(blocks, dryRun: dryRun),
  ];
}

bool _enabled(AiTrackerConfig config, String sink) => switch (sink) {
  'workinghours' => config.workingHours.enabled,
  'diarium' => config.diarium.enabled,
  'tabular' => config.tabular.enabled,
  _ => false,
};
