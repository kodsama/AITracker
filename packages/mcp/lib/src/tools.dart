import 'package:aitracker_engine/aitracker_engine.dart';

/// One MCP tool: a name, a human description, a JSON-Schema for its arguments,
/// and an executor that runs the engine and returns a structured result.
class McpTool {
  /// Creates a tool.
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.run,
  });

  /// Tool name as exposed to the client (snake_case).
  final String name;

  /// One-line description shown in `tools/list`.
  final String description;

  /// JSON Schema (draft-07 style) describing the `arguments` object.
  final Map<String, Object?> inputSchema;

  /// Executes the tool with [args]; returns a structured result map.
  final Future<Map<String, Object?>> Function(Map<String, Object?> args) run;
}

/// Builds the AITracker tool catalog.
///
/// Configuration and hand edits are read on every call rather than captured
/// once, so a change made in the desktop app is live for the next tool call.
/// [configPath] and [overridesPath] override where those live, which is what
/// the tests use.
List<McpTool> buildTools({String? configPath, String? overridesPath}) {
  AiTracker tracking() => AiTracker(
    config: AiTrackerConfig.load(configPath),
    overrides: OverrideStore.load(overridesPath),
    historyPath: HistoryStore.besideConfig(configPath),
  );

  List<TrackedBlock> read(Map<String, Object?> args) =>
      tracking().blocks(since: _since(args), until: _until(args));

  return [
    McpTool(
      name: 'list_hours',
      description:
          'List the blocks of time spent with an AI assistant, each with the '
          'project it bills to, read from the assistant transcripts.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'days': _days,
          'since': _iso('Only blocks starting at or after this local time.'),
          'until': _iso('Only blocks starting before this local time.'),
          'include_unmapped': {
            'type': 'boolean',
            'description':
                'Include blocks no rule maps to a project. Default true.',
          },
        },
      },
      run: (args) async {
        final includeUnmapped = args['include_unmapped'] as bool? ?? true;
        final blocks = read(
          args,
        ).where((b) => includeUnmapped || b.billable).toList();
        return {
          'ok': true,
          'blocks': [for (final block in blocks) _block(block)],
          'total_hours': _hours(
            blocks.fold(Duration.zero, (sum, b) => sum + b.block.duration),
          ),
        };
      },
    ),
    McpTool(
      name: 'summarize_hours',
      description:
          'Total the AI hours by project and by day over a window, the shape a '
          'timesheet or an invoice needs.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'days': _days,
          'since': _iso('Start of the window, local time.'),
          'until': _iso('End of the window, local time.'),
        },
      },
      run: (args) async {
        final blocks = read(args);
        final byProject = totalsByProject(blocks);
        final byDay = totalsByDay(blocks);
        return {
          'ok': true,
          'by_project': {
            for (final entry in byProject.entries)
              entry.key: _hours(entry.value),
          },
          'by_day': {
            for (final entry in byDay.entries)
              entry.key.toIso8601String().substring(0, 10): _hours(entry.value),
          },
          'total_hours': _hours(
            byProject.values.fold(Duration.zero, (sum, d) => sum + d),
          ),
        };
      },
    ),
    McpTool(
      name: 'list_unmapped',
      description:
          'Directories that hold AI hours no rule maps to a project, with how '
          'much time each is sitting on. These are the hours going nowhere.',
      inputSchema: {
        'type': 'object',
        'properties': {'days': _days, 'since': _iso('Start of the window.')},
      },
      run: (args) async {
        final totals = unmapped(read(args));
        return {
          'ok': true,
          'directories': [
            for (final entry in totals.entries)
              {'directory': entry.key, 'hours': _hours(entry.value)},
          ],
        };
      },
    ),
    McpTool(
      name: 'sync_workinghours',
      description:
          'File the blocks into the WorkingHours store. Previews by default; '
          'pass dry_run false to write. Time the ledger already holds is never '
          'written twice.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'days': _days,
          'since': _iso('Start of the window.'),
          'until': _iso('End of the window.'),
          'dry_run': _dryRun,
          'quit_app': _quitApp('WorkingHours'),
        },
      },
      run: (args) async {
        final config = AiTrackerConfig.load(configPath);
        final report = WorkingHoursSink(
          config: config.workingHours,
          minBlock: config.minBlock,
        ).sync(
          read(args),
          dryRun: args['dry_run'] as bool? ?? true,
          quitApp: args['quit_app'] as bool? ?? false,
        );
        return {'ok': report.refusal == null, ...report.toJson()};
      },
    ),
    McpTool(
      name: 'sync_calendar',
      description:
          'Publish the hours as a macOS calendar, one all-day event per worked '
          'day. Diarium reads system calendars, so this is how the hours show '
          'up there. Previews by default.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'days': _days,
          'since': _iso('Start of the window.'),
          'until': _iso('End of the window.'),
          'dry_run': _dryRun,
        },
      },
      run: (args) async {
        final config = AiTrackerConfig.load(configPath);
        final report = CalendarSink(
          config: config.calendar,
          links: config.links,
        ).sync(read(args), dryRun: args['dry_run'] as bool? ?? true);
        return {'ok': report.refusal == null, ...report.toJson()};
      },
    ),
    McpTool(
      name: 'sync_all',
      description:
          'File the blocks everywhere at once: WorkingHours, Diarium and the '
          'spreadsheets, whichever are enabled. Previews by default. Each app '
          'is closed and reopened on its own, and a refusal from one still '
          'leaves the others written.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'days': _days,
          'since': _iso('Start of the window.'),
          'until': _iso('End of the window.'),
          'dry_run': _dryRun,
          'quit_app': _quitApp('each app'),
          'only': {
            'type': 'array',
            'items': {'type': 'string', 'enum': kSinkNames},
            'description': 'Narrow the run to these sinks. Default: all of them.',
          },
        },
      },
      run: (args) async {
        final reports = syncAll(
          AiTrackerConfig.load(configPath),
          read(args),
          dryRun: args['dry_run'] as bool? ?? true,
          quitApps: args['quit_app'] as bool? ?? false,
          only: {for (final sink in (args['only'] as List?) ?? const []) '$sink'},
        );
        return {
          'ok': reports.every((r) => r.refusal == null),
          'sinks': [for (final report in reports) report.toJson()],
        };
      },
    ),
    McpTool(
      name: 'export_spreadsheet',
      description:
          'Write the blocks to the configured CSV and Excel files, one row per '
          'block, including the ones no rule mapped.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'days': _days,
          'since': _iso('Start of the window.'),
          'until': _iso('End of the window.'),
          'dry_run': _dryRun,
        },
      },
      run: (args) async {
        final config = AiTrackerConfig.load(configPath);
        final report = TabularSink(
          config: config.tabular,
        ).sync(read(args), dryRun: args['dry_run'] as bool? ?? true);
        return {'ok': true, ...report.toJson()};
      },
    ),
    McpTool(
      name: 'list_catalog',
      description:
          'What WorkingHours and Diarium already hold: projects with their '
          'colours, tags, the companies the ledger records, and the journal '
          'tags. Map onto these rather than inventing names.',
      inputSchema: const {'type': 'object', 'properties': <String, Object?>{}},
      run: (args) async => {
        'ok': true,
        ...Catalog.read(AiTrackerConfig.load(configPath)).toJson(),
      },
    ),
    McpTool(
      name: 'set_project_link',
      description:
          'Line a project up with the two apps: the name it is filed under in '
          'WorkingHours, its company tag there, the tags put on each work '
          'unit, its Diarium tag, and its colour.',
      inputSchema: {
        'type': 'object',
        'required': ['name'],
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Project name as this tool knows it.',
          },
          'working_hours': {
            'type': 'string',
            'description':
                'Project name in WorkingHours, when it differs from name.',
          },
          'company': {
            'type': 'string',
            'description':
                'Tag attached to the WorkingHours project, which is how that '
                'ledger records the company.',
          },
          'working_hours_tags': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Tags put on every work unit written.',
          },
          'calendar_label': {
            'type': 'string',
            'description':
                'Name this project goes under in the published calendar, and '
                'so in Diarium.',
          },
          'color': {
            'type': 'string',
            'description': 'Colour as #AARRGGBB, the way WorkingHours holds it.',
          },
        },
      },
      run: (args) async {
        final name = args['name']! as String;
        final config = AiTrackerConfig.load(configPath);
        final existing = config.linkFor(name);
        final link = ProjectLink(
          name: name,
          workingHours: args['working_hours'] as String? ?? existing?.workingHours,
          company: args['company'] as String? ?? existing?.company,
          workingHoursTags: args['working_hours_tags'] == null
              ? existing?.workingHoursTags ?? const []
              : [for (final tag in args['working_hours_tags']! as List) '$tag'],
          calendarLabel:
              args['calendar_label'] as String? ?? existing?.calendarLabel,
          color: args['color'] as String? ?? existing?.color,
        );
        final links = [
          for (final other in config.links)
            if (other.name != name) other,
          link,
        ];
        config.copyWith(links: links).save(configPath);
        return {'ok': true, 'link': link.toJson()};
      },
    ),
    McpTool(
      name: 'rename_project',
      description:
          'Rename a project. The rules, the mapping and the hand edits always '
          'move with it; WorkingHours and Diarium only when asked, which is how '
          'the same work can carry a different name in each app.',
      inputSchema: {
        'type': 'object',
        'required': ['from', 'to'],
        'properties': {
          'from': {'type': 'string', 'description': 'Current project name.'},
          'to': {'type': 'string', 'description': 'New project name.'},
          'in_working_hours': {
            'type': 'boolean',
            'description': 'Also rename the WorkingHours project. Default false.',
          },
          'dry_run': _dryRun,
          'quit_app': _quitApp('each app'),
        },
      },
      run: (args) async {
        final overrides = OverrideStore.load(overridesPath);
        final result = renameProject(
          AiTrackerConfig.load(configPath),
          from: args['from']! as String,
          to: args['to']! as String,
          inWorkingHours: args['in_working_hours'] as bool? ?? false,
          dryRun: args['dry_run'] as bool? ?? true,
          quitApps: args['quit_app'] as bool? ?? false,
          overrides: overrides,
        );
        if (result.applied) {
          result.config.save(configPath);
          overrides.save(overridesPath);
        }
        return {'ok': result.refusal == null, ...result.toJson()};
      },
    ),
    McpTool(
      name: 'sync_project_colors',
      description:
          'Write the mapped colours into WorkingHours so a project is drawn the '
          'same in both apps. Previews by default.',
      inputSchema: {
        'type': 'object',
        'properties': {'dry_run': _dryRun, 'quit_app': _quitApp('WorkingHours')},
      },
      run: (args) async {
        final config = AiTrackerConfig.load(configPath);
        final report = WorkingHoursSink(
          config: config.workingHours,
          links: config.links,
        ).applyColors(
          dryRun: args['dry_run'] as bool? ?? true,
          quitApp: args['quit_app'] as bool? ?? false,
        );
        return {'ok': report.refusal == null, ...report.toJson()};
      },
    ),
    McpTool(
      name: 'read_back_changes',
      description:
          'What WorkingHours now says about the units this tool wrote there: '
          'ones moved to another project, renamed or retimed. With adopt true '
          'the ledger version is kept as a hand edit, so the next scan does not '
          'undo it.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'days': _days,
          'since': _iso('Start of the window.'),
          'until': _iso('End of the window.'),
          'adopt': {
            'type': 'boolean',
            'description': 'Keep the ledger version. Default false, which only '
                'reports the differences.',
          },
          'keys': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Adopt only these blocks, as list_hours keys them. Omit for '
                'every difference.',
          },
        },
      },
      run: (args) async {
        final config = AiTrackerConfig.load(configPath);
        final differences = readBack(config, read(args));
        final wanted = args['keys'] == null
            ? differences
            : [
                for (final difference in differences)
                  if ((args['keys']! as List)
                      .map((k) => '$k')
                      .contains(difference.block.key))
                    difference,
              ];
        final adopting = args['adopt'] as bool? ?? false;
        if (adopting && wanted.isNotEmpty) {
          final overrides = OverrideStore.load(overridesPath);
          adopt(overrides, wanted);
          overrides.save(overridesPath);
        }
        return {
          'ok': true,
          'adopted': adopting ? wanted.length : 0,
          'changes': [for (final difference in wanted) difference.toJson()],
        };
      },
    ),
    McpTool(
      name: 'get_config',
      description:
          'The current configuration: transcript sources, thresholds, the '
          'directory-to-project rules and the sink settings.',
      inputSchema: const {'type': 'object', 'properties': <String, Object?>{}},
      run: (args) async => {
        'ok': true,
        'path': configPath ?? AiTrackerConfig.defaultPath(),
        'config': AiTrackerConfig.load(configPath).toJson(),
      },
    ),
    McpTool(
      name: 'set_project_rule',
      description:
          'Map a directory onto a project. The rule matches any session whose '
          'path contains the given text, and replaces an existing rule with the '
          'same match.',
      inputSchema: {
        'type': 'object',
        'required': ['match', 'project'],
        'properties': {
          'match': {
            'type': 'string',
            'description':
                'Text to look for in the session directory, case-insensitive; '
                'slashes and hyphens are interchangeable.',
          },
          'project': {
            'type': 'string',
            'description': 'Project name to bill, e.g. "Byte Buddies - idbuddy".',
          },
          'first': {
            'type': 'boolean',
            'description':
                'Put the rule ahead of the others, for a narrow match that '
                'would otherwise be shadowed. Default false.',
          },
        },
      },
      run: (args) async {
        final match = args['match']! as String;
        final config = AiTrackerConfig.load(configPath);
        final rules = [
          for (final rule in config.rules)
            if (rule.match.toLowerCase() != match.toLowerCase()) rule,
        ];
        final rule = ProjectRule(
          match: match,
          project: args['project']! as String,
        );
        if (args['first'] as bool? ?? false) {
          rules.insert(0, rule);
        } else {
          rules.add(rule);
        }
        config.copyWith(rules: rules).save(configPath);
        return {
          'ok': true,
          'rules': [for (final r in rules) r.toJson()],
        };
      },
    ),
    McpTool(
      name: 'edit_blocks',
      description:
          'Reassign, rename or strike out blocks by key, in one batch. The keys '
          'come from list_hours; the edits survive re-reading the transcripts.',
      inputSchema: {
        'type': 'object',
        'required': ['keys'],
        'properties': {
          'keys': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Block keys, as list_hours reports them.',
          },
          'project': {
            'type': 'string',
            'description': 'Project to bill these blocks to instead.',
          },
          'description': {
            'type': 'string',
            'description': 'Description to write on these blocks instead.',
          },
          'excluded': {
            'type': 'boolean',
            'description': 'Strike the blocks out of every sink.',
          },
          'clear': {
            'type': 'boolean',
            'description': 'Drop the edits on these blocks instead of adding.',
          },
        },
      },
      run: (args) async {
        final keys = [for (final key in (args['keys']! as List)) '$key'];
        final store = OverrideStore.load(overridesPath);
        final clear = args['clear'] as bool? ?? false;
        for (final key in keys) {
          if (clear) {
            store.set(key, null);
          } else {
            store.merge(
              key,
              BlockOverride(
                project: args['project'] as String?,
                description: args['description'] as String?,
                excluded: args['excluded'] as bool? ?? false,
              ),
            );
          }
        }
        store.save(overridesPath);
        return {'ok': true, 'edited': keys.length, 'cleared': clear};
      },
    ),
  ];
}

