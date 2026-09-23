// The type on every local here is the assertion: it fails to compile if a
// signature drifts, which is what this file exists to catch.
// ignore_for_file: omit_local_variable_types, prefer_function_declarations_over_variables

import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The shapes the engine hands out, exercised as a caller would hold them.
///
/// Line coverage says the code ran; these say the surface is usable: the types
/// can be named, the constants mean something, and the small helpers answer on
/// their own rather than only inside something bigger.
void main() {
  Log.enabled = false;

  test('a colour comparison is a list of differences', () {
    final List<ColourDifference> differences = compareColors(
      const AiTrackerConfig(
        sources: [],
        rules: [ProjectRule(match: 'x', project: 'A - x')],
        links: [ProjectLink(name: 'A - x', color: '#FF000000')],
      ),
      const Catalog(
        projects: [LedgerProject(name: 'A - x', hidden: false, color: '#FFFFFFFF')],
        tags: [LedgerTag(value: 'A', hidden: false)],
        companies: ['A'],
      ),
    );

    final ColourDifference difference = differences.single;
    expect(difference.here, '#FF000000');
    expect(difference.there, '#FFFFFFFF');
  });

  test('a catalogue tag says whether the app has archived it', () {
    const tag = LedgerTag(value: 'Programming', hidden: true);

    expect(tag.value, 'Programming');
    expect(tag.toJson(), {'value': 'Programming', 'hidden': true});
  });

  test('a summary row can be held and read', () {
    final List<SummaryRow> rows = summarise([
      TrackedBlock(
        block: WorkBlock(
          directory: '/repo',
          start: DateTime(2026, 9, 1, 9),
          end: DateTime(2026, 9, 1, 10),
        ),
        project: 'A - x',
        description: 'AI: repo',
      ),
    ], Grouping.day);

    final SummaryRow row = rows.single;
    expect(row.sortsBy, DateTime(2026, 9, 1));
    expect(row.label, contains('Sep'));
  });

  test('an archive summary says what is in it', () {
    const HistorySummary empty = HistorySummary(events: 0, files: 0, bytes: 0);

    expect(empty.first, isNull);
    expect(empty.toJson()['events'], 0);
  });

  test('a period can be described on its own', () {
    expect(
      describePeriod(
        Period(label: '', start: DateTime(2026, 9), end: DateTime(2026, 10)),
      ),
      'September 2026',
    );
    expect(
      describePeriod(
        Period(
          label: '',
          start: DateTime(2026, 9, 28),
          end: DateTime(2026, 10, 3),
        ),
      ),
      '28 Sep to 2 Oct',
    );
    expect(
      describePeriod(
        Period(
          label: '',
          start: DateTime(2026, 12, 30),
          end: DateTime(2027, 1, 2),
        ),
      ),
      '30 Dec to 1 Jan 2027',
    );
  });

  test('the ledger name convention is one separator, named once', () {
    expect(kProjectSeparator, ' - ');
    expect(
      composeProjectName('A', 'x'),
      'A${kProjectSeparator}x',
    );
  });

  test('the assistants looked for are named, not guessed at', () {
    expect(AiTrackerConfig.assistantFolders, contains('.gemini'));
    expect(AiTrackerConfig.assistantFolders, contains('.codex'));
    expect(
      AiTrackerConfig.assistantFolders.every((f) => f.startsWith('.')),
      isTrue,
    );
  });

  test('the archive says which schema it writes', () {
    final temp = Directory.systemTemp.createTempSync('aitracker_api');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = HistoryStore.open('${temp.path}/history.db');
    addTearDown(store.close);

    final db = sqlite3.open('${temp.path}/history.db');
    expect(
      db.select('pragma user_version').first.values.first,
      HistoryStore.schemaVersion,
    );
    db.close();
  });

  test('the calendar helper is looked for in a stated order', () {
    final List<String> places = CalendarSink.helperCandidates();

    expect(places.first, endsWith('.local/bin/aitracker-calendar'));
    expect(places, contains('/usr/local/bin/aitracker-calendar'));
    expect(places.every((p) => p.endsWith('aitracker-calendar')), isTrue);
  });

  test('a helper runner and a command runner are what tests stand in for', () {
    final HelperRunner helper = (executable, arguments) =>
        ProcessResult(0, 0, '{"ok":true}', '');
    final CommandRunner command = (executable, arguments) =>
        ProcessResult(0, 0, '', '');
    const Pause pause = _noWait;

    expect(helper('x', const []).stdout, '{"ok":true}');
    expect(command('x', const []).exitCode, 0);
    expect(() => pause(Duration.zero), returnsNormally);
  });

  test('a tag is made once and found after that', () {
    final temp = Directory.systemTemp.createTempSync('aitracker_api_tags');
    addTearDown(() => temp.deleteSync(recursive: true));
    final db = sqlite3.open('${temp.path}/wh.db');
    addTearDown(db.close);
    db.execute(
      'create table Tags (TagId integer primary key autoincrement not null, '
      'Value varchar not null, Type integer not null, SortIndex integer not null, '
      'AutoAssign integer not null, Details varchar not null, Icon varchar, '
      'Color varchar not null, AdjustmentValue float not null, '
      'Hidden integer not null)',
    );

    final first = WorkingHoursSink.tagId(db, 'Programming', '#FF000000');

    expect(WorkingHoursSink.tagId(db, 'Programming', '#FF000000'), first);
    expect(db.select('select * from Tags'), hasLength(1));
  });

  test('a ledger change carries the edit it would make', () {
    final block = TrackedBlock(
      block: WorkBlock(
        directory: '/repo',
        start: DateTime(2026, 9, 1, 9),
        end: DateTime(2026, 9, 1, 10),
      ),
      project: 'A - x',
      description: 'AI: repo',
    );
    final UnitDifference difference = UnitDifference(
      block: block,
      project: 'B - y',
      description: 'moved',
      start: DateTime(2026, 9, 1, 9, 30),
      end: DateTime(2026, 9, 1, 10),
    );

    final BlockOverride edit = difference.asOverride;
    expect(edit.project, 'B - y');
    expect(edit.description, 'moved');
    expect(edit.start, DateTime(2026, 9, 1, 9, 30));
  });

  test('a busy range is the pair a store already holds', () {
    final TimeRange busy = (
      start: DateTime(2026, 9, 1, 9),
      end: DateTime(2026, 9, 1, 10),
    );

    final left = subtractBusy(
      TrackedBlock(
        block: WorkBlock(
          directory: '/repo',
          start: DateTime(2026, 9, 1, 9),
          end: DateTime(2026, 9, 1, 11),
        ),
        project: 'A - x',
        description: 'AI: repo',
      ),
      [busy],
      const Duration(minutes: 5),
    );

    expect(left.single.block.start, busy.end);
  });

  test('a measure is a function a caller can hold', () {
    const BlockAmount amount = tokensUsed;

    expect(
      amount(
        TrackedBlock(
          block: WorkBlock(
            directory: '/repo',
            start: DateTime(2026, 9, 1, 9),
            end: DateTime(2026, 9, 1, 10),
            tokens: const TokenUsage(input: 40, output: 2),
          ),
          project: 'A - x',
          description: 'AI: repo',
        ),
      ),
      42,
    );
  });

  test('a log line has a level', () {
    expect(LogLevel.values, hasLength(4));
    expect(LogLevel.warn.name, 'warn');
  });

  test('a transcript line is read in a stated format', () {
    const TranscriptFormat format = TranscriptFormat.claudeCode;

    expect(
      parseTranscriptLine(
        '{"timestamp":"2026-09-01T09:00:00.000Z"}',
        format,
        directory: '/repo',
        session: 's',
      ),
      isNotNull,
    );
  });
}

void _noWait(Duration duration) {}
