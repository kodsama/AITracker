import 'package:aitracking_engine/aitracking_engine.dart';

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

/// Builds the AITracking tool catalog.
///
/// Configuration and hand edits are read on every call rather than captured
/// once, so a change made in the desktop app is live for the next tool call.
/// [configPath] and [overridesPath] override where those live, which is what
/// the tests use.
List<McpTool> buildTools({String? configPath, String? overridesPath}) {
  AiTracking tracking() => AiTracking(
    config: AiTrackingConfig.load(configPath),
    overrides: OverrideStore.load(overridesPath),
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
        final config = AiTrackingConfig.load(configPath);
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
      name: 'sync_diarium',
      description:
          'Write a daily AI-hours entry into the Diarium journal. Previews by '
          'default; a later run rewrites its own entry rather than duplicating.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'days': _days,
          'since': _iso('Start of the window.'),
          'until': _iso('End of the window.'),
          'dry_run': _dryRun,
          'quit_app': _quitApp('Diarium'),
        },
      },
      run: (args) async {
        final config = AiTrackingConfig.load(configPath);
        final report = DiariumSink(config: config.diarium).sync(
          read(args),
          dryRun: args['dry_run'] as bool? ?? true,
          quitApp: args['quit_app'] as bool? ?? false,
        );
        return {'ok': report.refusal == null, ...report.toJson()};
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
        final config = AiTrackingConfig.load(configPath);
        final report = TabularSink(
          config: config.tabular,
        ).sync(read(args), dryRun: args['dry_run'] as bool? ?? true);
        return {'ok': true, ...report.toJson()};
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
        'path': configPath ?? AiTrackingConfig.defaultPath(),
        'config': AiTrackingConfig.load(configPath).toJson(),
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
        final config = AiTrackingConfig.load(configPath);
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
