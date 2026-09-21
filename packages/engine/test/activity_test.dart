import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

ActivityEvent event(String time, String directory, [String session = 's1']) =>
    ActivityEvent(
      time: DateTime.parse(time),
      directory: directory,
      sessionId: session,
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

  group('TranscriptScanner', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('aitracker'));
    tearDown(() => temp.deleteSync(recursive: true));

    File transcript(String project, String name, String contents) {
      final dir = Directory('${temp.path}/projects/$project')
        ..createSync(recursive: true);
      return File('${dir.path}/$name')..writeAsStringSync(contents);
    }

    test('reads timestamps and the session directory', () {
      transcript(
        '-Users-me-code',
        'session.jsonl',
        '{"type":"system","timestamp":"2026-09-01T09:00:00.000Z","cwd":"/Users/me/code"}\n'
        '{"type":"user","timestamp":"2026-09-01T09:05:00.000Z","cwd":"/Users/me/code"}\n',
      );

      final events = TranscriptScanner([
        '${temp.path}/projects',
      ]).scan();

      expect(events, hasLength(2));
      expect(events.first.directory, '/Users/me/code');
      expect(events.first.sessionId, 'session');
    });

    test('stamps lines read before the first cwd with the one that follows', () {
      transcript(
        '-Users-me-code',
        'session.jsonl',
        '{"type":"mode","timestamp":"2026-09-01T09:00:00.000Z"}\n'
        '{"type":"system","timestamp":"2026-09-01T09:05:00.000Z","cwd":"/Users/me/code"}\n',
      );

      final events = TranscriptScanner(['${temp.path}/projects']).scan();

      expect(events.map((e) => e.directory), everyElement('/Users/me/code'));
    });

    test('falls back to the project folder when no line carries a cwd', () {
      transcript(
        '-Users-me-nowhere',
        'session.jsonl',
        '{"timestamp":"2026-09-01T09:00:00.000Z"}\n',
      );

      final events = TranscriptScanner(['${temp.path}/projects']).scan();

      expect(events.single.directory, '-Users-me-nowhere');
    });

    test('skips files older than the cutoff and ignores other extensions', () {
      transcript('p', 'notes.txt', 'ignored');
      final old = transcript(
        'p',
        'old.jsonl',
        '{"timestamp":"2020-01-01T09:00:00.000Z","cwd":"/old"}\n',
      );
      old.setLastModifiedSync(DateTime(2020, 1, 1));
      transcript(
        'p',
        'new.jsonl',
        '{"timestamp":"2026-09-01T09:00:00.000Z","cwd":"/new"}\n',
      );

      final events = TranscriptScanner([
        '${temp.path}/projects',
      ]).scan(since: DateTime(2026));

      expect(events.single.directory, '/new');
    });

    test('ignores a source directory that does not exist', () {
      expect(TranscriptScanner(['${temp.path}/missing']).scan(), isEmpty);
    });
  });

  group('other assistants', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('aitracker_gemini'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('reads the Gemini and Antigravity CLI history', () {
      final dir = Directory('${temp.path}/antigravity-cli')
        ..createSync(recursive: true);
      final start = DateTime(2026, 9, 1, 9).millisecondsSinceEpoch;
      File('${dir.path}/history.jsonl').writeAsStringSync(
        '{"display":"/career-ops","timestamp":$start,'
        '"workspace":"/Users/me/Developer/Career-Ops"}\n'
        '{"display":"do the thing","timestamp":${start + 300000},'
        '"workspace":"/Users/me/Developer/Career-Ops",'
        '"conversationId":"abc"}\n',
      );

      final events = TranscriptScanner([temp.path]).scan();

      expect(events, hasLength(2));
      expect(events.first.time, DateTime(2026, 9, 1, 9));
      expect(events.first.directory, '/Users/me/Developer/Career-Ops');
      expect(events.last.sessionId, 'abc');
      expect(events.last.tokens.isEmpty, isTrue);
    });

    test('tells the two layouts apart', () {
      expect(
        TranscriptScanner.formatOf('{"timestamp":"2026-09-01T09:00:00Z"}'),
        TranscriptFormat.claudeCode,
      );
      expect(
        TranscriptScanner.formatOf('{"timestamp":1784620258659,"workspace":"/x"}'),
        TranscriptFormat.geminiCli,
      );
      expect(TranscriptScanner.formatOf('{}'), TranscriptFormat.unknown);
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

    test('a transcript line carries its own usage', () {
      final temp = Directory.systemTemp.createTempSync('aitracker_tokens');
      addTearDown(() => temp.deleteSync(recursive: true));
      final dir = Directory('${temp.path}/projects/p')..createSync(recursive: true);
      File('${dir.path}/s.jsonl').writeAsStringSync(
        '{"timestamp":"2026-09-01T09:00:00.000Z","cwd":"/repo",'
        '"message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":18664,'
        '"cache_read_input_tokens":25336,"output_tokens":761}}}\n',
      );

      final events = TranscriptScanner(['${temp.path}/projects']).scan();

      expect(events.single.tokens.total, 44763);
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

    test('reads blocks from transcripts within a window', () {
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
