import 'dart:io';

import 'package:aitracker/main.dart';
import 'package:aitracker/src/state/app_state.dart';
import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A test run has no business writing to the user's log.
  Log.enabled = false;

  late Directory temp;
  late String configPath;
  late String overridesPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_app');
    configPath = '${temp.path}/config.json';
    overridesPath = '${temp.path}/overrides.json';

    final projects = Directory('${temp.path}/projects/p')
      ..createSync(recursive: true);
    final today = DateTime.now();
    String at(int hour, int minute) =>
        DateTime(today.year, today.month, today.day, hour, minute)
            .toUtc()
            .toIso8601String();
    File('${projects.path}/mapped.jsonl').writeAsStringSync(
      '{"timestamp":"${at(9, 0)}","cwd":"/Users/me/Developer/idbuddy"}\n'
      '{"timestamp":"${at(10, 30)}","cwd":"/Users/me/Developer/idbuddy"}\n',
    );
    File('${projects.path}/stray.jsonl').writeAsStringSync(
      '{"timestamp":"${at(13, 0)}","cwd":"/Users/me/Developer/mystery"}\n'
      '{"timestamp":"${at(13, 40)}","cwd":"/Users/me/Developer/mystery"}\n',
    );

    AiTrackerConfig(
      sources: ['${temp.path}/projects'],
      idleGap: const Duration(hours: 2),
      rules: const [
        ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy'),
      ],
      // Point the stores at files that do not exist, so a test never reads the
      // real WorkingHours or Diarium on this machine.
      workingHours: WorkingHoursSinkConfig(
        enabled: false,
        databasePath: '${temp.path}/wh.db',
      ),
      calendar: const CalendarSinkConfig(),
      tabular: TabularSinkConfig(
        enabled: true,
        csvPath: '${temp.path}/hours.csv',
        xlsxPath: '${temp.path}/hours.xlsx',
      ),
    ).save(configPath);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<AppState> pump(WidgetTester tester) async {
    // A desktop window, which is the only place this app runs.
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(
      configPath: configPath,
      overridesPath: overridesPath,
      background: false,
    );
    await tester.pumpWidget(AiTrackerApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('shows the hours, the projects and what is unmapped', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('1h 30m'), findsWidgets);
    expect(find.text('Byte Buddies - idbuddy'), findsWidgets);
    expect(find.text('unmapped'), findsOneWidget);
    expect(
      find.textContaining('no rule covers', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('selecting a block opens the batch bar and excluding it drops '
      'the total', (tester) async {
    final state = await pump(tester);

    // The list runs newest first, so the mapped morning block is the last row.
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Exclude'));
    await tester.pumpAndSettle();

    expect(state.total, Duration.zero);
    expect(OverrideStore.load(overridesPath).entries, hasLength(1));
  });

  testWidgets('a batch edit reassigns every selected block', (tester) async {
    final state = await pump(tester);

    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assign project'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Paperweight AI - x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(state.byProject.keys, contains('Paperweight AI - x'));
  });

  testWidgets('mapping the stray directory from the Projects screen', (
    tester,
  ) async {
    final state = await pump(tester);

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    expect(find.text('/Users/me/Developer/mystery'), findsOneWidget);

    await tester.tap(find.text('Map it'));
    await tester.pumpAndSettle();
    // Company and project are separate fields, as WorkingHours models them.
    await tester.enterText(find.byType(TextField).at(1), 'Academie');
    await tester.enterText(find.byType(TextField).at(2), 'AdBAI');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(state.strays, isEmpty);
    expect(
      AiTrackerConfig.load(configPath).rules.map((r) => r.project),
      contains('Academie - AdBAI'),
    );
    // The company rides along into the mapping, since the ledger tags it.
    expect(
      AiTrackerConfig.load(configPath).linkFor('Academie - AdBAI')?.company,
      'Academie',
    );
  });

  testWidgets('the archive keeps the hours after the transcripts go', (
    tester,
  ) async {
    final state = await pump(tester);
    expect(state.blocks, hasLength(2));

    // What an assistant prunes after a month, gone in one step.
    Directory('${temp.path}/projects').deleteSync(recursive: true);
    await state.refresh();
    await tester.pumpAndSettle();

    expect(state.blocks, hasLength(2));
    expect(state.archive().events, 4);
    expect(state.archive().files, 2);
  });

  testWidgets('settings switch a sink off and write it to disk', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Export CSV and Excel'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Export CSV and Excel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export CSV and Excel'));
    await tester.pumpAndSettle();

    expect(AiTrackerConfig.load(configPath).tabular.enabled, isFalse);
  });

  testWidgets('the graphs screen draws the period and its legend', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Graphs'));
    await tester.pumpAndSettle();

    // A month of days is drawn a week at a time.
    expect(find.text('By week'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    // Legend names both the mapped project and the unmapped time.
    expect(find.text('Byte Buddies - idbuddy'), findsWidgets);
    expect(find.text('Unmapped'), findsOneWidget);
    expect(find.text('Hover a day to see what it held.'), findsOneWidget);
  });

  testWidgets('the period picker switches the window', (tester) async {
    final state = await pump(tester);

    await tester.tap(find.text('Graphs'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Yesterday'));
    await tester.pumpAndSettle();

    expect(state.periodKind, PeriodKind.yesterday);
    expect(state.blocks, isEmpty);
    expect(find.text('Nothing in this window yet.'), findsOneWidget);
  });

  testWidgets('the list narrows to mapped or unmapped', (tester) async {
    final state = await pump(tester);

    expect(state.blocks, hasLength(2));
    expect(state.filterCounts[BlockFilter.unmapped], 1);

    await tester.tap(find.text('Unmapped 1'));
    await tester.pumpAndSettle();

    expect(state.blocks.single.project, isNull);
    expect(find.text('Paperweight AI - paperweight'), findsNothing);

    await tester.tap(find.text('Mapped 1'));
    await tester.pumpAndSettle();

    expect(state.blocks.single.project, 'Byte Buddies - idbuddy');
  });

  testWidgets('searching for unmapped finds the blocks going nowhere', (
    tester,
  ) async {
    final state = await pump(tester);

    await tester.enterText(find.byType(TextField).first, 'unmapped');
    await tester.pumpAndSettle();

    expect(state.blocks, hasLength(1));
    expect(state.blocks.single.project, isNull);
  });

  testWidgets('the banner jumps to the blocks it is complaining about', (
    tester,
  ) async {
    final state = await pump(tester);

    await tester.tap(find.text('Show them'));
    await tester.pumpAndSettle();

    expect(state.filter, BlockFilter.unmapped);
  });

  testWidgets('a filtered-out block cannot stay selected', (tester) async {
    final state = await pump(tester);

    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(state.selected, hasLength(1));

    await tester.tap(find.text('Unmapped 1'));
    await tester.pumpAndSettle();

    expect(state.selected, isEmpty);
  });

  testWidgets('the calendar lays a month out as a grid that fills the card', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Graphs'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    expect(
      find.text('${months[now.month - 1]} ${now.year}'),
      findsOneWidget,
    );
    // A month block per column, each with its weekday header: a wide card is
    // filled with the months either side rather than left empty.
    expect(find.text('W'), findsNWidgets(4));
    expect(
      find.text('${months[now.month % 12]} ${now.month == 12 ? now.year + 1 : now.year}'),
      findsOneWidget,
    );
    expect(find.text('${now.day}'), findsWidgets);
  });

  testWidgets('the arrows step the window by its own length', (tester) async {
    final state = await pump(tester);

    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();

    expect(state.periodStep, -1);
    final lastMonth = DateTime(DateTime.now().year, DateTime.now().month - 1);
    expect(state.period.start, lastMonth);
    // The stepped window says what it is, and can be dismissed back to today.
    expect(find.byType(Chip), findsWidgets);

    await tester.tap(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();

    expect(state.periodStep, 1);
  });

  testWidgets('a project is mapped onto the two apps and keeps its colour', (
    tester,
  ) async {
    final state = await pump(tester);

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Map to the apps').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'BB - idbuddy');
    await tester.enterText(find.byType(TextField).at(1), 'Byte Buddies');
    await tester.enterText(find.byType(TextField).at(2), 'idbuddy');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final link = state.config.linkFor('Byte Buddies - idbuddy')!;
    expect(link.workingHours, 'BB - idbuddy');
    expect(link.company, 'Byte Buddies');
    expect(link.calendarLabel, 'idbuddy');
    expect(AiTrackerConfig.load(configPath).links, hasLength(1));
  });

  testWidgets('renaming here alone leaves the ledger name in the mapping', (
    tester,
  ) async {
    final state = await pump(tester);

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Byte Buddies - ID');
    // Untick both apps: only this tool's name changes.
    await tester.tap(find.text('Rename the WorkingHours project too'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(state.config.rules.single.project, 'Byte Buddies - ID');
    expect(find.text('Byte Buddies - ID'), findsWidgets);
  });

  testWidgets('the project field suggests what exists and offers to create', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(2), 'idb');
    await tester.pumpAndSettle();
    expect(find.text('idbuddy'), findsWidgets);

    await tester.enterText(find.byType(TextField).at(2), 'Brand new');
    await tester.pumpAndSettle();
    expect(find.text('Create "Brand new"'), findsOneWidget);
  });

  testWidgets('sync shows both directions and only writes when told to', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Sync…'));
    await tester.pumpAndSettle();

    expect(find.text('Sync'), findsOneWidget);
    // Both directions are named, with nothing to take back here.
    expect(
      find.textContaining('Nothing has been changed in WorkingHours'),
      findsOneWidget,
    );
    expect(find.textContaining('would write 2 blocks'), findsOneWidget);
    expect(File('${temp.path}/hours.csv').existsSync(), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    expect(find.text('Synced'), findsOneWidget);
    expect(File('${temp.path}/hours.csv').readAsLinesSync(), hasLength(3));
  });
}
