import 'package:aitracker/main.dart';
import 'package:aitracker/src/screens/graphs_screen.dart';
import 'package:aitracker/src/screens/hours_screen.dart';
import 'package:aitracker/src/screens/rules_screen.dart';
import 'package:aitracker/src/screens/settings_screen.dart';
import 'package:aitracker/src/state/app_state.dart';
import 'package:aitracker/src/theme.dart';
import 'package:aitracker/src/widgets/batch_bar.dart';
import 'package:aitracker/src/widgets/block_list.dart';
import 'package:aitracker/src/widgets/breakdown.dart';
import 'package:aitracker/src/widgets/calendar_heatmap.dart';
import 'package:aitracker/src/widgets/period_picker.dart';
import 'package:aitracker/src/widgets/project_field.dart';
import 'package:aitracker/src/widgets/project_mapping.dart';
import 'package:aitracker/src/widgets/stacked_bars.dart';
import 'package:aitracker/src/widgets/summary_header.dart';
import 'package:aitracker/src/widgets/sync_dialog.dart';
import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture.dart';

/// Each widget on its own, built with the arguments it takes.
///
/// The screens exercise these together; here each one is given its inputs
/// directly, so a change to what a widget needs shows up as a broken test
/// rather than as a screen that quietly stops drawing something.
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

  /// A screen fills the window; a widget is given room to be as tall as it
  /// likes.
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    bool scrolls = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        home: Scaffold(
          body: scrolls ? SingleChildScrollView(child: child) : child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the header shows the totals and a way to sync', (tester) async {
    var synced = 0;

    await show(tester, SummaryHeader(state: state, onSync: () => synced++));
    await tester.tap(find.widgetWithText(FilledButton, 'Sync…'));

    expect(synced, 1);
    expect(find.text('ON THE CLOCK'), findsOneWidget);
    expect(find.text('TOKENS'), findsOneWidget);
  });

  testWidgets('the picker offers the windows and the arrows', (tester) async {
    await show(tester, PeriodPicker(state: state));

    expect(find.byTooltip('Previous'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);
    expect(find.byType(DropdownMenu<PeriodKind>), findsOneWidget);
  });

  testWidgets('the block list draws a row per block with its colour', (
    tester,
  ) async {
    await show(
      tester,
      SizedBox(height: 600, child: BlockList(state: state)),
      scrolls: false,
    );

    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.text('Select day'), findsOneWidget);
  });

  testWidgets('the batch bar acts on what is selected', (tester) async {
    state.toggleAll();

    await show(tester, BatchBar(state: state));

    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Exclude'));
    await tester.pumpAndSettle();
    expect(state.total, Duration.zero);
  });

  testWidgets('the breakdown lists what it was given', (tester) async {
    await show(tester, Breakdown(state: state));

    expect(find.text('Byte Buddies - idbuddy'), findsOneWidget);
    expect(find.text(unmappedLabel), findsOneWidget);
  });

  testWidgets('the bars take their buckets, series and colours', (
    tester,
  ) async {
    final period = state.period;

    await show(
      tester,
      StackedBars(
        buckets: bucketBlocks(state.blocks, period),
        width: bucketFor(period),
        series: const ['Byte Buddies - idbuddy', unmappedLabel],
        colorOf: (project) => state.colorFor(project, Brightness.light),
      ),
    );

    expect(find.byType(StackedBars), findsOneWidget);
  });

  testWidgets('the calendar takes its days and hands back the one clicked', (
    tester,
  ) async {
    DateTime? opened;

    await show(
      tester,
      CalendarHeatmap(
        days: dailyTotals(state.blocks),
        period: state.period,
        colorOf: (project) => state.colorFor(project, Brightness.dark),
        onDayTapped: (day) => opened = day,
      ),
    );
    final today = DateTime.now();
    final key =
        'day-${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await tester.tap(find.byKey(Key(key)));

    expect(opened, DateTime(today.year, today.month, today.day));
  });

  testWidgets('the project field suggests, creates and hands back', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? chosen;

    await show(
      tester,
      ProjectField(
        controller: controller,
        options: const ['Byte Buddies - idbuddy', 'RiACT - Code'],
        label: 'Project',
        hint: 'Company - Project',
        autofocus: true,
        onSubmitted: (value) => chosen = value,
      ),
    );
    await tester.enterText(find.byType(TextField), 'ria');
    await tester.pumpAndSettle();
    await tester.tap(find.text('RiACT - Code').last);
    await tester.pumpAndSettle();

    expect(chosen, 'RiACT - Code');
    expect(controller.text, 'RiACT - Code');
  });

  testWidgets('a target is named the way a person would say it', (
    tester,
  ) async {
    expect(sinkName('workinghours'), 'WorkingHours');
    expect(sinkName('calendar'), contains('Diarium'));
    expect(sinkName('tabular'), 'CSV and Excel');
  });

  testWidgets('each screen can be built on its own', (tester) async {
    await show(tester, HoursScreen(state: state), scrolls: false);
    expect(find.byType(HoursScreen), findsOneWidget);

    await show(
      tester,
      GraphsScreen(state: state, onOpenDay: (_) {}),
      scrolls: false,
    );
    expect(find.byType(GraphsScreen), findsOneWidget);
    expect(GraphsScreen.maxSeries, 7);
    expect(GraphsScreen.otherLabel, 'Other');
    expect(
      GraphsScreen.otherSeriesColor(
        tester.element(find.byType(GraphsScreen)),
      ),
      isNotNull,
    );

    await show(tester, RulesScreen(state: state), scrolls: false);
    expect(find.byType(RulesScreen), findsOneWidget);
    expect(find.byType(ProjectMapping), findsOneWidget);

    await show(tester, SettingsScreen(state: state), scrolls: false);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the shell holds the four screens', (tester) async {
    // The app builds its own shell over the state it was given.
    expect(AiTrackerApp(state: state).createState(), isNotNull);

    await show(tester, HomeShell(state: state), scrolls: false);

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Hours'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('the sync dialog can be built on its own', (tester) async {
    await show(tester, SyncDialog(state: state));

    expect(find.byType(SyncDialog), findsOneWidget);
  });

  test('the endpoint can be opened and closed from the state', () async {
    expect(state.tokenPath, endsWith('mcp-token'));

    await state.startMcp();
    expect(state.mcpPort, isNotNull);

    await state.stopMcp();
    expect(state.mcpPort, isNull);
  });

  test('a calendar cell has a size it will not go below or above', () {
    expect(CalendarHeatmap.minCell, lessThan(CalendarHeatmap.idealCell));
    expect(CalendarHeatmap.idealCell, lessThan(CalendarHeatmap.maxCell));
    expect(CalendarHeatmap.labelWidth, greaterThan(0));
  });

  test('a big number is read at a glance', () {
    expect(compactCount(950), '950');
    expect(compactCount(1500), '1.5k');
    expect(compactCount(2500000), '2.5M');
    expect(compactCount(3200000000), '3.2B');
  });

  test('the theme follows the brightness it is asked for', () {
    expect(appTheme(Brightness.dark).brightness, Brightness.dark);
    expect(appTheme(Brightness.light).brightness, Brightness.light);
  });

  test('the palette is fixed, in order, and folds past its end', () {
    expect(seed, isNotNull);
    expect(lightSeries, hasLength(8));
    expect(darkSeries, hasLength(8));
    expect(seriesColor(0, Brightness.light), lightSeries.first);
    expect(seriesColor(0, Brightness.dark), darkSeries.first);
    expect(seriesColor(99, Brightness.light), otherSeries(Brightness.light));
    expect(seriesColor(-1, Brightness.dark), otherSeries(Brightness.dark));
  });

  test('a colour reads and writes the way WorkingHours holds it', () {
    expect(parseArgb('#FF6C4AB6'), const Color(0xFF6C4AB6));
    expect(formatArgb(const Color(0xFF6C4AB6)), '#FF6C4AB6');
    expect(parseArgb('nonsense'), isNull);
    expect(parseArgb(null), isNull);
  });
}
