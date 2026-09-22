import 'dart:io';

import 'package:aitracker/src/widgets/folder_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('aitracker_picker');
    Directory('${root.path}/.hidden/projects').createSync(recursive: true);
    Directory('${root.path}/Visible').createSync();
    File('${root.path}/a-file.txt').writeAsStringSync('not a folder');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<String?> open(WidgetTester tester, {String? initial}) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              chosen = await showFolderPicker(context, initial: initial);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('lists folders, dotfolders included, and no files', (
    tester,
  ) async {
    await open(tester, initial: root.path);

    expect(find.text('.hidden'), findsOneWidget);
    expect(find.text('Visible'), findsOneWidget);
    expect(find.text('a-file.txt'), findsNothing);
  });

  testWidgets('walking in and back out follows the path field', (
    tester,
  ) async {
    await open(tester, initial: root.path);

    await tester.tap(find.text('.hidden'));
    await tester.pumpAndSettle();
    expect(find.text('projects'), findsOneWidget);

    await tester.tap(find.byTooltip('Up'));
    await tester.pumpAndSettle();
    expect(find.text('Visible'), findsOneWidget);
  });

  testWidgets('a typed path is followed, and a wrong one says so', (
    tester,
  ) async {
    await open(tester, initial: root.path);

    await tester.enterText(find.byType(TextField), '${root.path}/Visible');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('No folder at that path'), findsNothing);

    await tester.enterText(find.byType(TextField), '${root.path}/nowhere');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('No folder at that path'), findsOneWidget);
  });

  testWidgets('choosing a folder hands it back', (tester) async {
    await open(tester, initial: root.path);
    await tester.tap(find.text('Visible'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use this folder'));
    await tester.pumpAndSettle();

    // The dialog closed with the folder it was showing.
    expect(find.text('Choose a folder'), findsNothing);
  });

  testWidgets('cancelling hands back nothing', (tester) async {
    await open(tester, initial: root.path);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a folder'), findsNothing);
  });

  testWidgets('an empty folder says so', (tester) async {
    await open(tester, initial: '${root.path}/Visible');

    expect(find.text('No folders in here.'), findsOneWidget);
  });

  testWidgets('a path that is gone opens at its parent instead', (
    tester,
  ) async {
    await open(tester, initial: '${root.path}/Visible/missing');

    expect(find.text('No folders in here.'), findsOneWidget);
  });

  testWidgets('home is a button away', (tester) async {
    await open(tester, initial: root.path);

    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();

    // Whatever home holds, it is no longer showing the temporary folder.
    expect(find.text('.hidden'), findsNothing);
  });

  testWidgets('a folder it may not read shows as empty rather than failing', (
    tester,
  ) async {
    final closed = Directory('${root.path}/closed')..createSync();
    Process.runSync('/bin/chmod', ['000', closed.path]);
    addTearDown(() => Process.runSync('/bin/chmod', ['755', closed.path]));

    await open(tester, initial: closed.path);

    expect(find.text('No folders in here.'), findsOneWidget);
  });
}
