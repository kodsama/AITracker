import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';

/// How much a line matters.
enum LogLevel {
  /// Detail worth having when something is wrong.
  debug,

  /// What happened.
  info,

  /// Something was skipped or refused.
  warn,

  /// Something failed.
  error,
}

/// The log every front end writes to.
///
/// One file for the app, the CLI and the MCP server, because the interesting
/// question after the fact is what touched the timesheet, not which window was
/// open at the time.
abstract final class Log {
  /// Lines longer than this are cut; a stack trace belongs on its own lines.
  static const int maxLine = 2000;

  /// Rotated once it passes this, keeping one older file.
  static const int maxBytes = 2 * 1024 * 1024;

  /// Whether anything is written at all. Tests turn it off.
  static bool enabled = true;

  static String? _path;

  /// Where the log is kept: `~/Library/Logs/AI Tracker.log` on macOS, beside
  /// the configuration elsewhere.
  static String path() => _path ?? defaultPath();

  /// Where the log goes when nothing has said otherwise.
  static String defaultPath() {
    final home = AiTrackerConfig.homeDirectory();
    return Platform.isMacOS
        ? p.join(home, 'Library', 'Logs', 'AI Tracker.log')
        : p.join(p.dirname(AiTrackerConfig.defaultPath()), 'aitracker.log');
  }

  /// Sends the log somewhere else, which is what the tests do.
  static void useFile(String file) => _path = file;

  /// Writes one line.
  static void write(
    String message, {
    LogLevel level = LogLevel.info,
    Object? error,
  }) {
    if (!enabled) return;
    final line = StringBuffer()
      ..write(DateTime.now().toIso8601String())
      ..write('  ')
      ..write(level.name.toUpperCase().padRight(5))
      ..write(' ')
      ..write(message.length > maxLine ? message.substring(0, maxLine) : message);
    if (error != null) line.write('  <- $error');
    try {
      final file = File(path());
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        file.renameSync('${file.path}.1');
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append);
    } on FileSystemException {
      // A log that cannot be written must never take the run down with it.
    }
  }

  /// What happened.
  static void info(String message) => write(message);

  /// Something was skipped or refused.
  static void warn(String message) => write(message, level: LogLevel.warn);

  /// Something failed.
  static void error(String message, [Object? error]) =>
      write(message, level: LogLevel.error, error: error);

  /// The last [lines] of the log, oldest first.
  static List<String> tail([int lines = 200]) {
    final file = File(path());
    if (!file.existsSync()) return const [];
    try {
      final all = file.readAsLinesSync();
      return all.length <= lines ? all : all.sublist(all.length - lines);
    } on FileSystemException {
      return const [];
    }
  }

  /// Empties the log.
  static void clear() {
    final file = File(path());
    if (file.existsSync()) file.writeAsStringSync('');
  }
}
