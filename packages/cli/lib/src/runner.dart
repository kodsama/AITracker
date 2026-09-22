import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';

/// Usage text, printed for `help` and for anything unrecognised.
const String usage = '''
aitracker - file the hours you spend with an AI assistant

  aitracker preview [--days N] [--since DATE] [--until DATE]
      Show the blocks read out of the transcripts, and what is unmapped.

  aitracker sync [--days N] [--since DATE] [--apply] [--quit-apps]
                  [--only workinghours,diarium,tabular]
      Preview the writes, or make them with --apply. A running WorkingHours or
      Diarium is a refusal unless --quit-apps lets the run close it.

  aitracker config
      Print the configuration and where it lives.
''';

/// Runs one command. Returns the process exit code.
///
/// Output goes to [out] and [err] so the tests can read it back.
Future<int> run(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  String? configPath,
  String? overridesPath,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final command = args.isEmpty ? 'help' : args.first;
  final config = AiTrackerConfig.load(configPath);
  final tracking = AiTracker(
    config: config,
    overrides: OverrideStore.load(overridesPath),
    historyPath: HistoryStore.besideConfig(configPath),
  );
  final blocks = tracking.blocks(
    since: _since(args),
    until: _date(args, '--until'),
  );

  switch (command) {
    case 'preview':
      _preview(stdoutSink, blocks);
      return 0;

    case 'sync':
      final apply = args.contains('--apply');
      final reports = syncAll(
        config,
        blocks,
        dryRun: !apply,
        quitApps: args.contains('--quit-apps'),
        only: _list(args, '--only').toSet(),
      );
      if (reports.isEmpty) {
        stderrSink.writeln('no sink is enabled; see aitracker config');
        return 1;
      }
      var failed = false;
      for (final report in reports) {
        _report(stdoutSink, report, apply: apply);
        failed = failed || report.refusal != null;
      }
      return failed ? 1 : 0;

    case 'config':
      stdoutSink.writeln('config: ${configPath ?? AiTrackerConfig.defaultPath()}');
      stdoutSink.writeln('sources: ${config.sources.join(', ')}');
      stdoutSink.writeln(
        'idle gap: ${config.idleGap.inMinutes}m, '
        'minimum block: ${config.minBlock.inMinutes}m',
      );
      for (final rule in config.rules) {
        stdoutSink.writeln('  ${rule.match} -> ${rule.project}');
      }
      stdoutSink.writeln(
        'targets: workinghours=${config.workingHours.enabled} '
        'calendar=${config.calendar.enabled} '
        'spreadsheets=${config.tabular.enabled}',
      );
      return 0;

    case 'help':
    case '--help':
    case '-h':
      stdoutSink.write(usage);
      return 0;

    default:
      stderrSink.write(usage);
      return 64;
  }
}

void _preview(StringSink out, List<TrackedBlock> blocks) {
  if (blocks.isEmpty) {
    out.writeln('no activity in that window');
    return;
  }
  for (final block in blocks) {
    out.writeln(
      '${block.day.toIso8601String().substring(0, 10)}  '
      '${_clock(block.block.start)}-${_clock(block.block.end)}  '
      '${formatDuration(block.block.duration).padLeft(7)}  '
      '${block.project ?? '(unmapped)'}  ${block.description}',
    );
  }
  final totals = totalsByProject(blocks);
  out.writeln('');
  for (final entry in totals.entries) {
    out.writeln('${formatDuration(entry.value).padLeft(8)}  ${entry.key}');
  }
  out.writeln(
    '${formatDuration(totals.values.fold(Duration.zero, (a, b) => a + b)).padLeft(8)}  total',
  );
  final strays = unmapped(blocks);
  if (strays.isEmpty) return;
  out.writeln('\nunmapped, add a rule for these:');
  for (final entry in strays.entries) {
    out.writeln('${formatDuration(entry.value).padLeft(8)}  ${entry.key}');
  }
}

void _report(StringSink out, SyncReport report, {required bool apply}) {
  final verb = apply ? 'wrote' : 'would write';
  if (report.refusal != null) {
    out.writeln('${report.sink}: refused, ${report.refusal}');
    return;
  }
  out.writeln(
    '${report.sink}: $verb ${report.written.length} blocks, '
    '${formatDuration(report.total)}'
    '${report.skipped.isEmpty ? '' : ', skipped ${report.skipped.length} already logged'}',
  );
  for (final note in report.notes) {
    out.writeln('  $note');
  }
  for (final output in report.outputs) {
    out.writeln('  $output');
  }
  if (report.backup != null) out.writeln('  backup: ${report.backup}');
}

List<String> _list(List<String> args, String flag) {
  final value = _value(args, flag);
  if (value == null) return const [];
  return value.split(',').map((s) => s.trim()).toList();
}

DateTime? _since(List<String> args) {
  final since = _date(args, '--since');
  if (since != null) return since;
  final days = int.tryParse(_value(args, '--days') ?? '');
  if (days == null) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
}

DateTime? _date(List<String> args, String flag) {
  final value = _value(args, flag);
  return value == null ? null : DateTime.tryParse(value);
}

String? _value(List<String> args, String flag) {
  final index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';
