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


/// The separator WorkingHours projects put between the company and the work.
const String kProjectSeparator = ' - ';

/// `Byte Buddies - idbuddy`, the shape the ledger names a project.
///
/// A company on its own is not a project, and a project without a company is
/// just its own name, so both those cases fall back rather than leaving a
/// dangling separator.
String composeProjectName(String company, String project) {
  final left = company.trim();
  final right = project.trim();
  if (left.isEmpty) return right;
  if (right.isEmpty) return left;
  return '$left$kProjectSeparator$right';
}

/// Splits `Byte Buddies - idbuddy` back into its two halves.
///
/// Only the first separator counts: a project called `idbuddy - web` under
/// `Byte Buddies` keeps its own name intact.
({String company, String project}) splitProjectName(String name) {
  final at = name.indexOf(kProjectSeparator);
  if (at < 0) return (company: '', project: name.trim());
  return (
    company: name.substring(0, at).trim(),
    project: name.substring(at + kProjectSeparator.length).trim(),
  );
}

/// How one project this tool tracks lines up with the two apps.
///
/// Without an entry the project name is used verbatim in both. With one, the
/// same work can be filed under a different project name in WorkingHours, be
/// tagged there, and carry its own tag in the Diarium journal, so the three
/// apps can each keep the names their own users expect.
class ProjectLink {
  /// Creates a link.
  const ProjectLink({
    required this.name,
    this.workingHours,
    this.company,
    this.workingHoursTags = const [],
    this.calendarLabel,
    this.color,
  });

  /// Project name as this tool knows it, matching what a rule assigns.
  final String name;

  /// Project name in WorkingHours. Null means [name].
  final String? workingHours;

  /// Tag attached to the WorkingHours project when this tool creates it, which
  /// is how that ledger records the company.
  final String? company;

  /// Tags put on every work unit written for this project.
  final List<String> workingHoursTags;

  /// Name this project goes under in the published calendar, and so in
  /// Diarium. Null uses the project's own name.
  final String? calendarLabel;

  /// Colour for this project, `#AARRGGBB` as WorkingHours writes it. Null
  /// leaves the sink's default.
  final String? color;

  /// Project name to write in WorkingHours.
  String get workingHoursProject => workingHours ?? name;

  /// Reads a link from its JSON form.
  factory ProjectLink.fromJson(Map<String, Object?> json) => ProjectLink(
    name: json['name']! as String,
    workingHours: json['working_hours'] as String?,
    company: json['company'] as String?,
    workingHoursTags: [
      for (final tag in (json['working_hours_tags'] as List?) ?? const [])
        '$tag',
    ],
    calendarLabel: json['calendar_label'] as String?,
    color: json['color'] as String?,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'name': name,
    if (workingHours != null) 'working_hours': workingHours,
    if (company != null) 'company': company,
    if (workingHoursTags.isNotEmpty) 'working_hours_tags': workingHoursTags,
    if (calendarLabel != null) 'calendar_label': calendarLabel,
    if (color != null) 'color': color,
  };

  /// A copy with the given fields replaced.
  ProjectLink copyWith({
    String? name,
    String? workingHours,
    String? company,
    List<String>? workingHoursTags,
    String? calendarLabel,
    String? color,
  }) => ProjectLink(
    name: name ?? this.name,
    workingHours: workingHours ?? this.workingHours,
    company: company ?? this.company,
    workingHoursTags: workingHoursTags ?? this.workingHoursTags,
    calendarLabel: calendarLabel ?? this.calendarLabel,
    color: color ?? this.color,
  );
}

/// Where and how the WorkingHours sink writes.
class WorkingHoursSinkConfig {
  /// Creates the configuration.
  const WorkingHoursSinkConfig({
    this.enabled = true,
    this.databasePath = defaultDatabasePath,
    this.descriptionTemplate = 'AI: {repo}',
    this.color = '#FF6C4AB6',
    this.automatic = false,
  });

  /// Sandbox path of the WorkingHours store on macOS.
  static const String defaultDatabasePath =
      'Library/Containers/mac.partl.workinghours/Data/data.db';

  /// Whether a sync writes work units.
  final bool enabled;

  /// Whether the app files to it as soon as it finds new activity, rather than
  /// waiting for the button.
  final bool automatic;

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
        automatic: json['automatic'] as bool? ?? false,
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'database_path': databasePath,
    'description_template': descriptionTemplate,
    'color': color,
    'automatic': automatic,
  };
}

/// Where and how the calendar this tool publishes is written.
class CalendarSinkConfig {
  /// Creates the configuration.
  const CalendarSinkConfig({
    this.enabled = false,
    this.calendarName = 'AI work',
    this.titleTemplate = 'AI work: {hours}',
    this.automatic = false,
  });

