import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Maps a transcript's working directory onto a target project name.
///
/// [match] is a case-insensitive substring of the session's directory; the
/// first rule that matches wins, so put the specific ones first.
class ProjectRule {
  /// Creates a rule.
  const ProjectRule({required this.match, required this.project});

  /// Substring matched against the session directory, case-insensitively.
  final String match;

  /// Project name written to the sinks, e.g. `Byte Buddies - idbuddy`.
  final String project;

  /// Reads a rule from its JSON form.
  factory ProjectRule.fromJson(Map<String, Object?> json) => ProjectRule(
    match: json['match']! as String,
    project: json['project']! as String,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {'match': match, 'project': project};
}

/// Where and how the WorkingHours sink writes.
class WorkingHoursSinkConfig {
  /// Creates the configuration.
  const WorkingHoursSinkConfig({
    this.enabled = true,
    this.databasePath = defaultDatabasePath,
    this.descriptionTemplate = 'AI: {repo}',
    this.color = '#FF6C4AB6',
  });

  /// Sandbox path of the WorkingHours store on macOS.
  static const String defaultDatabasePath =
      'Library/Containers/mac.partl.workinghours/Data/data.db';

  /// Whether a sync writes work units.
  final bool enabled;

  /// Absolute path, or one relative to the home directory.
  final String databasePath;

  /// Description written on each work unit. `{repo}`, `{project}`,
  /// `{company}` and `{sessions}` are substituted.
  final String descriptionTemplate;

  /// ARGB colour given to projects this tool creates.
  final String color;

  /// Reads the configuration from its JSON form.
  factory WorkingHoursSinkConfig.fromJson(Map<String, Object?> json) =>
      WorkingHoursSinkConfig(
        enabled: json['enabled'] as bool? ?? true,
        databasePath: json['database_path'] as String? ?? defaultDatabasePath,
        descriptionTemplate:
            json['description_template'] as String? ?? 'AI: {repo}',
        color: json['color'] as String? ?? '#FF6C4AB6',
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'database_path': databasePath,
    'description_template': descriptionTemplate,
    'color': color,
  };
}

/// Where and how the Diarium sink writes.
class DiariumSinkConfig {
  /// Creates the configuration.
  const DiariumSinkConfig({
    this.enabled = false,
    this.databasePath = defaultDatabasePath,
    this.heading = 'AI hours',
    this.entryTimeOfDay = '23:55',
  });

  /// Sandbox path of the Diarium store on macOS.
  static const String defaultDatabasePath =
      'Library/Containers/mac.partl.Diarium/Data/data.db';

  /// Whether a sync writes journal entries.
  final bool enabled;

  /// Absolute path, or one relative to the home directory.
  final String databasePath;

  /// Heading of the entry this tool owns.
  final String heading;

  /// `HH:mm` the daily entry is stamped with. Diarium keys entries by their
  /// timestamp, so a fixed time makes re-runs update rather than duplicate.
  final String entryTimeOfDay;

  /// Reads the configuration from its JSON form.
  factory DiariumSinkConfig.fromJson(Map<String, Object?> json) =>
      DiariumSinkConfig(
        enabled: json['enabled'] as bool? ?? false,
        databasePath: json['database_path'] as String? ?? defaultDatabasePath,
        heading: json['heading'] as String? ?? 'AI hours',
        entryTimeOfDay: json['entry_time_of_day'] as String? ?? '23:55',
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'database_path': databasePath,
    'heading': heading,
    'entry_time_of_day': entryTimeOfDay,
  };
}

/// Where the spreadsheet exports land.
class TabularSinkConfig {
  /// Creates the configuration.
  const TabularSinkConfig({
    this.enabled = false,
    this.csvPath = 'Documents/AI hours.csv',
    this.xlsxPath = 'Documents/AI hours.xlsx',
  });

  /// Whether a sync writes the spreadsheets.
  final bool enabled;

