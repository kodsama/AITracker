import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const MacApp absent = MacApp(name: 'Absent', bundlePath: '/nonexistent');

void main() {
  late Directory temp;
  late String workingHours;
  late String diarium;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_rename');
    workingHours = '${temp.path}/wh.db';
    diarium = '${temp.path}/diarium.db';

    sqlite3.open(workingHours)
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

    sqlite3.open(diarium)
      ..execute(
        'create table Tags (DiaryTagId integer primary key autoincrement not null, '
        'Value varchar not null, Type integer not null, Color varchar, Icon varchar)',
      )
      ..execute("insert into Tags (Value, Type) values ('idbuddy', 0)")
      ..close();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  AiTrackerConfig config({List<ProjectLink> links = const []}) => AiTrackerConfig(
    sources: const [],
    rules: const [
      ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy'),
      ProjectRule(match: 'other', project: 'Elsewhere - other'),
    ],
    links: links,
    workingHours: WorkingHoursSinkConfig(databasePath: workingHours),
    diarium: DiariumSinkConfig(databasePath: diarium),
  );

  RenameResult rename(
    AiTrackerConfig from, {
    required String to,
    bool inWorkingHours = false,
    bool inDiarium = false,
    bool dryRun = false,
    OverrideStore? overrides,
  }) => renameProject(
    from,
    from: 'Byte Buddies - idbuddy',
    to: to,
    inWorkingHours: inWorkingHours,
    inDiarium: inDiarium,
    dryRun: dryRun,
    overrides: overrides,
    workingHoursApp: absent,
    diariumApp: absent,
  );

  test('renaming here alone keeps the ledger name, and writes down the link', () {
    final result = rename(config(), to: 'Byte Buddies - ID Buddy');

    expect(result.applied, isTrue);
    expect(result.config.rules.first.project, 'Byte Buddies - ID Buddy');
    // The ledger still calls it the old name, so the mapping records that.
    final link = result.config.linkFor('Byte Buddies - ID Buddy')!;
    expect(link.workingHours, 'Byte Buddies - idbuddy');
    final db = sqlite3.open(workingHours);
    expect(db.select('select Name from Projects').single['Name'], 'Byte Buddies - idbuddy');
    db.close();
  });

  test('renaming in WorkingHours moves the ledger project too', () {
    final result = rename(
      config(),
      to: 'Byte Buddies - ID Buddy',
      inWorkingHours: true,
    );

    expect(result.notes, contains('renamed the WorkingHours project "Byte Buddies - idbuddy"'));
    expect(result.config.linkFor('Byte Buddies - ID Buddy')?.workingHours, isNull);
    final db = sqlite3.open(workingHours);
    expect(db.select('select Name from Projects').single['Name'], 'Byte Buddies - ID Buddy');
    db.close();
  });

  test('renaming in Diarium moves the linked tag', () {
    final result = rename(
      config(
        links: const [
          ProjectLink(name: 'Byte Buddies - idbuddy', diariumTag: 'idbuddy'),
        ],
      ),
      to: 'ID Buddy',
      inDiarium: true,
    );

    expect(result.notes, contains('renamed the Diarium tag "idbuddy"'));
    expect(result.config.linkFor('ID Buddy')?.diariumTag, 'ID Buddy');
    final db = sqlite3.open(diarium);
    expect(db.select('select Value from Tags').single['Value'], 'ID Buddy');
    db.close();
  });

  test('hand edits naming the old project follow it', () {
    final overrides = OverrideStore()
      ..set('a|2026', const BlockOverride(project: 'Byte Buddies - idbuddy'))
      ..set('b|2026', const BlockOverride(project: 'Elsewhere - other'));

    rename(config(), to: 'ID Buddy', overrides: overrides);

    expect(overrides['a|2026']!.project, 'ID Buddy');
    expect(overrides['b|2026']!.project, 'Elsewhere - other');
  });

  test('a preview changes neither store', () {
    final result = rename(
      config(),
      to: 'ID Buddy',
      inWorkingHours: true,
      inDiarium: true,
      dryRun: true,
    );

    expect(result.applied, isFalse);
    expect(result.notes, contains('would rename the WorkingHours project "Byte Buddies - idbuddy"'));
    final db = sqlite3.open(workingHours);
    expect(db.select('select Name from Projects').single['Name'], 'Byte Buddies - idbuddy');
    db.close();
  });

  test('a rename to the same name, or to nothing, is refused', () {
    expect(rename(config(), to: 'Byte Buddies - idbuddy').refusal, 'nothing to rename');
    expect(rename(config(), to: '  ').refusal, 'nothing to rename');
  });

  test('a missing store is a refusal, not a half-done rename', () {
    final result = renameProject(
      const AiTrackerConfig(
        sources: [],
        workingHours: WorkingHoursSinkConfig(databasePath: '/nonexistent/wh.db'),
      ),
      from: 'a',
      to: 'b',
      inWorkingHours: true,
      dryRun: false,
      workingHoursApp: absent,
      diariumApp: absent,
    );

    expect(result.applied, isFalse);
    expect(result.refusal, contains('no WorkingHours database'));
  });

  test('renaming a project the ledger never saw leaves no stale pointer', () {
    final result = renameProject(
      config(),
      from: 'Elsewhere - other',
      to: 'Elsewhere - work',
      dryRun: false,
      workingHoursApp: absent,
      diariumApp: absent,
    );

    expect(result.config.linkFor('Elsewhere - work'), isNull);
    expect(result.config.rules.last.project, 'Elsewhere - work');
  });
}