  /// Whether an export publishes the calendar.
  final bool enabled;

  /// Calendar to keep, created on a local source if it is not there.
  final String calendarName;

  /// Title of each day's event. `{hours}` is the day's total.
  final String titleTemplate;

  /// Whether the app republishes it as soon as it finds new activity.
  final bool automatic;

  /// Reads the configuration from its JSON form.
  factory CalendarSinkConfig.fromJson(Map<String, Object?> json) =>
      CalendarSinkConfig(
        enabled: json['enabled'] as bool? ?? false,
        calendarName: json['calendar_name'] as String? ?? 'AI work',
        titleTemplate: json['title_template'] as String? ?? 'AI work: {hours}',
        automatic: json['automatic'] as bool? ?? false,
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'calendar_name': calendarName,
    'title_template': titleTemplate,
    'automatic': automatic,
  };
}

/// Where the spreadsheet exports land.
class TabularSinkConfig {
  /// Creates the configuration.
  const TabularSinkConfig({
    this.enabled = false,
    this.csvPath = 'Documents/AI hours.csv',
    this.xlsxPath = 'Documents/AI hours.xlsx',
    this.automatic = false,
  });

  /// Whether a sync writes the spreadsheets.
  final bool enabled;

  /// Whether the app rewrites them as soon as it finds new activity.
  final bool automatic;

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
        automatic: json['automatic'] as bool? ?? false,
      );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'csv_path': csvPath,
    'xlsx_path': xlsxPath,
    'automatic': automatic,
  };
}

