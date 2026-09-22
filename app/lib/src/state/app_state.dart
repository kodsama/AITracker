import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:aitracker_mcp/aitracker_mcp.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness, Color;

import '../theme.dart';

/// Which blocks the list shows.
enum BlockFilter {
  /// Everything in the window.
  all('All'),

  /// Only the blocks a rule or a hand edit put a project on.
  mapped('Mapped'),

  /// Only the blocks whose hours are going nowhere.
  unmapped('Unmapped');

  const BlockFilter(this.label);

  /// Name on the segment.
  final String label;

  /// Whether [block] belongs in this view.
  bool covers(TrackedBlock block) => switch (this) {
    BlockFilter.all => true,
    BlockFilter.mapped => block.project != null,
    BlockFilter.unmapped => block.project == null,
  };
}

/// How the hours are counted when two sessions overlap.
enum CountMode {
  /// A minute belongs to one project, so the totals add up to the clock. This
  /// is what a timesheet needs, and what every export writes.
  wallClock('Wall clock', 'A minute counts once, whoever was working'),

  /// Each project keeps its own timeline, so an hour worked in two
  /// repositories at once counts for both.
  perProject('Per project', 'Parallel sessions count for each project');

  const CountMode(this.label, this.help);

  /// Name on the toggle.
  final String label;

  /// One line of explanation under it.
  final String help;
}

/// Everything the windows read and write: the configuration, the blocks read
/// out of the transcripts, what is selected, and the MCP endpoint.
class AppState extends ChangeNotifier {
  /// Creates the state.
  ///
  /// [configPath] and [overridesPath] exist for the tests, as does
  /// [background]: scanning off the UI thread is what keeps the window
  /// responsive, and what makes a widget test wait on something it cannot
  /// pump.
  AppState({
    this.configPath,
    this.overridesPath,
    this.background = true,
  });

  /// Where the configuration is read from, null for the default location.
  final String? configPath;

  /// Where the hand edits are read from, null for the default location.
  final String? overridesPath;

  /// Whether a scan runs in its own isolate.
  final bool background;

  /// Where the MCP key is kept, null for the default location.
  String? get tokenPath => configPath == null
      ? null
      : '${configPath!.substring(0, configPath!.lastIndexOf('/'))}/mcp-token';

  /// Where the archive lives: beside whichever configuration is in use.
  String get historyPath => HistoryStore.besideConfig(configPath);

  AiTrackerConfig _config = const AiTrackerConfig(sources: []);
  OverrideStore _overrides = OverrideStore();
  Catalog _catalog = const Catalog();
  List<TrackedBlock> _blocks = const [];
  List<TrackedBlock> _exclusive = const [];
  List<TrackedBlock> _perProject = const [];
  final Set<String> _selected = {};
  PeriodKind _periodKind = PeriodKind.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;
  int _periodStep = 0;
  CountMode _mode = CountMode.wallClock;
  BlockFilter _filter = BlockFilter.all;
  String _query = '';
  bool _loading = true;
  bool _reading = false;
  int _scan = 0;
  ScanWorker? _worker;
  String? _trouble;
  List<SyncReport> _lastAutomatic = const [];
  ServerSocket? _mcp;

  /// Current configuration.
  AiTrackerConfig get config => _config;

  /// Blocks in the window, newest first, after the filter and the search box.
  List<TrackedBlock> get blocks {
    final needle = _query.trim().toLowerCase();
    if (_filter == BlockFilter.all && needle.isEmpty) return _blocks;
    return [
      for (final block in _blocks)
        if (_filter.covers(block) &&
            (needle.isEmpty || _haystack(block).contains(needle)))
          block,
    ];
  }

  /// What the search box looks through.
  ///
  /// A block with no project reads as "unmapped" on screen, so that is the word
  /// the search has to find it by.
  static String _haystack(TrackedBlock block) => [
    block.project ?? unmappedLabel,
    block.description,
    block.block.directory,
    if (block.excluded) 'excluded',
  ].join(' ').toLowerCase();

  /// Every block in the window, whatever the search box says.
  List<TrackedBlock> get allBlocks => _blocks;

  /// Keys of the selected blocks.
  Set<String> get selected => _selected;

