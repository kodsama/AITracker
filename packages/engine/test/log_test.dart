import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_log');
    Log.useFile('${temp.path}/log.txt');
    Log.enabled = true;
  });

  tearDown(() {
    Log.enabled = false;
    temp.deleteSync(recursive: true);
  });

  test('writes a level, a time and the message', () {
    Log.info('filed 3 blocks');
    Log.warn('WorkingHours is open');
    Log.error('could not write', const FileSystemException('nope'));

    final lines = Log.tail();
    expect(lines, hasLength(3));
    expect(lines.first, contains('INFO  filed 3 blocks'));
    expect(lines[1], contains('WARN  WorkingHours is open'));
    expect(lines.last, contains('ERROR could not write  <- '));
    expect(DateTime.tryParse(lines.first.split('  ').first), isNotNull);
  });

  test('tail returns the end of a long log', () {
    for (var i = 0; i < 50; i++) {
      Log.info('line $i');
    }

    final lines = Log.tail(10);

    expect(lines, hasLength(10));
    expect(lines.last, contains('line 49'));
  });

  test('rotates once it grows past the cap, keeping one older file', () {
    // Each line is capped at Log.maxLine, so it takes a few to pass the cap.
    final long = 'x' * Log.maxLine;
    for (var i = 0; i < 1200; i++) {
      Log.info(long);
    }

    expect(File('${temp.path}/log.txt.1').existsSync(), isTrue);
    expect(File('${temp.path}/log.txt').lengthSync(), lessThan(Log.maxBytes));
  });

  test('a silenced log writes nothing, and clear empties it', () {
    Log.info('kept');
    Log.enabled = false;
    Log.info('dropped');
    expect(Log.tail().single, contains('kept'));

    Log.enabled = true;
    Log.clear();
    expect(Log.tail(), isEmpty);
  });

  test('a log it cannot write is not a failure', () {
    // A path under a file rather than a folder: writing it cannot work.
    Log.useFile('/dev/null/nope/log.txt');

    expect(() => Log.info('swallowed'), returnsNormally);
    expect(Log.tail(), isEmpty);
  });

  test('a log it may not read tails as nothing', () {
    Log.info('written');
    Process.runSync('/bin/chmod', ['000', '${temp.path}/log.txt']);
    addTearDown(
      () => Process.runSync('/bin/chmod', ['644', '${temp.path}/log.txt']),
    );

    expect(Log.tail(), isEmpty);
  });

  test('it knows where it goes by default', () {
    expect(Log.defaultPath(), endsWith('AI Tracker.log'));
  });

  test('an unwritten log tails as nothing', () {
    Log.useFile('/nonexistent/place/log.txt');
    expect(Log.tail(), isEmpty);
  });
}