/// Everything the engine reads before it touches a transcript or a store.
class AiTrackerConfig {
  /// Creates a configuration.
  const AiTrackerConfig({
    required this.sources,
    this.idleGap = const Duration(minutes: 10),
    this.minBlock = const Duration(minutes: 5),
    this.rules = const [],
    this.links = const [],
    this.fallbackProject,
    this.workingHours = const WorkingHoursSinkConfig(),
    this.calendar = const CalendarSinkConfig(),
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

  /// How each project lines up with WorkingHours and Diarium.
  final List<ProjectLink> links;

  /// Project for sessions no rule matches. Null leaves them unassigned, which
  /// keeps them out of the sinks and lists them as unmapped instead.
  final String? fallbackProject;

  /// Sinks set to file by themselves.
  Set<String> get automaticSinks => {
    if (workingHours.enabled && workingHours.automatic) 'workinghours',
    if (calendar.enabled && calendar.automatic) 'calendar',
    if (tabular.enabled && tabular.automatic) 'tabular',
  };

  /// WorkingHours sink settings.
  final WorkingHoursSinkConfig workingHours;

  /// Calendar sink settings.
  final CalendarSinkConfig calendar;

  /// CSV and Excel sink settings.
  final TabularSinkConfig tabular;

  /// Whether the desktop app serves MCP on a local socket while it runs.
  final bool mcpEnabled;

  /// Port that socket binds to.
  final int mcpPort;

  /// Configuration with no rules, scanning whatever transcript roots exist.
  factory AiTrackerConfig.initial() =>
      AiTrackerConfig(sources: discoverSources());

  /// Reads a configuration from its JSON form.
  factory AiTrackerConfig.fromJson(Map<String, Object?> json) {
    final sources = (json['sources'] as List?)?.map((e) => '$e').toList();
    return AiTrackerConfig(
      sources: sources == null || sources.isEmpty
          ? discoverSources()
          : sources,
      idleGap: Duration(minutes: json['idle_gap_minutes'] as int? ?? 10),
      minBlock: Duration(minutes: json['min_block_minutes'] as int? ?? 5),
      rules: [
        for (final rule in (json['rules'] as List?) ?? const [])
          ProjectRule.fromJson((rule as Map).cast<String, Object?>()),
      ],
      links: [
        for (final link in (json['projects'] as List?) ?? const [])
          ProjectLink.fromJson((link as Map).cast<String, Object?>()),
      ],
      fallbackProject: json['fallback_project'] as String?,
      workingHours: WorkingHoursSinkConfig.fromJson(
        (json['working_hours'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      calendar: CalendarSinkConfig.fromJson(
        (json['calendar'] as Map?)?.cast<String, Object?>() ?? const {},
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
    'projects': [for (final link in links) link.toJson()],
    'fallback_project': fallbackProject,
    'working_hours': workingHours.toJson(),
    'calendar': calendar.toJson(),
    'tabular': tabular.toJson(),
    'mcp_enabled': mcpEnabled,
    'mcp_port': mcpPort,
  };

  /// A copy with the given fields replaced.
  AiTrackerConfig copyWith({
    List<String>? sources,
    Duration? idleGap,
    Duration? minBlock,
    List<ProjectRule>? rules,
    List<ProjectLink>? links,
    String? fallbackProject,
    WorkingHoursSinkConfig? workingHours,
    CalendarSinkConfig? calendar,
    TabularSinkConfig? tabular,
    bool? mcpEnabled,
    int? mcpPort,
  }) => AiTrackerConfig(
    sources: sources ?? this.sources,
    idleGap: idleGap ?? this.idleGap,
    minBlock: minBlock ?? this.minBlock,
    rules: rules ?? this.rules,
    links: links ?? this.links,
    fallbackProject: fallbackProject ?? this.fallbackProject,
    workingHours: workingHours ?? this.workingHours,
    calendar: calendar ?? this.calendar,
    tabular: tabular ?? this.tabular,
    mcpEnabled: mcpEnabled ?? this.mcpEnabled,
    mcpPort: mcpPort ?? this.mcpPort,
  );

  /// How [project] lines up with the two apps, if it has been mapped.
  ProjectLink? linkFor(String project) {
    for (final link in links) {
      if (link.name == project) return link;
    }
    return null;
  }

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

  /// Transcript folders the assistants on this machine are known to use.
  ///
  /// Claude Code keeps one directory per project under `~/.claude*/projects`,
  /// and `CLAUDE_CONFIG_DIR` lets a distribution move that root, so the sweep
  /// catches side-by-side installs. The others keep a history file under a
  /// folder of their own. A folder that is not there is not offered.
  static List<String> discoverSources() {
    final home = homeDirectory();
    final found = <String>[];

    void add(String path, {bool onlyWithTranscripts = false}) {
      if (found.contains(path)) return;
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      if (onlyWithTranscripts && !holdsTranscripts(dir)) return;
      found.add(path);
    }

    final configured = Platform.environment['CLAUDE_CONFIG_DIR'];
    if (configured != null && configured.isNotEmpty) {
      add(p.join(configured, 'projects'));
    }
    final dir = Directory(home);
    if (dir.existsSync()) {
      for (final entry in dir.listSync().whereType<Directory>()) {
        final name = p.basename(entry.path);
        if (!name.startsWith('.claude')) continue;
        add(p.join(entry.path, 'projects'));
      }
    }
    for (final assistant in assistantFolders) {
      add(p.join(home, assistant), onlyWithTranscripts: true);
    }
    found.sort();
    return found;
  }

  /// Folders the other assistants keep their history in.
  ///
  /// Each is offered when it holds transcripts, so a machine picks up whichever
  /// assistants it actually has. Several of these also exist as editor support
  /// folders full of extensions and caches; those hold no transcripts and are
  /// not offered, and would start being offered the day they do.
  static const List<String> assistantFolders = [
    '.gemini',
    '.antigravity',
    '.antigravity-ide',
    '.codex',
    '.cursor',
    '.windsurf',
    '.aider',
  ];

  /// Whether [dir] holds a transcript within [depth] levels.
  ///
  /// Stops at the first one: some of these folders hold thousands of files and
  /// the question is only whether there is anything to read.
  static bool holdsTranscripts(Directory dir, {int depth = 3}) {
    if (depth < 0) return false;
    try {
      for (final entry in dir.listSync(followLinks: false)) {
        if (entry is File && p.extension(entry.path) == '.jsonl') return true;
        if (entry is Directory && holdsTranscripts(entry, depth: depth - 1)) {
          return true;
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  /// The user's home directory.
  static String homeDirectory() =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;

  /// Resolves [path] against the home directory when it is relative.
  static String resolveHome(String path) =>
      p.isAbsolute(path) ? path : p.join(homeDirectory(), path);

  /// Where the configuration lives: `$AITRACKER_CONFIG`, else
  /// `~/Library/Application Support/AITracker/config.json`.
  static String defaultPath() {
    final override = Platform.environment['AITRACKER_CONFIG'];
    if (override != null && override.isNotEmpty) return override;
    return p.join(
      homeDirectory(),
      'Library',
      'Application Support',
      'AITracker',
      'config.json',
    );
  }

  /// Loads the configuration from [path], falling back to [initial] when the
  /// file does not exist yet.
  static AiTrackerConfig load([String? path]) {
    final file = File(path ?? defaultPath());
    if (!file.existsSync()) return AiTrackerConfig.initial();
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return AiTrackerConfig.initial();
    return AiTrackerConfig.fromJson(decoded.cast<String, Object?>());
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
