import 'dart:convert';
import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  Log.enabled = false;

  late Directory temp;
  late Directory projects;
  late HistoryStore store;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_history');
    projects = Directory('${temp.path}/projects/p')..createSync(recursive: true);
    store = HistoryStore.open('${temp.path}/history.db');
  });

  tearDown(() {
    store.close();
    temp.deleteSync(recursive: true);
  });

  String line(String time, {String cwd = '/repo', int output = 0}) =>
      '{"timestamp":"$time","cwd":"$cwd"'
      '${output == 0 ? '' : ',"message":{"usage":{"input_tokens":2,'
            '"cache_creation_input_tokens":10,"cache_read_input_tokens":20,'
            '"output_tokens":$output}}'}}';

  File write(String name, List<String> lines) =>
      File('${projects.path}/$name')..writeAsStringSync('${lines.join('\n')}\n');

  int ingest() => store.ingest(['${temp.path}/projects']);

  List<ActivityEvent> all() => store.events();

  test('reads the events, their directory and what they cost', () {
    write('a.jsonl', [
      line('2026-09-01T09:00:00.000Z', output: 700),
      line('2026-09-01T09:05:00.000Z'),
    ]);

    expect(ingest(), 2);
    final events = all();
    expect(events, hasLength(2));
    expect(events.first.directory, '/repo');
    expect(events.first.sessionId, 'a');
    expect(events.first.tokens.output, 700);
    expect(events.first.tokens.total, 732);
  });

  test('reading again adds nothing', () {
    write('a.jsonl', [line('2026-09-01T09:00:00.000Z')]);
    ingest();

    expect(ingest(), 0);
    expect(all(), hasLength(1));
  });

  test('only the new lines of a growing transcript are read', () {
    final file = write('a.jsonl', [line('2026-09-01T09:00:00.000Z')]);
    ingest();

    file.writeAsStringSync(
      '${line('2026-09-01T09:05:00.000Z')}\n',
      mode: FileMode.append,
    );

    expect(ingest(), 1);
    expect(all(), hasLength(2));
  });

  test('a half-written last line waits for the rest of it', () {
    final file = write('a.jsonl', [line('2026-09-01T09:00:00.000Z')]);
    ingest();
    file.writeAsStringSync('{"timestamp":"2026-09-0', mode: FileMode.append);

    expect(ingest(), 0);

    file.writeAsStringSync('1T09:05:00.000Z","cwd":"/repo"}\n', mode: FileMode.append);

    expect(ingest(), 1);
    expect(all(), hasLength(2));
  });

  test('a transcript rewritten from the start replaces what it had', () {
    final file = write('a.jsonl', [
      line('2026-09-01T09:00:00.000Z'),
      line('2026-09-01T09:05:00.000Z'),
    ]);
    ingest();

    file.writeAsStringSync('${line('2026-09-02T09:00:00.000Z')}\n');

    ingest();
    expect(all(), hasLength(1));
    expect(all().single.time.day, 2);
  });

  test('a transcript that goes away keeps its hours', () {
    write('a.jsonl', [
      line('2026-09-01T07:00:00.000Z'),
      line('2026-09-01T07:20:00.000Z'),
    ]);
    ingest();
    final before = store.blocks(
      from: DateTime(2026, 9),
      to: DateTime(2026, 10),
      idleGap: const Duration(minutes: 30),
      minBlock: const Duration(minutes: 5),
    );
    expect(before, hasLength(1));

    File('${projects.path}/a.jsonl').deleteSync();
    ingest();

    // The whole point: the transcripts are gone and the hours are not.
    expect(all(), hasLength(2));
    expect(
      store.blocks(
        from: DateTime(2026, 9),
        to: DateTime(2026, 10),
        idleGap: const Duration(minutes: 30),
        minBlock: const Duration(minutes: 5),
      ),
      hasLength(1),
    );
  });

  group('blocks', () {
    setUp(() {
      write('a.jsonl', [
        line('2026-09-01T07:00:00.000Z'),
        line('2026-09-01T07:20:00.000Z'),
        line('2026-09-01T12:00:00.000Z'),
        line('2026-09-01T12:30:00.000Z'),
      ]);
      ingest();
    });

    List<WorkBlock> read({Duration gap = const Duration(minutes: 30)}) =>
        store.blocks(
          from: DateTime(2026, 9),
          to: DateTime(2026, 10),
          idleGap: gap,
          minBlock: const Duration(minutes: 5),
        );

    test('are built from the archive and kept', () {
      final first = read();
      // Asking twice reads the stored blocks rather than rebuilding them.
      final second = read();

      expect(first, hasLength(2));
      expect(second.map((b) => b.start), first.map((b) => b.start));
      expect(first.first.duration, const Duration(minutes: 20));
    });

    test('a different idle gap gives a different reading of the same events', () {
      expect(read(), hasLength(2));

      // Wide enough to join the morning to the afternoon.
      expect(read(gap: const Duration(hours: 6)), hasLength(1));
    });

    test('new events make the day they fall in be worked out again', () {
      expect(read(), hasLength(2));

      File('${projects.path}/a.jsonl').writeAsStringSync(
        '${line('2026-09-01T12:40:00.000Z')}\n',
        mode: FileMode.append,
      );
      ingest();

      // The fixture writes UTC; the archive keeps local time.
      expect(read().last.end, DateTime.utc(2026, 9, 1, 12, 40).toLocal());
    });

    test('a stretch over midnight belongs to the day it continues into', () {
      write('night.jsonl', [
        line('2026-09-03T21:40:00.000Z', cwd: '/night'),
        line('2026-09-03T22:20:00.000Z', cwd: '/night'),
      ]);
      ingest();
      final local = DateTime(2026, 9, 3, 21, 40).toUtc();

      final blocks = store.blocks(
        from: DateTime(local.year, local.month, local.day),
        to: DateTime(local.year, local.month, local.day + 3),
        idleGap: const Duration(hours: 1),
        minBlock: const Duration(minutes: 5),
      );

      // However the zone falls, no piece may start before the day it is filed
      // under, and none may be counted twice.
      final starts = blocks.map((b) => b.start).toList();
      expect(starts.toSet(), hasLength(starts.length));
    });

    test('per project is kept apart from wall clock', () {
      write('b.jsonl', [
        line('2026-09-01T07:05:00.000Z', cwd: '/other'),
        line('2026-09-01T07:15:00.000Z', cwd: '/other'),
      ]);
      ingest();

      final wall = store.blocks(
        from: DateTime(2026, 9),
        to: DateTime(2026, 10),
        idleGap: const Duration(minutes: 30),
        minBlock: const Duration(minutes: 5),
      );
      final perProject = store.blocks(
        from: DateTime(2026, 9),
        to: DateTime(2026, 10),
        idleGap: const Duration(minutes: 30),
        minBlock: const Duration(minutes: 5),
        mode: BlockMode.perProject,
      );

      Duration total(List<WorkBlock> blocks) =>
          blocks.fold(Duration.zero, (sum, b) => sum + b.duration);

      expect(total(perProject), greaterThan(total(wall)));
    });

    test('forgetting the computed blocks keeps the events', () {
      read();

      store.forgetComputed();

      expect(all(), hasLength(4));
      expect(read(), hasLength(2));
    });
  });

  test('reads the Gemini and Antigravity CLI layout too', () {
    final at = DateTime(2026, 9, 1, 9).millisecondsSinceEpoch;
    write('history.jsonl', [
      '{"display":"hello","timestamp":$at,"workspace":"/Users/me/Career-Ops"}',
    ]);

    ingest();

    expect(all().single.directory, '/Users/me/Career-Ops');
  });

  test('a transcript with no directory falls back to its project folder', () {
    write('a.jsonl', ['{"timestamp":"2026-09-01T09:00:00.000Z"}']);

    ingest();

    expect(all().single.directory, 'p');
  });

  test('says what it holds', () {
    write('a.jsonl', [
      line('2026-09-01T09:00:00.000Z'),
      line('2026-09-02T09:00:00.000Z'),
    ]);
    ingest();

    final summary = store.summary();

    expect(summary.events, 2);
    expect(summary.files, 1);
    expect(summary.bytes, greaterThan(0));
    expect(summary.first!.isBefore(summary.last!), isTrue);
    expect(summary.toJson()['events'], 2);
  });

  test('a day is worked out again only when its own events change', () {
    write('a.jsonl', [line('2026-09-01T07:00:00.000Z'), line('2026-09-01T07:20:00.000Z')]);
    write('b.jsonl', [line('2026-09-05T07:00:00.000Z'), line('2026-09-05T07:20:00.000Z')]);
    ingest();
    List<WorkBlock> read() => store.blocks(
      from: DateTime(2026, 9),
      to: DateTime(2026, 10),
      idleGap: const Duration(minutes: 30),
      minBlock: const Duration(minutes: 5),
    );
    expect(read(), hasLength(2));

    // Appending to one day must not throw away what the other day cost.
    File('${projects.path}/a.jsonl').writeAsStringSync(
      '${line('2026-09-01T07:30:00.000Z')}\n',
      mode: FileMode.append,
    );
    ingest();

    final blocks = read();
    expect(blocks, hasLength(2));
    expect(blocks.first.duration, const Duration(minutes: 30));
    expect(blocks.last.duration, const Duration(minutes: 20));
  });

  test('a file that cannot be read does not stop the rest', () {
    write('a.jsonl', [line('2026-09-01T07:00:00.000Z')]);
    Directory('${projects.path}/b.jsonl').createSync();

    expect(ingest(), 1);
    expect(all(), hasLength(1));
  });

  test('a source folder that is not there is not a failure', () {
    expect(store.ingest(['/nonexistent/projects']), 0);
    expect(all(), isEmpty);
  });

  test('a line spanning two chunks is read whole', () {
    // A line longer than the read window has to be stitched back together.
    HistoryStore.chunkBytes = 64;
    addTearDown(() => HistoryStore.chunkBytes = 1 << 22);
    write('a.jsonl', [
      '{"timestamp":"2026-09-01T09:00:00.000Z","cwd":"/repo",'
          '"padding":"${'x' * 300}"}',
      line('2026-09-01T09:05:00.000Z'),
    ]);

    expect(ingest(), 2);
    expect(all().first.directory, '/repo');
  });

  test('a transcript outside a projects folder keeps its own folder name', () {
    final loose = Directory('${temp.path}/elsewhere/sessions')
      ..createSync(recursive: true);
    File('${loose.path}/a.jsonl').writeAsStringSync(
      '{"timestamp":"2026-09-01T09:00:00.000Z"}\n',
    );

    store.ingest(['${temp.path}/elsewhere']);

    // Nothing better to call it than where it was found.
    expect(all().single.directory, loose.path);
  });

  test('a transcript that cannot be opened is rolled back, not half-read', () {
    write('good.jsonl', [line('2026-09-01T09:00:00.000Z')]);
    // A directory wearing a transcript's name: stat succeeds, opening does not.
    Directory('${projects.path}/bad.jsonl').createSync();

    expect(ingest(), 1);
    expect(all(), hasLength(1));
    expect(store.summary().files, 1);
  });

  test('a transcript it may not open leaves the archive as it was', () {
    write('good.jsonl', [line('2026-09-01T09:00:00.000Z')]);
    final closed = write('closed.jsonl', [line('2026-09-02T09:00:00.000Z')]);
    Process.runSync('/bin/chmod', ['000', closed.path]);
    addTearDown(() => Process.runSync('/bin/chmod', ['644', closed.path]));

    expect(ingest(), 1);
    expect(all(), hasLength(1));
    // The one that could not be opened left nothing half-written behind it.
    expect(store.summary().files, 1);
  });

  test('the archive sits beside whichever configuration is in use', () {
    expect(HistoryStore.besideConfig(null), HistoryStore.defaultPath());
    expect(
      HistoryStore.besideConfig('/somewhere/config.json'),
      '/somewhere/history.db',
    );
  });

  test('reopening finds what the last run archived', () {
    write('a.jsonl', [line('2026-09-01T09:00:00.000Z')]);
    ingest();
    store.close();

    final reopened = HistoryStore.open('${temp.path}/history.db');
    addTearDown(reopened.close);

    expect(reopened.events(), hasLength(1));
    expect(reopened.summary().events, 1);
  });

  group('an editor database', () {
    /// Cursor's shape: a conversation naming its folder, and a row per turn.
    String cursorStore(List<String> times, {int touched = 0}) {
      final path = '${temp.path}/Cursor/User/globalStorage/state.vscdb';
      Directory(p.dirname(path)).createSync(recursive: true);
      final db = sqlite3.open(path);
      db.execute(
        'create table if not exists cursorDiskKV (key text primary key, '
        'value text)',
      );
      db.execute('delete from cursorDiskKV');
      db.execute('insert into cursorDiskKV values (?, ?)', [
        'composerData:c',
        json.encode({
          'lastUpdatedAt': touched,
          'workspaceIdentifier': {
            'uri': {'fsPath': '/repo/editor'},
          },
        }),
      ]);
      for (var i = 0; i < times.length; i++) {
        db.execute('insert into cursorDiskKV values (?, ?)', [
          'bubbleId:c:t$i',
          json.encode({'createdAt': times[i]}),
        ]);
      }
      db.close();
      return path;
    }

    test('is read, and read again only for what is new in it', () {
      final path = cursorStore([
        '2026-09-01T09:00:00.000Z',
        '2026-09-01T09:05:00.000Z',
      ]);

      expect(store.ingest([path]), 2);
      expect(store.events().map((e) => e.directory).toSet(), {'/repo/editor'});

      // Nothing has changed, so the database is not opened at all.
      expect(store.ingest([path]), 0);

      cursorStore([
        '2026-09-01T09:00:00.000Z',
        '2026-09-01T09:05:00.000Z',
        '2026-09-01T09:20:00.000Z',
      ], touched: DateTime.utc(2026, 9, 1, 9, 20).millisecondsSinceEpoch);
      File(path).setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));

      expect(store.ingest([path]), 1);
      expect(store.events(), hasLength(3));
    });

    test('counts as a source, and its blocks are the same blocks', () {
      final path = cursorStore([
        '2026-09-01T09:00:00.000Z',
        '2026-09-01T09:05:00.000Z',
      ]);
      store.ingest([path]);

      final blocks = store.blocks(
        from: DateTime.utc(2026, 8, 30).toLocal(),
        to: DateTime.utc(2026, 9, 3).toLocal(),
        idleGap: const Duration(minutes: 10),
        minBlock: Duration.zero,
      );

      expect(blocks, hasLength(1));
      expect(blocks.single.directory, '/repo/editor');
      expect(store.summary().files, 1);
    });

    test('one that is gone is reported, not fatal', () {
      expect(store.ingest(['${temp.path}/Cursor/User/globalStorage/state.vscdb']), 0);
    });
  });
}
