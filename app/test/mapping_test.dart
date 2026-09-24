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

  Future<void> openProjects(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    state = fixture.state();
    await tester.pumpWidget(AiTrackerApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects'));
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

  Finder inDialog(Finder matching) =>
      find.descendant(of: find.byType(AlertDialog), matching: matching);

  testWidgets('a rule is added from company and project', (tester) async {
    await openProjects(tester);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)).at(0), 'stunda');
    await tester.enterText(inDialog(find.byType(TextField)).at(1), 'Perso');
    await tester.enterText(inDialog(find.byType(TextField)).at(2), 'Stunda');
    await tester.pumpAndSettle();

    expect(find.textContaining('Filed as "Perso - Stunda"'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(state.config.rules.last.project, 'Perso - Stunda');
    expect(state.config.linkFor('Perso - Stunda')?.company, 'Perso');
  });

  testWidgets('rules can be reordered, edited and deleted', (tester) async {
    await openProjects(tester);
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)).at(0), 'other');
    await tester.enterText(inDialog(find.byType(TextField)).at(2), 'Other');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(state.config.rules, hasLength(2));

    await tester.tap(find.byTooltip('Move up').last);
    await tester.pumpAndSettle();
    expect(state.config.rules.first.match, 'other');

    await tester.tap(find.byTooltip('Move down').first);
    await tester.pumpAndSettle();
    expect(state.config.rules.first.match, 'idbuddy');

    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)).at(0), 'renamed');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(state.config.rules.first.match, 'renamed');

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(state.config.rules, hasLength(1));
  });

  testWidgets('a rule dialog will not save without both halves', (
    tester,
  ) async {
    await openProjects(tester);
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(state.config.rules, hasLength(1));
  });

  testWidgets('a project is mapped onto the ledger and the calendar', (
    tester,
  ) async {
    fixture.writeLedger(projects: ['BB - idbuddy']);
    await openProjects(tester);
    await scrollTo(tester, find.byTooltip('Map to the apps').first);

    await tester.tap(find.byTooltip('Map to the apps').first);
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)).at(0), 'BB - idbuddy');
    await tester.enterText(inDialog(find.byType(TextField)).at(1), 'Byte Buddies');
    await tester.enterText(inDialog(find.byType(TextField)).at(2), 'idbuddy');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final link = state.config.linkFor('Byte Buddies - idbuddy')!;
    expect(link.workingHours, 'BB - idbuddy');
    expect(link.company, 'Byte Buddies');
    expect(link.calendarLabel, 'idbuddy');
    expect(find.textContaining('WorkingHours: BB - idbuddy'), findsOneWidget);
  });

  testWidgets('work unit tags are picked from what the ledger has', (
    tester,
  ) async {
    fixture.writeLedger();
    final db = sqlite3.open(fixture.ledgerPath);
    db.execute(
      "insert into Tags (Value, Type, SortIndex, AutoAssign, Details, Color, "
      "AdjustmentValue, Hidden) values ('Programming', 0, 1, 0, '', '#FF0', 0.0, 0)",
    );
    db.close();
    fixture.config(workingHours: true).save(fixture.configPath);

    await openProjects(tester);
    await scrollTo(tester, find.byTooltip('Map to the apps').first);
    await tester.tap(find.byTooltip('Map to the apps').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Programming'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      state.config.linkFor('Byte Buddies - idbuddy')?.workingHoursTags,
      ['Programming'],
    );
  });

  testWidgets('a colour is chosen from the palette or typed as hex', (
    tester,
  ) async {
    await openProjects(tester);
    await scrollTo(tester, find.byTooltip('Colour').first);

    await tester.tap(find.byTooltip('Colour').first);
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)).first, '#FF123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Use'));
    await tester.pumpAndSettle();

    expect(state.config.linkFor('Byte Buddies - idbuddy')?.color, '#FF123456');

    await tester.tap(find.byTooltip('Colour').first);
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.byType(InkWell)).at(1));
    await tester.pumpAndSettle();

    expect(
      state.config.linkFor('Byte Buddies - idbuddy')?.color,
      isNot('#FF123456'),
    );
  });

  testWidgets('renaming here alone, or in the ledger too', (tester) async {
    fixture.writeLedger(projects: ['Byte Buddies - idbuddy']);
    fixture.config(workingHours: true).save(fixture.configPath);
    await openProjects(tester);
    await scrollTo(tester, find.text('Rename').first);

    await tester.tap(find.text('Rename').first);
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)).first, 'BB - ID');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(state.config.rules.single.project, 'BB - ID');
    final db = sqlite3.open(fixture.ledgerPath);
    expect(db.select('select Name from Projects').single['Name'], 'BB - ID');
    db.close();
  });

  testWidgets('colours can be taken from the ledger or sent to it', (
    tester,
  ) async {
    fixture.writeLedger(projects: ['Byte Buddies - idbuddy']);
    fixture.config(workingHours: true).save(fixture.configPath);
    await openProjects(tester);
    await scrollTo(tester, find.text('Colours…'));

    await tester.tap(find.text('Colours…'));
    await tester.pumpAndSettle();
    expect(find.textContaining('WorkingHours #FF112233'), findsOneWidget);

    await tester.tap(find.text('Import all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(
      state.config.linkFor('Byte Buddies - idbuddy')?.color,
      '#FF112233',
    );
    expect(
      find.text('Every project is the same colour on both sides.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('a colour can be sent the other way', (tester) async {
    fixture.writeLedger(projects: ['Byte Buddies - idbuddy']);
    fixture.config(workingHours: true).copyWith(
      links: const [
        ProjectLink(name: 'Byte Buddies - idbuddy', color: '#FF445566'),
      ],
    ).save(fixture.configPath);
    await openProjects(tester);
    await scrollTo(tester, find.text('Colours…'));

    await tester.tap(find.text('Colours…'));
    await tester.pumpAndSettle();

    // One project at a time rather than all of them: the row's own control.
    await tester.tap(find.text('Export').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    final db = sqlite3.open(fixture.ledgerPath);
    expect(db.select('select Color from Projects').single['Color'], '#FF445566');
    db.close();
  });

  testWidgets('choosing none leaves both sides alone', (tester) async {
    fixture.writeLedger(projects: ['Byte Buddies - idbuddy']);
    fixture.config(workingHours: true).save(fixture.configPath);
    await openProjects(tester);
    await scrollTo(tester, find.text('Colours…'));
    await tester.tap(find.text('Colours…'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();

    final apply = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply'),
    );
    expect(apply.onPressed, isNull);
  });

  testWidgets('the project field opens on its arrow and filters as it goes', (
    tester,
  ) async {
    fixture.writeLedger(projects: ['Byte Buddies - idbuddy', 'RiACT - Code']);
    fixture.config(workingHours: true).save(fixture.configPath);
    await openProjects(tester);
    await scrollTo(tester, find.byTooltip('Map to the apps').first);
    await tester.tap(find.byTooltip('Map to the apps').first);
    await tester.pumpAndSettle();

    // Emptied, the arrow shows everything the ledger holds.
    await tester.enterText(inDialog(find.byType(TextField)).at(0), '');
    await tester.tap(inDialog(find.byTooltip('Show all')).first);
    await tester.pumpAndSettle();
    expect(find.text('RiACT - Code'), findsWidgets);
    expect(find.text('Byte Buddies - idbuddy'), findsWidgets);

    // Typing narrows it, whether it starts the name or sits inside it.
    await tester.enterText(inDialog(find.byType(TextField)).at(0), 'ria');
    await tester.pumpAndSettle();
    expect(find.text('RiACT - Code'), findsWidgets);

    await tester.enterText(inDialog(find.byType(TextField)).at(0), 'buddies');
    await tester.pumpAndSettle();
    expect(find.text('Byte Buddies - idbuddy'), findsWidgets);
    expect(find.text('RiACT - Code'), findsNothing);

    await tester.enterText(inDialog(find.byType(TextField)).at(0), 'Brand new');
    await tester.pumpAndSettle();
    expect(find.text('Create "Brand new"'), findsOneWidget);

    await tester.tap(find.text('Create "Brand new"'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      state.config.linkFor('Byte Buddies - idbuddy')?.workingHours,
      'Brand new',
    );
  });

  testWidgets('a colour that cannot be sent says why', (tester) async {
    fixture.config(workingHours: true).copyWith(
      links: const [
        ProjectLink(name: 'Byte Buddies - idbuddy', color: '#FF445566'),
      ],
    ).save(fixture.configPath);
    await openProjects(tester);
    await scrollTo(tester, find.text('Colours…'));

    await tester.tap(find.text('Colours…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    // No ledger to write into, and the dialog says so rather than pretending.
    expect(find.textContaining('no WorkingHours database'), findsOneWidget);
  });

  testWidgets('a rename that the ledger refuses is reported', (tester) async {
    fixture.config(workingHours: true).save(fixture.configPath);
    await openProjects(tester);
    await scrollTo(tester, find.text('Rename').first);

    await tester.tap(find.text('Rename').first);
    await tester.pumpAndSettle();
    await tester.enterText(inDialog(find.byType(TextField)).first, 'BB - ID');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no WorkingHours database'), findsOneWidget);
  });

  testWidgets('a rename can be called off', (tester) async {
    await openProjects(tester);
    await scrollTo(tester, find.text('Rename').first);

    await tester.tap(find.text('Rename').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(state.config.rules.single.project, 'Byte Buddies - idbuddy');
  });

  testWidgets('a colour dialog can be closed without choosing', (
    tester,
  ) async {
    await openProjects(tester);
    await scrollTo(tester, find.byTooltip('Colour').first);

    await tester.tap(find.byTooltip('Colour').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(state.config.links, isEmpty);
  });

  testWidgets('a mapping dialog can be closed without saving', (tester) async {
    await openProjects(tester);
    await scrollTo(tester, find.byTooltip('Map to the apps').first);

    await tester.tap(find.byTooltip('Map to the apps').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(state.config.links, isEmpty);
  });

  testWidgets('with no rules yet the screen says so', (tester) async {
    fixture.config().copyWith(rules: const []).save(fixture.configPath);

    await openProjects(tester);

    expect(find.text('No rules yet. Every hour is unmapped.'), findsOneWidget);
    expect(
      find.text('Add a rule first; its project shows up here.'),
      findsOneWidget,
    );
  });

  testWidgets('an unmapped directory offers a rule that starts filled in', (
    tester,
  ) async {
    await openProjects(tester);
    await scrollTo(tester, find.text('Map it'));

    await tester.tap(find.text('Map it'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(inDialog(find.byType(TextField)).at(0)).controller?.text,
      'mystery',
    );
  });
}
