import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  Log.enabled = false;

  late Directory temp;
  late String path;

  TrackedBlock block({
    String project = 'Byte Buddies - idbuddy',
    String description = 'AI: idbuddy',
    DateTime? start,
    DateTime? end,
  }) => TrackedBlock(
    block: WorkBlock(
      directory: '/repo',
      start: start ?? DateTime(2026, 9, 1, 9),
      end: end ?? DateTime(2026, 9, 1, 10),
    ),
    project: project,
    description: description,
  );

  void writeUnit({
    required String project,
    required String description,
    required DateTime start,
    required DateTime end,
    String details = WorkingHoursSink.marker,
  }) {
    final db = sqlite3.open(path);
    final existing = db.select(
      'select ProjectId from Projects where Name = ?',
      [project],
    );
    final id = existing.isNotEmpty
        ? existing.first['ProjectId']! as int
        : () {
            db.execute(
              'insert into Projects (Name, Color, HourlyRate, Currency, '
              'Details, SortIndex, Hidden, IsLumpSum) '
              "values (?, '#FF000000', 0.0, 'kr', '', 1, 0, 0)",
              [project],
            );
            return db.lastInsertRowId;
          }();
    db.execute(
      'insert into WorkUnits (ProjectId, Duration, End, Description, Details, '
      'Start) values (?, ?, ?, ?, ?, ?)',
      [
        id,
        toTicks(end) - toTicks(start),
        toTicks(end),
        description,
        details,
        toTicks(start),
      ],
    );
    db.close();
  }

  AiTrackerConfig config({List<ProjectLink> links = const []}) =>
      AiTrackerConfig(
        sources: const [],
        links: links,
        workingHours: WorkingHoursSinkConfig(databasePath: path),
      );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_incoming');
    path = '${temp.path}/wh.db';
    sqlite3.open(path)
      ..execute('''
        create table Projects (ProjectId integer primary key autoincrement not null,
          Name varchar not null, Icon varchar, Color varchar not null,
          HourlyRate float not null, Currency varchar not null, Details varchar not null,
          SortIndex integer not null, Hidden integer not null, IsLumpSum integer not null);
        create table WorkUnits (WorkUnitId integer primary key autoincrement not null,
          ProjectId integer not null, Duration bigint not null, End bigint not null,
          Description varchar not null, Details varchar not null, Start bigint not null);
      ''')
      ..close();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('a unit moved to another project comes back', () {
    writeUnit(
      project: 'Paperweight AI - paperweight',
      description: 'AI: idbuddy',
      start: DateTime(2026, 9, 1, 9),
      end: DateTime(2026, 9, 1, 10),
    );

    final differences = readBack(config(), [block()]);

    expect(differences, hasLength(1));
    expect(differences.single.reassigned, isTrue);
    expect(differences.single.project, 'Paperweight AI - paperweight');
    expect(differences.single.changes.single, contains('project:'));
  });

  test('a renamed or retimed unit comes back', () {
    writeUnit(
      project: 'Byte Buddies - idbuddy',
      description: 'pairing on the importer',
      start: DateTime(2026, 9, 1, 9, 30),
      end: DateTime(2026, 9, 1, 10),
    );

    final difference = readBack(config(), [block()]).single;

    expect(difference.renamed, isTrue);
    expect(difference.retimed, isTrue);
    expect(difference.start, DateTime(2026, 9, 1, 9, 30));
    expect(difference.changes, hasLength(2));
  });

  test('a minute either way is not a change', () {
    writeUnit(
      project: 'Byte Buddies - idbuddy',
      description: 'AI: idbuddy',
      start: DateTime(2026, 9, 1, 9, 1),
      end: DateTime(2026, 9, 1, 10),
    );

    expect(readBack(config(), [block()]), isEmpty);
  });

  test('a row somebody else wrote is left alone', () {
    writeUnit(
      project: 'RiACT - Code',
      description: 'stand-up',
      start: DateTime(2026, 9, 1, 9),
      end: DateTime(2026, 9, 1, 10),
      details: '',
    );

    expect(readBack(config(), [block()]), isEmpty);
  });

  test('the ledger name is read back through the mapping', () {
    writeUnit(
      project: 'BB - idbuddy',
      description: 'AI: idbuddy',
      start: DateTime(2026, 9, 1, 9),
      end: DateTime(2026, 9, 1, 10),
    );

    final difference = readBack(
      config(
        links: const [
          ProjectLink(name: 'Byte Buddies - idbuddy', workingHours: 'BB - idbuddy'),
        ],
      ),
      [block()],
    );

    // Same project, under the name the ledger files it as: nothing to report.
    expect(difference, isEmpty);
  });

  test('the unit that overlaps most is the one that matched', () {
    writeUnit(
      project: 'Perso - FireRaccoon',
      description: 'AI: idbuddy',
      start: DateTime(2026, 9, 1, 8),
      end: DateTime(2026, 9, 1, 9, 10),
    );
    writeUnit(
      project: 'Paperweight AI - paperweight',
      description: 'AI: idbuddy',
      start: DateTime(2026, 9, 1, 9, 10),
      end: DateTime(2026, 9, 1, 10),
    );

    final difference = readBack(config(), [block()]).single;

    expect(difference.project, 'Paperweight AI - paperweight');
  });

  test('adopting writes the ledger version as a hand edit', () {
    writeUnit(
      project: 'Paperweight AI - paperweight',
      description: 'pairing',
      start: DateTime(2026, 9, 1, 9, 30),
      end: DateTime(2026, 9, 1, 10),
    );
    final overrides = OverrideStore();

    adopt(overrides, readBack(config(), [block()]));

    final override = overrides[block().key]!;
    expect(override.project, 'Paperweight AI - paperweight');
    expect(override.description, 'pairing');
    expect(override.start, DateTime(2026, 9, 1, 9, 30));
  });

  test('a difference serialises for a client', () {
    writeUnit(
      project: 'Paperweight AI - paperweight',
      description: 'pairing',
      start: DateTime(2026, 9, 1, 9, 30),
      end: DateTime(2026, 9, 1, 10),
    );

    final json = readBack(config(), [block()]).single.toJson();

    expect(json['project'], 'Paperweight AI - paperweight');
    expect(json['description'], 'pairing');
    expect(json['start'], '2026-09-01T09:30:00.000');
    expect((json['changes']! as List), hasLength(3));
    expect(json['key'], block().key);
  });

  test('a store that is not a database reads back as nothing', () {
    File(path).writeAsStringSync('not a database at all');

    expect(readBack(config(), [block()]), isEmpty);
  });

  test('nothing to read is not an error', () {
    expect(readBack(config(), []), isEmpty);
    expect(readBack(config(), [block()]), isEmpty);
    expect(
      readBack(
        const AiTrackerConfig(
          sources: [],
          workingHours: WorkingHoursSinkConfig(databasePath: '/nonexistent.db'),
        ),
        [block()],
      ),
      isEmpty,
    );
  });
}
