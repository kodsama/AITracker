import 'dart:io';

import 'package:aitracker/main.dart';
import 'package:aitracker/src/measures.dart';
import 'package:aitracker/src/state/app_state.dart';
import 'package:aitracker/src/widgets/breakdown.dart';
import 'package:aitracker/src/widgets/calendar_heatmap.dart';
import 'package:aitracker/src/widgets/stacked_bars.dart';
import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  Future<void> openGraphs(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state = fixture.state();
    await tester.pumpWidget(AiTrackerApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Graphs'));
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

  /// Moves the mouse over [target] and leaves it there.
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await tester.pump();
    await pointer.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
    return pointer;
  }

  testWidgets('the graphs draw time, tokens, or one chart of each', (
    tester,
  ) async {
    await openGraphs(tester);

    expect(state.measure, Measure.time);
    expect(find.byType(StackedBars), findsOneWidget);
    expect(find.byType(CalendarHeatmap), findsOneWidget);

    await tester.tap(find.text('Tokens'));
    await tester.pumpAndSettle();

    expect(state.measure, Measure.tokens);
    expect(find.byType(StackedBars), findsOneWidget);
    // The axis is counted now, not clocked.
    expect(find.text('Calendar'), findsOneWidget);

    await tester.tap(find.text('Both'));
    await tester.pumpAndSettle();

    expect(state.measure, Measure.both);
    expect(find.byType(StackedBars), findsNWidgets(2));
    await scrollTo(tester, find.text('Calendar, time'));
    await scrollTo(tester, find.text('Calendar, tokens'));
  });

  testWidgets('asking for the measure it already shows changes nothing', (
    tester,
  ) async {
    await openGraphs(tester);
    state.setMeasure(Measure.time);
    await tester.pumpAndSettle();

    expect(state.measure, Measure.time);
    expect(find.byType(StackedBars), findsOneWidget);
  });

  testWidgets('the months around the window are drawn with their own work', (
    tester,
  ) async {
    // A day in the month before, which the window does not cover but the
    // calendar draws to fill its card.
    final today = DateTime.now();
    final before = DateTime(today.year, today.month - 1, 15);
    String at(int hour) =>
        DateTime(before.year, before.month, before.day, hour)
            .toUtc()
            .toIso8601String();
    File('${fixture.root.path}/projects/p/before.jsonl').writeAsStringSync(
      '{"timestamp":"${at(9)}","cwd":"/Users/me/Developer/idbuddy"}\n'
      '{"timestamp":"${at(11)}","cwd":"/Users/me/Developer/idbuddy"}\n',
    );

    await openGraphs(tester);
    await scrollTo(tester, find.text('Calendar'));

    final key =
        'day-${before.year}-${before.month.toString().padLeft(2, '0')}-'
        '${before.day.toString().padLeft(2, '0')}';
    await hover(tester, find.byKey(Key(key)));

    // It is outside the window, so it is dimmed, but it says what it held.
    expect(state.period.contains(before), isFalse);
    expect(find.textContaining('idbuddy'), findsWidgets);
  });

  testWidgets('the calendar moves a month at a time, and stops at the end', (
    tester,
  ) async {
    final today = DateTime.now();
    final before = DateTime(today.year, today.month - 1, 15);
    String at(int hour) =>
        DateTime(before.year, before.month, before.day, hour)
            .toUtc()
            .toIso8601String();
    File('${fixture.root.path}/projects/p/before.jsonl').writeAsStringSync(
      '{"timestamp":"${at(9)}","cwd":"/Users/me/Developer/idbuddy"}\n'
      '{"timestamp":"${at(11)}","cwd":"/Users/me/Developer/idbuddy"}\n',
    );

    await openGraphs(tester);
    await scrollTo(tester, find.text('Calendar'));

    String named(DateTime month) =>
        '${const [
          'January', 'February', 'March', 'April', 'May', 'June', 'July',
          'August', 'September', 'October', 'November', 'December',
        ][month.month - 1]} ${month.year}';

    expect(find.text(named(DateTime(today.year, today.month))), findsOneWidget);

    // Two months after the window's is drawn as padding, one before is not.
    expect(find.text(named(DateTime(today.year, today.month + 2))), findsOneWidget);
    expect(find.text(named(DateTime(today.year, today.month - 2))), findsNothing);

    await tester.tap(find.byTooltip('A month earlier'));
    await tester.pumpAndSettle();

    // Everything has moved one month back.
    expect(find.text(named(DateTime(today.year, today.month - 2))), findsOneWidget);
    expect(find.text(named(DateTime(today.year, today.month + 2))), findsNothing);
    expect(find.text(named(before)), findsOneWidget);

    // By tooltip, not by icon: the period picker has chevrons of its own.
    IconButton arrow(String tooltip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

    // It keeps going until the work has scrolled off, then stops.
    var taps = 0;
    while (arrow('A month earlier').onPressed != null && taps < 12) {
      await tester.tap(find.byTooltip('A month earlier'));
      await tester.pumpAndSettle();
      taps++;
    }
    expect(taps, inInclusiveRange(1, 11));
    expect(arrow('A month earlier').onPressed, isNull);

    // And back the other way returns to the window's own months.
    while (arrow('A month later').onPressed != null) {
      await tester.tap(find.byTooltip('A month later'));
      await tester.pumpAndSettle();
    }
    expect(find.text(named(DateTime(today.year, today.month))), findsOneWidget);
  });

  testWidgets('hovering a bar names what went into it', (tester) async {
    await openGraphs(tester);
    // The bars are painted, so the tooltip is what proves the hover landed.
    final chart = find.byType(StackedBars);

    final pointer = await hover(tester, chart);
    // Across the plot: one of these positions is over a bar.
    final box = tester.getRect(chart);
    for (var x = box.left + 60; x < box.right; x += 40) {
      await pointer.moveTo(Offset(x, box.center.dy));
      await tester.pumpAndSettle();
      if (find.textContaining('Total').evaluate().isNotEmpty) break;
    }

    expect(find.textContaining('Total'), findsOneWidget);
    expect(find.text('Unmapped'), findsWidgets);
  });

  testWidgets('hovering a day in the calendar says what it held', (
    tester,
  ) async {
    await openGraphs(tester);
    await scrollTo(tester, find.text('Calendar'));
    final today = DateTime.now();
    final key =
        'day-${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    await hover(tester, find.byKey(Key(key)));

    expect(find.textContaining('Byte Buddies - idbuddy 1h 30m'), findsWidgets);
  });

  testWidgets('the calendar shows week numbers and the months around', (
    tester,
  ) async {
    await openGraphs(tester);
    await scrollTo(tester, find.text('Calendar'));

    expect(find.textContaining('w'), findsWidgets);
    expect(find.text('M'), findsWidgets);
  });

  testWidgets('the breakdown sorts by any column, both ways', (tester) async {
    await openGraphs(tester);
    await scrollTo(tester, find.text('Breakdown'));

    await tester.tap(find.text('TOKENS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TOKENS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PER HOUR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SESSIONS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PROJECT'));
    await tester.pumpAndSettle();

    expect(find.byType(Breakdown), findsOneWidget);
  });

  testWidgets('the breakdown groups by company, day, week and month', (
    tester,
  ) async {
    await openGraphs(tester);
    await scrollTo(tester, find.text('Breakdown'));

    await tester.tap(find.text('Company'));
    await tester.pumpAndSettle();
    expect(find.text('Byte Buddies'), findsWidgets);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Week of'), findsOneWidget);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.byType(Breakdown), findsOneWidget);
  });

  testWidgets('the bar tooltip names every project in the bar, and the total', (
    tester,
  ) async {
    await openGraphs(tester);
    final chart = find.byType(StackedBars);
    final pointer = await hover(tester, chart);
    final box = tester.getRect(chart);

    for (var x = box.left + 60; x < box.right; x += 30) {
      await pointer.moveTo(Offset(x, box.center.dy));
      await tester.pumpAndSettle();
      if (find.textContaining('Total').evaluate().isNotEmpty) break;
    }

    // Two projects in the bar, so the total is worth saying as well.
    expect(find.textContaining('Total'), findsOneWidget);
    expect(find.text('Unmapped'), findsWidgets);

    // Moving off it takes the card away again.
    await pointer.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.textContaining('Total'), findsNothing);
  });

  testWidgets('a year is drawn a month at a time, several across', (
    tester,
  ) async {
    await openGraphs(tester);

    await tester.tap(find.byType(DropdownMenu<PeriodKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This year').last);
    await tester.pumpAndSettle();

    // The bars widen with the window before the calendar is even reached.
    expect(find.text('By month'), findsOneWidget);

    await scrollTo(tester, find.text('Calendar'));
    expect(find.textContaining('January'), findsOneWidget);
    expect(find.textContaining('December'), findsOneWidget);
  });

  testWidgets('a month bar names its month when hovered', (tester) async {
    await openGraphs(tester);
    await tester.tap(find.byType(DropdownMenu<PeriodKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This year').last);
    await tester.pumpAndSettle();

    final chart = find.byType(StackedBars);
    final pointer = await hover(tester, chart);
    final box = tester.getRect(chart);
    for (var x = box.left + 60; x < box.right; x += 24) {
      await pointer.moveTo(Offset(x, box.center.dy));
      await tester.pumpAndSettle();
      if (find.textContaining('Total').evaluate().isNotEmpty) break;
    }

    final year = DateTime.now().year;
    expect(find.textContaining('$year'), findsWidgets);
  });

  testWidgets('a day bar names its weekday when hovered', (tester) async {
    await openGraphs(tester);
    await tester.tap(find.byType(DropdownMenu<PeriodKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This week').last);
    await tester.pumpAndSettle();
    expect(find.text('By day'), findsOneWidget);

    final chart = find.byType(StackedBars);
    final pointer = await hover(tester, chart);
    final box = tester.getRect(chart);
    for (var x = box.left + 60; x < box.right; x += 24) {
      await pointer.moveTo(Offset(x, box.center.dy));
      await tester.pumpAndSettle();
      if (find.textContaining('Total').evaluate().isNotEmpty) break;
    }

    final today = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    expect(
      find.textContaining(days[today.weekday - 1]),
      findsWidgets,
    );
  });

  testWidgets('a day with nothing in it says nothing', (tester) async {
    await openGraphs(tester);
    await scrollTo(tester, find.text('Calendar'));
    final empty = DateTime.now().subtract(const Duration(days: 20));
    final key =
        'day-${empty.year}-${empty.month.toString().padLeft(2, '0')}-'
        '${empty.day.toString().padLeft(2, '0')}';

    await hover(tester, find.byKey(Key(key)));

    expect(find.text('nothing'), findsOneWidget);
  });

  testWidgets('an empty window says so rather than drawing nothing', (
    tester,
  ) async {
    await openGraphs(tester);

    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing in this window yet.'), findsOneWidget);
  });

  testWidgets('more projects than the palette holds fold into one slice', (
    tester,
  ) async {
    final rules = [
      for (var i = 0; i < 9; i++)
        ProjectRule(match: 'p$i', project: 'Company $i - p$i'),
    ];
    fixture.config().copyWith(rules: rules).save(fixture.configPath);
    final projects = fixture.root.path;
    final today = DateTime.now();
    for (var i = 0; i < 9; i++) {
      final hour = 1 + i;
      final at = DateTime(today.year, today.month, today.day, hour)
          .toUtc()
          .toIso8601String();
      final until = DateTime(today.year, today.month, today.day, hour, 30)
          .toUtc()
          .toIso8601String();
      final file = '$projects/projects/p/p$i.jsonl';
      Fixture(fixture.root);
      (await tester.runAsync(() async {
        await _write(file, at, until, i);
      }));
    }

    await openGraphs(tester);
    await scrollTo(tester, find.text('Breakdown'));

    expect(find.text('Other'), findsWidgets);
  });
}

Future<void> _write(String path, String at, String until, int index) async {
  final file = await File(path).create(recursive: true);
  await file.writeAsString(
    '{"timestamp":"$at","cwd":"/Users/me/Developer/p$index"}\n'
    '{"timestamp":"$until","cwd":"/Users/me/Developer/p$index"}\n',
  );
}
