import 'dart:io';

import 'package:aitracker/src/measures.dart';
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

  group('what is already worked out', () {
    test('a scan works out every day the archive covers, not just the window',
        () async {
      // Work two months before the window the app opens on.
      final projects = Directory('${fixture.root.path}/projects/p');
      final old = DateTime.now().subtract(const Duration(days: 60));
      String at(int hour) =>
          DateTime(old.year, old.month, old.day, hour).toUtc().toIso8601String();
      File('${projects.path}/older.jsonl').writeAsStringSync(
        '{"timestamp":"${at(9)}","cwd":"/Users/me/Developer/idbuddy"}\n'
        '{"timestamp":"${at(11)}","cwd":"/Users/me/Developer/idbuddy"}\n',
      );

      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      // It gets there a slice at a time, and the slice is a stated size.
      expect(AppState.warmSlice, greaterThan(0));

      // Nothing is left to work out, whatever window is asked for next.
      final store = HistoryStore.open(state.historyPath);
      addTearDown(store.close);
      expect(
        store.warm(
          idleGap: state.config.idleGap,
          minBlock: state.config.minBlock,
          limit: 0,
        ),
        0,
      );

      // And that older window is served from what is stored.
      await state.setPeriod(
        PeriodKind.custom,
        start: DateTime(old.year, old.month, old.day),
        end: DateTime(old.year, old.month, old.day),
      );
      expect(state.blocks, hasLength(1));
    });
  });

  group('holding it all', () {
    /// Work sixty days ago as well as today, so there is history outside the
    /// window the app opens on.
    DateTime writeOlder() {
      final old = DateTime.now().subtract(const Duration(days: 60));
      String at(int hour) =>
          DateTime(old.year, old.month, old.day, hour).toUtc().toIso8601String();
      File('${fixture.root.path}/projects/p/older.jsonl').writeAsStringSync(
        '{"timestamp":"${at(9)}","cwd":"/Users/me/Developer/idbuddy"}\n'
        '{"timestamp":"${at(11)}","cwd":"/Users/me/Developer/idbuddy"}\n',
      );
      return DateTime(old.year, old.month, old.day);
    }

    test('every block is held, whatever window is on screen', () async {
      writeOlder();
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      // The window shows today's work; what is held covers the older day too.
      expect(state.blocks, hasLength(2));
      expect(state.everyBlock.length, greaterThan(state.blocks.length));
      // And what is read is everything there is, not a window over it.
      expect(AppState.everything.contains(DateTime(2001)), isTrue);
      expect(AppState.everything.contains(DateTime(2099)), isTrue);
    });

    test('changing the window reads nothing back', () async {
      final old = writeOlder();
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      // With the archive gone there is nothing left to read, so anything the
      // window shows after this was already in hand.
      File(state.historyPath).deleteSync();

      await state.setPeriod(
        PeriodKind.custom,
        start: old,
        end: old,
      );

      expect(state.blocks, hasLength(1));
      expect(state.blocks.single.block.start.day, old.day);

      await state.setPeriod(PeriodKind.thisMonth);
      expect(state.blocks, hasLength(2));
    });

    test('stepping the window and switching the count read nothing back', () async {
      writeOlder();
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();
      File(state.historyPath).deleteSync();

      final held = state.everyBlock.length;

      await state.stepPeriod(-1);
      await state.stepPeriod(1);

      // Back where it started, with nothing lost and nothing fetched.
      expect(state.blocks, hasLength(2));
      expect(state.everyBlock, hasLength(held));

      state.setMode(CountMode.perProject);
      expect(state.blocks, hasLength(2));
      expect(state.everyBlock, isNotEmpty);
    });
  });

  group('what the next run opens on', () {
    test('the window, the count and the measure outlive the app', () async {
      final first = fixture.state();
      await first.load();
      await first.setPeriod(PeriodKind.thisYear);
      first.setMode(CountMode.perProject);
      first.setMeasure(Measure.tokens);
      first.dispose();

      final second = fixture.state();
      addTearDown(second.dispose);
      await second.load();

      expect(second.periodKind, PeriodKind.thisYear);
      expect(second.mode, CountMode.perProject);
      expect(second.measure, Measure.tokens);
      // And it is where the window starts, not just what it is called.
      expect(second.period.start, DateTime(DateTime.now().year));
    });

    test('a custom window keeps both its dates', () async {
      final first = fixture.state();
      await first.load();
      await first.setPeriod(
        PeriodKind.custom,
        start: DateTime(2026, 3, 1),
        end: DateTime(2026, 3, 31),
      );
      first.dispose();

      final second = fixture.state();
      addTearDown(second.dispose);
      await second.load();

      expect(second.periodKind, PeriodKind.custom);
      expect(second.period.start, DateTime(2026, 3, 1));
      expect(second.period.end.isAfter(DateTime(2026, 3, 31)), isTrue);
    });

    test('a configuration naming no window opens on this month', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      expect(state.periodKind, PeriodKind.thisMonth);
      expect(AiTrackerConfig.load(fixture.configPath).view.toJson(), isEmpty);
    });

    test('a window it does not recognise is not one it opens on', () async {
      final config = AiTrackerConfig.load(fixture.configPath);
      config
          .copyWith(view: const ViewConfig(period: 'lastFortnight', mode: 'x'))
          .save(fixture.configPath);

      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      expect(state.periodKind, PeriodKind.thisMonth);
      expect(state.mode, CountMode.wallClock);
    });

    test('going back writes the window it went back to', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();
      await state.setPeriod(PeriodKind.thisYear);

      await state.goBack();

      expect(
        AiTrackerConfig.load(fixture.configPath).view.period,
        PeriodKind.thisMonth.name,
      );
    });
  });

  group('going back', () {
    test('a screen is remembered, and back returns to it', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      expect(state.canGoBack, isFalse);
      expect(state.canGoForward, isFalse);

      state.goTo(Screen.graphs);
      expect(state.screen, Screen.graphs);
      expect(state.canGoBack, isTrue);

      await state.goBack();
      expect(state.screen, Screen.hours);
      expect(state.canGoBack, isFalse);
      expect(state.canGoForward, isTrue);

      await state.goForward();
      expect(state.screen, Screen.graphs);
      expect(state.canGoForward, isFalse);
    });

    test('opening the same screen again is not a move', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      state.goTo(Screen.hours);

      expect(state.canGoBack, isFalse);
    });

    test('a day opened from the graphs is one move back to the graphs', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();
      state.goTo(Screen.graphs);
      final was = state.period;

      await state.openDay(DateTime(2026, 9, 14));

      expect(state.screen, Screen.hours);
      expect(state.period.start, DateTime(2026, 9, 14));

      await state.goBack();

      expect(state.screen, Screen.graphs);
      expect(state.period.start, was.start);
      expect(state.period.end, was.end);
    });

    test('the window, the filter, the mode and the measure all come back',
        () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      await state.setPeriod(PeriodKind.thisWeek);
      state.setFilter(BlockFilter.unmapped);
      state.setMode(CountMode.perProject);
      state.setMeasure(Measure.tokens);

      await state.goBack();
      expect(state.measure, Measure.time);
      await state.goBack();
      expect(state.mode, CountMode.wallClock);
      await state.goBack();
      expect(state.filter, BlockFilter.all);
      await state.goBack();
      expect(state.periodKind, PeriodKind.thisMonth);
      expect(state.canGoBack, isFalse);
    });

    test('stepping the window is a move of its own', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      await state.stepPeriod(-1);
      expect(state.periodStep, -1);

      await state.goBack();

      expect(state.periodStep, 0);
    });

    test('typing leaves one entry, not one per letter', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      for (final query in ['u', 'un', 'unm', 'unmapped']) {
        state.setQuery(query);
      }
      expect(state.query, 'unmapped');

      await state.goBack();

      expect(state.query, '');
      expect(state.canGoBack, isFalse);
    });

    test('a new move throws away what forward was holding', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      state.goTo(Screen.graphs);
      await state.goBack();
      expect(state.canGoForward, isTrue);

      state.goTo(Screen.settings);

      expect(state.canGoForward, isFalse);
    });

    test('back and forward at the ends do nothing', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      await state.goBack();
      await state.goForward();

      expect(state.screen, Screen.hours);
      expect(state.canGoBack, isFalse);
    });

    test('it remembers a stated number of moves and no more', () async {
      final state = fixture.state();
      addTearDown(state.dispose);
      await state.load();

      for (var i = 0; i <= AppState.historyDepth + 10; i++) {
        state.goTo(i.isEven ? Screen.graphs : Screen.hours);
      }
      var steps = 0;
      while (state.canGoBack) {
        await state.goBack();
        steps++;
      }

      expect(steps, AppState.historyDepth);
    });
  });
}
