import 'dart:io';

import 'package:aitracking/main.dart';
import 'package:aitracking/src/state/app_state.dart';
import 'package:aitracking_engine/aitracking_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late String configPath;
  late String overridesPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracking_app');
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

    AiTrackingConfig(
      sources: ['${temp.path}/projects'],
      idleGap: const Duration(hours: 2),
      rules: const [
        ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy'),
      ],
      workingHours: const WorkingHoursSinkConfig(enabled: false),
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
    );
    await tester.pumpWidget(AiTrackingApp(state: state));
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
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
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
    await tester.enterText(find.byType(TextField).last, 'Academie - AdBAI');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(state.strays, isEmpty);
    expect(
      AiTrackingConfig.load(configPath).rules.map((r) => r.project),
      contains('Academie - AdBAI'),
    );
  });

  testWidgets('settings switch a sink off and write it to disk', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export CSV and Excel'));
    await tester.pumpAndSettle();

    expect(AiTrackingConfig.load(configPath).tabular.enabled, isFalse);
  });

  testWidgets('sync previews first, and only writes when told to', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Sync'));
    await tester.pumpAndSettle();

    expect(find.text('Ready to file'), findsOneWidget);
    expect(find.textContaining('2 blocks'), findsOneWidget);
    expect(File('${temp.path}/hours.csv').existsSync(), isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Write'));
    await tester.pumpAndSettle();

    expect(find.text('Filed'), findsOneWidget);
    expect(File('${temp.path}/hours.csv').readAsLinesSync(), hasLength(3));
  });
}
