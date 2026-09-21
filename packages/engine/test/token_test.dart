import 'dart:io';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:test/test.dart';

void main() {
  Log.enabled = false;

  late Directory temp;
  late String path;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('aitracker_token');
    path = '${temp.path}/mcp-token';
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('there is no key until one is issued', () {
    expect(McpToken.read(path), isNull);

    final token = McpToken.ensure(path);

    expect(token, isNotEmpty);
    expect(McpToken.read(path), token);
    expect(McpToken.ensure(path), token);
  });

  test('a key is long, random and readable only by its owner', () {
    final first = McpToken.issue(path);
    final second = McpToken.issue(path);

    expect(first.length, greaterThanOrEqualTo(32));
    expect(first, isNot(second));
    expect(first, isNot(contains('=')));
    if (Platform.isMacOS || Platform.isLinux) {
      final mode = File(path).statSync().mode & 0x1FF;
      expect(mode, 0x180, reason: 'user read and write only');
    }
  });

  test('revoking shuts the endpoint', () {
    McpToken.issue(path);

    McpToken.revoke(path);

    expect(McpToken.read(path), isNull);
    // Revoking what is not there is not an error.
    expect(() => McpToken.revoke(path), returnsNormally);
  });

  test('an empty file counts as no key', () {
    File(path).writeAsStringSync('   \n');

    expect(McpToken.read(path), isNull);
  });

  test('the default lives beside the configuration', () {
    expect(McpToken.path(), endsWith('AITracker/mcp-token'));
  });
}
