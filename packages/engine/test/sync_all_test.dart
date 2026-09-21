import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  // A test run has no business writing to the user's log.
  Log.enabled = false;

  late Directory temp;
  late AiTrackerConfig config;

  final blocks = [
    TrackedBlock(
      block: WorkBlock(
        directory: '/repo',
        start: DateTime(2026, 9, 1, 9),
        end: DateTime(2026, 9, 1, 10),
      ),
      project: 'Byte Buddies - idbuddy',
      description: 'AI: repo',
    ),
  ];

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_sync');
    sqlite3.open('${temp.path}/wh.db')
      ..execute('''
        create table Settings (SettingId varchar primary key not null, Value varchar);
        create table Projects (ProjectId integer primary key autoincrement not null,
          Name varchar not null, Icon varchar, Color varchar not null,
          HourlyRate float not null, Currency varchar not null, Details varchar not null,
          SortIndex integer not null, Hidden integer not null, IsLumpSum integer not null);
        create table WorkUnits (WorkUnitId integer primary key autoincrement not null,
          ProjectId integer not null, Duration bigint not null, End bigint not null,
          Description varchar not null, Details varchar not null, Start bigint not null);
        create table Tags (TagId integer primary key autoincrement not null,
          Value varchar not null, Type integer not null, SortIndex integer not null,
          AutoAssign integer not null, Details varchar not null, Icon varchar,
          Color varchar not null, AdjustmentValue float not null, Hidden integer not null);
        create table WorkUnitTags (WorkUnitId integer not null, TagId integer not null,
          CustomValue varchar);
        create table ProjectTags (ProjectId integer not null, TagId integer not null);
      ''')
      ..execute("insert into Settings values ('WatchStarted', '')")
      ..close();

    config = AiTrackerConfig(
      sources: const [],
      workingHours: WorkingHoursSinkConfig(databasePath: '${temp.path}/wh.db'),
      calendar: const CalendarSinkConfig(enabled: true),
      tabular: TabularSinkConfig(
        enabled: true,
        csvPath: '${temp.path}/hours.csv',
        xlsxPath: '${temp.path}/hours.xlsx',
      ),
    );
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('files everything enabled in one pass', () {
    final reports = syncAll(config, blocks, dryRun: false);

    expect(reports.map((r) => r.sink), kSinkNames);
    // The calendar needs its EventKit helper, which a test machine may not
    // have built; the other two are pure file work and must have run.
    expect(reports.first.applied, isTrue);
    expect(reports.last.applied, isTrue);
    final db = sqlite3.open('${temp.path}/wh.db');
    expect(db.select('select * from WorkUnits'), hasLength(1));
    db.close();
    expect(File('${temp.path}/hours.csv').existsSync(), isTrue);
  });

  test('a preview touches none of them', () {
    final reports = syncAll(config, blocks);

    expect(reports.every((r) => r.applied), isFalse);
    final db = sqlite3.open('${temp.path}/wh.db');
    expect(db.select('select * from WorkUnits'), isEmpty);
    db.close();
    expect(File('${temp.path}/hours.csv').existsSync(), isFalse);
  });

  test('a disabled sink is left out', () {
    final reports = syncAll(
      config.copyWith(calendar: const CalendarSinkConfig()),
      blocks,
    );

    expect(reports.map((r) => r.sink), ['workinghours', 'tabular']);
  });

  test('only narrows the run', () {
    final reports = syncAll(config, blocks, only: {'tabular'});

    expect(reports.single.sink, 'tabular');
  });

  test('one sink refusing leaves the others reported', () {
    final reports = syncAll(
      config.copyWith(
        workingHours: const WorkingHoursSinkConfig(
          databasePath: '/nonexistent/wh.db',
        ),
      ),
      blocks,
      dryRun: false,
    );

    expect(reports.first.refusal, contains('no WorkingHours database'));
    expect(reports.last.applied, isTrue);
  });

  group('project names', () {
    test('a company and a project make the ledger name', () {
      expect(
        composeProjectName('Byte Buddies', 'idbuddy'),
        'Byte Buddies - idbuddy',
      );
      expect(composeProjectName('', 'idbuddy'), 'idbuddy');
      expect(composeProjectName('Byte Buddies', ''), 'Byte Buddies');
      expect(composeProjectName(' Byte Buddies ', ' idbuddy '), 'Byte Buddies - idbuddy');
    });

    test('and split back, first separator only', () {
      expect(splitProjectName('Byte Buddies - idbuddy'), (
        company: 'Byte Buddies',
        project: 'idbuddy',
      ));
      // A project with its own separator keeps its whole name.
      expect(splitProjectName('Byte Buddies - idbuddy - web'), (
        company: 'Byte Buddies',
        project: 'idbuddy - web',
      ));
      expect(splitProjectName('idbuddy'), (company: '', project: 'idbuddy'));
    });
  });

  group('ProjectLink', () {
    test('defaults the ledger name to its own, and round trips', () {
      const plain = ProjectLink(name: 'Byte Buddies - idbuddy');
      expect(plain.workingHoursProject, 'Byte Buddies - idbuddy');

      const full = ProjectLink(
        name: 'Byte Buddies - idbuddy',
        workingHours: 'BB - idbuddy',
        company: 'Byte Buddies',
        workingHoursTags: ['Programming'],
        calendarLabel: 'idbuddy',
        color: '#FF34D399',
      );
      final copy = ProjectLink.fromJson(full.toJson());

      expect(copy.workingHoursProject, 'BB - idbuddy');
      expect(copy.company, 'Byte Buddies');
      expect(copy.workingHoursTags, ['Programming']);
      expect(copy.calendarLabel, 'idbuddy');
      expect(copy.color, '#FF34D399');
      expect(copy.copyWith(color: '#FF000000').color, '#FF000000');
    });

    test('rides along in the configuration file', () {
      final path = '${temp.path}/config.json';
      config
          .copyWith(
            links: const [
              ProjectLink(name: 'A - a', workingHours: 'B', calendarLabel: 'c'),
            ],
          )
          .save(path);

      final loaded = AiTrackerConfig.load(path);

      expect(loaded.linkFor('A - a')?.workingHours, 'B');
      expect(loaded.linkFor('A - a')?.calendarLabel, 'c');
      expect(loaded.linkFor('missing'), isNull);
    });
  });
}