  /// Window the screens are showing, after any stepping back or forward.
  Period get period => shiftPeriod(
    _periodKind,
    periodFor(_periodKind, start: _customStart, end: _customEnd),
    _periodStep,
  );

  /// How many windows away from the named one the screens are.
  int get periodStep => _periodStep;

  /// Which named window is selected.
  PeriodKind get periodKind => _periodKind;

  /// How overlapping sessions are counted.
  CountMode get mode => _mode;

  /// What the search box holds.
  String get query => _query;

  /// Which blocks the list is narrowed to.
  BlockFilter get filter => _filter;

  /// How many blocks each filter would show, for the counts on the segments.
  Map<BlockFilter, int> get filterCounts => {
    for (final filter in BlockFilter.values)
      filter: _blocks.where(filter.covers).length,
  };

  /// What the two apps already hold: projects, tags, companies.
  Catalog get catalog => _catalog;

  /// Whether a scan is in flight.
  bool get loading => _loading;

  /// Whether transcripts are being read into the archive, which on a first run
  /// takes a while and is worth saying out loud.
  bool get reading => _reading;

  /// What went wrong last, for the banner. Null when all is well.
  String? get trouble => _trouble;

  /// What the sinks set to file by themselves did on the last scan.
  List<SyncReport> get lastAutomatic => _lastAutomatic;

  /// Port the MCP endpoint is listening on, null when it is off.
  int? get mcpPort => _mcp?.port;

  /// Time per project in the window.
  Map<String, Duration> get byProject => totalsByProject(blocks);

  /// Directories in the window that no rule covers.
  Map<String, Duration> get strays => unmapped(blocks);

  /// Total billable time in the window, as the current mode counts it.
  Duration get total =>
      byProject.values.fold(Duration.zero, (sum, d) => sum + d);

  /// Time the assistant was working, counting a minute once however many
  /// sessions were in it.
  Duration get wallClock =>
      unionDuration([for (final block in _exclusive) block.block]);

  /// Tokens the window's exchanges reported.
  TokenUsage get tokens => _exclusive.fold(
    TokenUsage.zero,
    (sum, block) => sum + block.block.tokens,
  );

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

  /// Companies the ledger knows, plus the ones already mapped.
  List<String> get knownCompanies {
    final names = <String>{
      ..._catalog.companies,
      for (final link in _config.links)
        if (link.company != null) link.company!,
    };
    return names.toList()..sort();
  }

  /// The hand edit on [key], if there is one.
  BlockOverride? overrideFor(String key) => _overrides[key];

  /// Colour a project is drawn in: the one it was given, else the one the
  /// ledger draws it in, else its slot in the chart palette.
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

  /// Reads the configuration and scans the transcripts.
  ///
  /// The worker is started once and kept: it holds the parsed transcripts, so
  /// changing the window rereads only the files that moved.
  Future<void> load() async {
    _config = AiTrackerConfig.load(configPath);
    _overrides = OverrideStore.load(overridesPath);
    _catalog = Catalog.read(_config);
    _worker ??= background
        ? await ScanWorker.start(historyPath: historyPath)
        : null;
    if (_config.mcpEnabled && _mcp == null) await startMcp();
    await refresh();
  }

  /// Rescans the transcripts with the current configuration.
  ///
  /// The scan reads hundreds of files, so it runs off the UI thread; a scan
  /// started while one is running wins, and the older result is dropped rather
  /// than flickering onto the screen.
  Future<void> refresh() async {
    final generation = ++_scan;
    _loading = true;
    _trouble = null;
    notifyListeners();

    // What is already archived first, so a window paints at once; then the
    // transcripts, which on a first run is a minute of reading.
    await _load(generation, ingest: false);
    if (generation != _scan) return;
    _reading = true;
    notifyListeners();
    await _load(generation, ingest: true);
    if (generation != _scan) return;
    _reading = false;
    _loading = false;
    notifyListeners();
    await _fileAutomatically();
  }

