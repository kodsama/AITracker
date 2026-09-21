import 'package:flutter/material.dart';

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
class HomeShell extends StatefulWidget {
  /// Creates the shell.
  const HomeShell({required this.state, super.key});

  /// App state, passed down to each screen.
  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            labelType: NavigationRailLabelType.all,
            backgroundColor: scheme.surfaceContainerLowest,
            leading: Padding(
              padding: const EdgeInsets.only(top: 28, bottom: 12),
              child: Image.asset('assets/logo/icon.png', width: 36, height: 36),
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
            child: AnimatedBuilder(
              animation: widget.state,
              builder: (context, _) => switch (_index) {
                0 => HoursScreen(state: widget.state),
                1 => GraphsScreen(state: widget.state),
                2 => RulesScreen(state: widget.state),
                _ => SettingsScreen(state: widget.state),
              },
            ),
          ),
        ],
      ),
    );
  }
}
