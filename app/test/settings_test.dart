import 'dart:io';


import 'package:aitracker/main.dart';
import 'package:aitracker/src/reveal.dart';
import 'package:aitracker/src/state/app_state.dart';
import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

void main() {
  Log.enabled = false;

  late Fixture fixture;
  late AppState state;

  setUp(() => fixture = Fixture.create());
  tearDown(() {
    state.dispose();
    fixture.dispose();
  });

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state = fixture.state();
    await tester.pumpWidget(AiTrackerApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the thresholds commit when the thumb is let go', (tester) async {
    await openSettings(tester);

    final slider = find.byType(Slider).first;
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(state.config.idleGap.inMinutes, lessThan(120));
    expect(AiTrackerConfig.load(fixture.configPath).idleGap.inMinutes,
        state.config.idleGap.inMinutes);
  });

  testWidgets('the counting mode is a choice, and the hours follow it', (
    tester,
  ) async {
    await openSettings(tester);

    await tester.tap(find.text('Per project'));
    await tester.pumpAndSettle();

    expect(state.mode, CountMode.perProject);
  });

  testWidgets('a transcript folder can be added, edited and removed', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.text('Add folder'));

    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();
    // The dialog's own field, not one of the screen's behind it.
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      fixture.root.path,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this folder'));
    await tester.pumpAndSettle();

    expect(state.config.sources, contains(fixture.root.path));

    await scrollTo(tester, find.byTooltip('Remove').first);
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();

    expect(state.config.sources, hasLength(1));
  });

  testWidgets('a folder that is gone is marked as such', (tester) async {
    fixture.config().copyWith(sources: ['${fixture.root.path}/gone']).save(
      fixture.configPath,
    );

    await openSettings(tester);
    await scrollTo(tester, find.text('Not there any more'));

    expect(find.text('Not there any more'), findsOneWidget);
  });

  testWidgets('each target switches on, off, and on to file by itself', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.text('Export to WorkingHours'));

    await tester.tap(find.text('Export to WorkingHours'));
    await tester.pumpAndSettle();
    expect(state.config.workingHours.enabled, isTrue);

    await tester.tap(find.text('Keep it up to date by itself').first);
    await tester.pumpAndSettle();
    expect(state.config.workingHours.automatic, isTrue);

    await scrollTo(tester, find.text('Publish the calendar'));
    await tester.tap(find.text('Publish the calendar'));
    await tester.pumpAndSettle();
    expect(state.config.calendar.enabled, isTrue);

    await scrollTo(tester, find.text('Export CSV and Excel'));
    await tester.tap(find.text('Export CSV and Excel'));
    await tester.pumpAndSettle();
    expect(state.config.tabular.enabled, isFalse);
  });

  testWidgets('a description template and a calendar name are typed in', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.widgetWithText(TextField, 'AI: {repo}'));

    await tester.enterText(
      find.widgetWithText(TextField, 'AI: {repo}'),
      '{company} on {repo}',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(state.config.workingHours.descriptionTemplate, '{company} on {repo}');
  });

  testWidgets('a spreadsheet path can be browsed to', (tester) async {
    await openSettings(tester);
    await scrollTo(tester, find.widgetWithText(TextField, 'CSV'));

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(TextField, 'CSV'),
        matching: find.byTooltip('Browse'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      fixture.root.path,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this folder'));
    await tester.pumpAndSettle();

    expect(state.config.tabular.csvPath, '${fixture.root.path}/hours.csv');
  });

  testWidgets('the port is typed in, and the key can be copied or replaced', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await openSettings(tester);
    await scrollTo(tester, find.text('Listen on localhost'));

    await tester.enterText(find.widgetWithText(TextField, 'Port'), '9100');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(state.config.mcpPort, 9100);

    final key = state.mcpToken;
    await tester.tap(find.byTooltip('Copy'));
    await tester.pumpAndSettle();
    expect(copied.single, key);
    expect(find.text('Key copied'), findsOneWidget);

    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    expect(state.mcpToken, isNot(key));
  });

  testWidgets('the shortest block is a slider of its own', (tester) async {
    await openSettings(tester);

    await tester.drag(find.byType(Slider).at(1), const Offset(200, 0));
    await tester.pumpAndSettle();

    expect(state.config.minBlock.inMinutes, greaterThan(5));
  });

  testWidgets('a transcript folder can be pointed somewhere else', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.byTooltip('Edit').first);

    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      fixture.root.path,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this folder'));
    await tester.pumpAndSettle();

    expect(state.config.sources, [fixture.root.path]);
  });

  testWidgets('an editor database is listed as one, and a missing one as gone', (
    tester,
  ) async {
    final store = File(
      '${fixture.root.path}/Cursor/User/globalStorage/state.vscdb',
    )..createSync(recursive: true);

    await openSettings(tester);
    await state.save(
      state.config.copyWith(
        sources: [store.path, '${fixture.root.path}/gone'],
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(store.path));

    expect(find.text('An editor database'), findsOneWidget);
    expect(find.byIcon(Icons.storage_outlined), findsOneWidget);
    expect(find.text('Not there any more'), findsOneWidget);
    expect(find.byIcon(Icons.folder_off_outlined), findsOneWidget);
  });

  testWidgets('an editor the list has never had is offered, and taken', (
    tester,
  ) async {
    final store = File(
      '${fixture.root.path}/Library/Application Support/Cursor/User/'
      'globalStorage/state.vscdb',
    )..createSync(recursive: true);

    await openSettings(tester);
    expect(find.text('An editor on this machine, not read'), findsOneWidget);

    await scrollTo(tester, find.text('Read it'));
    await tester.tap(find.text('Read it'));
    await tester.pumpAndSettle();

    expect(state.config.sources, contains(store.path));
    expect(find.text('An editor on this machine, not read'), findsNothing);
  });

  testWidgets('with no transcript folder at all it says so', (tester) async {
    fixture.config().copyWith(sources: const []).save(fixture.configPath);

    await openSettings(tester);
    await scrollTo(tester, find.text('No transcript folder yet. Add one.'));

    expect(find.text('No transcript folder yet. Add one.'), findsOneWidget);
  });

  testWidgets('the ledger, the calendar and the workbook take a new path', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.widgetWithText(TextField, 'Database'));

    await tester.enterText(
      find.widgetWithText(TextField, 'Database'),
      '${fixture.root.path}/elsewhere.db',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      state.config.workingHours.databasePath,
      '${fixture.root.path}/elsewhere.db',
    );

    await scrollTo(tester, find.widgetWithText(TextField, 'Calendar name'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Calendar name'),
      'Assistant',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(state.config.calendar.calendarName, 'Assistant');

    await tester.enterText(
      find.widgetWithText(TextField, 'Event title'),
      'AI {hours}',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(state.config.calendar.titleTemplate, 'AI {hours}');

    await scrollTo(tester, find.widgetWithText(TextField, 'Excel'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Excel'),
      '${fixture.root.path}/book.xlsx',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(state.config.tabular.xlsxPath, '${fixture.root.path}/book.xlsx');
  });

  testWidgets('the calendar and the spreadsheets can file themselves', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.text('Publish the calendar'));
    await tester.tap(find.text('Publish the calendar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep it up to date by itself').last);
    await tester.pumpAndSettle();
    expect(state.config.calendar.automatic, isTrue);

    await scrollTo(tester, find.text('Rewrite them by themselves'));
    await tester.tap(find.text('Rewrite them by themselves'));
    await tester.pumpAndSettle();
    expect(state.config.tabular.automatic, isTrue);
  });

  testWidgets('the endpoint opens on the switch and says where', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.text('Listen on localhost'));
    await tester.enterText(find.widgetWithText(TextField, 'Port'), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // A socket needs the real clock, which a widget test has to ask for.
    await tester.runAsync(
      () => state.save(state.config.copyWith(mcpEnabled: true)),
    );
    await tester.pumpAndSettle();

    expect(state.mcpPort, isNotNull);
    expect(find.textContaining('Listening on 127.0.0.1:'), findsOneWidget);

    await tester.runAsync(
      () => state.save(state.config.copyWith(mcpEnabled: false)),
    );
    await tester.pumpAndSettle();
    expect(state.mcpPort, isNull);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('both folders can be shown in Finder', (tester) async {
    final revealed = <String>[];
    final was = revealInFinder;
    revealInFinder = revealed.add;
    addTearDown(() => revealInFinder = was);

    await openSettings(tester);
    await scrollTo(tester, find.text('History'));
    await tester.tap(find.byTooltip('Show in Finder').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show in Finder').last);
    await tester.pumpAndSettle();

    expect(revealed, hasLength(2));
    expect(revealed.first, state.historyPath);
    expect(revealed.last, Log.path());
  });

  testWidgets('the archive and the log say where they are', (tester) async {
    await openSettings(tester);
    await scrollTo(tester, find.text('History'));

    expect(find.textContaining('events from 2 transcripts'), findsWidgets);
    expect(find.textContaining(state.historyPath), findsWidgets);

    await tester.tap(find.byTooltip('Refresh').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('4 events'), findsWidgets);
  });

  testWidgets('the log can be read and emptied', (tester) async {
    Log.useFile('${fixture.root.path}/log.txt');
    Log.enabled = true;
    addTearDown(() => Log.enabled = false);
    Log.info('something happened');

    await openSettings(tester);
    await scrollTo(tester, find.text('Clear'));
    await tester.tap(find.byTooltip('Refresh').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('something happened'), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing logged yet.'), findsOneWidget);
  });

  testWidgets('a helper path is kept when the next calendar field changes', (
    tester,
  ) async {
    await openSettings(tester);
    await scrollTo(tester, find.widgetWithText(TextField, 'Helper'));

    final helper = '${fixture.root.path}/aitracker-calendar';
    await tester.enterText(find.widgetWithText(TextField, 'Helper'), helper);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(state.config.calendar.helperPath, helper);
    expect(find.text('Publishing through $helper'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Calendar name'),
      'Assistant',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(state.config.calendar.calendarName, 'Assistant');
    expect(state.config.calendar.helperPath, helper);
  });
}
