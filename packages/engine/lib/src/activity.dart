import 'dart:io';

import 'package:path/path.dart' as p;

/// One timestamped line of a transcript: the moment something happened, and
/// where the session was working.
class ActivityEvent {
  /// Creates an event.
  const ActivityEvent({
    required this.time,
    required this.directory,
    required this.sessionId,
  });

  /// When it happened, in local time.
  final DateTime time;

  /// Working directory of the session that produced it.
  final String directory;

  /// Transcript the event came from, used to count sessions per block.
  final String sessionId;
}

/// A contiguous stretch of attention on one directory.
class WorkBlock {
  /// Creates a block.
  const WorkBlock({
    required this.directory,
    required this.start,
    required this.end,
    this.sessions = 1,
  });

  /// Working directory the work happened in.
  final String directory;

  /// First moment of the block, local time.
  final DateTime start;

  /// Last moment of the block, local time.
  final DateTime end;

  /// How many transcripts contributed to it.
  final int sessions;

  /// Wall-clock length.
  Duration get duration => end.difference(start);

  /// A copy with the given fields replaced.
  WorkBlock copyWith({
    String? directory,
    DateTime? start,
    DateTime? end,
    int? sessions,
  }) => WorkBlock(
    directory: directory ?? this.directory,
    start: start ?? this.start,
    end: end ?? this.end,
    sessions: sessions ?? this.sessions,
  );

  @override
  String toString() => 'WorkBlock($directory, $start -> $end)';
}

/// Reads AI assistant transcripts and yields their activity events.
///
/// Claude Code writes one JSONL file per session under
/// `<root>/<encoded-project>/…`, each line carrying an ISO `timestamp` and the
/// session's `cwd`. Lines are scanned as text rather than decoded as JSON: a
/// transcript holds whole tool payloads, and only two fields are wanted.
class TranscriptScanner {
  /// Creates a scanner over [sources], each a directory of transcripts.
  const TranscriptScanner(this.sources);

  /// Directories to walk, recursively.
  final List<String> sources;

  /// Every event at or after [since], in no particular order.
  List<ActivityEvent> scan({DateTime? since}) {
    final events = <ActivityEvent>[];
    for (final source in sources) {
      final dir = Directory(source);
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (p.extension(file.path) != '.jsonl') continue;
        if (since != null && file.lastModifiedSync().isBefore(since)) continue;
        events.addAll(readTranscript(file, since: since));
      }
    }
    return events;
  }

  /// Events from a single transcript [file].
  ///
  /// The session's directory is the first `cwd` the file mentions; a transcript
  /// with none falls back to the name of the project folder holding it.
  List<ActivityEvent> readTranscript(File file, {DateTime? since}) {
    final sessionId = p.basenameWithoutExtension(file.path);
    String? directory;
    final events = <ActivityEvent>[];
    final List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } on FileSystemException {
      return const [];
    }
    for (final line in lines) {
      directory ??= _extract(line, '"cwd":"');
      final stamp = _extract(line, '"timestamp":"');
      if (stamp == null) continue;
      final time = DateTime.tryParse(stamp)?.toLocal();
      if (time == null) continue;
      if (since != null && time.isBefore(since)) continue;
      events.add(
        ActivityEvent(
          time: time,
          directory: directory ?? _projectFolder(file),
          sessionId: sessionId,
        ),
      );
    }
    if (directory == null) return events;
    // The directory is only known once a line mentions it, so stamp the ones
    // read before that with the value the session turned out to have.
    return [
      for (final event in events)
        ActivityEvent(
          time: event.time,
          directory: directory,
          sessionId: event.sessionId,
        ),
    ];
  }

  static String _projectFolder(File file) {
    final parts = p.split(file.parent.path);
    final index = parts.lastIndexOf('projects');
    if (index >= 0 && index + 1 < parts.length) return parts[index + 1];
    return file.parent.path;
  }

  static String? _extract(String line, String key) {
    final start = line.indexOf(key);
    if (start < 0) return null;
    final from = start + key.length;
    final end = line.indexOf('"', from);
    if (end < 0) return null;
    return line.substring(from, end);
  }
}

/// Turns [events] into work blocks.
///
/// Time between two consecutive events counts as worked when the gap is at most
/// [idleGap], and is credited to the directory of the earlier one, so parallel
/// sessions in two repositories never bill the same minute twice. Blocks
/// shorter than [minBlock] are dropped, blocks are trimmed so none overlap, and
/// anything crossing local midnight is split so a day's total stays a day's.
List<WorkBlock> buildBlocks(
  List<ActivityEvent> events, {
  Duration idleGap = const Duration(minutes: 10),
  Duration minBlock = const Duration(minutes: 5),
}) {
  if (events.length < 2) return const [];
  final sorted = [...events]..sort((a, b) => a.time.compareTo(b.time));

  final spans = <_Span>[];
  for (var i = 0; i < sorted.length - 1; i++) {
    final event = sorted[i];
    final gap = sorted[i + 1].time.difference(event.time);
    if (gap > idleGap) continue;
    final last = spans.isEmpty ? null : spans.last;
    // Same directory and no other repository in between: extend the span.
    if (last != null &&
        last.directory == event.directory &&
        last.end == event.time) {
      last.end = sorted[i + 1].time;
      last.sessions.add(event.sessionId);
    } else {
      spans.add(
        _Span(event.directory, event.time, sorted[i + 1].time, event.sessionId),
      );
    }
  }

  final merged = <_Span>[];
  for (final span in spans) {
    final last = merged.isEmpty ? null : merged.last;
    if (last != null &&
        last.directory == span.directory &&
        span.start.difference(last.end) <= idleGap) {
      last.end = span.end;
      last.sessions.addAll(span.sessions);
    } else {
      merged.add(span);
    }
  }

  final blocks = <WorkBlock>[];
  DateTime? previousEnd;
  for (final span in merged) {
    final start = previousEnd != null && span.start.isBefore(previousEnd)
        ? previousEnd
        : span.start;
    if (span.end.difference(start) < minBlock) continue;
    blocks.add(
      WorkBlock(
        directory: span.directory,
        start: start,
        end: span.end,
        sessions: span.sessions.length,
      ),
    );
    previousEnd = span.end;
  }
  return _splitAtMidnight(blocks);
}

class _Span {
  _Span(this.directory, this.start, this.end, String session)
    : sessions = {session};

  final String directory;
  final DateTime start;
  DateTime end;
  final Set<String> sessions;
}

List<WorkBlock> _splitAtMidnight(List<WorkBlock> blocks) {
  final result = <WorkBlock>[];
  for (final block in blocks) {
    var start = block.start;
    while (true) {
      final midnight = DateTime(start.year, start.month, start.day + 1);
      if (!block.end.isAfter(midnight)) {
        result.add(block.copyWith(start: start));
        break;
      }
      result.add(block.copyWith(start: start, end: midnight));
      start = midnight;
    }
  }
  return result;
}
