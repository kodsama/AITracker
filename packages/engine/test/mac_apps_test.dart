import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

void main() {
  Log.enabled = false;

  /// A machine that answers whatever the test says, and remembers what it was
  /// asked to do.
  late List<List<String>> asked;
  late List<String> running;
  late int waits;

  MacApp app({int quitsAfter = 0}) {
    var looks = 0;
    return MacApp(
      name: 'WorkingHours',
      bundlePath: '/Applications/WorkingHours.app',
      run: (executable, arguments) {
        asked.add([executable, ...arguments]);
        if (executable != '/bin/ps') return ProcessResult(0, 0, '', '');
        final answer = running.join('\n');
        looks++;
        return ProcessResult(
          0,
          0,
          quitsAfter > 0 && looks > quitsAfter ? '' : answer,
          '',
        );
      },
      pause: (_) => waits++,
    );
  }

  setUp(() {
    asked = [];
    waits = 0;
    running = [
      '/sbin/launchd',
      '/Applications/WorkingHours.app/Contents/MacOS/WorkingHours',
    ];
  });

  test('an app is running when its executable is in the process list', () {
    expect(app().isRunning, isTrue);
    expect(asked.single, ['/bin/ps', '-Ao', 'command']);
  });

  test('a helper inside the bundle is not the app', () {
    running = [
      '/Applications/WorkingHours.app/Contents/PlugIns/WidgetExtension.appex/'
          'Contents/MacOS/WidgetExtension -LaunchArguments x',
    ];

    expect(app().isRunning, isFalse);
  });

  test('quitting an app that is not running asks nothing', () {
    running = [];

    expect(app().quit(), isTrue);
    expect(asked.map((a) => a.first), ['/bin/ps']);
  });

  test('quitting asks the app, then waits until it is gone', () {
    final result = app(quitsAfter: 2).quit();

    expect(result, isTrue);
    expect(asked[1], [
      '/usr/bin/osascript',
      '-e',
      'quit app "WorkingHours"',
    ]);
    expect(waits, greaterThan(0));
  });

  test('an app that will not quit is reported, not waited on forever', () {
    final result = app().quit(timeout: const Duration(milliseconds: 20));

    expect(result, isFalse);
  });

  test('launching starts it hidden, so a scheduled run keeps the focus', () {
    app().launch();

    expect(asked.single, [
      '/usr/bin/open',
      '-g',
      '-j',
      '/Applications/WorkingHours.app',
    ]);
  });

  test('the executable is the one inside the bundle', () {
    expect(
      app().executable,
      '/Applications/WorkingHours.app/Contents/MacOS/WorkingHours',
    );
    expect(MacApp.workingHours.name, 'WorkingHours');
    expect(MacApp.diarium.bundlePath, '/Applications/Diarium.app');
  });

  group('owns', () {
    test('is true only for the copy inside the app container', () {
      expect(
        MacApp.workingHours.owns(WorkingHoursSinkConfig.defaultDatabasePath),
        isTrue,
      );
      expect(MacApp.workingHours.owns('/tmp/wh.db'), isFalse);
      expect(MacApp.diarium.owns(WorkingHoursSinkConfig.defaultDatabasePath),
          isFalse);
      // An app with no container of its own guards nothing.
      expect(app().owns(WorkingHoursSinkConfig.defaultDatabasePath), isFalse);
    });
  });
}
