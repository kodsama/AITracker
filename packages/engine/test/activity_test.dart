import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

ActivityEvent event(
  String time,
  String directory, [
  String session = 's1',
  String model = '',
]) => ActivityEvent(
  time: DateTime.parse(time),
  directory: directory,
  sessionId: session,
  model: model,
);

void main() {
  // A test run has no business writing to the user's log.
  Log.enabled = false;

  group('ticks', () {
    test('matches a timestamp WorkingHours actually wrote', () {
      // Row 4835 of the live store: a work unit starting 13:07 on 2026-05-15.
      expect(fromTicks(639144472200000000), DateTime(2026, 5, 15, 13, 7));
    });

    test('round trips local wall-clock time', () {
      final now = DateTime(2026, 9, 21, 14, 32, 5);
      expect(fromTicks(toTicks(now)), now);
    });
  });

  group('buildBlocks', () {
    test('joins events separated by less than the idle gap', () {
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo/a'),
        event('2026-09-01T09:04:00', '/repo/a'),
        event('2026-09-01T09:12:00', '/repo/a'),
      ], idleGap: const Duration(minutes: 10));

      expect(blocks, hasLength(1));
      expect(blocks.single.start, DateTime(2026, 9, 1, 9));
      expect(blocks.single.end, DateTime(2026, 9, 1, 9, 12));
    });

    test('ends a block when the gap exceeds the idle threshold', () {
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo/a'),
        event('2026-09-01T09:08:00', '/repo/a'),
        event('2026-09-01T12:00:00', '/repo/a'),
        event('2026-09-01T12:09:00', '/repo/a'),
      ], idleGap: const Duration(minutes: 10));

      expect(blocks, hasLength(2));
      expect(blocks.first.end, DateTime(2026, 9, 1, 9, 8));
      expect(blocks.last.start, DateTime(2026, 9, 1, 12));
    });

    test('never bills the same minute to two repositories', () {
      // Two sessions interleaved: an hour of wall clock, not two.
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo/a', 'a'),
        event('2026-09-01T09:05:00', '/repo/b', 'b'),
        event('2026-09-01T09:30:00', '/repo/a', 'a'),
        event('2026-09-01T09:35:00', '/repo/b', 'b'),
        event('2026-09-01T10:00:00', '/repo/a', 'a'),
      ], idleGap: const Duration(minutes: 30));

      final total = blocks.fold(Duration.zero, (sum, b) => sum + b.duration);
      expect(total, const Duration(hours: 1));
      for (var i = 1; i < blocks.length; i++) {
        expect(blocks[i].start.isBefore(blocks[i - 1].end), isFalse);
      }
    });

    test('drops blocks shorter than the minimum', () {
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo/a'),
        event('2026-09-01T09:02:00', '/repo/a'),
      ], minBlock: const Duration(minutes: 5));

      expect(blocks, isEmpty);
    });

    test('splits a block that crosses midnight', () {
      final blocks = buildBlocks([
        event('2026-09-01T23:50:00', '/repo/a'),
        event('2026-09-02T00:10:00', '/repo/a'),
      ], idleGap: const Duration(minutes: 30));

      expect(blocks, hasLength(2));
      expect(blocks.first.end, DateTime(2026, 9, 2));
      expect(blocks.last.start, DateTime(2026, 9, 2));
    });

    test('a block says what it is, for a log line', () {
      final block = buildBlocks([
        event('2026-09-01T09:00:00', '/repo/a'),
        event('2026-09-01T09:08:00', '/repo/a'),
      ]).single;

      expect(
        block.toString(),
        'WorkBlock(/repo/a, 2026-09-01 09:00:00.000 -> 2026-09-01 09:08:00.000)',
      );
    });

    test('a detour into another repository does not chop a stretch in two', () {
      // A minute in /repo/b in the middle of an hour on /repo/a: too short to
      // keep, and the hour either side is one block, not two.
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo/a'),
        event('2026-09-01T09:20:00', '/repo/a'),
        event('2026-09-01T09:21:00', '/repo/b'),
        event('2026-09-01T09:22:00', '/repo/a'),
        event('2026-09-01T09:40:00', '/repo/a'),
      ], idleGap: const Duration(minutes: 30));

      expect(blocks.map((b) => b.directory), ['/repo/a']);
      expect(blocks.single.duration, const Duration(minutes: 40));
    });

    test('counts the sessions that fed a block', () {
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo/a', 'one'),
        event('2026-09-01T09:05:00', '/repo/a', 'two'),
        event('2026-09-01T09:10:00', '/repo/a', 'two'),
      ]);

      expect(blocks.single.sessions, 2);
    });

    test('returns nothing for a single event', () {
      expect(buildBlocks([event('2026-09-01T09:00:00', '/repo/a')]), isEmpty);
    });
  });

  group('reading a line', () {
    test('tells the two layouts apart', () {
      expect(
        formatOf('{"timestamp":"2026-09-01T09:00:00Z"}'),
        TranscriptFormat.claudeCode,
      );
      expect(
        formatOf('{"timestamp":1784620258659,"workspace":"/x"}'),
        TranscriptFormat.geminiCli,
      );
      expect(formatOf('{}'), TranscriptFormat.unknown);
    });

    test('reads the time, the directory and the session', () {
      final event = parseTranscriptLine(
        '{"timestamp":"2026-09-01T09:00:00.000Z","cwd":"/repo",'
        '"conversationId":"abc"}',
        TranscriptFormat.claudeCode,
        directory: '/repo',
        session: 'file',
      )!;

      expect(event.time, DateTime.utc(2026, 9, 1, 9).toLocal());
      expect(event.directory, '/repo');
      expect(event.sessionId, 'abc');
    });

    test('reads the Gemini and Antigravity CLI layout', () {
      final at = DateTime(2026, 9, 1, 9).millisecondsSinceEpoch;
      final line = '{"display":"hi","timestamp":$at,"workspace":"/work"}';

      expect(directoryIn(line, TranscriptFormat.geminiCli), '/work');
      expect(
        parseTranscriptLine(
          line,
          TranscriptFormat.geminiCli,
          directory: '/work',
          session: 'file',
        )!.time,
        DateTime(2026, 9, 1, 9),
      );
    });

    test('a number after a space is still a number', () {
      expect(extractNumber('{"timestamp": 1784620258659}', '"timestamp":'),
          1784620258659);
      expect(extractNumber('{"a":1}', '"missing":'), 0);
      expect(extractString('{"cwd":"/repo"}', '"none":'), isNull);
      expect(extractString('{"cwd":"unterminated', '"cwd":"'), isNull);
    });

    test('a line with no time is not an event', () {
      expect(
        parseTranscriptLine(
          '{"type":"mode"}',
          TranscriptFormat.claudeCode,
          directory: '/repo',
          session: 'file',
        ),
        isNull,
      );
    });

    test('the model that answered is read, and made-up turns credit none', () {
      expect(
        parseTranscriptLine(
          '{"timestamp":"2026-09-01T09:00:00.000Z",'
          '"message":{"model":"claude-opus-5"}}',
          TranscriptFormat.claudeCode,
          directory: '/repo',
          session: 'file',
        )!.model,
        'claude-opus-5',
      );
      // Claude Code writes <synthetic> on the messages it makes up itself.
      expect(modelIn('{"message":{"model":"<synthetic>"}}'), '');
      expect(modelIn('{"timestamp":"x"}'), '');
    });

    test('costs are read off the usage block, and only from it', () {
      expect(
        usageIn(
          '{"message":{"usage":{"input_tokens":2,'
          '"cache_creation_input_tokens":18664,'
          '"cache_read_input_tokens":25336,"output_tokens":761}}}',
        ).total,
        44763,
      );
      expect(usageIn('{"timestamp":"x"}').isEmpty, isTrue);
    });
  });

  group('what a block is charged', () {
    ActivityEvent spending(String time, int cost, [String directory = '/repo']) =>
        ActivityEvent(
          time: DateTime.parse(time),
          directory: directory,
          sessionId: 's',
          tokens: TokenUsage(input: cost),
        );

    test('the exchange that closed a stretch is counted in it', () {
      final blocks = buildBlocks([
        spending('2026-09-01T09:00:00', 10),
        spending('2026-09-01T09:30:00', 90),
        // Far enough away to end the stretch, and to start none of its own.
        spending('2026-09-01T19:00:00', 5),
      ], idleGap: const Duration(hours: 1), minBlock: Duration.zero);

      expect(blocks.single.tokens.total, 100);
    });

    test('a stretch over midnight is charged once, to the halves it became', () {
      final blocks = buildBlocks([
        spending('2026-09-01T23:30:00', 60),
        spending('2026-09-02T00:30:00', 40),
      ], idleGap: const Duration(hours: 2), minBlock: Duration.zero);

      expect(blocks, hasLength(2));
      expect(blocks.first.tokens.total, 60);
      expect(blocks.last.tokens.total, 40);
    });

    test('what happened between two blocks is charged to neither', () {
      final blocks = buildBlocks([
        spending('2026-09-01T09:00:00', 10),
        spending('2026-09-01T09:30:00', 10),
        spending('2026-09-01T15:00:00', 999),
        spending('2026-09-01T19:00:00', 10),
        spending('2026-09-01T19:30:00', 10),
      ], idleGap: const Duration(hours: 1), minBlock: Duration.zero);

      expect(blocks, hasLength(2));
      expect(blocks.fold<int>(0, (sum, b) => sum + b.tokens.total), 40);
    });
  });

  group('models', () {
    test('a block counts the turns each model took, and names the busiest', () {
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo', 's1', 'claude-opus-5'),
        event('2026-09-01T09:10:00', '/repo', 's1', 'claude-sonnet-5'),
        event('2026-09-01T09:20:00', '/repo', 's1', 'claude-opus-5'),
        event('2026-09-01T09:30:00', '/repo', 's1'),
      ], idleGap: const Duration(minutes: 15), minBlock: Duration.zero);

      expect(blocks.single.models, {'claude-opus-5': 2, 'claude-sonnet-5': 1});
      expect(blocks.single.model, 'claude-opus-5');
    });

    test('a block nobody recorded a model for names none', () {
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo'),
        event('2026-09-01T09:10:00', '/repo'),
      ], idleGap: const Duration(minutes: 15), minBlock: Duration.zero);

      expect(blocks.single.models, isEmpty);
      expect(blocks.single.model, '');
    });

    test('a glance absorbed into a longer stretch brings its models', () {
      final blocks = buildBlocks([
        event('2026-09-01T09:00:00', '/repo', 's1', 'claude-opus-5'),
        event('2026-09-01T09:10:00', '/repo', 's1', 'claude-opus-5'),
        event('2026-09-01T09:11:00', '/other', 's2', 'claude-fable-5'),
        event('2026-09-01T09:12:00', '/repo', 's1', 'claude-sonnet-5'),
        event('2026-09-01T09:40:00', '/repo', 's1', 'claude-sonnet-5'),
      ], idleGap: const Duration(hours: 1), minBlock: const Duration(minutes: 5));

      expect(blocks.single.models['claude-fable-5'], 1);
      expect(blocks.single.model, 'claude-opus-5');
      // And its sessions, which the block counts.
      expect(blocks.single.sessions, 2);
    });

    test('what a glance spent is spent inside the block that swallowed it', () {
      ActivityEvent spending(String time, String directory, int cost) =>
          ActivityEvent(
            time: DateTime.parse(time),
            directory: directory,
            sessionId: 's',
            tokens: TokenUsage(input: cost),
          );

      final blocks = buildBlocks([
        spending('2026-09-01T09:00:00', '/repo', 10),
        spending('2026-09-01T09:10:00', '/repo', 10),
        spending('2026-09-01T09:11:00', '/other', 500),
        spending('2026-09-01T09:12:00', '/repo', 10),
        spending('2026-09-01T09:40:00', '/repo', 10),
      ], idleGap: const Duration(hours: 1), minBlock: const Duration(minutes: 5));

      // The minute in the other repository is inside this block's hours, so
      // its tokens are inside its totals.
      expect(blocks.single.tokens.total, 540);
    });
  });

  group('tokens', () {
    test('are read off the assistant turns and summed into the block', () {
      final blocks = buildBlocks([
        ActivityEvent(
          time: DateTime(2026, 9, 1, 9),
          directory: '/repo',
          sessionId: 's',
          tokens: const TokenUsage(input: 2, output: 761, cacheWrite: 18664),
        ),
        ActivityEvent(
          time: DateTime(2026, 9, 1, 9, 8),
          directory: '/repo',
          sessionId: 's',
          tokens: const TokenUsage(cacheRead: 25336, output: 100),
        ),
      ]);

      final tokens = blocks.single.tokens;
      expect(tokens.output, 861);
      expect(tokens.cacheWrite, 18664);
      expect(tokens.cacheRead, 25336);
      expect(tokens.total, 44863);
      expect(tokens.fresh, 19527);
    });

  });

  group('parallel sessions', () {
    ActivityEvent at(String time, String directory) => ActivityEvent(
      time: DateTime.parse(time),
      directory: directory,
      sessionId: directory,
    );

    test('per-project blocks overlap, the exclusive ones do not', () {
      final events = [
        at('2026-09-01T09:00:00', '/a'),
        at('2026-09-01T09:05:00', '/b'),
        at('2026-09-01T09:30:00', '/a'),
        at('2026-09-01T09:35:00', '/b'),
      ];

      final exclusive = buildBlocks(events, idleGap: const Duration(hours: 1));
      final perProject = buildProjectBlocks(
        events,
        idleGap: const Duration(hours: 1),
      );

      // Half an hour of wall clock, worked in two repositories at once.
      expect(unionDuration(exclusive), const Duration(minutes: 35));
      expect(
        perProject.fold(Duration.zero, (sum, b) => sum + b.duration),
        const Duration(minutes: 60),
      );
      expect(unionDuration(perProject), const Duration(minutes: 35));
    });
  });

  group('AiTrackerConfig', () {
    test('matches the first rule and falls back when none do', () {
      const config = AiTrackerConfig(
        sources: [],
        rules: [
          ProjectRule(match: 'byte-buddies-idbuddy', project: 'BB - idbuddy'),
          ProjectRule(match: 'byte-buddies', project: 'BB - other'),
        ],
        fallbackProject: 'Unsorted',
      );

      // A rule written with hyphens matches the real path, and the flattened
      // folder name a transcript without a cwd falls back to.
      expect(
        config.projectFor('/Users/me/Developer/Byte-Buddies/IDBuddy'),
        'BB - idbuddy',
      );
      expect(
        config.projectFor('-Users-me-Developer-Byte-Buddies-IDBuddy'),
        'BB - idbuddy',
      );
      // And the folder as it is really spelled, with a space in it.
      expect(
        config.projectFor('/Users/me/Developer/Byte Buddies/idbuddy'),
        'BB - idbuddy',
      );
      expect(config.projectFor('/Users/me/Developer/Byte-Buddies/x'), 'BB - other');
      expect(config.projectFor('/Users/me/elsewhere'), 'Unsorted');
      // The fallback is not a rule: what it catches has none.
      expect(
        config.ruleFor('/Users/me/Developer/Byte-Buddies/x')?.match,
        'byte-buddies',
      );
      expect(config.ruleFor('/Users/me/elsewhere'), isNull);
    });

    test('leaves unmatched directories unassigned without a fallback', () {
      const config = AiTrackerConfig(sources: []);
      expect(config.projectFor('/anywhere'), isNull);
    });

    test('round trips through JSON', () {
      final temp = Directory.systemTemp.createTempSync('aitracker');
      addTearDown(() => temp.deleteSync(recursive: true));
      const config = AiTrackerConfig(
        sources: ['/tmp/projects'],
        idleGap: Duration(minutes: 15),
        minBlock: Duration(minutes: 3),
        rules: [ProjectRule(match: 'x', project: 'Y - z')],
        fallbackProject: 'Unsorted',
        calendar: CalendarSinkConfig(enabled: true, calendarName: 'AI'),
        mcpEnabled: true,
        mcpPort: 9100,
      );
      final path = '${temp.path}/config.json';

      config.save(path);
      final loaded = AiTrackerConfig.load(path);

      expect(loaded.sources, ['/tmp/projects']);
      expect(loaded.idleGap, const Duration(minutes: 15));
      expect(loaded.minBlock, const Duration(minutes: 3));
      expect(loaded.rules.single.project, 'Y - z');
      expect(loaded.fallbackProject, 'Unsorted');
      expect(loaded.calendar.enabled, isTrue);
      expect(loaded.calendar.calendarName, 'AI');
      expect(loaded.mcpEnabled, isTrue);
      expect(loaded.mcpPort, 9100);
    });

    test('falls back to the discovered sources for a missing file', () {
      final config = AiTrackerConfig.load('/nonexistent/config.json');
      expect(config.sources, AiTrackerConfig.discoverSources());
    });

    test('no sources at all is a choice, not a reason to go looking', () {
      final temp = Directory.systemTemp.createTempSync('aitracker_sources');
      addTearDown(() => temp.deleteSync(recursive: true));
      final path = '${temp.path}/config.json';
      const AiTrackerConfig(sources: []).save(path);

      expect(AiTrackerConfig.load(path).sources, isEmpty);
    });
  });

  group('AiTracker', () {
    WorkBlock block({String directory = '/Users/me/Developer/idbuddy'}) =>
        WorkBlock(
          directory: directory,
          start: DateTime(2026, 9, 1, 9),
          end: DateTime(2026, 9, 1, 10),
          sessions: 2,
        );

    test('templates the description from the block', () {
      final tracking = AiTracker(
        historyPath: null,
        config: const AiTrackerConfig(
          sources: [],
          rules: [ProjectRule(match: 'idbuddy', project: 'Byte Buddies - idbuddy')],
          workingHours: WorkingHoursSinkConfig(
            descriptionTemplate: '{company}/{repo} ({sessions})',
          ),
        ),
      );

      final tracked = tracking.resolve(block());

      expect(tracked.description, 'Byte Buddies/idbuddy (2)');
      expect(tracked.company, 'Byte Buddies');
      expect(tracked.repo, 'idbuddy');
      expect(tracked.billable, isTrue);
    });

    test('applies a hand edit over the rules', () {
      final overrides = OverrideStore()
        ..set(
          OverrideStore.keyFor('/Users/me/Developer/idbuddy', DateTime(2026, 9, 1, 9)),
          BlockOverride(
            project: 'Elsewhere - work',
            description: 'pairing',
            end: DateTime(2026, 9, 1, 9, 30),
          ),
        );
      final tracking = AiTracker(
        historyPath: null,
        config: const AiTrackerConfig(sources: []),
        overrides: overrides,
      );

      final tracked = tracking.resolve(block());

      expect(tracked.project, 'Elsewhere - work');
      expect(tracked.description, 'pairing');
      expect(tracked.block.duration, const Duration(minutes: 30));
    });

    test('keeps an excluded block out of the billable set', () {
      final overrides = OverrideStore()
        ..merge(
          OverrideStore.keyFor('/Users/me/Developer/idbuddy', DateTime(2026, 9, 1, 9)),
          const BlockOverride(excluded: true),
        );
      final tracking = AiTracker(
        historyPath: null,
        config: const AiTrackerConfig(
          sources: [],
          rules: [ProjectRule(match: 'idbuddy', project: 'BB - idbuddy')],
        ),
        overrides: overrides,
      );

      final tracked = tracking.resolve(block());

      expect(tracked.excluded, isTrue);
      expect(tracked.billable, isFalse);
      expect(totalsByProject([tracked]), isEmpty);
    });

    test('summarises by project, by day and by what is unmapped', () {
      final tracking = AiTracker(
        historyPath: null,
        config: const AiTrackerConfig(
          sources: [],
          rules: [ProjectRule(match: 'idbuddy', project: 'BB - idbuddy')],
        ),
      );
      final tracked = [
        tracking.resolve(block()),
        tracking.resolve(
          WorkBlock(
            directory: '/Users/me/Developer/mystery',
            start: DateTime(2026, 9, 1, 11),
            end: DateTime(2026, 9, 1, 11, 30),
          ),
        ),
      ];

      expect(totalsByProject(tracked), {'BB - idbuddy': const Duration(hours: 1)});
      expect(totalsByDay(tracked), {DateTime(2026, 9, 1): const Duration(hours: 1)});
      expect(unmapped(tracked), {
        '/Users/me/Developer/mystery': const Duration(minutes: 30),
      });
    });

    test('reads blocks through the archive, within a window', () {
      final temp = Directory.systemTemp.createTempSync('aitracker');
      addTearDown(() => temp.deleteSync(recursive: true));
      final dir = Directory('${temp.path}/projects/p')..createSync(recursive: true);
      final start = DateTime(2026, 9, 1, 9).toUtc().toIso8601String();
      final end = DateTime(2026, 9, 1, 9, 30).toUtc().toIso8601String();
      File('${dir.path}/s.jsonl').writeAsStringSync(
        '{"timestamp":"$start","cwd":"/Users/me/Developer/idbuddy"}\n'
        '{"timestamp":"$end","cwd":"/Users/me/Developer/idbuddy"}\n',
      );

      final tracking = AiTracker(
        config: AiTrackerConfig(
          sources: ['${temp.path}/projects'],
          idleGap: const Duration(hours: 1),
          rules: const [ProjectRule(match: 'idbuddy', project: 'BB - idbuddy')],
        ),
        historyPath: '${temp.path}/history.db',
      );

      expect(tracking.blocks(), hasLength(1));
      expect(tracking.blocks(until: DateTime(2026, 9, 1)), isEmpty);
    });
  });

  group('formatDuration', () {
    test('reads like a timesheet', () {
      expect(formatDuration(const Duration(minutes: 45)), '45m');
      expect(formatDuration(const Duration(hours: 7, minutes: 20)), '7h 20m');
    });
  });
}
