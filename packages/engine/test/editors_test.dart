import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aitracker_engine/aitracker_engine.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Writes a protobuf field the way the editors do, which is what these tests
/// need in order to hand the reader something shaped like the real thing.
class Wire {
  final BytesBuilder _out = BytesBuilder();

  void varint(int number, int value) {
    _key(number, 0);
    _raw(value);
  }

  void bytes(int number, List<int> value) {
    _key(number, 2);
    _raw(value.length);
    _out.add(value);
  }

  void text(int number, String value) => bytes(number, utf8.encode(value));

  /// A double, and a float: the two fixed widths a schema puts in the way of
  /// anything reading past them.
  void fixed64(int number, int value) {
    _key(number, 1);
    for (var i = 0; i < 8; i++) {
      _out.addByte(value >> (8 * i) & 0xff);
    }
  }

  void fixed32(int number, int value) {
    _key(number, 5);
    for (var i = 0; i < 4; i++) {
      _out.addByte(value >> (8 * i) & 0xff);
    }
  }

  /// A field with a wire type protobuf has never defined.
  void nonsense(int number) => _key(number, 7);

  void put(List<int> value) => _out.add(value);

  void message(int number, void Function(Wire) build) {
    final inner = Wire();
    build(inner);
    bytes(number, inner.done());
  }

  /// A `google.protobuf.Timestamp`, which is what the times are held as.
  void time(int number, DateTime at) => message(number, (w) {
    w.varint(1, at.toUtc().millisecondsSinceEpoch ~/ 1000);
    w.varint(2, 0);
  });

  Uint8List done() => _out.toBytes();

  void _key(int number, int type) => _raw(number << 3 | type);

  void _raw(int value) {
    var rest = value;
    while (rest >= 0x80) {
      _out.addByte(rest & 0x7f | 0x80);
      rest >>= 7;
    }
    _out.addByte(rest);
  }
}

