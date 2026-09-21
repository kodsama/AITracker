import 'dart:io';

/// Whether a macOS app bundle is running, and how to stop and restart it.
///
/// Both target apps keep their SQLite store open and write it back from memory,
/// so a sync has to happen while the app is closed. `pgrep` does not match an
/// app bundle reliably here, so the check enumerates processes and looks for
/// the executable path instead.
class MacApp {
  /// Describes the app at [bundlePath], named [name] for `osascript`.
  const MacApp({required this.name, required this.bundlePath});

  /// WorkingHours, as installed from the App Store.
  static const MacApp workingHours = MacApp(
    name: 'WorkingHours',
    bundlePath: '/Applications/WorkingHours.app',
  );

  /// Diarium, as installed from the App Store.
  static const MacApp diarium = MacApp(
    name: 'Diarium',
    bundlePath: '/Applications/Diarium.app',
  );

  /// Name `osascript` knows the app by.
  final String name;

  /// Path of the `.app` bundle.
  final String bundlePath;

  /// Path of the main executable inside the bundle.
  String get executable => '$bundlePath/Contents/MacOS/$name';

  /// Whether the app itself is running. Helper processes such as the widget
  /// extension live in `Contents/PlugIns` and do not count.
  bool get isRunning {
    if (!Platform.isMacOS) return false;
    final result = Process.runSync('/bin/ps', ['-Ao', 'command']);
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
  bool quit({Duration timeout = const Duration(seconds: 20)}) {
    if (!isRunning) return true;
    Process.runSync('/usr/bin/osascript', ['-e', 'quit app "$name"']);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!isRunning) return true;
      sleep(const Duration(milliseconds: 250));
    }
    return false;
  }

  /// Launches the app again, hidden so a scheduled run does not steal focus.
  void launch() {
    if (!Platform.isMacOS) return;
    Process.runSync('/usr/bin/open', ['-g', '-j', bundlePath]);
  }
}
