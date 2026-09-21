import 'dart:io';

import 'package:aitracking_cli/aitracking_cli.dart';
import 'package:aitracking_engine/aitracking_engine.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String configPath;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracking_cli');
    configPath = '${temp.path}/config.json';
    out = StringBuffer();
    err = StringBuffer();

    final projects = Directory('${temp.path}/projects/p')
      ..createSync(recursive: true);
    String at(int hour, int minute) =>
        DateTime(2026, 9, 1, hour, minute).toUtc().toIso8601String();
    File('${projects.path}/mapped.jsonl').writeAsStringSync(
      '{"timestamp":"${at(9, 0)}","cwd":"/Users/me/Developer/idbuddy"}\n'
      '{"timestamp":"${at(10, 30)}","cwd":"/Users/me/Developer/idbuddy"}\n',
    );
    File('${projects.path}/stray.jsonl').writeAsStringSync(
      '{"timestamp":"${at(13, 0)}","cwd":"/Users/me/Developer/mystery"}\n'
      '{"timestamp":"${at(13, 40)}","cwd":"/Users/me/Developer/mystery"}\n',
    );

    AiTrackingConfig(
      sources: ['${temp.path}/projects'],
      idleGap: const Duration(hours: 2),
      rules: const [
        ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy'),
      ],
      workingHours: const WorkingHoursSinkConfig(enabled: false),
      tabular: TabularSinkConfig(
        enabled: true,
        csvPath: '${temp.path}/hours.csv',
        xlsxPath: '${temp.path}/hours.xlsx',
      ),
    ).save(configPath);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<int> cli(List<String> args) =>
      run(args, out: out, err: err, configPath: configPath,
          overridesPath: '${temp.path}/overrides.json');

  test('preview lists the blocks, the totals and what is unmapped', () async {
    expect(await cli(['preview']), 0);

    expect(out.toString(), contains('09:00-10:30'));
    expect(out.toString(), contains('Byte Buddies - idbuddy'));
    expect(out.toString(), contains('1h 30m  total'));
    expect(out.toString(), contains('unmapped, add a rule for these'));
    expect(out.toString(), contains('/Users/me/Developer/mystery'));
  });

  test('preview says so when the window is empty', () async {
    expect(await cli(['preview', '--since', '2030-01-01']), 0);
    expect(out.toString().trim(), 'no activity in that window');
  });

  test('sync previews without touching anything', () async {
    expect(await cli(['sync']), 0);

    expect(out.toString(), contains('tabular: would write 2 blocks'));
    expect(File('${temp.path}/hours.csv').existsSync(), isFalse);
  });

  test('sync --apply writes the enabled sinks only', () async {
    expect(await cli(['sync', '--apply']), 0);

    expect(out.toString(), contains('tabular: wrote 2 blocks'));
    expect(out.toString(), isNot(contains('workinghours')));
    expect(File('${temp.path}/hours.csv').readAsLinesSync(), hasLength(3));
  });

  test('--only narrows the run, and an empty set is an error', () async {
    expect(await cli(['sync', '--only', 'diarium']), 1);
    expect(err.toString(), contains('no sink is enabled'));
  });

  test('a refusal is reported and sets the exit code', () async {
    AiTrackingConfig.load(configPath)
        .copyWith(
          workingHours: const WorkingHoursSinkConfig(
            databasePath: '/nonexistent/wh.db',
          ),
          tabular: const TabularSinkConfig(),
        )
        .save(configPath);

    expect(await cli(['sync', '--apply', '--only', 'workinghours']), 1);
    expect(out.toString(), contains('refused, no WorkingHours database'));
  });

  test('--days looks back from today', () async {
    expect(await cli(['preview', '--days', '1']), 0);
    expect(out.toString().trim(), 'no activity in that window');
  });

  test('config prints where things live and which sinks are on', () async {
    expect(await cli(['config']), 0);

    expect(out.toString(), contains(configPath));
    expect(out.toString(), contains('idbuddy -> Byte Buddies - idbuddy'));
    expect(out.toString(), contains('workinghours=false'));
  });

  test('help explains itself, an unknown command complains', () async {
    expect(await cli(['help']), 0);
    expect(out.toString(), contains('aitracking preview'));

    expect(await cli(['nonsense']), 64);
    expect(err.toString(), contains('aitracking sync'));
  });
}
