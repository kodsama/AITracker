import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'log.dart';

/// Runs a command and waits for it.
///
/// Injected so a test can say what the machine would have answered instead of
/// asking it: whether an app is running, and whether it agreed to quit, decide
/// whether a timesheet gets written.
typedef CommandRunner =
    ProcessResult Function(String executable, List<String> arguments);

/// Waits, so a test does not have to.
typedef Pause = void Function(Duration duration);

/// Whether a macOS app bundle is running, and how to stop and restart it.
///
/// Both target apps keep their SQLite store open and write it back from memory,
/// so a sync has to happen while the app is closed. `pgrep` does not match an
/// app bundle reliably here, so the check enumerates processes and looks for
/// the executable path instead.
class MacApp {
  /// Describes the app at [bundlePath], named [name] for `osascript`.
  const MacApp({
    required this.name,
    required this.bundlePath,
    this.run = Process.runSync,
    this.pause = sleep,
    this.quitTimeout = const Duration(seconds: 20),
    this.container = '',
  });

  /// WorkingHours, as installed from the App Store.
  static const MacApp workingHours = MacApp(
    name: 'WorkingHours',
    bundlePath: '/Applications/WorkingHours.app',
    container: 'Library/Containers/mac.partl.workinghours',
  );

  /// Diarium, as installed from the App Store.
  static const MacApp diarium = MacApp(
    name: 'Diarium',
    bundlePath: '/Applications/Diarium.app',
    container: 'Library/Containers/mac.partl.Diarium',
  );

  /// Name `osascript` knows the app by.
  final String name;

  /// Path of the `.app` bundle.
  final String bundlePath;

  /// How commands are run.
  final CommandRunner run;

  /// How the quit loop waits between looks.
  final Pause pause;

  /// How long [quit] waits for the app to go away.
  final Duration quitTimeout;

  /// The app's sandbox container, relative to the home directory. Empty means
  /// the app owns no store, so nothing needs guarding.
  final String container;

  /// Whether [databasePath] is the copy this app keeps open.
  ///
  /// A store outside the app's own container is nobody's live database, so it
  /// can be written without closing anything. That is also what keeps the tests
  /// off the machine's real apps: they hand a fake app a container of their
  /// own.
  bool owns(String databasePath) =>
      container.isNotEmpty &&
      p.isWithin(
        AiTrackerConfig.resolveHome(container),
        AiTrackerConfig.resolveHome(databasePath),
      );

  /// Path of the main executable inside the bundle.
  String get executable => '$bundlePath/Contents/MacOS/$name';

  /// Whether the app itself is running. Helper processes such as the widget
  /// extension live in `Contents/PlugIns` and do not count.
  bool get isRunning {
    if (!Platform.isMacOS) return false;
    final result = run('/bin/ps', ['-Ao', 'command']);
    final out = result.stdout;
    if (out is! String) return false;
    return out
        .split('\n')
        .any((line) => line.trimLeft().startsWith(executable));
  }

  /// Asks the app to quit and waits until it is gone, up to [timeout].
  ///
  /// Returns false when it is still running afterwards, which a caller must
  /// treat as "do not write".
  bool quit({Duration? timeout}) {
    if (!isRunning) return true;
    Log.info('asking $name to quit');
    run('/usr/bin/osascript', ['-e', 'quit app "$name"']);
    final deadline = DateTime.now().add(timeout ?? quitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!isRunning) return true;
      pause(const Duration(milliseconds: 250));
    }
    Log.warn('$name did not quit');
    return false;
  }

  /// Launches the app again, hidden so a scheduled run does not steal focus.
  void launch() {
    if (!Platform.isMacOS) return;
    Log.info('starting $name again');
    run('/usr/bin/open', ['-g', '-j', bundlePath]);
  }
}
