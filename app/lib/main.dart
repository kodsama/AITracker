import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/screens/graphs_screen.dart';
import 'src/screens/hours_screen.dart';
import 'src/screens/rules_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/state/app_state.dart';
import 'src/theme.dart';

void main() {
  runApp(AiTrackerApp(state: AppState()));
}

/// The desktop app: read the hours, correct them, file them.
class AiTrackerApp extends StatefulWidget {
  /// Creates the app over [state].
  const AiTrackerApp({required this.state, super.key});

  /// Configuration, blocks and selection.
  final AppState state;

  @override
  State<AiTrackerApp> createState() => _AiTrackerAppState();
}

class _AiTrackerAppState extends State<AiTrackerApp> {
  @override
  void initState() {
    super.initState();
    widget.state.load();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Tracker',
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    home: HomeShell(state: widget.state),
  );
}

/// Window frame: the rail on the left, the chosen screen on the right.
///
/// Which screen is open belongs to the state rather than to this widget, so
/// that going back can put it back.
class HomeShell extends StatelessWidget {
  /// Creates the shell.
  const HomeShell({required this.state, super.key});

  /// App state, passed down to each screen.
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            state.goBack,
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
            state.goForward,
      },
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: state,
          builder: (context, _) => Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: state.screen.index,
                  onDestinationSelected: (index) =>
                      state.goTo(Screen.values[index]),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: scheme.surfaceContainerLowest,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 28, bottom: 12),
                    child: Image.asset(
                      'assets/logo/icon.png',
                      width: 36,
                      height: 36,
                    ),
                  ),
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Back  ⌘[',
                              icon: const Icon(Icons.arrow_back),
                              onPressed: state.canGoBack ? state.goBack : null,
                            ),
                            IconButton(
                              tooltip: 'Forward  ⌘]',
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: state.canGoForward
                                  ? state.goForward
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.schedule_outlined),
                      selectedIcon: Icon(Icons.schedule),
                      label: Text('Hours'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.bar_chart_outlined),
                      selectedIcon: Icon(Icons.bar_chart),
                      label: Text('Graphs'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.alt_route_outlined),
                      selectedIcon: Icon(Icons.alt_route),
                      label: Text('Projects'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: switch (state.screen) {
                    Screen.hours => HoursScreen(state: state),
                    Screen.graphs => GraphsScreen(
                      state: state,
                      onOpenDay: state.openDay,
                    ),
                    Screen.projects => RulesScreen(state: state),
                    Screen.settings => SettingsScreen(state: state),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
