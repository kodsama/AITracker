import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

void main() {
  Log.enabled = false;

  late Directory temp;
  late ScanWorker worker;
  late AiTrackerConfig config;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('aitracker_worker');
    final projects = Directory('${temp.path}/projects/p')
      ..createSync(recursive: true);
    File('${projects.path}/a.jsonl').writeAsStringSync(
      '{"timestamp":"2026-09-01T07:00:00.000Z","cwd":"/Users/me/idbuddy"}\n'
      '{"timestamp":"2026-09-01T07:30:00.000Z","cwd":"/Users/me/idbuddy"}\n',
    );
    File('${projects.path}/b.jsonl').writeAsStringSync(
      '{"timestamp":"2026-09-01T11:00:00.000Z","cwd":"/Users/me/mystery"}\n'
      '{"timestamp":"2026-09-01T11:40:00.000Z","cwd":"/Users/me/mystery"}\n',
    );
    config = AiTrackerConfig(
      sources: ['${temp.path}/projects'],
      idleGap: const Duration(hours: 1),
      rules: const [
        ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy'),
      ],
    );
    worker = await ScanWorker.start(
      logging: true,
      logFile: '${temp.path}/log.txt',
      historyPath: '${temp.path}/history.db',
    );
  });

  tearDown(() async {
    await worker.stop();
    temp.deleteSync(recursive: true);
  });

  Period window() => periodFor(
    PeriodKind.custom,
    start: DateTime(2026, 9),
    end: DateTime(2026, 9, 30),
  );

  test('starting it without being told where to log is allowed', () async {
    final quiet = await ScanWorker.start(
      logging: false,
      historyPath: '${temp.path}/quiet.db',
    );
    addTearDown(quiet.stop);

    final result = await quiet.scan(
      config: config,
      overrides: OverrideStore(),
      window: window(),
    );

    expect(result.wallClock, hasLength(2));
  });

  test('returns both readings, resolved through the rules', () async {
    final result = await worker.scan(
      config: config,
      overrides: OverrideStore(),
      window: window(),
    );

    expect(result.wallClock, hasLength(2));
    expect(result.wallClock.first.project, 'Byte Buddies - idbuddy');
    expect(result.wallClock.last.project, isNull);
    expect(result.perProject, hasLength(2));
  });

  test('carries the hand edits across the isolate', () async {
    final first = await worker.scan(
      config: config,
      overrides: OverrideStore(),
      window: window(),
    );
    final overrides = OverrideStore()
      ..set(
        first.wallClock.last.key,
        const BlockOverride(project: 'Perso - mystery'),
      );

    final second = await worker.scan(
      config: config,
      overrides: overrides,
      window: window(),
    );

    expect(second.wallClock.last.project, 'Perso - mystery');
  });

  test('answers several scans in the order they were asked', () async {
    final results = await Future.wait([
      worker.scan(
        config: config,
        overrides: OverrideStore(),
        window: window(),
      ),
      worker.scan(
        config: config,
        overrides: OverrideStore(),
        window: periodFor(
          PeriodKind.custom,
          start: DateTime(2026, 9),
          end: DateTime(2026, 9),
        ),
      ),
    ]);

    expect(results.first.wallClock, hasLength(2));
    expect(results.last.wallClock, hasLength(2));
  });

  test('a second scan reads nothing new off disk', () async {
    await worker.scan(
      config: config,
      overrides: OverrideStore(),
      window: window(),
    );
    Log.useFile('${temp.path}/log.txt');
    final afterFirst = Log.tail().length;

    await worker.scan(
      config: config,
      overrides: OverrideStore(),
      window: window(),
    );

    // The archive only speaks up when it took something in.
    expect(Log.tail().length, afterFirst);
    expect(File('${temp.path}/history.db').existsSync(), isTrue);
  });

  test('a request it cannot read comes back as the reason, not a crash', () {
    final history = HistoryStore.open('${temp.path}/direct.db');
    addTearDown(history.close);

    final answer = ScanWorker.respond([
      1,
      config.toJson(),
      <String, Object?>{},
      'not a date',
      DateTime(2026, 10).toIso8601String(),
      true,
    ], history);

    expect(answer, isA<String>());
    expect(answer as String, contains('not a date'));
  });

  test('a request it can read comes back as both readings', () {
    final history = HistoryStore.open('${temp.path}/direct.db');
    addTearDown(history.close);

    final answer = ScanWorker.respond([
      1,
      config.toJson(),
      <String, Object?>{},
      DateTime(2026, 9).toIso8601String(),
      DateTime(2026, 10).toIso8601String(),
      true,
      0,
    ], history);

    expect(answer, isA<ScanResult>());
    expect((answer as ScanResult).wallClock, hasLength(2));
    // Nothing was asked to be worked out ahead, so nothing is outstanding.
    expect(answer.unworked, 0);
  });

  test('a request can work out days no window asked for', () {
    // Work in July as well, which the window below does not cover: those are
    // the days there would otherwise be nothing stored for.
    File('${temp.path}/projects/p/c.jsonl').writeAsStringSync(
      '{"timestamp":"2026-07-01T07:00:00.000Z","cwd":"/Users/me/idbuddy"}\n'
      '{"timestamp":"2026-07-01T07:30:00.000Z","cwd":"/Users/me/idbuddy"}\n',
    );
    final history = HistoryStore.open('${temp.path}/warm.db');
    addTearDown(history.close);

    ScanResult ask(int warm) =>
        ScanWorker.respond([
              1,
              config.toJson(),
              <String, Object?>{},
              DateTime(2026, 9).toIso8601String(),
              DateTime(2026, 10).toIso8601String(),
              true,
              warm,
            ], history)
            as ScanResult;

    // One day at a time, so there is something left after the first round.
    expect(ask(1).unworked, greaterThan(0));
    var left = ask(1).unworked;
    while (left > 0) {
      left = ask(1).unworked;
    }

    // And once everything is worked out, nothing is asked for again.
    expect(ask(40).unworked, 0);
  });

  test('a stopped worker answers nothing rather than hanging', () async {
    await worker.stop();

    final result = await worker.scan(
      config: config,
      overrides: OverrideStore(),
      window: window(),
    );

    expect(result.wallClock, isEmpty);
  });
}
