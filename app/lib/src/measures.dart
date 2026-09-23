import 'package:aitracker_engine/aitracker_engine.dart';

/// One quantity a chart can draw, and how it reads once drawn.
///
/// The charts themselves work in plain numbers so that hours and tokens go
/// through the same painter; this is what says which number and what to call
/// it on the axis.
class Amount {
  const Amount._({
    required this.label,
    required this.of,
    required this.format,
    required this.tick,
    required this.steps,
  });

  /// Hours, held as seconds so a chart can add them up.
  static const Amount time = Amount._(
    label: 'Time',
    of: secondsWorked,
    format: _asDuration,
    tick: _asHours,
    steps: [
      3600,
      7200,
      14400,
      21600,
      28800,
      43200,
      57600,
      86400,
      144000,
      216000,
      360000,
      720000,
      1440000,
    ],
  );

  /// Tokens, everything that passed through, cache included.
  static const Amount tokens = Amount._(
    label: 'Tokens',
    of: tokensUsed,
    format: _asCount,
    tick: _asCount,
    steps: [
      1000,
      10000,
      50000,
      100000,
      500000,
      1000000,
      5000000,
      10000000,
      50000000,
      100000000,
      500000000,
      1000000000,
    ],
  );

  /// What the measure is called.
  final String label;

  /// How much of it a block is worth.
  final BlockAmount of;

  /// How a value reads in a tooltip or a legend.
  final String Function(double value) format;

  /// How a value reads on an axis, where there is less room.
  final String Function(double value) tick;

  /// The axis tops to choose between, smallest first.
  ///
  /// A round top with four gridlines under it, rather than whatever the tallest
  /// bar happens to be: the same period drawn twice should put the gridlines in
  /// the same places.
  final List<int> steps;

  /// The axis top for a chart whose tallest bar is [most].
  double ceiling(double most) {
    if (most <= 0) return steps.first.toDouble();
    for (final step in steps) {
      if (most <= step) return step.toDouble();
    }
    return (most / steps.last).ceil() * steps.last.toDouble();
  }
}

/// Which of the two a screen is showing.
enum Measure {
  /// Hours alone.
  time('Time'),

  /// Tokens alone.
  tokens('Tokens'),

  /// Both, one chart each: two quantities of different size never share an
  /// axis.
  both('Both');

  const Measure(this.label);

  /// What the control calls it.
  final String label;

  /// The charts to draw, in order.
  List<Amount> get amounts => switch (this) {
    Measure.time => const [Amount.time],
    Measure.tokens => const [Amount.tokens],
    Measure.both => const [Amount.time, Amount.tokens],
  };
}

String _asDuration(double seconds) =>
    formatDuration(Duration(seconds: seconds.round()));

String _asHours(double seconds) {
  final hours = seconds / 3600;
  return hours >= 10 || hours == hours.roundToDouble()
      ? '${hours.round()}h'
      : '${hours.toStringAsFixed(1)}h';
}

String _asCount(double value) => compactCount(value.round());

/// `1.2M`, `450k`, `37`: a token count at a glance.
String compactCount(int count) {
  if (count >= 1000000000) return '${(count / 1000000000).toStringAsFixed(1)}B';
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
  return '$count';
}