  /// Absolute path, or one relative to the home directory.
  final String csvPath;

  /// Absolute path, or one relative to the home directory.
  final String xlsxPath;

  /// Reads the configuration from its JSON form.
  factory TabularSinkConfig.fromJson(Map<String, Object?> json) =>
      TabularSinkConfig(
        enabled: json['enabled'] as bool? ?? false,
        csvPath: json['csv_path'] as String? ?? 'Documents/AI hours.csv',
        xlsxPath: json['xlsx_path'] as String? ?? 'Documents/AI hours.xlsx',
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'csv_path': csvPath,
    'xlsx_path': xlsxPath,
  };
}

/// Everything the engine reads before it touches a transcript or a store.
class AiTrackingConfig {
  /// Creates a configuration.
  const AiTrackingConfig({
    required this.sources,
    this.idleGap = const Duration(minutes: 10),
    this.minBlock = const Duration(minutes: 5),
    this.rules = const [],
    this.fallbackProject,
    this.workingHours = const WorkingHoursSinkConfig(),
    this.diarium = const DiariumSinkConfig(),
    this.tabular = const TabularSinkConfig(),
    this.mcpEnabled = false,
    this.mcpPort = 8788,
  });

  /// Directories holding one subdirectory per project of `*.jsonl` transcripts.
  final List<String> sources;

  /// Silence longer than this ends a work block.
  final Duration idleGap;

  /// Blocks shorter than this are dropped as noise.
  final Duration minBlock;

  /// Directory-to-project rules, most specific first.
  final List<ProjectRule> rules;

  /// Project for sessions no rule matches. Null leaves them unassigned, which
  /// keeps them out of the sinks and lists them as unmapped instead.
  final String? fallbackProject;

  /// WorkingHours sink settings.
  final WorkingHoursSinkConfig workingHours;

  /// Diarium sink settings.
  final DiariumSinkConfig diarium;

  /// CSV and Excel sink settings.
  final TabularSinkConfig tabular;

  /// Whether the desktop app serves MCP on a local socket while it runs.
  final bool mcpEnabled;

  /// Port that socket binds to.
  final int mcpPort;

  /// Configuration with no rules, scanning whatever transcript roots exist.
  factory AiTrackingConfig.initial() =>
      AiTrackingConfig(sources: discoverSources());