void main() {
  Log.enabled = false;

  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('aitracker_editors'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// A Cursor database: conversations in one row each, their turns in others.
  String cursor(
    List<({String id, String? directory, int touched, List<String> turns})>
    conversations,
  ) {
    final path = '${temp.path}/cursor/User/globalStorage/state.vscdb';
    Directory('${temp.path}/cursor/User/globalStorage').createSync(
      recursive: true,
    );
    final db = sqlite3.open(path);
    db.execute('create table cursorDiskKV (key text primary key, value text)');
    for (final c in conversations) {
      db.execute('insert into cursorDiskKV values (?, ?)', [
        'composerData:${c.id}',
        json.encode({
          'composerId': c.id,
          'lastUpdatedAt': c.touched,
          if (c.directory != null)
            'workspaceIdentifier': {
              'id': 'w',
              'uri': {'fsPath': c.directory, 'path': c.directory},
            },
        }),
      ]);
      for (var i = 0; i < c.turns.length; i++) {
        db.execute('insert into cursorDiskKV values (?, ?)', [
          'bubbleId:${c.id}:turn$i',
          c.turns[i],
        ]);
      }
    }
    db.close();
    return path;
  }

  String turn(String? at, {int input = 0, int output = 0}) => json.encode({
    'createdAt': ?at,
    'tokenCount': {'inputTokens': input, 'outputTokens': output},
    'text': 'a message long enough to be worth not decoding',
  });

  /// An Antigravity database: every conversation in one row, as protobuf in
  /// base64, each conversation itself protobuf in base64.
  String antigravity(List<Uint8List> conversations, {String? key}) {
    final path = '${temp.path}/Antigravity/User/globalStorage/state.vscdb';
    Directory('${temp.path}/Antigravity/User/globalStorage').createSync(
      recursive: true,
    );
    final outer = Wire();
    for (var i = 0; i < conversations.length; i++) {
      outer.message(1, (entry) {
        entry.text(1, 'conversation-$i');
        entry.message(2, (held) => held.text(1, base64.encode(conversations[i])));
      });
    }
    final db = sqlite3.open(path);
    db.execute('create table ItemTable (key text primary key, value text)');
    db.execute('insert into ItemTable values (?, ?)', [
      key ?? 'antigravityUnifiedStateSync.trajectorySummaries',
      base64.encode(outer.done()),
    ]);
    db.close();
    return path;
  }

  Uint8List conversation({
    required String folder,
    required DateTime created,
    required DateTime updated,
    List<DateTime> steps = const [],
  }) {
    final w = Wire();
    w.text(1, 'Some piece of work');
    w.time(3, updated);
    w.time(7, created);
    w.message(9, (uri) {
      uri.text(1, folder);
      uri.text(2, 'file:///');
    });
    w.time(10, updated);
    w.message(12, (block) {
      for (final step in steps) {
        block.message(1, (s) => s.message(5, (e) => e.time(1, step)));
      }
    });
    return w.done();
  }

  group('finding them', () {
    test('an editor database is recognised by the folder it sits in', () {
      expect(
        editorAt('/x/Library/Application Support/Cursor/User/globalStorage/state.vscdb'),
        EditorStore.cursor,
      );
      expect(
        editorAt('/x/Antigravity IDE/User/globalStorage/state.vscdb'),
        EditorStore.antigravity,
      );
      expect(editorAt('/x/Code/User/globalStorage/state.vscdb'), isNull);
      expect(editorAt('/x/Cursor/User/globalStorage/other.db'), isNull);
      expect(editorAt('/x/.claude/projects'), isNull);
    });

    test('both editors are looked for under a stated home', () {
      expect(discoverEditorStores(temp.path), isEmpty);

      final paths = [
        for (final editor in ['Cursor', 'Antigravity', 'Antigravity IDE'])
          '${temp.path}/Library/Application Support/$editor/User/globalStorage/'
              'state.vscdb',
      ];
      for (final path in paths) {
        File(path).createSync(recursive: true);
      }

      expect(discoverEditorStores(temp.path), paths);
      expect(EditorStore.cursor.key, 'cursor');
    });
  });

  group('Cursor', () {
    test('a conversation that names its folder becomes its turns', () {
      final path = cursor([
        (
          id: 'a',
          directory: '/repo/one',
          touched: 0,
          turns: [
            turn('2026-09-01T09:00:00.000Z', input: 30, output: 12),
            turn('2026-09-01T09:05:00.000Z'),
          ],
        ),
      ]);

      final events = readEditorStore(path, EditorStore.cursor);

      expect(events, hasLength(2));
      expect(events.first.directory, '/repo/one');
      expect(events.first.sessionId, 'a');
      expect(
        events.first.time,
        DateTime.utc(2026, 9, 1, 9).toLocal(),
      );
      expect(events.first.tokens.input, 30);
      expect(events.first.tokens.output, 12);
      expect(events.last.tokens.total, 0);
    });

    test('a conversation that names no folder is left out', () {
      final path = cursor([
        (
          id: 'a',
          directory: null,
          touched: 0,
          turns: [turn('2026-09-01T09:00:00.000Z')],
        ),
        (
          id: 'b',
          directory: '/repo/two',
          touched: 0,
          turns: [turn('2026-09-01T10:00:00.000Z')],
        ),
      ]);

      final events = readEditorStore(path, EditorStore.cursor);

      expect(events.map((e) => e.directory), ['/repo/two']);
    });

    test('a turn with no time of its own is left out', () {
      final path = cursor([
        (
          id: 'a',
          directory: '/repo',
          touched: 0,
          turns: [turn(null), turn('nonsense'), turn('2026-09-01T09:00:00.000Z')],
        ),
      ]);

      expect(readEditorStore(path, EditorStore.cursor), hasLength(1));
    });

    test('reading again takes what is newer and nothing else', () {
      final path = cursor([
        (
          id: 'a',
          directory: '/repo',
          touched: DateTime.utc(2026, 9, 1, 10).millisecondsSinceEpoch,
          turns: [
            turn('2026-09-01T09:00:00.000Z'),
            turn('2026-09-01T10:00:00.000Z'),
          ],
        ),
      ]);

      final after = DateTime.utc(2026, 9, 1, 9, 30).toLocal();
      final events = readEditorStore(path, EditorStore.cursor, after: after);

      expect(events, hasLength(1));
      expect(events.single.time, DateTime.utc(2026, 9, 1, 10).toLocal());
    });

    test('a conversation untouched since the last read is not opened', () {
      // Its turns are newer than the watermark, so only the conversation's own
      // time keeps them out: that is the check being made here.
      final path = cursor([
        (
          id: 'a',
          directory: '/repo',
          touched: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
          turns: [turn('2026-09-01T09:00:00.000Z')],
        ),
      ]);

      expect(
        readEditorStore(
          path,
          EditorStore.cursor,
          after: DateTime.utc(2026, 8, 15).toLocal(),
        ),
        isEmpty,
      );
    });
  });

  group('Antigravity', () {
    test('a conversation becomes the moments it happened in', () {
      final path = antigravity([
        conversation(
          folder: 'file:///repo/with%20a%20space',
          created: DateTime.utc(2026, 9, 1, 9),
          updated: DateTime.utc(2026, 9, 1, 11),
          steps: [
            DateTime.utc(2026, 9, 1, 9, 30),
            DateTime.utc(2026, 9, 1, 10),
          ],
        ),
      ]);

      final events = readEditorStore(path, EditorStore.antigravity);

      expect(events.map((e) => e.directory).toSet(), {'/repo/with a space'});
      expect(events.map((e) => e.sessionId).toSet(), {'conversation-0'});
      expect(events.map((e) => e.time).toSet(), {
        DateTime.utc(2026, 9, 1, 9).toLocal(),
        DateTime.utc(2026, 9, 1, 9, 30).toLocal(),
        DateTime.utc(2026, 9, 1, 10).toLocal(),
        DateTime.utc(2026, 9, 1, 11).toLocal(),
      });
    });

    test('a step outside the conversation is not one of its steps', () {
      // The times are found by shape rather than by field number, so a pair of
      // numbers elsewhere in the message can read as one. Anything outside the
      // conversation's own span is not kept.
      final path = antigravity([
        conversation(
          folder: 'file:///repo',
          created: DateTime.utc(2026, 9, 1, 9),
          updated: DateTime.utc(2026, 9, 1, 10),
          steps: [
            DateTime.utc(2026, 9, 1, 9, 30),
            DateTime.utc(2020, 1, 1),
            DateTime.utc(2030, 1, 1),
          ],
        ),
      ]);

      final events = readEditorStore(path, EditorStore.antigravity);

      expect(events.map((e) => e.time.year).toSet(), {2026});
      expect(events, hasLength(3));
    });

    test('a conversation held somewhere else is left out', () {
      final path = antigravity([
        conversation(
          folder: 'vscode-remote://ssh-remote%2Bbox/home/lex/work',
          created: DateTime.utc(2026, 9, 1, 9),
          updated: DateTime.utc(2026, 9, 1, 10),
        ),
        conversation(
          folder: 'file:///repo',
          created: DateTime.utc(2026, 9, 2, 9),
          updated: DateTime.utc(2026, 9, 2, 10),
        ),
      ]);

      final events = readEditorStore(path, EditorStore.antigravity);

      expect(events.map((e) => e.directory).toSet(), {'/repo'});
    });

    test('reading again takes what is newer and nothing else', () {
      final path = antigravity([
        conversation(
          folder: 'file:///repo',
          created: DateTime.utc(2026, 9, 1, 9),
          updated: DateTime.utc(2026, 9, 1, 11),
          steps: [DateTime.utc(2026, 9, 1, 10)],
        ),
      ]);

      final events = readEditorStore(
        path,
        EditorStore.antigravity,
        after: DateTime.utc(2026, 9, 1, 9, 30).toLocal(),
      );

      expect(events.map((e) => e.time).toSet(), {
        DateTime.utc(2026, 9, 1, 10).toLocal(),
        DateTime.utc(2026, 9, 1, 11).toLocal(),
      });
    });

    test('fields of a kind it does not read are stepped over', () {
      // A release that adds a double or a float in front of what is wanted
      // must not stop the reader getting to it.
      final w = Wire();
      w.fixed64(2, 1);
      w.fixed32(4, 2);
      w.time(3, DateTime.utc(2026, 9, 1, 10));
      w.time(7, DateTime.utc(2026, 9, 1, 9));
      w.message(9, (uri) => uri.text(1, 'file:///repo'));

      final events = readEditorStore(
        antigravity([w.done()]),
        EditorStore.antigravity,
      );

      expect(events.map((e) => e.time).toSet(), {
        DateTime.utc(2026, 9, 1, 9).toLocal(),
        DateTime.utc(2026, 9, 1, 10).toLocal(),
      });
    });

    test('a field of no kind at all stops that conversation, not the read', () {
      final broken = Wire();
      broken.nonsense(1);
      final path = antigravity([
        broken.done(),
        conversation(
          folder: 'file:///repo',
          created: DateTime.utc(2026, 9, 1, 9),
          updated: DateTime.utc(2026, 9, 1, 10),
        ),
      ]);

      expect(readEditorStore(path, EditorStore.antigravity), hasLength(2));
    });

    test('a step that is not a message is not a step', () {
      // The times are found by walking whatever is nested, so a field holding
      // bytes that are not a message at all has to be walked over.
      final w = Wire();
      w.time(3, DateTime.utc(2026, 9, 1, 10));
      w.time(7, DateTime.utc(2026, 9, 1, 9));
      w.message(9, (uri) => uri.text(1, 'file:///repo'));
      w.message(12, (block) {
        block.bytes(1, const [0x08, 0xff, 0xff, 0xff]);
        block.message(2, (s) => s.time(1, DateTime.utc(2026, 9, 1, 9, 30)));
      });

      final events = readEditorStore(
        antigravity([w.done()]),
        EditorStore.antigravity,
      );

      expect(events, hasLength(3));
    });

    test('a conversation named in bytes that are not text still reads', () {
      final outer = Wire();
      outer.message(1, (entry) {
        entry.bytes(1, const [0xff, 0xfe]);
        entry.message(
          2,
          (held) => held.text(
            1,
            base64.encode(
              conversation(
                folder: 'file:///repo',
                created: DateTime.utc(2026, 9, 1, 9),
                updated: DateTime.utc(2026, 9, 1, 10),
              ),
            ),
          ),
        );
      });
      final path = '${temp.path}/named.vscdb';
      final db = sqlite3.open(path);
      db.execute('create table ItemTable (key text primary key, value text)');
      db.execute('insert into ItemTable values (?, ?)', [
        'antigravityUnifiedStateSync.trajectorySummaries',
        base64.encode(outer.done()),
      ]);
      db.close();

      final events = readEditorStore(path, EditorStore.antigravity);

      expect(events, isNotEmpty);
      expect(events.first.sessionId, '1');
    });

    test('a row that will not decode at all is stepped over', () {
      final path = '${temp.path}/torn.vscdb';
      final db = sqlite3.open(path);
      db.execute('create table ItemTable (key text primary key, value text)');
      db.execute('insert into ItemTable values (?, ?)', [
        'antigravityUnifiedStateSync.trajectorySummaries',
        // A field header promising bytes that the row was cut off before.
        base64.encode(const [0x0a, 0x7f]),
      ]);
      db.close();

      expect(readEditorStore(path, EditorStore.antigravity), isEmpty);
    });

    test('a workspace on another machine is left out', () {
      final w = Wire();
      w.time(3, DateTime.utc(2026, 9, 1, 10));
      w.time(7, DateTime.utc(2026, 9, 1, 9));
      w.message(9, (uri) => uri.text(1, 'file://a-server/repo'));

      expect(
        readEditorStore(antigravity([w.done()]), EditorStore.antigravity),
        isEmpty,
      );
    });

    test('a conversation that will not decode is stepped over', () {
      final path = antigravity([
        Uint8List.fromList([0xff, 0xff, 0xff]),
        conversation(
          folder: 'file:///repo',
          created: DateTime.utc(2026, 9, 1, 9),
          updated: DateTime.utc(2026, 9, 1, 10),
        ),
      ]);

      expect(readEditorStore(path, EditorStore.antigravity), isNotEmpty);
    });

    test('a conversation with no time of its own is left out', () {
      final w = Wire();
      w.text(1, 'nothing but a title');
      w.message(9, (uri) => uri.text(1, 'file:///repo'));

      expect(
        readEditorStore(antigravity([w.done()]), EditorStore.antigravity),
        isEmpty,
      );
    });

    test('rows under another key are read too', () {
      final path = antigravity([
        conversation(
          folder: 'file:///repo',
          created: DateTime.utc(2026, 9, 1, 9),
          updated: DateTime.utc(2026, 9, 1, 10),
        ),
      ], key: 'unifiedStateSync.trajectorySummaries');

      expect(readEditorStore(path, EditorStore.antigravity), isNotEmpty);
    });
  });

  group('when it is not readable', () {
    test('a database that is not there is not an error', () {
      expect(
        readEditorStore('${temp.path}/nothing.vscdb', EditorStore.cursor),
        isEmpty,
      );
    });

    test('a database without the tables is not an error', () {
      final path = '${temp.path}/empty.vscdb';
      sqlite3.open(path)
        ..execute('create table other (a int)')
        ..close();

      expect(readEditorStore(path, EditorStore.cursor), isEmpty);
      expect(readEditorStore(path, EditorStore.antigravity), isEmpty);
    });

    test('a value that is not base64 is stepped over', () {
      final path = '${temp.path}/bad.vscdb';
      final db = sqlite3.open(path);
      db.execute('create table ItemTable (key text primary key, value text)');
      db.execute('insert into ItemTable values (?, ?)', [
        'antigravityUnifiedStateSync.trajectorySummaries',
        'not base64 at all',
      ]);
      db.execute('insert into ItemTable values (?, ?)', [
        'other.trajectorySummaries',
        42,
      ]);
      db.close();

      expect(readEditorStore(path, EditorStore.antigravity), isEmpty);
    });
  });
}
