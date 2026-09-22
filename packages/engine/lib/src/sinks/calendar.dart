import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config.dart';
import '../periods.dart';
import '../tracking.dart';
import 'report.dart';

/// How the engine runs the EventKit helper. Injected so tests never touch the
/// real calendar.
typedef HelperRunner =
    ProcessResult Function(String executable, List<String> arguments);

/// Publishes the hours as a macOS calendar: one all-day event per worked day,
/// titled with the day's total.
///
/// This is how the hours reach Diarium. Diarium reads system calendars as one
/// of its sources and lets you switch each one on or off in its own settings,
/// so a calendar of our own shows up there beside WorkingHours without writing
/// a single row into its journal. Apple Calendar shows the same events.
///
/// EventKit is not reachable from Dart, so the writing is done by a small Swift
/// helper built from `tool/aitracker-calendar.swift`.
class CalendarSink {
  /// Creates the sink.
  const CalendarSink({
    required this.config,
    this.links = const [],
    this.helperPath,
    this.run = Process.runSync,
  });

  /// Calendar name and title template.
  final CalendarSinkConfig config;

  /// How each project is labelled in the events.
  final List<ProjectLink> links;

  /// Helper to run.
  ///
  /// Null falls back to the configured path and then to the usual places.
  /// Empty says there is none, which is how a test reaches the not-built
  /// refusal without depending on what happens to be installed.
  final String? helperPath;

  /// Runs the helper.
  final HelperRunner run;

  /// Where the helper is looked for, in order.
  static List<String> helperCandidates() => [
    p.join(
      AiTrackerConfig.homeDirectory(),
      '.local',
      'bin',
      'aitracker-calendar',
    ),
    '/usr/local/bin/aitracker-calendar',
    p.join(p.dirname(Platform.resolvedExecutable), 'aitracker-calendar'),
    p.join(
      p.dirname(p.dirname(Platform.resolvedExecutable)),
      'Resources',
      'aitracker-calendar',
    ),
  ];

  /// The helper, or null when it has not been built.
  String? get helper {
    final chosen = helperPath ?? config.helperPath;
    if (chosen.isNotEmpty) return chosen;
    if (helperPath != null) return null;
    for (final candidate in helperCandidates()) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Publishes the calendar, or reports what it would change.
  ///
  /// Days in the window that no longer have hours lose their event, so the
  /// calendar keeps matching the transcripts rather than accumulating.
  SyncReport sync(List<TrackedBlock> blocks, {bool dryRun = true}) {
    final tool = helper;
    if (tool == null) {
      return SyncReport(
        sink: 'calendar',
        applied: false,
        refusal:
            'the calendar helper is not built; run tool/build-calendar-helper.sh',
      );
    }

    final billable = blocks.where((b) => b.billable).toList();
    final byDay = dailyTotals(billable);
    if (byDay.isEmpty) {
      return SyncReport(sink: 'calendar', applied: !dryRun);
    }

    final days = byDay.keys.toList()..sort();
    final request = {
      'calendar': config.calendarName,
      'from': _day(days.first),
      'to': _day(days.last),
      'dryRun': dryRun,
      'days': [
        for (final day in days)
          {
            'date': _day(day),
            'title': config.titleTemplate.replaceAll(
              '{hours}',
              formatDuration(bucketTotal(byDay[day]!)),
            ),
            'notes': _notes(byDay[day]!),
          },
      ],
    };

    // A fresh directory per call: two runs sharing one request file would read
    // each other's half-written JSON.
    final scratch = Directory.systemTemp.createTempSync('aitracker-calendar');
    final file = File(p.join(scratch.path, 'request.json'))
      ..writeAsStringSync(jsonEncode(request));
    final result = run(tool, [file.path]);
    try {
      scratch.deleteSync(recursive: true);
    } on FileSystemException {
      // A temp file that will not delete is not worth failing a sync over.
    }

    final output = result.stdout;
    final decoded = output is String && output.trim().isNotEmpty
        ? (jsonDecode(output) as Map).cast<String, Object?>()
        : const <String, Object?>{};
    if (decoded['ok'] != true) {
      return SyncReport(
        sink: 'calendar',
        applied: false,
        refusal:
            '${decoded['error'] ?? 'the calendar helper failed'}'
            '${result.stderr is String && (result.stderr as String).trim().isNotEmpty ? ': ${result.stderr}' : ''}',
      );
    }

    final verb = dryRun ? 'would ' : '';
    return SyncReport(
      sink: 'calendar',
      applied: !dryRun,
      written: billable,
      notes: [
        '$verb${dryRun ? 'add' : 'added'} ${decoded['created']} days, '
            '$verb${dryRun ? 'update' : 'updated'} ${decoded['updated']}, '
            '$verb${dryRun ? 'clear' : 'cleared'} ${decoded['removed']}'
            ' in "${config.calendarName}"',
        if ((decoded['unchanged'] as int? ?? 0) > 0)
          '${decoded['unchanged']} days already matched',
      ],
    );
  }

  /// The per-project breakdown, which the event carries in its notes.
  String _notes(Map<String, Duration> row) {
    final entries = row.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries)
        '${_label(entry.key)}: ${formatDuration(entry.value)}',
    ].join('\n');
  }

  String _label(String project) =>
      links.where((link) => link.name == project).firstOrNull?.calendarLabel ??
      project;

  static String _day(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
}
