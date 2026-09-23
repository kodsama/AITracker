import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:aitracker/src/state/app_state.dart';
import 'package:sqlite3/sqlite3.dart';

/// A machine of its own for one test: transcripts, a configuration, an archive
/// and a WorkingHours ledger, none of them the real ones.
class Fixture {
  Fixture(this.root);

  /// Creates the folders and writes two transcripts, one mapped and one not.
  ///
  /// Home points here too, so anything looked for in the user's own folders,
  /// an editor's database among them, is looked for in this one instead and
  /// the tests say the same thing on any machine.
  factory Fixture.create() {
    final root = Directory.systemTemp.createTempSync('aitracker_app');
    AiTrackerConfig.environment = {'HOME': root.path};
    final fixture = Fixture(root);
    fixture.writeTranscripts();
    fixture.config().save(fixture.configPath);
    return fixture;
  }

  /// Where everything lives.
  final Directory root;

  /// Path of the configuration this fixture writes.
  String get configPath => '${root.path}/config.json';

  /// Path of the hand edits.
  String get overridesPath => '${root.path}/overrides.json';

  /// Path of the WorkingHours ledger, which is created on demand.
  String get ledgerPath => '${root.path}/wh.db';

  /// Two transcripts today: an hour and a half on a mapped project, and
  /// forty minutes on one no rule covers.
  void writeTranscripts() {
    final projects = Directory('${root.path}/projects/p')
      ..createSync(recursive: true);
    final today = DateTime.now();
    String at(int hour, int minute) =>
        DateTime(today.year, today.month, today.day, hour, minute)
            .toUtc()
            .toIso8601String();
    File('${projects.path}/mapped.jsonl').writeAsStringSync(
      '{"timestamp":"${at(9, 0)}","cwd":"/Users/me/Developer/idbuddy",'
      '"message":{"model":"claude-opus-5","usage":{"input_tokens":10,'
      '"output_tokens":700,"cache_creation_input_tokens":20,'
      '"cache_read_input_tokens":300}}}\n'
      '{"timestamp":"${at(10, 30)}","cwd":"/Users/me/Developer/idbuddy",'
      '"message":{"model":"claude-sonnet-5"}}\n',
    );
    File('${projects.path}/stray.jsonl').writeAsStringSync(
      '{"timestamp":"${at(13, 0)}","cwd":"/Users/me/Developer/mystery"}\n'
      '{"timestamp":"${at(13, 40)}","cwd":"/Users/me/Developer/mystery"}\n',
    );
  }

  /// The configuration: spreadsheets on, the apps off, everything temporary.
  AiTrackerConfig config({
    bool workingHours = false,
    bool calendar = false,
    bool tabular = true,
  }) => AiTrackerConfig(
    sources: ['${root.path}/projects'],
    idleGap: const Duration(hours: 2),
    rules: const [
      ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy'),
    ],
    workingHours: WorkingHoursSinkConfig(
      enabled: workingHours,
      databasePath: ledgerPath,
    ),
    calendar: CalendarSinkConfig(enabled: calendar),
    tabular: TabularSinkConfig(
      enabled: tabular,
      csvPath: '${root.path}/hours.csv',
      xlsxPath: '${root.path}/hours.xlsx',
    ),
  );

  /// A WorkingHours ledger holding [projects], with the tables this tool uses.
  void writeLedger({List<String> projects = const ['RiACT - Code']}) {
    final db = sqlite3.open(ledgerPath);
    db.execute('''
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
    ''');
    db.execute("insert into Settings values ('WatchStarted', '')");
    for (final project in projects) {
      db.execute(
        'insert into Projects (Name, Color, HourlyRate, Currency, Details, '
        "SortIndex, Hidden, IsLumpSum) values (?, '#FF112233', 0.0, 'kr', '', 1, 0, 0)",
        [project],
      );
    }
    db.close();
  }

  /// A state pointed at this fixture, scanning on the calling thread so a test
  /// can wait for it.
  AppState state() => AppState(
    configPath: configPath,
    overridesPath: overridesPath,
    background: false,
  );

  /// Removes everything.
  void dispose() {
    AiTrackerConfig.environment = Platform.environment;
    root.deleteSync(recursive: true);
  }
}
