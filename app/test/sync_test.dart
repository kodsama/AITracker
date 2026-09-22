import 'dart:io';

import 'package:aitracker/main.dart';
import 'package:aitracker/src/state/app_state.dart';
import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

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

  Future<void> openSync(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state = fixture.state();
    await tester.pumpWidget(AiTrackerApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sync…'));
    await tester.pumpAndSettle();
  }

  /// A unit this tool wrote, since changed in the ledger.
  void writeChangedUnit(TrackedBlock block) {
    final db = sqlite3.open(fixture.ledgerPath);
    db.execute(
      'insert into WorkUnits (ProjectId, Duration, End, Description, Details, '
      'Start) values (1, 0, ?, ?, ?, ?)',
      [
        toTicks(block.block.end),
        'renamed in the ledger',
        WorkingHoursSink.marker,
        toTicks(block.block.start),
      ],
    );
    db.close();
  }

  testWidgets('with nothing changed it offers only the way out', (
    tester,
  ) async {
    await openSync(tester);

    expect(find.text('Sync'), findsOneWidget);
    expect(
      find.textContaining('Nothing has been changed in WorkingHours'),
      findsOneWidget,
    );
    expect(find.textContaining('would write 2 blocks'), findsOneWidget);
  });

  testWidgets('a target can be left out of the run', (tester) async {
    await openSync(tester);
    await tester.tap(find.text('CSV and Excel'));
    await tester.pumpAndSettle();

    expect(find.text('not included'), findsOneWidget);
    final write = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Write'),
    );
    expect(write.onPressed, isNull);
  });

  testWidgets('a refusal is shown rather than a number', (tester) async {
    fixture.config(workingHours: true).save(fixture.configPath);

    await openSync(tester);

    expect(find.textContaining('no WorkingHours database'), findsOneWidget);
  });

  testWidgets('closing the app for the write is offered, and can be declined', (
    tester,
  ) async {
    fixture.writeLedger();
    fixture.config(workingHours: true).save(fixture.configPath);

    await openSync(tester);

    expect(find.text('Close WorkingHours for the write'), findsOneWidget);
    await tester.tap(find.text('Close WorkingHours for the write'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    expect(find.text('Synced'), findsOneWidget);
    expect(find.textContaining('wrote 1 blocks'), findsWidgets);
    expect(find.textContaining('backup:'), findsOneWidget);
  });

  testWidgets('what the ledger changed comes back, and can be left', (
    tester,
  ) async {
    fixture.writeLedger(projects: ['Moved elsewhere']);
    fixture.config(workingHours: true).save(fixture.configPath);
    final probe = fixture.state();
    await probe.load();
    writeChangedUnit(probe.blocks.firstWhere((b) => b.project != null));
    probe.dispose();

    await openSync(tester);

    expect(find.textContaining('Changed in WorkingHours'), findsOneWidget);
    expect(find.textContaining('renamed in the ledger'), findsWidgets);

    // Left unticked, it is not taken.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    expect(state.overrideFor(state.blocks.first.key)?.description, isNull);
  });

  testWidgets('a change taken back becomes a hand edit', (tester) async {
    fixture.writeLedger(projects: ['Moved elsewhere']);
    fixture.config(workingHours: true).save(fixture.configPath);
    final probe = fixture.state();
    await probe.load();
    final block = probe.blocks.firstWhere((b) => b.project != null);
    writeChangedUnit(block);
    probe.dispose();

    await openSync(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Take and write'));
    await tester.pumpAndSettle();

    expect(find.text('Synced'), findsOneWidget);
    expect(
      state.blocks.firstWhere((b) => b.key == block.key).description,
      'renamed in the ledger',
    );
  });

  testWidgets('with no target switched on it says so', (tester) async {
    fixture.config(tabular: false).save(fixture.configPath);

    await openSync(tester);

    expect(find.text('No target is switched on. See Settings.'), findsOneWidget);
  });

  testWidgets('the files it wrote are named', (tester) async {
    await openSync(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    expect(find.textContaining('hours.csv'), findsWidgets);
    expect(File('${fixture.root.path}/hours.csv').existsSync(), isTrue);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsNothing);
  });
}
