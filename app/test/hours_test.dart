import 'dart:io';

import 'package:aitracker/main.dart';
import 'package:aitracker/src/state/app_state.dart';
import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

/// A state that is forever mid-scan, for the one thing only a slow scan shows.
class _Reading extends AppState {
  _Reading(Fixture fixture)
    : super(
        configPath: fixture.configPath,
        overridesPath: fixture.overridesPath,
        background: false,
      );

  @override
  bool get loading => true;

  @override
  bool get reading => true;
}

void main() {
  Log.enabled = false;

  late Fixture fixture;
  late AppState state;

  setUp(() => fixture = Fixture.create());
  tearDown(() {
    state.dispose();
    fixture.dispose();
  });

  Future<void> openHours(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state = fixture.state();
    await tester.pumpWidget(AiTrackerApp(state: state));
    await tester.pumpAndSettle();
  }

  testWidgets('the search box clears from its own button', (tester) async {
    await openHours(tester);

    await tester.enterText(find.byKey(const Key('search')), 'idbuddy');
    await tester.pumpAndSettle();
    expect(state.blocks, hasLength(1));

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    expect(state.query, isEmpty);
    expect(state.blocks, hasLength(2));
  });

  testWidgets('a day and a week can be selected from their heading', (
    tester,
  ) async {
    await openHours(tester);

    await tester.tap(find.text('Select day').first);
    await tester.pumpAndSettle();
    expect(state.selected, hasLength(2));

    await tester.tap(find.text('Clear selection'));
    await tester.pumpAndSettle();
    expect(state.selected, isEmpty);

    await tester.tap(find.text('Select week').first);
    await tester.pumpAndSettle();
    expect(state.selected, hasLength(2));
  });

  testWidgets('a batch rename writes the description on every one', (
    tester,
  ) async {
    await openHours(tester);
    await tester.tap(find.text('Select day').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'pairing on the importer',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(
      state.blocks.map((b) => b.description),
      everyElement('pairing on the importer'),
    );
  });

  testWidgets('a batch edit can be cancelled', (tester) async {
    await openHours(tester);
    await tester.tap(find.text('Select day').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Assign project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(state.overrideFor(state.blocks.first.key), isNull);
  });

  testWidgets('an excluded block is marked and left out of the totals', (
    tester,
  ) async {
    await openHours(tester);
    await tester.tap(find.text('Select day').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Exclude'));
    await tester.pumpAndSettle();

    expect(state.total, Duration.zero);
    expect(find.byTooltip('Left out of every sink'), findsWidgets);
  });

  testWidgets('an edited block is marked as edited', (tester) async {
    await openHours(tester);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'by hand',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edited by hand'), findsOneWidget);
  });

  testWidgets('a window with nothing in it says so', (tester) async {
    await openHours(tester);

    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();

    expect(find.text('No assistant activity in this window.'), findsOneWidget);
  });

  testWidgets('a custom range is picked from the calendar', (tester) async {
    await openHours(tester);

    await tester.tap(find.text('Pick dates'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);

    // A full-screen range picker closes on its X, not a Cancel button.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(state.periodKind, PeriodKind.thisMonth);
  });

  testWidgets('two dates picked from the calendar become the window', (
    tester,
  ) async {
    await openHours(tester);

    await tester.tap(find.text('Pick dates'));
    await tester.pumpAndSettle();
    // The range picker opens on the current window; pick two days in it.
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(state.periodKind, PeriodKind.custom);
    expect(state.period.days, 3);
  });

  testWidgets('a scan says it is reading while it reads', (tester) async {
    // A scan of a real history takes a while; here it is over in a
    // microsecond, so the state that says so is put on screen directly.
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state = _Reading(fixture);
    await tester.pumpWidget(AiTrackerApp(state: state));
    await tester.pump();

    expect(find.text('reading transcripts'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('the window can be chosen from the dropdown', (tester) async {
    await openHours(tester);

    await tester.tap(find.byType(DropdownMenu<PeriodKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This year').last);
    await tester.pumpAndSettle();

    expect(state.periodKind, PeriodKind.thisYear);

    await tester.tap(find.byType(DropdownMenu<PeriodKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dates…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(state.periodKind, PeriodKind.thisYear);
  });

  testWidgets('a stepped window can be cleared from its chip', (tester) async {
    await openHours(tester);

    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(find.byType(Chip), findsWidgets);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(state.periodStep, 0);
  });

  testWidgets('the words beside the total go before the total does', (
    tester,
  ) async {
    await openHours(tester, size: const Size(800, 900));

    expect(find.text('with an AI assistant'), findsNothing);
    expect(find.text('1h 30m'), findsWidgets);
    // Still room for the button to say what it is.
    expect(find.widgetWithText(FilledButton, 'Sync…'), findsOneWidget);
  });

  testWidgets('narrower still, the button becomes its icon', (tester) async {
    await openHours(tester, size: const Size(620, 900));

    expect(find.byTooltip('Sync'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sync…'), findsNothing);
    expect(find.text('1h 30m'), findsWidgets);
  });

  testWidgets('counting per project says so beside the total', (tester) async {
    await openHours(tester);

    state.setMode(CountMode.perProject);
    await tester.pumpAndSettle();

    expect(find.textContaining('across projects'), findsOneWidget);
    expect(find.textContaining('on the clock'), findsWidgets);
  });

  testWidgets('a field follows the configuration when it changes elsewhere', (
    tester,
  ) async {
    await openHours(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'AI: {repo}'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Changed from outside the screen, as the MCP server would.
    await state.save(
      state.config.copyWith(
        workingHours: WorkingHoursSinkConfig(
          databasePath: fixture.ledgerPath,
          descriptionTemplate: 'from elsewhere',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'from elsewhere'), findsOneWidget);
  });

  testWidgets('a custom window is named by its two dates', (tester) async {
    await openHours(tester);

    await state.setPeriod(
      PeriodKind.custom,
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 5),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/9/26 to 5/9/26'), findsOneWidget);
  });

  testWidgets('a target that throws while filing itself is reported', (
    tester,
  ) async {
    await openHours(tester);

    await state.save(
      state.config.copyWith(
        tabular: const TabularSinkConfig(
          enabled: true,
          automatic: true,
          // Under a file rather than a folder: writing it cannot work.
          csvPath: '/dev/null/nope/hours.csv',
          xlsxPath: '/dev/null/nope/hours.xlsx',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Automatic filing failed'), findsOneWidget);
  });

  testWidgets('what went wrong is said on screen', (tester) async {
    await openHours(tester);

    // The archive folder taken away underneath it: the next read cannot work.
    Process.runSync('/bin/chmod', ['000', fixture.root.path]);
    addTearDown(() => Process.runSync('/bin/chmod', ['755', fixture.root.path]));
    await state.refresh();
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not read the transcripts'), findsOneWidget);
  });
}
