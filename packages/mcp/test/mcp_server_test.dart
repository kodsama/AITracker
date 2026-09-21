import 'dart:convert';
import 'dart:io';

import 'package:aitracking_engine/aitracking_engine.dart';
import 'package:aitracking_mcp/aitracking_mcp.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String configPath;
  late String overridesPath;
  late McpServer server;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracking_mcp');
    configPath = '${temp.path}/config.json';
    overridesPath = '${temp.path}/overrides.json';

    final projects = Directory('${temp.path}/projects/p')
      ..createSync(recursive: true);
    String at(int hour, int minute) =>
        DateTime(2026, 9, 1, hour, minute).toUtc().toIso8601String();
    // One transcript per repository, which is how Claude Code stores them.
    File('${projects.path}/mapped.jsonl').writeAsStringSync(
      '{"timestamp":"${at(9, 0)}","cwd":"/Users/me/Developer/idbuddy"}\n'
      '{"timestamp":"${at(9, 30)}","cwd":"/Users/me/Developer/idbuddy"}\n',
    );
    File('${projects.path}/stray.jsonl').writeAsStringSync(
      '{"timestamp":"${at(11, 0)}","cwd":"/Users/me/Developer/mystery"}\n'
      '{"timestamp":"${at(11, 40)}","cwd":"/Users/me/Developer/mystery"}\n',
    );

    AiTrackingConfig(
      sources: ['${temp.path}/projects'],
      idleGap: const Duration(hours: 1),
      rules: const [
        ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy'),
      ],
    ).save(configPath);

    server = McpServer(
      tools: buildTools(configPath: configPath, overridesPath: overridesPath),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<Map<String, Object?>> call(
    String tool, [
    Map<String, Object?> args = const {},
  ]) async {
    final response = await server.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': tool, 'arguments': args},
    });
    final result = (response!['result']! as Map).cast<String, Object?>();
    return (result['structuredContent']! as Map).cast<String, Object?>();
  }

  group('protocol', () {
    test('announces itself and its tools', () async {
      final initialize = await server.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{},
      });
      final info =
          ((initialize!['result']! as Map)['serverInfo']! as Map)
              .cast<String, Object?>();
      expect(info['name'], 'aitracking');

      final list = await server.handle({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      });
      final tools = ((list!['result']! as Map)['tools']! as List)
          .map((t) => (t as Map)['name'])
          .toList();
      expect(
        tools,
        containsAll([
          'list_hours',
          'summarize_hours',
          'sync_workinghours',
          'sync_diarium',
          'export_spreadsheet',
          'edit_blocks',
        ]),
      );
    });

    test('answers a notification with nothing and an unknown method with an error',
        () async {
      expect(
        await server.handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
        isNull,
      );
      final response = await server.handle({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'nope',
      });
      expect((response!['error']! as Map)['code'], -32601);
    });

    test('reports an unknown tool without pretending it ran', () async {
      final response = await server.handle({
        'jsonrpc': '2.0',
        'id': 4,
        'method': 'tools/call',
        'params': {'name': 'no_such_tool', 'arguments': <String, Object?>{}},
      });
      expect((response!['error']! as Map)['code'], -32602);
    });

    test('a malformed line is a parse error, not a crash', () async {
      final response = await processLine(server, '{not json');
      expect((response!['error']! as Map)['code'], -32700);
    });
  });

  group('tools', () {
    test('list_hours reads the transcripts and keys every block', () async {
      final result = await call('list_hours');
      final blocks = (result['blocks']! as List).cast<Map<String, Object?>>();

      expect(blocks, hasLength(2));
      expect(blocks.first['project'], 'Byte Buddies - idbuddy');
      expect(blocks.first['hours'], 0.5);
      expect(blocks.first['key'], contains('/Users/me/Developer/idbuddy|'));
      expect(blocks.last['project'], isNull);
      expect(result['total_hours'], closeTo(1.17, 0.01));
    });

    test('list_hours can leave the unmapped blocks out', () async {
      final result = await call('list_hours', {'include_unmapped': false});
      expect((result['blocks']! as List), hasLength(1));
    });

    test('summarize_hours totals by project and by day', () async {
      final result = await call('summarize_hours');
      expect(result['by_project'], {'Byte Buddies - idbuddy': 0.5});
      expect(result['by_day'], {'2026-09-01': 0.5});
    });

    test('list_unmapped names the directory going nowhere', () async {
      final result = await call('list_unmapped');
      final directories =
          (result['directories']! as List).cast<Map<String, Object?>>();
      expect(directories.single['directory'], '/Users/me/Developer/mystery');
      expect(directories.single['hours'], closeTo(0.67, 0.01));
    });

    test('set_project_rule maps the stray directory, and takes effect at once',
        () async {
      await call('set_project_rule', {
        'match': 'mystery',
        'project': 'Paperweight AI - mystery',
        'first': true,
      });

      final result = await call('summarize_hours');
      expect(
        (result['by_project']! as Map).keys,
        containsAll(['Byte Buddies - idbuddy', 'Paperweight AI - mystery']),
      );
      expect(AiTrackingConfig.load(configPath).rules.first.match, 'mystery');
    });

    test('get_config reports where the configuration lives', () async {
      final result = await call('get_config');
      expect(result['path'], configPath);
      expect((result['config']! as Map)['idle_gap_minutes'], 60);
    });

    test('edit_blocks strikes blocks out in one batch, and clears them again',
        () async {
      final blocks = (await call('list_hours'))['blocks']! as List;
      final key = (blocks.first as Map)['key']! as String;

      await call('edit_blocks', {
        'keys': [key],
        'excluded': true,
      });
      expect((await call('summarize_hours'))['by_project'], isEmpty);

      await call('edit_blocks', {
        'keys': [key],
        'clear': true,
      });
      expect((await call('summarize_hours'))['by_project'], isNotEmpty);
    });

    test('edit_blocks reassigns and renames', () async {
      final blocks = (await call('list_hours'))['blocks']! as List;
      final key = (blocks.last as Map)['key']! as String;

      await call('edit_blocks', {
        'keys': [key],
        'project': 'Academie de Bernadac - AdBAI',
        'description': 'exploratory work',
      });

      final after = ((await call('list_hours'))['blocks']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((b) => b['key'] == key);
      expect(after['project'], 'Academie de Bernadac - AdBAI');
      expect(after['description'], 'exploratory work');
    });

    test('export_spreadsheet previews before it writes', () async {
      final csv = '${temp.path}/hours.csv';
      AiTrackingConfig.load(configPath)
          .copyWith(
            tabular: TabularSinkConfig(
              csvPath: csv,
              xlsxPath: '${temp.path}/hours.xlsx',
            ),
          )
          .save(configPath);

      final preview = await call('export_spreadsheet');
      expect(preview['applied'], isFalse);
      expect(File(csv).existsSync(), isFalse);

      final written = await call('export_spreadsheet', {'dry_run': false});
      expect(written['applied'], isTrue);
      expect(File(csv).readAsLinesSync(), hasLength(3));
    });

    test('sync_workinghours refuses a store that is not there', () async {
      AiTrackingConfig.load(configPath)
          .copyWith(
            workingHours: const WorkingHoursSinkConfig(
              databasePath: '/nonexistent/wh.db',
            ),
          )
          .save(configPath);

      final result = await call('sync_workinghours', {'dry_run': false});

      expect(result['ok'], isFalse);
      expect(result['refusal'], contains('no WorkingHours database'));
    });

    test('sync_diarium previews the day it would journal', () async {
      final path = '${temp.path}/diarium.db';
      sqlite3.open(path)
        ..execute(
          'create table Entries (DiaryEntryId bigint primary key not null, '
          'Heading varchar not null, Text varchar not null, '
          'Rating integer not null, Latitude float not null, '
          'Longitude float not null)',
        )
        ..close();
      AiTrackingConfig.load(configPath)
          .copyWith(diarium: DiariumSinkConfig(databasePath: path))
          .save(configPath);

      final result = await call('sync_diarium');

      expect(result['ok'], isTrue);
      expect(result['applied'], isFalse);
      expect(result['notes'], ['would create the 2026-09-01 entry']);
    });

    test('a tool that throws comes back as a tool error, not a dead server',
        () async {
      final failing = McpServer(
        tools: [
          McpTool(
            name: 'boom',
            description: 'always fails',
            inputSchema: const {'type': 'object'},
            run: (_) async => throw const FileSystemException('nope'),
          ),
        ],
      );

      final response = await failing.handle({
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'tools/call',
        'params': {'name': 'boom', 'arguments': <String, Object?>{}},
      });

      final result = (response!['result']! as Map).cast<String, Object?>();
      expect(result['isError'], isTrue);
      expect(jsonEncode(result['content']), contains('boom'));
    });
  });
}