  Future<void> _load(int generation, {required bool ingest}) async {
    final config = _config;
    final overrides = _overrides;
    final window = period;
    try {
      final worker = _worker;
      final found = worker != null
          ? await worker.scan(
              config: config,
              overrides: overrides,
              window: window,
              ingest: ingest,
            )
          : _scanHere(config, overrides, window, ingest: ingest);
      if (generation != _scan) return;
      _exclusive = found.wallClock;
      _perProject = found.perProject;
      _blocks = (_mode == CountMode.perProject ? _perProject : _exclusive)
          .reversed
          .toList();
      _selected.removeWhere((key) => !_blocks.any((b) => b.key == key));
      notifyListeners();
    } on Object catch (error) {
      if (generation != _scan) return;
      _trouble = 'Could not read the transcripts: $error';
    }
  }

  /// Scans on this thread, which is what the tests do: an isolate a widget
  /// test cannot pump is an isolate a widget test cannot wait for.
  ScanResult _scanHere(
    AiTrackerConfig config,
    OverrideStore overrides,
    Period window, {
    bool ingest = true,
  }) {
    final tracking = AiTracker(
      config: config,
      overrides: overrides,
      historyPath: historyPath,
    );
    return ScanResult(
      wallClock: tracking.blocks(
        since: window.start,
        until: window.end,
        ingest: ingest,
      ),
      perProject: tracking.blocks(
        since: window.start,
        until: window.end,
        mode: BlockMode.perProject,
        ingest: false,
      ),
    );
  }

  /// Runs the sinks that file by themselves.
  ///
  /// An automatic run never closes an app: if WorkingHours is open it is left
  /// alone and said so, because taking someone's timer away in the background
  /// is not a thing a background job should do.
  Future<void> _fileAutomatically() async {
    final automatic = _config.automaticSinks;
    if (automatic.isEmpty || _exclusive.isEmpty) return;
    try {
      _lastAutomatic = syncAll(
        _config,
        _exclusive,
        dryRun: false,
        only: automatic,
      );
    } on Object catch (error) {
      _trouble = 'Automatic filing failed: $error';
    }
    notifyListeners();
  }

  /// Switches the window and rescans. [start] and [end] apply to a custom one.
  Future<void> setPeriod(
    PeriodKind kind, {
    DateTime? start,
    DateTime? end,
  }) async {
    _periodKind = kind;
    _periodStep = 0;
    if (kind == PeriodKind.custom) {
      _customStart = start ?? _customStart;
      _customEnd = end ?? _customEnd;
    }
    await refresh();
  }

  /// Steps the window back or forward by its own length.
  Future<void> stepPeriod(int delta) async {
    _periodStep += delta;
    await refresh();
  }

  /// Switches how overlapping sessions are counted.
  ///
  /// Both readings come out of one scan, so this is a swap rather than a
  /// reason to go back to disk.
  void setMode(CountMode mode) {
    _mode = mode;
    _blocks = (mode == CountMode.perProject ? _perProject : _exclusive)
        .reversed
        .toList();
    _selected.removeWhere((key) => !_blocks.any((b) => b.key == key));
    notifyListeners();
  }

  /// Filters the list.
  void setQuery(String query) {
    _query = query;
    _dropUnseenSelection();
  }

  /// Narrows the list to mapped, unmapped or everything.
  void setFilter(BlockFilter filter) {
    _filter = filter;
    _dropUnseenSelection();
  }

  /// A block that has scrolled out of the list cannot stay selected, or a bulk
  /// edit would reach rows nobody can see.
  void _dropUnseenSelection() {
    final shown = blocks.map((b) => b.key).toSet();
    _selected.removeWhere((key) => !shown.contains(key));
    notifyListeners();
  }

  /// Selects or deselects one block.
  void toggle(String key) {
    if (!_selected.remove(key)) _selected.add(key);
    notifyListeners();
  }

  /// Selects every block on screen, or clears the selection.
  void toggleAll() {
    if (_selected.length == blocks.length) {
      _selected.clear();
    } else {
      _selected
        ..clear()
        ..addAll(blocks.map((b) => b.key));
    }
    notifyListeners();
  }

  /// Clears the selection.
  void selectNone() {
    _selected.clear();
    notifyListeners();
  }

  /// Adds every block of [day] to the selection.
  void selectDay(DateTime day) {
    _selected.addAll(
      blocks.where((b) => b.day == day).map((b) => b.key),
    );
    notifyListeners();
  }

