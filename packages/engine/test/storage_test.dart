import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // A test run has no business writing to the user's log.
  Log.enabled = false;

  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('aitracker_store'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('OverrideStore', () {
    test('survives a round trip to disk', () {
      final path = '${temp.path}/overrides.json';
      OverrideStore()
        ..set(
          'a',
          BlockOverride(
            project: 'BB - idbuddy',
            description: 'pairing',
            start: DateTime(2026, 9, 1, 9),
            end: DateTime(2026, 9, 1, 10),
          ),
        )
        ..set('b', const BlockOverride(excluded: true))
        ..save(path);

      final loaded = OverrideStore.load(path);

      expect(loaded.entries, hasLength(2));
      expect(loaded['a']!.project, 'BB - idbuddy');
      expect(loaded['a']!.description, 'pairing');
      expect(loaded['a']!.start, DateTime(2026, 9, 1, 9));
      expect(loaded['a']!.end, DateTime(2026, 9, 1, 10));
      expect(loaded['b']!.excluded, isTrue);
    });

    test('merging keeps the fields the new edit leaves alone', () {
      final store = OverrideStore()
        ..set('a', const BlockOverride(project: 'BB - idbuddy'))
        ..merge('a', const BlockOverride(description: 'pairing'))
        ..merge('a', const BlockOverride(excluded: true));

      expect(store['a']!.project, 'BB - idbuddy');
      expect(store['a']!.description, 'pairing');
      expect(store['a']!.excluded, isTrue);
    });

    test('a null override clears the entry', () {
      final store = OverrideStore()
        ..set('a', const BlockOverride(excluded: true))
        ..set('a', null);

      expect(store.entries, isEmpty);
    });

    test('keys a block by where and when it started', () {
      expect(
        OverrideStore.keyFor('/repo', DateTime(2026, 9, 1, 9)),
        '/repo|2026-09-01T09:00:00.000',
      );
    });

    test('an absent or unreadable file loads as empty', () {
      expect(OverrideStore.load('${temp.path}/nothing.json').entries, isEmpty);
      final broken = '${temp.path}/broken.json';
      File(broken).writeAsStringSync('[]');
      expect(OverrideStore.load(broken).entries, isEmpty);
    });

    test('lives beside the configuration', () {
      expect(
        p.dirname(OverrideStore.defaultPath()),
        p.dirname(AiTrackerConfig.defaultPath()),
      );
      expect(p.basename(OverrideStore.defaultPath()), 'overrides.json');
    });
  });

  group('paths', () {
    test('a relative sink path hangs off the home directory', () {
      expect(
        AiTrackerConfig.resolveHome('Documents/AI hours.csv'),
        p.join(AiTrackerConfig.homeDirectory(), 'Documents/AI hours.csv'),
      );
      expect(AiTrackerConfig.resolveHome('/tmp/x.csv'), '/tmp/x.csv');
    });

    test('the configuration lives in Application Support', () {
      expect(
        AiTrackerConfig.defaultPath(),
        endsWith('Library/Application Support/AITracker/config.json'),
      );
    });

    test('a folder is only offered when it holds transcripts', () {
      final assistant = Directory('${temp.path}/.someone/sessions')
        ..createSync(recursive: true);
      final empty = Directory('${temp.path}/.nobody/extensions')
        ..createSync(recursive: true);

      expect(
        AiTrackerConfig.holdsTranscripts(Directory('${temp.path}/.someone')),
        isFalse,
      );

      File('${assistant.path}/a.jsonl').writeAsStringSync('{}\n');

      expect(
        AiTrackerConfig.holdsTranscripts(Directory('${temp.path}/.someone')),
        isTrue,
      );
      expect(
        AiTrackerConfig.holdsTranscripts(Directory(empty.parent.path)),
        isFalse,
      );
      // Deep enough to hide from a shallow look is deep enough to ignore.
      expect(
        AiTrackerConfig.holdsTranscripts(
          Directory('${temp.path}/.someone'),
          depth: 0,
        ),
        isFalse,
      );
    });

    test('sources are discovered from the assistant config directories', () {
      final found = AiTrackerConfig.discoverSources();
      for (final source in found) {
        // Claude Code keeps a projects folder; the Gemini and Antigravity CLIs
        // keep their history under ~/.gemini.
        expect(
          p.basename(source) == 'projects' || p.basename(source) == '.gemini',
          isTrue,
          reason: source,
        );
        expect(Directory(source).existsSync(), isTrue);
      }
      expect(found, equals([...found]..sort()));
    });

    test('a configuration file holding the wrong shape falls back', () {
      final path = '${temp.path}/config.json';
      File(path).writeAsStringSync('"not a config"');
      expect(AiTrackerConfig.load(path).rules, isEmpty);
    });
  });

  group('MacApp', () {
    const missing = MacApp(name: 'Absent', bundlePath: '/nonexistent/App.app');

    test('finds its executable inside the bundle', () {
      expect(missing.executable, '/nonexistent/App.app/Contents/MacOS/Absent');
    });

    test('an app that is not installed is not running, and quits trivially', () {
      expect(missing.isRunning, isFalse);
      expect(missing.quit(), isTrue);
    });

    test('launching one that is not there is survivable', () {
      expect(missing.launch, returnsNormally);
    });
  });

  group('SyncReport', () {
    test('serialises what a client needs to see', () {
      final report = SyncReport(
        sink: 'workinghours',
        applied: true,
        written: [
          TrackedBlock(
            block: WorkBlock(
              directory: '/repo',
              start: DateTime(2026, 9, 1, 9),
              end: DateTime(2026, 9, 1, 10, 30),
            ),
            project: 'BB - idbuddy',
            description: 'AI: repo',
          ),
        ],
        notes: ['created project "BB - idbuddy"'],
        outputs: ['/tmp/hours.csv'],
        backup: '/tmp/backup.sqlite',
      );

      final json = report.toJson();

      expect(json['sink'], 'workinghours');
      expect(json['applied'], isTrue);
      expect(json['written'], 1);
      expect(json['total_hours'], 1.5);
      expect(json['notes'], ['created project "BB - idbuddy"']);
      expect(json['outputs'], ['/tmp/hours.csv']);
      expect(json['backup'], '/tmp/backup.sqlite');
      expect((json['blocks']! as List).single, {
        'project': 'BB - idbuddy',
        'description': 'AI: repo',
        'start': '2026-09-01T09:00:00.000',
        'end': '2026-09-01T10:30:00.000',
        'hours': 1.5,
      });
    });

    test('a refusal says so and carries no blocks', () {
      final json = SyncReport(
        sink: 'diarium',
        applied: false,
        refusal: 'Diarium is running',
      ).toJson();

      expect(json['refusal'], 'Diarium is running');
      expect(json['written'], 0);
      expect(json['total_hours'], 0.0);
      expect(json.containsKey('backup'), isFalse);
    });
  });
}
