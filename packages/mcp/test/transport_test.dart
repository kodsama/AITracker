import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aitracker_mcp/aitracker_mcp.dart';
import 'package:test/test.dart';

/// A sink that keeps what a transport wrote, so the loop can be driven without
/// a real stdout.
class _Recorder implements IOSink {
  final StringBuffer buffer = StringBuffer();

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  final server = McpServer(
    tools: [
      McpTool(
        name: 'echo',
        description: 'returns what it was given',
        inputSchema: const {'type': 'object'},
        run: (args) async => {'ok': true, 'args': args},
      ),
    ],
  );

  String request(int id, [String method = 'ping']) =>
      jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method});

  group('stdio', () {
    test('answers each line and ignores the blank ones', () async {
      final output = _Recorder();
      await serveStdio(
        server,
        input: Stream.value(
          utf8.encode('${request(1)}\n\n${request(2, 'tools/list')}\n'),
        ),
        output: output,
      );

      final lines = output.buffer.toString().trim().split('\n');
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first), containsPair('id', 1));
      expect(jsonDecode(lines.last), containsPair('id', 2));
    });

    test('says nothing back to a notification', () async {
      final output = _Recorder();
      await serveStdio(
        server,
        input: Stream.value(
          utf8.encode('${jsonEncode({'jsonrpc': '2.0', 'method': 'x'})}\n'),
        ),
        output: output,
      );

      expect(output.buffer.toString(), isEmpty);
    });
  });

  group('tcp', () {
    test('serves a client over a socket and keeps replies in order', () async {
      final logs = <String>[];
      final socket = await serveTcp(server, port: 0, onLog: logs.add);
      addTearDown(socket.close);

      final client = await Socket.connect('127.0.0.1', socket.port);
      final replies = <Map<String, Object?>>[];
      final done = Completer<void>();
      utf8.decoder
          .bind(client)
          .transform(const LineSplitter())
          .listen((line) {
            replies.add((jsonDecode(line) as Map).cast<String, Object?>());
            if (replies.length == 3) done.complete();
          });

      client.writeln(request(1));
      client.writeln(request(2, 'tools/list'));
      client.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': 'echo',
            'arguments': {'hello': 'there'},
          },
        }),
      );
      await done.future.timeout(const Duration(seconds: 5));
      await client.close();

      expect(replies.map((r) => r['id']), [1, 2, 3]);
      expect(
        ((replies.last['result']! as Map)['structuredContent']! as Map)['args'],
        {'hello': 'there'},
      );
      expect(logs.first, contains('listening on 127.0.0.1'));
    });

    test('a non-object payload is an invalid request', () async {
      final response = await processLine(server, '42');
      expect((response!['error']! as Map)['code'], -32600);
    });
  });
}
