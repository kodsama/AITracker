/// What one exchange cost, as the assistant reported it.
class TokenUsage {
  /// Creates a count.
  const TokenUsage({
    this.input = 0,
    this.output = 0,
    this.cacheWrite = 0,
    this.cacheRead = 0,
  });

  /// Nothing counted.
  static const TokenUsage zero = TokenUsage();

  /// Fresh prompt tokens.
  final int input;

  /// Tokens the assistant produced.
  final int output;

  /// Tokens written into the prompt cache.
  final int cacheWrite;

  /// Tokens served from the prompt cache.
  final int cacheRead;

  /// Everything that passed through, cache included.
  int get total => input + output + cacheWrite + cacheRead;

  /// Everything that was not a cache hit, which is what a bill is mostly made
  /// of.
  int get fresh => input + output + cacheWrite;

  /// Whether anything was counted at all.
  bool get isEmpty => total == 0;

  /// Sums two counts.
  TokenUsage operator +(TokenUsage other) => TokenUsage(
    input: input + other.input,
    output: output + other.output,
    cacheWrite: cacheWrite + other.cacheWrite,
    cacheRead: cacheRead + other.cacheRead,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'input': input,
    'output': output,
    'cache_write': cacheWrite,
    'cache_read': cacheRead,
    'total': total,
  };
}

/// One timestamped line of a transcript: the moment something happened, where
/// the session was working, and what that exchange cost.
class ActivityEvent {
  /// Creates an event.
  const ActivityEvent({
    required this.time,
    required this.directory,
    required this.sessionId,
    this.tokens = TokenUsage.zero,
  });

  /// When it happened, in local time.
  final DateTime time;

  /// Working directory of the session that produced it.
  final String directory;

  /// Transcript the event came from, used to count sessions per block.
  final String sessionId;

  /// Tokens this line reported, zero for the lines that report none.
  final TokenUsage tokens;
}

/// A contiguous stretch of attention on one directory.
class WorkBlock {
  /// Creates a block.
  const WorkBlock({
    required this.directory,
    required this.start,
    required this.end,
    this.sessions = 1,
    this.tokens = TokenUsage.zero,
  });

  /// Working directory the work happened in.
  final String directory;

  /// First moment of the block, local time.
  final DateTime start;

  /// Last moment of the block, local time.
  final DateTime end;

  /// How many transcripts contributed to it.
  final int sessions;

  /// Tokens the exchanges inside it reported.
  final TokenUsage tokens;

  /// Wall-clock length.
  Duration get duration => end.difference(start);

  /// A copy with the given fields replaced.
  WorkBlock copyWith({
    String? directory,
    DateTime? start,
    DateTime? end,
    int? sessions,
    TokenUsage? tokens,
  }) => WorkBlock(
    directory: directory ?? this.directory,
    start: start ?? this.start,
    end: end ?? this.end,
    sessions: sessions ?? this.sessions,
    tokens: tokens ?? this.tokens,
  );

  @override
  String toString() => 'WorkBlock($directory, $start -> $end)';
}

/// How a transcript line is laid out.
enum TranscriptFormat {
  /// Claude Code: an ISO `timestamp`, the session's `cwd`, and a `usage` block
  /// on the assistant's turns.
  claudeCode,

  /// The Gemini and Antigravity CLIs: an epoch-millisecond `timestamp` and the
  /// `workspace` the prompt was typed in. No token counts are recorded.
  geminiCli,

  /// Nothing recognisable.
  unknown,
}

/// The layout of [line], for picking the fields out of the rest of the file.
TranscriptFormat formatOf(String line) {
  if (line.contains('"timestamp":"')) return TranscriptFormat.claudeCode;
  if (line.contains('"workspace":"') && line.contains('"timestamp":')) {
    return TranscriptFormat.geminiCli;
  }
  return TranscriptFormat.unknown;
}

/// The working directory [line] names, if it names one.
String? directoryIn(String line, TranscriptFormat format) =>
    format == TranscriptFormat.geminiCli
    ? extractString(line, '"workspace":"')
    : extractString(line, '"cwd":"');

