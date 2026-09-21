import 'dart:async';
import 'dart:isolate';

import 'activity.dart';
import 'cache.dart';
import 'config.dart';
import 'log.dart';
import 'overrides.dart';
import 'periods.dart';
import 'tracking.dart';

/// The two readings of one scan.
class ScanResult {
  /// Creates a result.
  const ScanResult({required this.wallClock, required this.perProject});

  /// Blocks that never overlap: a minute belongs to one project. This is what
  /// every export writes.
  final List<TrackedBlock> wallClock;

  /// Each project on its own timeline, so parallel sessions count for both.
  final List<TrackedBlock> perProject;

  /// Nothing found.
  static const ScanResult empty = ScanResult(wallClock: [], perProject: []);
}

/// Scans transcripts in one long-lived isolate that keeps what it parsed.
///
/// Two things have to be true at once: the window must stay responsive while a
/// hundred megabytes of JSONL is read, and a rescan after changing the period
/// must not read it all again. A fresh isolate per scan gives the first and
/// loses the second, since the cache dies with it, so the isolate stays and the
/// cache lives inside it.
class ScanWorker {
  ScanWorker._(this._commands, this._responses, this._alive);

  final SendPort _commands;
  final ReceivePort _responses;
  final Completer<void> _alive;
  final Map<int, Completer<ScanResult>> _waiting = {};
  int _next = 0;
  bool _stopped = false;

  /// Starts the worker.
  ///
  /// An isolate gets its own copy of every static, the log included, so where
  /// it writes has to be handed over rather than assumed.
  static Future<ScanWorker> start({bool logging = true, String? logFile}) async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    final alive = Completer<void>();
    await Isolate.spawn(
      _run,
      [responses.sendPort, logging, logFile ?? Log.path()],
      debugName: 'aitracker-scan',
    );
    late final ScanWorker worker;
    responses.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (message is! List || message.length != 2) return;
      worker._settle(message[0] as int, message[1]);
    });
    final commands = await ready.future;
    return worker = ScanWorker._(commands, responses, alive);
  }

  /// Blocks in [window], resolved through [config] and [overrides].
  Future<ScanResult> scan({
    required AiTrackerConfig config,
    required OverrideStore overrides,
    required Period window,
  }) {
    if (_stopped) return Future.value(ScanResult.empty);
    final id = _next++;
    final waiting = Completer<ScanResult>();
    _waiting[id] = waiting;
    _commands.send([
      id,
      config.toJson(),
      {
        for (final entry in overrides.entries.entries)
          entry.key: entry.value.toJson(),
      },
      window.start.toIso8601String(),
      window.end.toIso8601String(),
    ]);
    return waiting.future;
  }

  /// Stops the worker and drops its cache.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _commands.send(null);
    _responses.close();
    for (final waiting in _waiting.values) {
      if (!waiting.isCompleted) waiting.complete(ScanResult.empty);
    }
    _waiting.clear();
    if (!_alive.isCompleted) _alive.complete();
  }

  void _settle(int id, Object? payload) {
    final waiting = _waiting.remove(id);
    if (waiting == null || waiting.isCompleted) return;
    if (payload is ScanResult) {
      waiting.complete(payload);
    } else {
      waiting.completeError(
        payload is Object ? payload : StateError('the scan failed'),
      );
    }
  }

  /// The isolate: one cache, one scan at a time, answers tagged with the id
  /// they were asked under.
  static void _run(List<Object?> boot) {
    final responses = boot[0]! as SendPort;
    Log.enabled = boot[1]! as bool;
    Log.useFile(boot[2]! as String);
    final commands = ReceivePort();
    responses.send(commands.sendPort);
    final cache = TranscriptCache();

    commands.listen((message) {
      if (message == null) {
        commands.close();
        return;
      }
      final request = message as List;
      final id = request[0] as int;
      try {
        final config = AiTrackerConfig.fromJson(
          (request[1] as Map).cast<String, Object?>(),
        );
        final overrides = OverrideStore({
          for (final entry in (request[2] as Map).cast<String, Object?>().entries)
            entry.key: BlockOverride.fromJson(
              (entry.value! as Map).cast<String, Object?>(),
            ),
        });
        final start = DateTime.parse(request[3] as String);
        final end = DateTime.parse(request[4] as String);

        final tracking = AiTracker(config: config, overrides: overrides);
        final events = TranscriptScanner(
          config.sources,
          cache: cache,
        ).scan(since: start);
        List<TrackedBlock> resolve(List<WorkBlock> blocks) => [
          for (final block in blocks)
            if (block.start.isBefore(end)) tracking.resolve(block),
        ];
        responses.send([
          id,
          ScanResult(
            wallClock: resolve(
              buildBlocks(
                events,
                idleGap: config.idleGap,
                minBlock: config.minBlock,
              ),
            ),
            perProject: resolve(
              buildProjectBlocks(
                events,
                idleGap: config.idleGap,
                minBlock: config.minBlock,
              ),
            ),
          ),
        ]);
      } on Object catch (error) {
        Log.error('scan failed', error);
        responses.send([id, '$error']);
      }
    });
  }
}
