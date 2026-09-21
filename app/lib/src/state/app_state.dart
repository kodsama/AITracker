import 'dart:io';

import 'package:aitracking_engine/aitracking_engine.dart';
import 'package:aitracking_mcp/aitracking_mcp.dart';
import 'package:flutter/foundation.dart';

/// How far back the window reaches. Null days means everything on disk.
class Range {
  /// Creates a range.
  const Range(this.label, this.days);

  /// Text on the chip.
  final String label;

  /// Days back from today, null for everything.
  final int? days;

  /// The ranges the header offers.
  static const List<Range> all = [
    Range('7 days', 7),
    Range('30 days', 30),
    Range('90 days', 90),
    Range('Everything', null),
  ];

  /// Start of the window, or null.
  DateTime? get since {
    if (days == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(Duration(days: days!));
  }
}

/// Everything the windows read and write: the configuration, the blocks read
/// out of the transcripts, what is selected, and the MCP endpoint.
class AppState extends ChangeNotifier {
  /// Creates the state. [configPath] and [overridesPath] exist for the tests.
  AppState({this.configPath, this.overridesPath});

  /// Where the configuration is read from, null for the default location.
  final String? configPath;

  /// Where the hand edits are read from, null for the default location.
  final String? overridesPath;

  AiTrackingConfig _config = const AiTrackingConfig(sources: []);
  OverrideStore _overrides = OverrideStore();
  List<TrackedBlock> _blocks = const [];
  final Set<String> _selected = {};
  Range _range = Range.all[1];
  bool _loading = true;
  ServerSocket? _mcp;

  /// Current configuration.
  AiTrackingConfig get config => _config;

  /// Blocks in the window, newest first.
  List<TrackedBlock> get blocks => _blocks;

  /// Keys of the selected blocks.
  Set<String> get selected => _selected;

  /// Window the header is showing.
  Range get range => _range;

  /// Whether a scan is in flight.
  bool get loading => _loading;

  /// Port the MCP endpoint is listening on, null when it is off.
  int? get mcpPort => _mcp?.port;

  /// Time per project in the window.
  Map<String, Duration> get byProject => totalsByProject(_blocks);

  /// Directories in the window that no rule covers.
  Map<String, Duration> get strays => unmapped(_blocks);

  /// Every project name the configuration or a hand edit mentions.
  List<String> get knownProjects {
    final names = <String>{
      for (final rule in _config.rules) rule.project,
      for (final override in _overrides.entries.values)
        if (override.project != null) override.project!,
      if (_config.fallbackProject != null) _config.fallbackProject!,
    };
    return names.toList()..sort();
  }

  /// The hand edit on [key], if there is one.
  BlockOverride? overrideFor(String key) => _overrides[key];

  /// Total billable time in the window.
  Duration get total =>
      byProject.values.fold(Duration.zero, (sum, d) => sum + d);

  /// Reads the configuration and scans the transcripts.
  Future<void> load() async {
    _config = AiTrackingConfig.load(configPath);
    _overrides = OverrideStore.load(overridesPath);
    if (_config.mcpEnabled && _mcp == null) await startMcp();
    await refresh();
  }

  /// Rescans the transcripts with the current configuration.
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final tracking = AiTracking(config: _config, overrides: _overrides);
    final found = tracking.blocks(since: _range.since);
    _blocks = found.reversed.toList();
    _selected.removeWhere((key) => !_blocks.any((b) => b.key == key));
    _loading = false;
    notifyListeners();
  }

  /// Switches the window and rescans.
  Future<void> setRange(Range range) async {
    _range = range;
    await refresh();
  }

  /// Selects or deselects one block.
  void toggle(String key) {
    if (!_selected.remove(key)) _selected.add(key);
    notifyListeners();
  }

  /// Selects every block on screen, or clears the selection.
  void toggleAll() {
    if (_selected.length == _blocks.length) {
      _selected.clear();
    } else {
      _selected
        ..clear()
        ..addAll(_blocks.map((b) => b.key));
    }
    notifyListeners();
  }

  /// Applies [edit] to every selected block.
  Future<void> editSelected(BlockOverride edit) async {
    for (final key in _selected) {
      _overrides.merge(key, edit);
    }
    _overrides.save(overridesPath);
    await refresh();
  }

  /// Drops the hand edits on every selected block.
  Future<void> clearSelectedEdits() async {
    for (final key in _selected) {
      _overrides.set(key, null);
    }
    _overrides.save(overridesPath);
    await refresh();
  }

  /// Saves [config] and rescans with it.
  Future<void> save(AiTrackingConfig config) async {
    _config = config;
    config.save(configPath);
    if (config.mcpEnabled && _mcp == null) {
      await startMcp();
    } else if (!config.mcpEnabled && _mcp != null) {
      await stopMcp();
    }
    await refresh();
  }

  /// Previews or performs the writes, and returns what each sink reported.
  Future<List<SyncReport>> sync({
    required bool apply,
    bool quitApps = false,
  }) async {
    final reports = <SyncReport>[
      if (_config.workingHours.enabled)
        WorkingHoursSink(
          config: _config.workingHours,
          minBlock: _config.minBlock,
        ).sync(_blocks, dryRun: !apply, quitApp: quitApps),
      if (_config.diarium.enabled)
        DiariumSink(
          config: _config.diarium,
        ).sync(_blocks, dryRun: !apply, quitApp: quitApps),
      if (_config.tabular.enabled)
        TabularSink(config: _config.tabular).sync(_blocks, dryRun: !apply),
    ];
    if (apply) await refresh();
    return reports;
  }

  /// Starts the MCP endpoint on the configured port.
  Future<void> startMcp() async {
    _mcp = await serveTcp(
      McpServer(
        tools: buildTools(
          configPath: configPath,
          overridesPath: overridesPath,
        ),
      ),
      port: _config.mcpPort,
    );
    notifyListeners();
  }

  /// Stops the MCP endpoint.
  Future<void> stopMcp() async {
    await _mcp?.close();
    _mcp = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _mcp?.close();
    super.dispose();
  }
}
