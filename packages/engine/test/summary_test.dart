import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

void main() {
  Log.enabled = false;

  TrackedBlock block({
    String? project = 'Byte Buddies - idbuddy',
    String directory = '/Users/me/Developer/idbuddy',
    DateTime? start,
    int minutes = 60,
    int output = 0,
    int sessions = 1,
    bool excluded = false,
  }) {
    final from = start ?? DateTime(2026, 9, 1, 9);
    return TrackedBlock(
      block: WorkBlock(
        directory: directory,
        start: from,
        end: from.add(Duration(minutes: minutes)),
        sessions: sessions,
        tokens: TokenUsage(output: output, cacheRead: output * 10),
      ),
      project: project,
      description: 'AI: idbuddy',
      excluded: excluded,
    );
  }

  test('groups by project, heaviest first, and keeps the unmapped', () {
    final rows = summarise([
      block(output: 100),
      block(project: 'Paperweight AI - paperweight', minutes: 120, output: 50),
      block(project: null, minutes: 30),
    ], Grouping.project);

    expect(rows.map((r) => r.label), [
      'Paperweight AI - paperweight',
      'Byte Buddies - idbuddy',
      unmappedLabel,
    ]);
    expect(rows.first.time, const Duration(hours: 2));
    expect(rows[1].tokens.total, 1100);
  });

  test('adds up the time, the tokens, the blocks and the sessions', () {
    final rows = summarise([
      block(output: 100, sessions: 2),
      block(start: DateTime(2026, 9, 1, 14), minutes: 30, output: 20),
    ], Grouping.project);

    final row = rows.single;
    expect(row.time, const Duration(minutes: 90));
    expect(row.tokens.output, 120);
    expect(row.tokens.total, 1320);
    expect(row.blocks, 2);
    expect(row.sessions, 3);
    expect(row.tokensPerHour, 880);
  });

  test('by company, with a name for the projects that have none', () {
    final rows = summarise([
      block(),
      block(project: 'idbuddy', minutes: 30),
      block(project: null, minutes: 10),
    ], Grouping.company);

    expect(rows.map((r) => r.label), ['Byte Buddies', 'No company', unmappedLabel]);
  });

  test('by repository, which is the folder rather than the path', () {
    final rows = summarise([
      block(),
      block(directory: '/Users/me/Developer/paperweight', minutes: 30),
    ], Grouping.repository);

    expect(rows.map((r) => r.label), ['idbuddy', 'paperweight']);
  });

  group('calendar groupings read in calendar order', () {
    final blocks = [
      block(start: DateTime(2026, 9, 14, 9), minutes: 30),
      block(start: DateTime(2026, 9, 1, 9), minutes: 120),
      block(start: DateTime(2026, 10, 2, 9), minutes: 15),
    ];

    test('by day', () {
      expect(summarise(blocks, Grouping.day).map((r) => r.label), [
        'Tue 1 Sep',
        'Mon 14 Sep',
        'Fri 2 Oct',
      ]);
    });

    test('by week', () {
      expect(summarise(blocks, Grouping.week).map((r) => r.label), [
        'Week of 31 Aug',
        'Week of 14 Sep',
        'Week of 28 Sep',
      ]);
    });

    test('by month', () {
      final rows = summarise(blocks, Grouping.month);
      expect(rows.map((r) => r.label), ['Sep 2026', 'Oct 2026']);
      expect(rows.first.time, const Duration(minutes: 150));
    });
  });

  test('a struck-out block is not counted', () {
    final rows = summarise([
      block(),
      block(start: DateTime(2026, 9, 1, 14), excluded: true),
    ], Grouping.project);

    expect(rows.single.blocks, 1);
  });

  test('serialises for a client', () {
    final row = summarise([block(output: 100)], Grouping.project).single;

    expect(row.toJson(), {
      'label': 'Byte Buddies - idbuddy',
      'hours': 1.0,
      'tokens': {
        'input': 0,
        'output': 100,
        'cache_write': 0,
        'cache_read': 1000,
        'total': 1100,
      },
      'blocks': 1,
      'sessions': 1,
    });
  });

  test('nothing in, nothing out', () {
    expect(summarise(const [], Grouping.project), isEmpty);
  });
}
