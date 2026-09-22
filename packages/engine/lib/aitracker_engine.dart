/// Turns the transcripts an AI coding assistant leaves behind into work blocks,
/// and files them where the hours are supposed to live.
///
/// The engine is Flutter-free so the CLI, the MCP server and the desktop app
/// all run the same measurement and the same writes.
library;

export 'src/activity.dart';
export 'src/catalog.dart';
export 'src/colors.dart';
export 'src/config.dart';
export 'src/history.dart';
export 'src/log.dart';
export 'src/mac_apps.dart';
export 'src/overrides.dart';
export 'src/periods.dart';
export 'src/rename.dart';
export 'src/sinks/calendar.dart';
export 'src/sinks/incoming.dart';
export 'src/sinks/report.dart';
export 'src/sinks/sync.dart';
export 'src/sinks/tabular.dart';
export 'src/sinks/workinghours.dart';
export 'src/ticks.dart';
export 'src/token.dart';
export 'src/tracking.dart';
export 'src/worker.dart';