const Map<String, Object?> _days = {
  'type': 'integer',
  'description': 'Look back this many days from now. Ignored when since is set.',
};

const Map<String, Object?> _dryRun = {
  'type': 'boolean',
  'description': 'Preview without writing. Default true.',
};

Map<String, Object?> _iso(String description) => {
  'type': 'string',
  'description': '$description ISO 8601, e.g. 2026-09-01.',
};

Map<String, Object?> _quitApp(String app) => {
  'type': 'boolean',
  'description':
      'Close $app for the write and start it again afterwards. Without this a '
      'running $app is a refusal, because it would overwrite the rows from its '
      'own memory. Default false.',
};

Map<String, Object?> _block(TrackedBlock block) => {
  'key': block.key,
  'project': block.project,
  'description': block.description,
  'repository': block.repo,
  'directory': block.block.directory,
  'start': block.block.start.toIso8601String(),
  'end': block.block.end.toIso8601String(),
  'hours': _hours(block.block.duration),
  'sessions': block.block.sessions,
  if (block.excluded) 'excluded': true,
};

double _hours(Duration duration) =>
    double.parse((duration.inMinutes / 60).toStringAsFixed(2));

DateTime? _since(Map<String, Object?> args) {
  final since = args['since'] as String?;
  if (since != null && since.isNotEmpty) return DateTime.tryParse(since);
  final days = args['days'] as int?;
  if (days == null) return null;
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
}

DateTime? _until(Map<String, Object?> args) {
  final until = args['until'] as String?;
  if (until == null || until.isEmpty) return null;
  return DateTime.tryParse(until);
}
