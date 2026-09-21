import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String workingHours;
  late String diarium;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_catalog');
    workingHours = '${temp.path}/wh.db';
    diarium = '${temp.path}/diarium.db';

    sqlite3.open(workingHours)
      ..execute('''
        create table Projects (
          ProjectId integer primary key autoincrement not null, Name varchar not null,
          Icon varchar, Color varchar not null, HourlyRate float not null,
          Currency varchar not null, Details varchar not null, SortIndex integer not null,
          Hidden integer not null, IsLumpSum integer not null);
        create table Tags (
          TagId integer primary key autoincrement not null, Value varchar not null,
          Type integer not null, SortIndex integer not null, AutoAssign integer not null,
          Details varchar not null, Icon varchar, Color varchar not null,
          AdjustmentValue float not null, Hidden integer not null);
        create table ProjectTags (ProjectId integer not null, TagId integer not null);
      ''')
      ..execute(
        "insert into Projects (Name, Color, HourlyRate, Currency, Details, SortIndex, Hidden, IsLumpSum) "
        "values ('RiACT - Code', '#FF69BD0D', 0.0, 'kr', '', 1, 0, 0), "
        "('Sigma - Axis Camera', '#FF410006', 0.0, 'kr', '', 2, 1, 0)",
      )
      ..execute(
        "insert into Tags (Value, Type, SortIndex, AutoAssign, Details, Color, AdjustmentValue, Hidden) "
        "values ('RiACT', 0, 1, 0, '', '#FF02F115', 0.0, 0), "
        "('Programming', 0, 2, 0, '', '#FF8F020C', 0.0, 0), "
        "('Retired', 0, 3, 0, '', '#FF000000', 0.0, 1)",
      )
      ..execute('insert into ProjectTags values (1, 1)')
      ..close();

    sqlite3.open(diarium)
      ..execute(
        'create table Tags (DiaryTagId integer primary key autoincrement not null, '
        'Value varchar not null, Type integer not null, Color varchar, Icon varchar)',
      )
      ..execute("insert into Tags (Value, Type) values ('Work', 0), ('Travel', 0)")
      ..close();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  AiTrackerConfig config() => AiTrackerConfig(
    sources: const [],
    workingHours: WorkingHoursSinkConfig(databasePath: workingHours),
    diarium: DiariumSinkConfig(databasePath: diarium),
  );

  test('reads the projects, their colours and whether they are archived', () {
    final catalog = Catalog.read(config());

    expect(catalog.projects.map((p) => p.name), [
      'RiACT - Code',
      'Sigma - Axis Camera',
    ]);
    expect(catalog.projects.first.color, '#FF69BD0D');
    expect(catalog.projects.first.hidden, isFalse);
    expect(catalog.projects.last.hidden, isTrue);
  });

  test('a customer is the tag the ledger hangs on a project', () {
    final catalog = Catalog.read(config());

    expect(catalog.customers, ['RiACT']);
    expect(catalog.projects.first.customer, 'RiACT');
    expect(catalog.projects.last.customer, isNull);
  });

  test('reads every tag, archived ones included, and the journal tags too', () {
    final catalog = Catalog.read(config());

    expect(catalog.tags.map((t) => t.value), [
      'Programming',
      'Retired',
      'RiACT',
    ]);
    expect(catalog.tags.firstWhere((t) => t.value == 'Retired').hidden, isTrue);
    expect(catalog.diariumTags.map((t) => t.value), ['Travel', 'Work']);
  });

  test('a missing or broken store reads as empty rather than failing', () {
    final empty = Catalog.read(
      const AiTrackerConfig(
        sources: [],
        workingHours: WorkingHoursSinkConfig(databasePath: '/nonexistent/wh.db'),
        diarium: DiariumSinkConfig(databasePath: '/nonexistent/d.db'),
      ),
    );
    expect(empty.projects, isEmpty);
    expect(empty.diariumTags, isEmpty);

    final junk = '${temp.path}/junk.db';
    File(junk).writeAsStringSync('not a database');
    final broken = Catalog.read(
      AiTrackerConfig(
        sources: const [],
        workingHours: WorkingHoursSinkConfig(databasePath: junk),
        diarium: DiariumSinkConfig(databasePath: junk),
      ),
    );
    expect(broken.projects, isEmpty);
    expect(broken.diariumTags, isEmpty);
  });

  test('serialises for a client', () {
    final json = Catalog.read(config()).toJson();

    expect((json['projects']! as List).first, {
      'name': 'RiACT - Code',
      'hidden': false,
      'color': '#FF69BD0D',
      'customer': 'RiACT',
    });
    expect(json['customers'], ['RiACT']);
  });

  group('colours', () {
    test('are pushed into the ledger, and previewed first', () {
      final sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: workingHours),
        links: const [
          ProjectLink(name: 'RiACT - Code', color: '#FF6C4AB6'),
          ProjectLink(name: 'Gone - Missing', color: '#FF112233'),
        ],
        app: const MacApp(name: 'Absent', bundlePath: '/nonexistent'),
      );

      expect(sink.applyColors().notes.first, contains('would colour'));
      final db = sqlite3.open(workingHours);
      expect(
        db.select("select Color from Projects where Name = 'RiACT - Code'").single['Color'],
        '#FF69BD0D',
      );
      db.close();

      final report = sink.applyColors(dryRun: false);

      expect(report.applied, isTrue);
      expect(report.notes, [
        'coloured "RiACT - Code" #FF6C4AB6',
        'no project "Gone - Missing" to colour',
      ]);
      final after = sqlite3.open(workingHours);
      expect(
        after.select("select Color from Projects where Name = 'RiACT - Code'").single['Color'],
        '#FF6C4AB6',
      );
      after.close();
    });

    test('a project this tool creates is drawn in its linked colour', () {
      sqlite3.open(workingHours)
        ..execute('''
          create table Settings (SettingId varchar primary key not null, Value varchar);
          create table WorkUnits (
            WorkUnitId integer primary key autoincrement not null, ProjectId integer not null,
            Duration bigint not null, End bigint not null, Description varchar not null,
            Details varchar not null, Start bigint not null);
          create table WorkUnitTags (
            WorkUnitId integer not null, TagId integer not null, CustomValue varchar);
        ''')
        ..execute("insert into Settings values ('WatchStarted', '')")
        ..close();
      final sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: workingHours),
        links: const [
          ProjectLink(name: 'Byte Buddies - idbuddy', color: '#FF34D399'),
        ],
        app: const MacApp(name: 'Absent', bundlePath: '/nonexistent'),
      );

      sink.sync([
        TrackedBlock(
          block: WorkBlock(
            directory: '/repo',
            start: DateTime(2026, 9, 1, 9),
            end: DateTime(2026, 9, 1, 10),
          ),
          project: 'Byte Buddies - idbuddy',
          description: 'AI: repo',
        ),
      ], dryRun: false);

      final db = sqlite3.open(workingHours);
      expect(
        db
            .select("select Color from Projects where Name = 'Byte Buddies - idbuddy'")
            .single['Color'],
        '#FF34D399',
      );
      db.close();
    });
  });
}