/// One transcript line as an event, or null when it carries no time.
///
/// Lines are read as text rather than decoded as JSON: a transcript holds whole
/// tool payloads, and only a few fields are wanted.
ActivityEvent? parseTranscriptLine(
  String line,
  TranscriptFormat format, {
  required String directory,
  required String session,
}) {
  final DateTime? time;
  if (format == TranscriptFormat.geminiCli) {
    final millis = extractNumber(line, '"timestamp":');
    time = millis == 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  } else {
    final stamp = extractString(line, '"timestamp":"');
    time = stamp == null ? null : DateTime.tryParse(stamp)?.toLocal();
  }
  if (time == null) return null;
  return ActivityEvent(
    time: time,
    directory: directory,
    sessionId: extractString(line, '"conversationId":"') ?? session,
    tokens: usageIn(line),
  );
}

/// What the line says the exchange cost. Lines that carry no usage block, which
/// is most of them, cost nothing.
TokenUsage usageIn(String line) {
  if (!line.contains('"usage"')) return TokenUsage.zero;
  return TokenUsage(
    input: extractNumber(line, '"input_tokens":'),
    output: extractNumber(line, '"output_tokens":'),
    cacheWrite: extractNumber(line, '"cache_creation_input_tokens":'),
    cacheRead: extractNumber(line, '"cache_read_input_tokens":'),
  );
}

/// The string value following [key], or null when the line has no such key.
String? extractString(String line, String key) {
  final start = line.indexOf(key);
  if (start < 0) return null;
  final from = start + key.length;
  final end = line.indexOf('"', from);
  if (end < 0) return null;
  return line.substring(from, end);
}

/// The number following [key], or zero when the line has no such key.
int extractNumber(String line, String key) {
  final start = line.indexOf(key);
  if (start < 0) return 0;
  var at = start + key.length;
  while (at < line.length && line[at] == ' ') {
    at++;
  }
  final digits = StringBuffer();
  while (at < line.length && _isDigit(line.codeUnitAt(at))) {
    digits.writeCharCode(line.codeUnitAt(at));
    at++;
  }
  return int.tryParse(digits.toString()) ?? 0;
}

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

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
      last.tokens += event.tokens;
    } else {
      spans.add(
        _Span(event.directory, event.time, sorted[i + 1].time, event.sessionId)
          ..tokens += event.tokens,
      );
    }
    // The closing event of a stretch reports the exchange that ended it.
    if (i == sorted.length - 2) spans.last.tokens += sorted[i + 1].tokens;
  }

  // A minute spent in another repository in the middle of an hour's work is a
  // glance, not a second block: anything too short to keep is absorbed, and the
  // work either side of it stays one stretch.
  final merged = <_Span>[];
  for (final span in spans) {
    final previous = merged.lastIndexWhere((m) => m.directory == span.directory);
    final interrupted = previous >= 0 &&
        merged
            .skip(previous + 1)
            .every((m) => m.end.difference(m.start) < minBlock);
    if (previous >= 0 &&
        interrupted &&
        span.start.difference(merged[previous].end) <= idleGap) {
      merged[previous].end = span.end;
      merged[previous].sessions.addAll(span.sessions);
      merged[previous].tokens += span.tokens;
      merged.removeRange(previous + 1, merged.length);
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
        tokens: span.tokens,
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
  TokenUsage tokens = TokenUsage.zero;
}

/// Wall-clock time covered by [blocks], counting a minute once however many
/// sessions were running in it.
///
/// The exclusive blocks [buildBlocks] returns never overlap, so this is their
/// plain sum; it earns its keep over per-project blocks, which do overlap.
Duration unionDuration(Iterable<WorkBlock> blocks) {
  final sorted = [...blocks]..sort((a, b) => a.start.compareTo(b.start));
  var total = Duration.zero;
  DateTime? until;
  for (final block in sorted) {
    final start = until != null && until.isAfter(block.start)
        ? until
        : block.start;
    if (!start.isBefore(block.end)) continue;
    total += block.end.difference(start);
    until = block.end;
  }
  return total;
}

/// Blocks per directory, each on its own timeline.
///
/// Two repositories worked at once produce overlapping blocks here, so the
/// totals answer "how much did this project get" rather than "how long was the
/// assistant working". [buildBlocks] answers the second, and a timesheet wants
/// that one.
List<WorkBlock> buildProjectBlocks(
  List<ActivityEvent> events, {
  Duration idleGap = const Duration(minutes: 10),
  Duration minBlock = const Duration(minutes: 5),
}) {
  final byDirectory = <String, List<ActivityEvent>>{};
  for (final event in events) {
    byDirectory.putIfAbsent(event.directory, () => []).add(event);
  }
  return [
    for (final directory in byDirectory.values)
      ...buildBlocks(directory, idleGap: idleGap, minBlock: minBlock),
  ]..sort((a, b) => a.start.compareTo(b.start));
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
