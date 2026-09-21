import 'dart:convert';
import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

void main() {
  // A test run has no business writing to the user's log.
  Log.enabled = false;

  late Map<String, Object?> request;
  late Map<String, Object?> answer;

  ProcessResult stub(String executable, List<String> arguments) {
    request = (jsonDecode(File(arguments.single).readAsStringSync()) as Map)
        .cast<String, Object?>();
    return ProcessResult(0, 0, jsonEncode(answer), '');
  }

  CalendarSink sink({
    List<ProjectLink> links = const [],
    CalendarSinkConfig config = const CalendarSinkConfig(enabled: true),
  }) => CalendarSink(
    config: config,
    links: links,
    helperPath: '/stub/aitracker-calendar',
    run: stub,
  );

  TrackedBlock block(
    String day,
    String project, {
    int hours = 1,
    String start = '09:00',
  }) => TrackedBlock(
    block: WorkBlock(
      directory: '/repo',
      start: DateTime.parse('${day}T$start:00'),
      end: DateTime.parse('${day}T$start:00').add(Duration(hours: hours)),
    ),
    project: project,
    description: 'AI: repo',
  );

  setUp(() {
    request = {};
    answer = {
      'ok': true,
      'calendar': 'AI work',
      'created': 2,
      'updated': 0,
      'removed': 0,
      'unchanged': 0,
    };
  });

  test('asks for one day per worked day, titled with the total', () {
    final report = sink().sync([
      block('2026-09-01', 'Byte Buddies - idbuddy'),
      block('2026-09-01', 'Byte Buddies - idbuddy', start: '13:00', hours: 2),
      block('2026-09-03', 'Paperweight AI - paperweight'),
    ], dryRun: false);

    final days = (request['days']! as List).cast<Map<String, Object?>>();
    expect(days.map((d) => d['date']), ['2026-09-01', '2026-09-03']);
    expect(days.first['title'], 'AI work: 3h 0m');
    expect(request['calendar'], 'AI work');
    expect(request['from'], '2026-09-01');
    expect(request['to'], '2026-09-03');
    expect(request['dryRun'], isFalse);
    expect(report.applied, isTrue);
    expect(report.notes.first, contains('added 2 days'));
  });

  test('the notes carry the day broken down by project', () {
    sink().sync([
      block('2026-09-01', 'Byte Buddies - idbuddy'),
      block('2026-09-01', 'Paperweight AI - paperweight', start: '14:00', hours: 2),
    ], dryRun: false);

    final day = ((request['days']! as List).first as Map)['notes'];
    expect(day, 'Paperweight AI - paperweight: 2h 0m\nByte Buddies - idbuddy: 1h 0m');
  });

  test('a project can go under another name in the calendar', () {
    sink(
      links: const [
        ProjectLink(name: 'Byte Buddies - idbuddy', calendarLabel: 'idbuddy'),
      ],
    ).sync([block('2026-09-01', 'Byte Buddies - idbuddy')], dryRun: false);

    expect(((request['days']! as List).first as Map)['notes'], 'idbuddy: 1h 0m');
  });

  test('the title template is the user’s', () {
    sink(
      config: const CalendarSinkConfig(
        enabled: true,
        calendarName: 'Assistant',
        titleTemplate: 'AI {hours}',
      ),
    ).sync([block('2026-09-01', 'A - a')], dryRun: false);

    expect(request['calendar'], 'Assistant');
    expect(((request['days']! as List).first as Map)['title'], 'AI 1h 0m');
  });

  test('a preview asks the helper to change nothing', () {
    final report = sink().sync([block('2026-09-01', 'A - a')]);

    expect(request['dryRun'], isTrue);
    expect(report.applied, isFalse);
    expect(report.notes.first, contains('would add'));
  });

  test('unmapped and excluded time stays out of the calendar', () {
    final report = sink().sync([
      TrackedBlock(
        block: WorkBlock(
          directory: '/repo',
          start: DateTime(2026, 9, 1, 9),
          end: DateTime(2026, 9, 1, 10),
        ),
        project: null,
        description: 'AI: repo',
      ),
    ], dryRun: false);

    expect(request, isEmpty);
    expect(report.applied, isTrue);
    expect(report.written, isEmpty);
  });

  test('a helper that fails is a refusal carrying its reason', () {
    answer = {'ok': false, 'error': 'calendar access was refused'};

    final report = sink().sync([block('2026-09-01', 'A - a')], dryRun: false);

    expect(report.applied, isFalse);
    expect(report.refusal, contains('calendar access was refused'));
  });

  test('says how to build the helper when it is not there', () {
    const missing = CalendarSink(
      config: CalendarSinkConfig(enabled: true),
      helperPath: '',
    );

    final report = missing.sync([block('2026-09-01', 'A - a')]);

    expect(report.refusal, contains('tool/build-calendar-helper.sh'));
  });
}