  /// Reads a configuration from its JSON form.
  factory AiTrackingConfig.fromJson(Map<String, Object?> json) {
    final sources = (json['sources'] as List?)?.map((e) => '$e').toList();
    return AiTrackingConfig(
      sources: sources == null || sources.isEmpty
          ? discoverSources()
          : sources,
      idleGap: Duration(minutes: json['idle_gap_minutes'] as int? ?? 10),
      minBlock: Duration(minutes: json['min_block_minutes'] as int? ?? 5),
      rules: [
        for (final rule in (json['rules'] as List?) ?? const [])
          ProjectRule.fromJson((rule as Map).cast<String, Object?>()),
      ],
      fallbackProject: json['fallback_project'] as String?,
      workingHours: WorkingHoursSinkConfig.fromJson(
        (json['working_hours'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      diarium: DiariumSinkConfig.fromJson(
        (json['diarium'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      tabular: TabularSinkConfig.fromJson(
        (json['tabular'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      mcpEnabled: json['mcp_enabled'] as bool? ?? false,
      mcpPort: json['mcp_port'] as int? ?? 8788,
    );
  }

  /// JSON form, as written to [defaultPath].
  Map<String, Object?> toJson() => {
    'sources': sources,
    'idle_gap_minutes': idleGap.inMinutes,
    'min_block_minutes': minBlock.inMinutes,
    'rules': [for (final rule in rules) rule.toJson()],
    'fallback_project': fallbackProject,
    'working_hours': workingHours.toJson(),
    'diarium': diarium.toJson(),
    'tabular': tabular.toJson(),
    'mcp_enabled': mcpEnabled,
    'mcp_port': mcpPort,
  };

  /// A copy with the given fields replaced.
  AiTrackingConfig copyWith({
    List<String>? sources,
    Duration? idleGap,
    Duration? minBlock,
    List<ProjectRule>? rules,
    String? fallbackProject,
    WorkingHoursSinkConfig? workingHours,
    DiariumSinkConfig? diarium,
    TabularSinkConfig? tabular,
    bool? mcpEnabled,
    int? mcpPort,
  }) => AiTrackingConfig(
    sources: sources ?? this.sources,
    idleGap: idleGap ?? this.idleGap,
    minBlock: minBlock ?? this.minBlock,
    rules: rules ?? this.rules,
    fallbackProject: fallbackProject ?? this.fallbackProject,
    workingHours: workingHours ?? this.workingHours,
    diarium: diarium ?? this.diarium,
    tabular: tabular ?? this.tabular,
    mcpEnabled: mcpEnabled ?? this.mcpEnabled,
    mcpPort: mcpPort ?? this.mcpPort,
  );

  /// Project a session in [directory] belongs to, or null when no rule matches
  /// and no [fallbackProject] is set.
  ///
  /// Separators, spaces and underscores are folded to hyphens on both sides, so
  /// one rule reads the same against the real path (`Byte Buddies/idbuddy`) and
  /// against the flattened folder name Claude Code stores transcripts under
  /// (`byte-buddies-idbuddy`).
  String? projectFor(String directory) {
    final haystack = _fold(directory);
    for (final rule in rules) {
      if (haystack.contains(_fold(rule.match))) return rule.project;
    }
    return fallbackProject;
  }

  static String _fold(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s/\\_-]+'), '-');

  /// Every `~/.claude*/projects` directory on the machine.
  ///
  /// Claude Code keeps its transcripts there, and `CLAUDE_CONFIG_DIR` lets a
  /// distribution move that root, so the glob catches side-by-side installs.
  static List<String> discoverSources() {
    final home = homeDirectory();
    final found = <String>[];
    final configured = Platform.environment['CLAUDE_CONFIG_DIR'];
    if (configured != null && configured.isNotEmpty) {
      found.add(p.join(configured, 'projects'));
    }
    final dir = Directory(home);
    if (dir.existsSync()) {
      for (final entry in dir.listSync().whereType<Directory>()) {
        final name = p.basename(entry.path);
        if (!name.startsWith('.claude')) continue;
        final projects = p.join(entry.path, 'projects');
        if (Directory(projects).existsSync() && !found.contains(projects)) {
          found.add(projects);
        }
      }
    }
    found.sort();
    return found;
  }

  /// The user's home directory.
  static String homeDirectory() =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;

  /// Resolves [path] against the home directory when it is relative.
  static String resolveHome(String path) =>
      p.isAbsolute(path) ? path : p.join(homeDirectory(), path);

  /// Where the configuration lives: `$AITRACKING_CONFIG`, else
  /// `~/Library/Application Support/AITracking/config.json`.
  static String defaultPath() {
    final override = Platform.environment['AITRACKING_CONFIG'];
    if (override != null && override.isNotEmpty) return override;
    return p.join(
      homeDirectory(),
      'Library',
      'Application Support',
      'AITracking',
      'config.json',
    );
  }

  /// Loads the configuration from [path], falling back to [initial] when the
  /// file does not exist yet.
  static AiTrackingConfig load([String? path]) {
    final file = File(path ?? defaultPath());
    if (!file.existsSync()) return AiTrackingConfig.initial();
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return AiTrackingConfig.initial();
    return AiTrackingConfig.fromJson(decoded.cast<String, Object?>());
  }

  /// Writes the configuration to [path], creating the directory if needed.
  void save([String? path]) {
    final file = File(path ?? defaultPath());
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
    );
  }
}
