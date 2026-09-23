import 'package:aitracker/src/measures.dart';
import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:flutter_test/flutter_test.dart';

TrackedBlock block({int hours = 1, int tokens = 0}) => TrackedBlock(
  block: WorkBlock(
    directory: '/repo',
    start: DateTime(2026, 9, 1, 9),
    end: DateTime(2026, 9, 1, 9).add(Duration(hours: hours)),
    tokens: TokenUsage(input: tokens, cacheRead: tokens),
  ),
  project: 'A - a',
  description: 'AI: repo',
);

void main() {
  test('a measure says what a block is worth', () {
    expect(Amount.time.of(block(hours: 2)), 7200);
    expect(Amount.tokens.of(block(tokens: 400)), 800);
  });

  test('an axis reaches a round number above the tallest bar', () {
    // The same period drawn twice should put the gridlines in the same places,
    // so the top is one of a fixed set rather than whatever the data is.
    expect(Amount.time.ceiling(0), 3600);
    expect(Amount.time.ceiling(3599), 3600);
    expect(Amount.time.ceiling(3601), 7200);
    expect(Amount.tokens.ceiling(750), 1000);
    expect(Amount.tokens.ceiling(2000000), 5000000);
  });

  test('an axis beyond the biggest step still lands on a round number', () {
    expect(Amount.time.ceiling(1440001), 2880000);
    expect(Amount.tokens.ceiling(1000000001), 2000000000);
  });

  test('time reads as a timesheet reads it, tokens as a count', () {
    expect(Amount.time.format(9000), '2h 30m');
    expect(Amount.time.tick(7200), '2h');
    expect(Amount.time.tick(5400), '1.5h');
    expect(Amount.time.tick(72000), '20h');
    expect(Amount.tokens.format(1500), '1.5k');
    expect(Amount.tokens.tick(2400000), '2.4M');
  });

  test('a count folds at each thousand', () {
    expect(compactCount(37), '37');
    expect(compactCount(1500), '1.5k');
    expect(compactCount(2400000), '2.4M');
    expect(compactCount(3200000000), '3.2B');
  });

  test('asking for both asks for one chart of each', () {
    expect(Measure.time.amounts, [Amount.time]);
    expect(Measure.tokens.amounts, [Amount.tokens]);
    expect(Measure.both.amounts, [Amount.time, Amount.tokens]);
    expect(Measure.both.label, 'Both');
    expect(Amount.tokens.label, 'Tokens');
  });
}
