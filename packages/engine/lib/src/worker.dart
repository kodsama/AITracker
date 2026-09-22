import 'dart:async';
import 'dart:isolate';

import 'config.dart';
import 'history.dart';
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

  /// Sent by the isolate once it has closed the archive.
  static const String _stopped = 'stopped';

  final SendPort _commands;
  final ReceivePort _responses;
  final Completer<void> _alive;
  final Completer<void> _closed = Completer<void>();
  final Map<int, Completer<ScanResult>> _waiting = {};
  int _next = 0;
  bool _stopping = false;

  /// Starts the worker.
  ///
  /// An isolate gets its own copy of every static, the log included, so where
  /// it writes has to be handed over rather than assumed.
  static Future<ScanWorker> start({
    bool logging = true,
    String? logFile,
    String? historyPath,
  }) async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    final alive = Completer<void>();
    await Isolate.spawn(
      _run,
      [
        responses.sendPort,
        logging,
        logFile ?? Log.path(),
        historyPath ?? HistoryStore.defaultPath(),
      ],
      debugName: 'aitracker-scan',
    );
    late final ScanWorker worker;
    responses.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (message == _stopped) {
        worker._closed.complete();
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
    if (_stopping) return Future.value(ScanResult.empty);
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

  /// Stops the worker and waits for it to let go of the archive.
  ///
  /// Waiting matters: the archive is a file with a write-ahead log beside it,
  /// and a caller that deletes or copies it straight after stopping would
  /// otherwise catch it mid-close.
  Future<void> stop() async {
    if (_stopping) return _closed.future;
    _stopping = true;
    _commands.send(null);
    await _closed.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => Log.warn('the scan worker did not confirm it stopped'),
    );
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
    final history = HistoryStore.open(boot[3]! as String);

    commands.listen((message) {
      if (message == null) {
        history.close();
        responses.send(_stopped);
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

        final tracking = AiTracker(
          config: config,
          overrides: overrides,
          history: history,
          historyPath: null,
        );
        history.ingest(config.sources);
        responses.send([
          id,
          ScanResult(
            wallClock: tracking.blocks(since: start, until: end),
            perProject: tracking.blocks(
              since: start,
              until: end,
              mode: BlockMode.perProject,
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
