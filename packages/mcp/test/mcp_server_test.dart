import 'dart:convert';
import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:aitracker_mcp/aitracker_mcp.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  // A test run has no business writing to the user's log.
  Log.enabled = false;

  late Directory temp;
  late String configPath;
  late String overridesPath;
  late McpServer server;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_mcp');
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

    AiTrackerConfig(
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
      expect(info['name'], 'aitracker');

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
          'sync_calendar',
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
      expect(AiTrackerConfig.load(configPath).rules.first.match, 'mystery');
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

    test('list_catalog reports what the apps already hold', () async {
      final wh = '${temp.path}/wh.db';
      sqlite3.open(wh)
        ..execute('''
          create table Projects (ProjectId integer primary key autoincrement not null,
            Name varchar not null, Icon varchar, Color varchar not null,
            HourlyRate float not null, Currency varchar not null, Details varchar not null,
            SortIndex integer not null, Hidden integer not null, IsLumpSum integer not null);
          create table Tags (TagId integer primary key autoincrement not null,
            Value varchar not null, Type integer not null, SortIndex integer not null,
            AutoAssign integer not null, Details varchar not null, Icon varchar,
            Color varchar not null, AdjustmentValue float not null, Hidden integer not null);
          create table ProjectTags (ProjectId integer not null, TagId integer not null);
        ''')
        ..execute(
          "insert into Projects (Name, Color, HourlyRate, Currency, Details, SortIndex, Hidden, IsLumpSum) "
          "values ('RiACT - Code', '#FF69BD0D', 0.0, 'kr', '', 1, 0, 0)",
        )
        ..execute(
          "insert into Tags (Value, Type, SortIndex, AutoAssign, Details, Color, AdjustmentValue, Hidden) "
          "values ('RiACT', 0, 1, 0, '', '#FF02F115', 0.0, 0)",
        )
        ..execute('insert into ProjectTags values (1, 1)')
        ..close();
      AiTrackerConfig.load(configPath)
          .copyWith(workingHours: WorkingHoursSinkConfig(databasePath: wh))
          .save(configPath);

      final result = await call('list_catalog');

      expect((result['projects']! as List).single, {
        'name': 'RiACT - Code',
        'hidden': false,
        'color': '#FF69BD0D',
        'company': 'RiACT',
      });
      expect(result['companies'], ['RiACT']);
    });

    test('set_project_link maps a project across the apps and keeps what it is '
        'not told', () async {
      await call('set_project_link', {
        'name': 'Byte Buddies - idbuddy',
        'working_hours': 'BB - idbuddy',
        'company': 'Byte Buddies',
        'working_hours_tags': ['Programming'],
        'calendar_label': 'idbuddy',
        'color': '#FF34D399',
      });
      await call('set_project_link', {
        'name': 'Byte Buddies - idbuddy',
        'color': '#FF6C4AB6',
      });

      final link = AiTrackerConfig.load(configPath).linkFor('Byte Buddies - idbuddy')!;
      expect(link.workingHours, 'BB - idbuddy');
      expect(link.company, 'Byte Buddies');
      expect(link.workingHoursTags, ['Programming']);
      expect(link.calendarLabel, 'idbuddy');
      expect(link.color, '#FF6C4AB6');
    });

    test('rename_project moves the rules, and the ledger when asked', () async {
      final wh = '${temp.path}/wh.db';
      sqlite3.open(wh)
        ..execute(
          'create table Projects (ProjectId integer primary key autoincrement not null, '
          'Name varchar not null, Icon varchar, Color varchar not null, '
          'HourlyRate float not null, Currency varchar not null, Details varchar not null, '
          'SortIndex integer not null, Hidden integer not null, IsLumpSum integer not null)',
        )
        ..execute(
          "insert into Projects (Name, Color, HourlyRate, Currency, Details, SortIndex, Hidden, IsLumpSum) "
          "values ('Byte Buddies - idbuddy', '#FF000000', 0.0, 'kr', '', 1, 0, 0)",
        )
        ..close();
      AiTrackerConfig.load(configPath)
          .copyWith(workingHours: WorkingHoursSinkConfig(databasePath: wh))
          .save(configPath);

      final preview = await call('rename_project', {
        'from': 'Byte Buddies - idbuddy',
        'to': 'Byte Buddies - ID Buddy',
        'in_working_hours': true,
      });
      expect(preview['applied'], isFalse);

      await call('rename_project', {
        'from': 'Byte Buddies - idbuddy',
        'to': 'Byte Buddies - ID Buddy',
        'in_working_hours': true,
        'dry_run': false,
      });

      expect(
        AiTrackerConfig.load(configPath).rules.single.project,
        'Byte Buddies - ID Buddy',
      );
      final db = sqlite3.open(wh);
      expect(
        db.select('select Name from Projects').single['Name'],
        'Byte Buddies - ID Buddy',
      );
      db.close();
    });

    test('export_spreadsheet previews before it writes', () async {
      final csv = '${temp.path}/hours.csv';
      AiTrackerConfig.load(configPath)
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

    test('sync_all files both stores in one call', () async {
      final workingHours = '${temp.path}/wh.db';
      sqlite3.open(workingHours)
        ..execute('''
          create table Settings (SettingId varchar primary key not null, Value varchar);
          create table Projects (
            ProjectId integer primary key autoincrement not null, Name varchar not null,
            Icon varchar, Color varchar not null, HourlyRate float not null,
            Currency varchar not null, Details varchar not null, SortIndex integer not null,
            Hidden integer not null, IsLumpSum integer not null);
          create table WorkUnits (
            WorkUnitId integer primary key autoincrement not null, ProjectId integer not null,
            Duration bigint not null, End bigint not null, Description varchar not null,
            Details varchar not null, Start bigint not null);
          create table Tags (
            TagId integer primary key autoincrement not null, Value varchar not null,
            Type integer not null, SortIndex integer not null, AutoAssign integer not null,
            Details varchar not null, Icon varchar, Color varchar not null,
            AdjustmentValue float not null, Hidden integer not null);
          create table WorkUnitTags (
            WorkUnitId integer not null, TagId integer not null, CustomValue varchar);
          create table ProjectTags (ProjectId integer not null, TagId integer not null);
        ''')
        ..execute("insert into Settings values ('WatchStarted', '')")
        ..close();
      AiTrackerConfig.load(configPath)
          .copyWith(
            workingHours: WorkingHoursSinkConfig(databasePath: workingHours),
            calendar: const CalendarSinkConfig(),
            tabular: TabularSinkConfig(
              enabled: true,
              csvPath: '${temp.path}/hours.csv',
              xlsxPath: '${temp.path}/hours.xlsx',
            ),
          )
          .save(configPath);

      final preview = await call('sync_all');
      expect(preview['ok'], isTrue);
      expect((preview['sinks']! as List), hasLength(2));

      final written = await call('sync_all', {'dry_run': false});

      final sinks = (written['sinks']! as List).cast<Map<String, Object?>>();
      expect(sinks.map((s) => s['sink']), ['workinghours', 'tabular']);
      expect(sinks.every((s) => s['applied'] == true), isTrue);
      final wh = sqlite3.open(workingHours);
      expect(wh.select('select * from WorkUnits'), hasLength(1));
      wh.close();
      expect(File('${temp.path}/hours.csv').existsSync(), isTrue);
    });

    test('sync_all can be narrowed to one sink', () async {
      AiTrackerConfig.load(configPath)
          .copyWith(
            tabular: TabularSinkConfig(
              enabled: true,
              csvPath: '${temp.path}/hours.csv',
              xlsxPath: '${temp.path}/hours.xlsx',
            ),
          )
          .save(configPath);

      final result = await call('sync_all', {
        'only': ['tabular'],
      });

      expect((result['sinks']! as List), hasLength(1));
    });

    test('sync_workinghours refuses a store that is not there', () async {
      AiTrackerConfig.load(configPath)
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
