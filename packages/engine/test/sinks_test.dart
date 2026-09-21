import 'dart:io';

import 'package:aitracking_engine/aitracking_engine.dart';
import 'package:excel/excel.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// An app bundle that is certainly not running, so the sinks' "quit first"
/// guard does not depend on what the machine happens to have open.
const MacApp absent = MacApp(name: 'Absent', bundlePath: '/nonexistent');

TrackedBlock tracked({
  required DateTime start,
  required DateTime end,
  String project = 'Byte Buddies - idbuddy',
  String directory = '/Users/me/Developer/idbuddy',
  String description = 'AI: idbuddy',
  bool excluded = false,
}) => TrackedBlock(
  block: WorkBlock(directory: directory, start: start, end: end),
  project: project,
  description: description,
  excluded: excluded,
);

String workingHoursDb(Directory temp, {String? timerStartedAt}) {
  final path = '${temp.path}/wh.db';
  final db = sqlite3.open(path);
  db.execute('''
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
  ''');
  db.execute("insert into Settings values ('WatchStarted', ?)", [timerStartedAt ?? '']);
  db.execute(
    "insert into Projects (Name, Color, HourlyRate, Currency, Details, SortIndex, Hidden, IsLumpSum) "
    "values ('RiACT - Code', '#FF69BD0D', 0.0, 'kr', '', 1, 0, 0)",
  );
  db.close();
  return path;
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('aitracking'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('subtractBusy', () {
    final block = tracked(
      start: DateTime(2026, 9, 1, 9),
      end: DateTime(2026, 9, 1, 12),
    );

    test('drops a block the store already covers end to end', () {
      final left = subtractBusy(block, [
        (start: DateTime(2026, 9, 1, 8), end: DateTime(2026, 9, 1, 13)),
      ], const Duration(minutes: 5));

      expect(left, isEmpty);
    });

    test('keeps the uncovered remainder', () {
      final left = subtractBusy(block, [
        (start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10)),
      ], const Duration(minutes: 5));

      expect(left, hasLength(1));
      expect(left.single.block.start, DateTime(2026, 9, 1, 10));
      expect(left.single.block.end, DateTime(2026, 9, 1, 12));
    });

    test('splits around a meeting in the middle', () {
      final left = subtractBusy(block, [
        (start: DateTime(2026, 9, 1, 10), end: DateTime(2026, 9, 1, 11)),
      ], const Duration(minutes: 5));

      expect(left.map((b) => b.block.start), [
        DateTime(2026, 9, 1, 9),
        DateTime(2026, 9, 1, 11),
      ]);
    });

    test('throws away a remainder below the minimum', () {
      final left = subtractBusy(block, [
        (start: DateTime(2026, 9, 1, 9, 2), end: DateTime(2026, 9, 1, 13)),
      ], const Duration(minutes: 5));

      expect(left, isEmpty);
    });

    test('leaves a block that does not touch the busy range', () {
      final left = subtractBusy(block, [
        (start: DateTime(2026, 9, 1, 13), end: DateTime(2026, 9, 1, 14)),
      ], const Duration(minutes: 5));

      expect(left.single.block.duration, const Duration(hours: 3));
    });
  });

  group('WorkingHoursSink', () {
    test('refuses when the database is missing', () {
      const sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: '/nonexistent/wh.db'),
        app: absent,
      );

      final report = sink.sync([], dryRun: false);

      expect(report.applied, isFalse);
      expect(report.refusal, contains('no WorkingHours database'));
    });

    test('refuses while a timer is running', () {
      final path = workingHoursDb(temp, timerStartedAt: '639251000000000000');
      final sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: path),
        app: absent,
      );

      final report = sink.sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10)),
      ], dryRun: false);

      expect(report.applied, isFalse);
      expect(report.refusal, contains('timer is running'));
    });

    test('a preview writes nothing and names the project it would create', () {
      final path = workingHoursDb(temp);
      final sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: path),
        app: absent,
      );

      final report = sink.sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10)),
      ]);

      expect(report.applied, isFalse);
      expect(report.written, hasLength(1));
      expect(report.notes, ['would create project "Byte Buddies - idbuddy"']);
      final db = sqlite3.open(path);
      expect(db.select('select * from WorkUnits'), isEmpty);
      db.close();
    });

    test('writes the unit, creates the project, and backs the store up', () {
      final path = workingHoursDb(temp);
      final sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: path),
        app: absent,
      );

      final report = sink.sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10, 30)),
      ], dryRun: false);

      expect(report.applied, isTrue);
      expect(report.total, const Duration(hours: 1, minutes: 30));
      expect(File(report.backup!).existsSync(), isTrue);

      final db = sqlite3.open(path);
      final unit = db.select('select * from WorkUnits').single;
      expect(fromTicks(unit['Start']! as int), DateTime(2026, 9, 1, 9));
      expect(fromTicks(unit['End']! as int), DateTime(2026, 9, 1, 10, 30));
      expect(unit['Duration'], (unit['End']! as int) - (unit['Start']! as int));
      expect(unit['Description'], 'AI: idbuddy');
      expect(unit['Details'], WorkingHoursSink.marker);
      final project = db
          .select('select * from Projects where Name = ?', ['Byte Buddies - idbuddy'])
          .single;
      // The currency comes from the projects already in the ledger.
      expect(project['Currency'], 'kr');
      expect(unit['ProjectId'], project['ProjectId']);
      db.close();
    });

    test('skips time the ledger already holds, whatever project it sits under', () {
      final path = workingHoursDb(temp);
      final db = sqlite3.open(path);
      db.execute(
        'insert into WorkUnits (ProjectId, Duration, End, Description, Details, Start) '
        'values (1, 0, ?, ?, ?, ?)',
        [
          toTicks(DateTime(2026, 9, 1, 10)),
          'stand-up',
          '',
          toTicks(DateTime(2026, 9, 1, 9)),
        ],
      );
      db.close();
      final sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: path),
        app: absent,
      );

      final report = sink.sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 11)),
      ], dryRun: false);

      expect(report.written, hasLength(1));
      expect(report.written.single.block.start, DateTime(2026, 9, 1, 10));
      final after = sqlite3.open(path);
      expect(after.select('select * from WorkUnits'), hasLength(2));
      after.close();
    });

    test('reports a block as skipped when the ledger covers all of it', () {
      final path = workingHoursDb(temp);
      final db = sqlite3.open(path);
      db.execute(
        'insert into WorkUnits (ProjectId, Duration, End, Description, Details, Start) '
        'values (1, 0, ?, ?, ?, ?)',
        [
          toTicks(DateTime(2026, 9, 1, 12)),
          'all day',
          '',
          toTicks(DateTime(2026, 9, 1, 8)),
        ],
      );
      db.close();
      final sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: path),
        app: absent,
      );

      final report = sink.sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 11)),
      ], dryRun: false);

      expect(report.written, isEmpty);
      expect(report.skipped, hasLength(1));
      expect(report.backup, isNull);
    });

    test('leaves unmapped and excluded blocks alone', () {
      final path = workingHoursDb(temp);
      final sink = WorkingHoursSink(
        config: WorkingHoursSinkConfig(databasePath: path),
        app: absent,
      );

      final report = sink.sync([
        TrackedBlock(
          block: WorkBlock(
            directory: '/x',
            start: DateTime(2026, 9, 1, 9),
            end: DateTime(2026, 9, 1, 10),
          ),
          project: null,
          description: 'unmapped',
        ),
        tracked(
          start: DateTime(2026, 9, 1, 11),
          end: DateTime(2026, 9, 1, 12),
          excluded: true,
        ),
      ], dryRun: false);

      expect(report.written, isEmpty);
      final db = sqlite3.open(path);
      expect(db.select('select * from WorkUnits'), isEmpty);
      db.close();
    });
  });

  group('DiariumSink', () {
    String diariumDb() {
      final path = '${temp.path}/diarium.db';
      final db = sqlite3.open(path);
      db.execute(
        'create table Entries (DiaryEntryId bigint primary key not null, '
        'Heading varchar not null, Text varchar not null, Rating integer not null, '
        'Latitude float not null, Longitude float not null)',
      );
      db.close();
      return path;
    }

    test('writes one entry per day, carrying its own marker', () {
      final path = diariumDb();
      final sink = DiariumSink(
        config: DiariumSinkConfig(databasePath: path, entryTimeOfDay: '23:55'),
        app: absent,
      );

      sink.sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10)),
        tracked(start: DateTime(2026, 9, 1, 11), end: DateTime(2026, 9, 1, 11, 30)),
        tracked(start: DateTime(2026, 9, 2, 9), end: DateTime(2026, 9, 2, 10)),
      ], dryRun: false);

      final db = sqlite3.open(path);
      final entries = db.select('select * from Entries order by DiaryEntryId');
      expect(entries, hasLength(2));
      expect(fromTicks(entries.first['DiaryEntryId']! as int), DateTime(2026, 9, 1, 23, 55));
      expect(entries.first['Heading'], 'AI hours');
      expect(entries.first['Text'], contains('Byte Buddies - idbuddy: 1h 30m'));
      expect(entries.first['Text'], contains('Total: 1h 30m'));
      expect(entries.first['Text'], contains(DiariumSink.marker));
      db.close();
    });

    test('rewrites its own entry instead of adding a second one', () {
      final path = diariumDb();
      final sink = DiariumSink(
        config: DiariumSinkConfig(databasePath: path),
        app: absent,
      );
      final block = tracked(
        start: DateTime(2026, 9, 1, 9),
        end: DateTime(2026, 9, 1, 10),
      );

      sink.sync([block], dryRun: false);
      final report = sink.sync([
        block,
        tracked(start: DateTime(2026, 9, 1, 11), end: DateTime(2026, 9, 1, 12)),
      ], dryRun: false);

      final db = sqlite3.open(path);
      expect(db.select('select * from Entries'), hasLength(1));
      expect(db.select('select Text from Entries').single['Text'], contains('Total: 2h 0m'));
      db.close();
      expect(report.notes.single, contains('updated'));
    });

    test('steps past an entry the user wrote at the same minute', () {
      final path = diariumDb();
      final db = sqlite3.open(path);
      db.execute('insert into Entries values (?, ?, ?, 0, 0.0, 0.0)', [
        toTicks(DateTime(2026, 9, 1, 23, 55)),
        'Dinner',
        '<p>mine</p>',
      ]);
      db.close();
      final sink = DiariumSink(
        config: DiariumSinkConfig(databasePath: path),
        app: absent,
      );

      sink.sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10)),
      ], dryRun: false);

      final after = sqlite3.open(path);
      final entries = after.select('select * from Entries order by DiaryEntryId');
      expect(entries, hasLength(2));
      expect(entries.first['Heading'], 'Dinner');
      expect(fromTicks(entries.last['DiaryEntryId']! as int), DateTime(2026, 9, 1, 23, 56));
      after.close();
    });

    test('a preview writes nothing', () {
      final path = diariumDb();
      final sink = DiariumSink(
        config: DiariumSinkConfig(databasePath: path),
        app: absent,
      );

      final report = sink.sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10)),
      ]);

      expect(report.applied, isFalse);
      expect(report.notes.single, contains('would create the 2026-09-01 entry'));
      final db = sqlite3.open(path);
      expect(db.select('select * from Entries'), isEmpty);
      db.close();
    });

    test('refuses when the database is missing, and shrugs at an empty day', () {
      const missing = DiariumSink(
        config: DiariumSinkConfig(databasePath: '/nonexistent/d.db'),
        app: absent,
      );
      expect(missing.sync([]).refusal, contains('no Diarium database'));

      final sink = DiariumSink(
        config: DiariumSinkConfig(databasePath: diariumDb()),
        app: absent,
      );
      expect(sink.sync([], dryRun: false).applied, isTrue);
    });
  });

  group('TabularSink', () {
    TabularSink sinkInto(Directory dir) => TabularSink(
      config: TabularSinkConfig(
        csvPath: '${dir.path}/hours.csv',
        xlsxPath: '${dir.path}/hours.xlsx',
      ),
    );

    test('writes every non-excluded block to both formats', () {
      final report = sinkInto(temp).sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10, 30)),
        tracked(
          start: DateTime(2026, 9, 1, 11),
          end: DateTime(2026, 9, 1, 12),
          excluded: true,
        ),
      ], dryRun: false);

      expect(report.applied, isTrue);
      expect(report.outputs, hasLength(2));

      final lines = File('${temp.path}/hours.csv').readAsLinesSync();
      expect(lines.first, TabularSink.columns.join(','));
      expect(lines, hasLength(2));
      expect(
        lines[1],
        '2026-09-01,09:00,10:30,1.50,1h 30m,Byte Buddies,'
        'Byte Buddies - idbuddy,AI: idbuddy,idbuddy,1',
      );

      final book = Excel.decodeBytes(File('${temp.path}/hours.xlsx').readAsBytesSync());
      final sheet = book['AI hours'];
      expect(sheet.rows, hasLength(2));
      expect(sheet.rows[1][3]!.value, const DoubleCellValue(1.5));
    });

    test('keeps unmapped blocks, with the project column empty', () {
      sinkInto(temp).sync([
        TrackedBlock(
          block: WorkBlock(
            directory: '/Users/me/mystery',
            start: DateTime(2026, 9, 1, 9),
            end: DateTime(2026, 9, 1, 10),
          ),
          project: null,
          description: 'AI: mystery',
        ),
      ], dryRun: false);

      final lines = File('${temp.path}/hours.csv').readAsLinesSync();
      expect(lines[1], '2026-09-01,09:00,10:00,1.00,1h 0m,,,AI: mystery,mystery,1');
    });

    test('quotes a description holding a comma', () {
      sinkInto(temp).sync([
        tracked(
          start: DateTime(2026, 9, 1, 9),
          end: DateTime(2026, 9, 1, 10),
          description: 'AI: idbuddy, take two',
        ),
      ], dryRun: false);

      expect(
        File('${temp.path}/hours.csv').readAsLinesSync()[1],
        contains('"AI: idbuddy, take two"'),
      );
    });

    test('a preview names the files it would write', () {
      final report = sinkInto(temp).sync([
        tracked(start: DateTime(2026, 9, 1, 9), end: DateTime(2026, 9, 1, 10)),
      ]);

      expect(report.applied, isFalse);
      expect(report.notes, hasLength(2));
      expect(File('${temp.path}/hours.csv').existsSync(), isFalse);
    });
  });
}
