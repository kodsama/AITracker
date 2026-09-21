import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:aitracker_mcp/aitracker_mcp.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, Color;

import '../theme.dart';

/// Everything the windows read and write: the configuration, the blocks read
/// out of the transcripts, what is selected, and the MCP endpoint.
class AppState extends ChangeNotifier {
  /// Creates the state. [configPath] and [overridesPath] exist for the tests.
  AppState({this.configPath, this.overridesPath});

  /// Where the configuration is read from, null for the default location.
  final String? configPath;

  /// Where the hand edits are read from, null for the default location.
  final String? overridesPath;

  AiTrackerConfig _config = const AiTrackerConfig(sources: []);
  OverrideStore _overrides = OverrideStore();
  Catalog _catalog = const Catalog();
  List<TrackedBlock> _blocks = const [];
  final Set<String> _selected = {};
  PeriodKind _periodKind = PeriodKind.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _loading = true;
  ServerSocket? _mcp;

  /// Current configuration.
  AiTrackerConfig get config => _config;

  /// Blocks in the window, newest first.
  List<TrackedBlock> get blocks => _blocks;

  /// Keys of the selected blocks.
  Set<String> get selected => _selected;

  /// Window the screens are showing.
  Period get period => periodFor(
    _periodKind,
    start: _customStart,
    end: _customEnd,
  );

  /// Which named window is selected.
  PeriodKind get periodKind => _periodKind;

  /// What the two apps already hold: projects, tags, customers, journal tags.
  Catalog get catalog => _catalog;

  /// Whether a scan is in flight.
  bool get loading => _loading;

  /// Port the MCP endpoint is listening on, null when it is off.
  int? get mcpPort => _mcp?.port;

  /// Time per project in the window.
  Map<String, Duration> get byProject => totalsByProject(_blocks);

  /// Directories in the window that no rule covers.
  Map<String, Duration> get strays => unmapped(_blocks);

  /// Every project name in play: the rules, the mapping, the hand edits and
  /// what WorkingHours already holds.
  List<String> get knownProjects {
    final names = <String>{
      for (final rule in _config.rules) rule.project,
      for (final link in _config.links) link.name,
      for (final override in _overrides.entries.values)
        if (override.project != null) override.project!,
      if (_config.fallbackProject != null) _config.fallbackProject!,
      for (final project in _catalog.projects)
        if (!project.hidden) project.name,
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
    _config = AiTrackerConfig.load(configPath);
    _overrides = OverrideStore.load(overridesPath);
    _catalog = Catalog.read(_config);
    if (_config.mcpEnabled && _mcp == null) await startMcp();
    await refresh();
  }

  /// Rescans the transcripts with the current configuration.
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final tracking = AiTracker(config: _config, overrides: _overrides);
    final window = period;
    final found = tracking.blocks(since: window.start, until: window.end);
    _blocks = found.reversed.toList();
    _selected.removeWhere((key) => !_blocks.any((b) => b.key == key));
    _loading = false;
    notifyListeners();
  }

  /// Switches the window and rescans. [start] and [end] apply to a custom one.
  Future<void> setPeriod(
    PeriodKind kind, {
    DateTime? start,
    DateTime? end,
  }) async {
    _periodKind = kind;
    if (kind == PeriodKind.custom) {
      _customStart = start ?? _customStart;
      _customEnd = end ?? _customEnd;
    }
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

  /// Colour a project is drawn in: the one it was given, else the one the
  /// ledger draws it in, else its slot in the chart palette.
  ///
  /// The slot follows the project name, not its rank in the current window, so
  /// a filter that drops a project never repaints the others.
  Color colorFor(String project, Brightness brightness) {
    final chosen = parseArgb(_config.linkFor(project)?.color);
    if (chosen != null) return chosen;
    final link = _config.linkFor(project);
    final ledgerName = link?.workingHoursProject ?? project;
    for (final entry in _catalog.projects) {
      if (entry.name != ledgerName) continue;
      final colour = parseArgb(entry.color);
      if (colour != null) return colour;
    }
    if (project == unmappedLabel) return otherSeries(brightness);
    return seriesColor(knownProjects.indexOf(project), brightness);
  }

  /// Adds or replaces the mapping for a project.
  Future<void> saveLink(ProjectLink link) async {
    final links = [
      for (final other in _config.links)
        if (other.name != link.name) other,
      link,
    ];
    await save(_config.copyWith(links: links));
  }

  /// Renames a project, carrying the name into the apps that were asked for.
  Future<RenameResult> rename(
    String from,
    String to, {
    bool inWorkingHours = false,
    bool inDiarium = false,
    bool quitApps = true,
  }) async {
    final result = renameProject(
      _config,
      from: from,
      to: to,
      inWorkingHours: inWorkingHours,
      inDiarium: inDiarium,
      dryRun: false,
      quitApps: quitApps,
      overrides: _overrides,
    );
    if (result.applied) {
      _overrides.save(overridesPath);
      await save(result.config);
    }
    return result;
  }

  /// Pushes the mapped colours into WorkingHours.
  Future<SyncReport> pushColors({bool quitApps = true}) async {
    final report = WorkingHoursSink(
      config: _config.workingHours,
      links: _config.links,
    ).applyColors(dryRun: false, quitApp: quitApps);
    _catalog = Catalog.read(_config);
    notifyListeners();
    return report;
  }

  /// Saves [config] and rescans with it.
  Future<void> save(AiTrackerConfig config) async {
    _config = config;
    config.save(configPath);
    _catalog = Catalog.read(config);
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
    final reports = syncAll(
      _config,
      _blocks,
      dryRun: !apply,
      quitApps: quitApps,
    );
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