  /// Adds every block of the week [day] falls in to the selection.
  void selectWeek(DateTime day) {
    final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
    final next = monday.add(const Duration(days: 7));
    _selected.addAll(
      blocks
          .where((b) => !b.day.isBefore(monday) && b.day.isBefore(next))
          .map((b) => b.key),
    );
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

  /// Adds or replaces the mapping for a project.
  Future<void> saveLink(ProjectLink link) async {
    final links = [
      for (final other in _config.links)
        if (other.name != link.name) other,
      link,
    ];
    await save(_config.copyWith(links: links));
  }

  /// Renames a project, carrying the name into the ledger if asked.
  Future<RenameResult> rename(
    String from,
    String to, {
    bool inWorkingHours = false,
    bool quitApps = true,
  }) async {
    final result = renameProject(
      _config,
      from: from,
      to: to,
      inWorkingHours: inWorkingHours,
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

  /// How each project's colour compares with the ledger's.
  List<ColourDifference> colourDifferences() =>
      compareColors(_config, _catalog);

  /// Copies the ledger's colours into the mapping.
  Future<void> importColors(Set<String> projects) async {
    await save(pullColors(_config, colourDifferences(), only: projects));
  }

  /// Writes the mapped colours into the ledger.
  Future<SyncReport> exportColors(Set<String> projects) async {
    final report = WorkingHoursSink(
      config: _config.workingHours,
      links: _config.links,
    ).applyColors(dryRun: false, quitApp: true, only: projects);
    _catalog = Catalog.read(_config);
    notifyListeners();
    return report;
  }

  /// Saves [config] and rescans with it.
  Future<void> save(AiTrackerConfig config) async {
    _config = config;
    config.save(configPath);
    _catalog = Catalog.read(config);
    await refresh();
    // After the scan, not before: a scan clears the last thing that went
    // wrong, and an endpoint that would not open is worth keeping on screen.
    // Against the configuration as it stands now, not as it was passed in, so
    // one save finishing late cannot undo a newer one.
    if (_config.mcpEnabled && _mcp == null) {
      await startMcp();
    } else if (!_config.mcpEnabled && _mcp != null) {
      await stopMcp();
    }
  }

  /// Previews or performs the writes, and returns what each sink reported.
  ///
  /// Exports always use the wall-clock blocks: a timesheet cannot hold the same
  /// minute twice, whatever the screen is showing.
  Future<List<SyncReport>> export({
    required bool apply,
    bool quitApps = false,
    Set<String> only = const {},
  }) async {
    final reports = syncAll(
      _config,
      _exclusive,
      dryRun: !apply,
      quitApps: quitApps,
      only: only,
    );
    if (apply) await refresh();
    return reports;
  }

  /// What the archive holds, for the line in Settings.
  HistorySummary archive() {
    final store = HistoryStore.open(historyPath);
    try {
      return store.summary();
    } finally {
      store.close();
    }
  }

  /// What WorkingHours now says about the blocks this tool wrote there.
  List<UnitDifference> readBackFromLedger() => readBack(_config, _exclusive);

  /// Adopts the ledger's version of the chosen blocks as hand edits.
  Future<void> adoptFromLedger(Iterable<UnitDifference> chosen) async {
    if (chosen.isEmpty) return;
    adopt(_overrides, chosen);
    _overrides.save(overridesPath);
    await refresh();
  }

  /// The key a networked client must present. Issued on first use.
  String get mcpToken => McpToken.ensure(tokenPath);

  /// Issues a new key, which drops every client using the old one.
  Future<String> regenerateMcpToken() async {
    final token = McpToken.issue(tokenPath);
    if (_mcp != null) {
      await stopMcp();
      await startMcp();
    }
    notifyListeners();
    return token;
  }

  /// Starts the MCP endpoint on the configured port.
  Future<void> startMcp() async {
    try {
      _mcp = await serveTcp(
        McpServer(
          tools: buildTools(
            configPath: configPath,
            overridesPath: overridesPath,
          ),
          requiredToken: McpToken.ensure(tokenPath),
        ),
        port: _config.mcpPort,
      );
    } on Object catch (error) {
      _trouble = 'Could not listen on port ${_config.mcpPort}: $error';
    }
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
    _worker?.stop();
    super.dispose();
  }
}
