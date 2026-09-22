import 'dart:io';

import 'package:aitracker/src/state/app_state.dart';
import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart' show Brightness, Color, Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'fixture.dart';

void main() {
  Log.enabled = false;

  late Fixture fixture;
  late AppState state;

  setUp(() async {
    fixture = Fixture.create();
    state = fixture.state();
    await state.load();
  });

  tearDown(() {
    state.dispose();
    fixture.dispose();
  });

  test('a load reads the transcripts into blocks', () {
    expect(state.blocks, hasLength(2));
    expect(state.loading, isFalse);
    expect(state.reading, isFalse);
    expect(state.trouble, isNull);
    expect(state.byProject.keys, ['Byte Buddies - idbuddy']);
    expect(state.total, const Duration(minutes: 90));
    expect(state.wallClock, const Duration(minutes: 130));
    expect(state.tokens.total, 1030);
    expect(state.strays.keys, ['/Users/me/Developer/mystery']);
  });

  test('the window can be stepped and named', () async {
    await state.setPeriod(PeriodKind.today);
    expect(state.blocks, hasLength(2));

    await state.stepPeriod(-1);
    expect(state.periodStep, -1);
    expect(state.blocks, isEmpty);

    await state.setPeriod(PeriodKind.thisMonth);
    expect(state.periodStep, 0);
  });

  test('counting per project is a swap, not another read', () {
    final before = state.blocks.length;

    state.setMode(CountMode.perProject);

    expect(state.mode, CountMode.perProject);
    expect(state.blocks.length, greaterThanOrEqualTo(before));
    state.setMode(CountMode.wallClock);
    expect(state.blocks.length, before);
  });

  test('the filter and the search narrow the same list', () {
    state.setFilter(BlockFilter.unmapped);
    expect(state.blocks.single.project, isNull);
    expect(state.filterCounts[BlockFilter.mapped], 1);

    state.setFilter(BlockFilter.all);
    state.setQuery('idbuddy');
    expect(state.blocks, hasLength(1));

    state.setQuery('nothing at all');
    expect(state.blocks, isEmpty);
    state.setQuery('');
  });

  test('selection follows what is on screen', () {
    state.toggleAll();
    expect(state.selected, hasLength(2));
    state.toggleAll();
    expect(state.selected, isEmpty);

    final block = state.blocks.first;
    state.toggle(block.key);
    expect(state.selected, {block.key});
    state.toggle(block.key);
    expect(state.selected, isEmpty);

    state.selectDay(block.day);
    expect(state.selected, hasLength(2));
    state.selectNone();
    expect(state.selected, isEmpty);

    state.selectWeek(block.day);
    expect(state.selected, hasLength(2));
    state.selectNone();
  });

  test('a hand edit survives the next read, and can be taken back', () async {
    final key = state.blocks.first.key;
    state.toggle(key);

    await state.editSelected(const BlockOverride(project: 'Perso - mine'));
    expect(
      state.blocks.firstWhere((b) => b.key == key).project,
      'Perso - mine',
    );
    expect(state.overrideFor(key), isNotNull);

    await state.clearSelectedEdits();
    expect(state.overrideFor(key), isNull);
  });

  test('a mapping is saved and read back', () async {
    await state.saveLink(
      const ProjectLink(
        name: 'Byte Buddies - idbuddy',
        company: 'Byte Buddies',
        color: '#FF6C4AB6',
      ),
    );

    expect(state.config.linkFor('Byte Buddies - idbuddy')?.company, 'Byte Buddies');
    expect(state.knownCompanies, contains('Byte Buddies'));
    expect(
      state.colorFor('Byte Buddies - idbuddy', Brightness.dark),
      const Color(0xFF6C4AB6),
    );
  });

  test('a project with no colour of its own takes one from the palette', () {
    final colour = state.colorFor('Byte Buddies - idbuddy', Brightness.light);
    final unmapped = state.colorFor(unmappedLabel, Brightness.light);

    expect(colour, isNot(Colors.transparent));
    expect(unmapped, isNot(colour));
  });

  test('the ledger colour is used when the mapping has none', () async {
    fixture.writeLedger(projects: ['Byte Buddies - idbuddy']);
    await state.save(fixture.config(workingHours: true));

    expect(
      state.colorFor('Byte Buddies - idbuddy', Brightness.dark),
      const Color(0xFF112233),
    );
    expect(state.catalog.projects, hasLength(1));
  });

  test('renaming carries the rules and the hand edits with it', () async {
    final key = state.blocks.first.key;
    state.toggle(key);
    await state.editSelected(
      const BlockOverride(project: 'Byte Buddies - idbuddy'),
    );

    final result = await state.rename(
      'Byte Buddies - idbuddy',
      'Byte Buddies - ID',
    );

    expect(result.applied, isTrue);
    expect(state.config.rules.single.project, 'Byte Buddies - ID');
    expect(state.overrideFor(key)?.project, 'Byte Buddies - ID');
  });

  test('colours can be compared with the ledger and taken either way', () async {
    fixture.writeLedger(projects: ['Byte Buddies - idbuddy']);
    await state.save(fixture.config(workingHours: true));

    final differences = state.colourDifferences();
    expect(differences.single.there, '#FF112233');

    await state.importColors({'Byte Buddies - idbuddy'});
    expect(
      state.config.linkFor('Byte Buddies - idbuddy')?.color,
      '#FF112233',
    );

    await state.saveLink(
      const ProjectLink(name: 'Byte Buddies - idbuddy', color: '#FF445566'),
    );
    final report = await state.exportColors({'Byte Buddies - idbuddy'});

    expect(report.applied, isTrue);
    final db = sqlite3.open(fixture.ledgerPath);
    expect(db.select('select Color from Projects').single['Color'], '#FF445566');
    db.close();
  });

  test('an export previews, then writes what was asked for', () async {
    final preview = await state.export(apply: false);
    expect(preview.single.sink, 'tabular');
    expect(preview.single.applied, isFalse);
    expect(File('${fixture.root.path}/hours.csv').existsSync(), isFalse);

    final written = await state.export(apply: true);

    expect(written.single.applied, isTrue);
    expect(File('${fixture.root.path}/hours.csv').readAsLinesSync(), hasLength(3));
  });

  test('what the ledger had done to a unit comes back', () async {
    fixture.writeLedger(projects: ['Moved elsewhere']);
    await state.save(fixture.config(workingHours: true));
    final block = state.blocks.firstWhere((b) => b.project != null);
    final db = sqlite3.open(fixture.ledgerPath);
    db.execute(
      'insert into WorkUnits (ProjectId, Duration, End, Description, Details, '
      'Start) values (1, 0, ?, ?, ?, ?)',
      [
        toTicks(block.block.end),
        'moved by hand',
        WorkingHoursSink.marker,
        toTicks(block.block.start),
      ],
    );
    db.close();

    final changes = state.readBackFromLedger();
    expect(changes.single.project, 'Moved elsewhere');

    await state.adoptFromLedger(changes);

    expect(
      state.blocks.firstWhere((b) => b.key == block.key).project,
      'Moved elsewhere',
    );
    // Nothing to take is not a write.
    await state.adoptFromLedger(const []);
  });

  test('scanning in its own isolate gives the same answer', () async {
    final background = AppState(
      configPath: fixture.configPath,
      overridesPath: fixture.overridesPath,
    );
    addTearDown(background.dispose);

    await background.load();

    expect(background.blocks, hasLength(2));
    expect(background.allBlocks, hasLength(2));
    // And again, off the archive rather than the transcripts.
    await background.refresh();
    expect(background.blocks, hasLength(2));
  });

  test('a target that cannot file itself says so instead of failing', () async {
    await state.save(
      fixture.config().copyWith(
        workingHours: const WorkingHoursSinkConfig(
          enabled: true,
          automatic: true,
          databasePath: '/nonexistent/wh.db',
        ),
      ),
    );

    expect(state.lastAutomatic.first.refusal, contains('no WorkingHours'));
  });

  test('the archive says what it holds', () {
    final summary = state.archive();

    expect(summary.events, 4);
    expect(summary.files, 2);
    expect(state.historyPath, endsWith('history.db'));
  });

  test('the key is issued once and can be replaced', () async {
    final first = state.mcpToken;

    expect(first, isNotEmpty);
    expect(state.mcpToken, first);
    expect(await state.regenerateMcpToken(), isNot(first));
  });

  test('the endpoint opens and closes on the setting', () async {
    expect(state.mcpPort, isNull);

    await state.save(fixture.config().copyWith(mcpEnabled: true, mcpPort: 0));
    expect(state.mcpPort, isNotNull);

    await state.save(fixture.config().copyWith(mcpEnabled: false));
    expect(state.mcpPort, isNull);
  });

  test('a port already taken is reported rather than thrown', () async {
    final held = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(held.close);

    await state.save(
      fixture.config().copyWith(mcpEnabled: true, mcpPort: held.port),
    );

    expect(state.trouble, contains('Could not listen'));
  });

  test('hours stay after the transcripts they came from are gone', () async {
    Directory('${fixture.root.path}/projects').deleteSync(recursive: true);

    await state.refresh();

    // The archive is the record; losing the folder loses nothing.
    expect(state.blocks, hasLength(2));
    expect(state.trouble, isNull);
    expect(state.archive().events, 4);
  });

  test('a source that never existed reads as nothing', () async {
    final empty = Fixture(Directory.systemTemp.createTempSync('aitracker_none'));
    addTearDown(empty.dispose);
    empty.config().copyWith(sources: ['${empty.root.path}/nothing']).save(
      empty.configPath,
    );
    final other = empty.state();
    addTearDown(other.dispose);

    await other.load();

    expect(other.blocks, isEmpty);
    expect(other.trouble, isNull);
  });

  test('the targets set to file themselves run after a read', () async {
    await state.save(
      fixture.config().copyWith(
        tabular: TabularSinkConfig(
          enabled: true,
          automatic: true,
          csvPath: '${fixture.root.path}/auto.csv',
          xlsxPath: '${fixture.root.path}/auto.xlsx',
        ),
      ),
    );

    expect(state.lastAutomatic.single.sink, 'tabular');
    expect(File('${fixture.root.path}/auto.csv').existsSync(), isTrue);
  });
}
