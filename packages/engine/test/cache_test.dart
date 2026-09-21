import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

void main() {
  Log.enabled = false;

  late Directory temp;
  late Directory projects;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_cache');
    projects = Directory('${temp.path}/projects/p')..createSync(recursive: true);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  File write(String name, List<String> times, {String cwd = '/repo'}) =>
      File('${projects.path}/$name')..writeAsStringSync(
        times
            .map((t) => '{"timestamp":"$t","cwd":"$cwd"}')
            .join('\n'),
      );

  test('an unchanged transcript is not read twice', () {
    write('a.jsonl', ['2026-09-01T09:00:00.000Z', '2026-09-01T09:05:00.000Z']);
    final cache = TranscriptCache();
    final scanner = TranscriptScanner([
      '${temp.path}/projects',
    ], cache: cache);

    final first = scanner.scan();
    // Reading through the cache a second time must give the same events.
    final second = scanner.scan();

    expect(first, hasLength(2));
    expect(second.map((e) => e.time), first.map((e) => e.time));
    expect(cache.length, 1);
  });

  test('a transcript that grew is read again', () {
    final file = write('a.jsonl', ['2026-09-01T09:00:00.000Z']);
    final cache = TranscriptCache();
    final scanner = TranscriptScanner([
      '${temp.path}/projects',
    ], cache: cache);
    expect(scanner.scan(), hasLength(1));

    file.writeAsStringSync(
      '{"timestamp":"2026-09-01T09:00:00.000Z","cwd":"/repo"}\n'
      '{"timestamp":"2026-09-01T09:05:00.000Z","cwd":"/repo"}\n',
    );

    expect(scanner.scan(), hasLength(2));
  });

  test('the window is applied to cached events, not baked into them', () {
    write('a.jsonl', ['2026-09-01T09:00:00.000Z', '2026-09-10T09:00:00.000Z']);
    final cache = TranscriptCache();
    final scanner = TranscriptScanner([
      '${temp.path}/projects',
    ], cache: cache);

    // A narrow window first, then a wider one: the second must not be limited
    // by what the first asked for.
    expect(scanner.scan(since: DateTime(2026, 9, 5)), hasLength(1));
    expect(scanner.scan(since: DateTime(2026, 8)), hasLength(2));
  });

  test('a transcript that went away is forgotten', () {
    final file = write('a.jsonl', ['2026-09-01T09:00:00.000Z']);
    write('b.jsonl', ['2026-09-02T09:00:00.000Z']);
    final cache = TranscriptCache();
    final scanner = TranscriptScanner([
      '${temp.path}/projects',
    ], cache: cache);
    scanner.scan();
    expect(cache.length, 2);

    file.deleteSync();
    scanner.scan();

    expect(cache.length, 1);
  });

  test('a transcript older than the window is not read at all', () {
    final old = write('old.jsonl', ['2026-01-01T09:00:00.000Z']);
    old.setLastModifiedSync(DateTime(2026, 1, 1));
    write('new.jsonl', ['2026-09-01T09:00:00.000Z']);
    final cache = TranscriptCache();
    final scanner = TranscriptScanner([
      '${temp.path}/projects',
    ], cache: cache);

    expect(scanner.scan(since: DateTime(2026, 8)), hasLength(1));
    expect(cache.holds('${projects.path}/old.jsonl'), isFalse);

    // Widening the window is what pulls it in.
    expect(scanner.scan(since: DateTime(2025)), hasLength(2));
    expect(cache.holds('${projects.path}/old.jsonl'), isTrue);
  });

  test('clearing it makes the next scan read everything again', () {
    write('a.jsonl', ['2026-09-01T09:00:00.000Z']);
    final cache = TranscriptCache();
    TranscriptScanner(['${temp.path}/projects'], cache: cache).scan();

    cache.clear();

    expect(cache.length, 0);
  });

  test('without a cache the scan still works', () {
    write('a.jsonl', ['2026-09-01T09:00:00.000Z', '2026-09-01T09:05:00.000Z']);

    expect(TranscriptScanner(['${temp.path}/projects']).scan(), hasLength(2));
  });

  test('a file that cannot be looked at is nothing to read', () {
    final cache = TranscriptCache();

    expect(cache.events('/nonexistent/a.jsonl', () => const []), isNull);
    expect(cache.length, 0);
  });
}
