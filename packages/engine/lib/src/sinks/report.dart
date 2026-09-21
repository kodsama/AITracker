import '../tracking.dart';

/// What a sink did, or would have done.
class SyncReport {
  /// Creates a report.
  SyncReport({
    required this.sink,
    required this.applied,
    this.refusal,
    List<TrackedBlock>? written,
    List<TrackedBlock>? skipped,
    List<String>? notes,
    List<String>? outputs,
    this.backup,
  }) : written = written ?? const [],
       skipped = skipped ?? const [],
       notes = notes ?? const [],
       outputs = outputs ?? const [];

  /// Which sink this is: `workinghours`, `diarium` or `tabular`.
  final String sink;

  /// Whether anything was actually written. False for a preview, and false
  /// when [refusal] explains why the sink stood down.
  final bool applied;

  /// Why nothing was written, when a guard stopped the run.
  final String? refusal;

  /// Blocks written, or that a preview would write.
  final List<TrackedBlock> written;

  /// Blocks left out because the target already covers that time.
  final List<TrackedBlock> skipped;

  /// Anything worth saying: projects created, entries updated, days touched.
  final List<String> notes;

  /// Files the sink produced.
  final List<String> outputs;

  /// Copy of the store taken before the first write.
  final String? backup;

  /// Time in [written].
  Duration get total =>
      written.fold(Duration.zero, (sum, b) => sum + b.block.duration);

  /// JSON form, as the MCP tools and the CLI report it.
  Map<String, Object?> toJson() => {
    'sink': sink,
    'applied': applied,
    if (refusal != null) 'refusal': refusal,
    'written': written.length,
    'skipped': skipped.length,
    'total_hours': double.parse(
      (total.inMinutes / 60).toStringAsFixed(2),
    ),
    'blocks': [
      for (final b in written)
        {
          'project': b.project,
          'description': b.description,
          'start': b.block.start.toIso8601String(),
          'end': b.block.end.toIso8601String(),
          'hours': double.parse(
            (b.block.duration.inMinutes / 60).toStringAsFixed(2),
          ),
        },
    ],
    if (notes.isNotEmpty) 'notes': notes,
    if (outputs.isNotEmpty) 'outputs': outputs,
    if (backup != null) 'backup': backup,
  };
}

/// A stretch of time already accounted for in a target store.
typedef TimeRange = ({DateTime start, DateTime end});

/// [block] with every range in [busy] cut out of it.
///
/// Time a store already holds, whatever project it sits under, is time the user
/// already logged; writing over it would bill the same minute twice.
List<TrackedBlock> subtractBusy(
  TrackedBlock block,
  List<TimeRange> busy,
  Duration minBlock,
) {
  var pieces = <({DateTime start, DateTime end})>[
    (start: block.block.start, end: block.block.end),
  ];
  for (final range in busy) {
    final next = <({DateTime start, DateTime end})>[];
    for (final piece in pieces) {
      if (!range.start.isBefore(piece.end) || !piece.start.isBefore(range.end)) {
        next.add(piece);
        continue;
      }
      if (piece.start.isBefore(range.start)) {
        next.add((start: piece.start, end: range.start));
      }
      if (range.end.isBefore(piece.end)) {
        next.add((start: range.end, end: piece.end));
      }
    }
    pieces = next;
    if (pieces.isEmpty) break;
  }
  return [
    for (final piece in pieces)
      if (piece.end.difference(piece.start) >= minBlock)
        TrackedBlock(
          block: block.block.copyWith(start: piece.start, end: piece.end),
          project: block.project,
          description: block.description,
          excluded: block.excluded,
        ),
  ];
}
