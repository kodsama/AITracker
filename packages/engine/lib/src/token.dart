import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'config.dart';

/// The key an MCP client presents before it may call anything over the network.
///
/// Stdio needs none: a client that can spawn the binary already has everything
/// the binary has. The TCP endpoint is a socket anything on the machine can
/// reach, so it is gated on this.
class McpToken {
  const McpToken._();

  /// Where the key is kept, beside the configuration.
  static String path() =>
      p.join(p.dirname(AiTrackerConfig.defaultPath()), 'mcp-token');

  /// The key, or null when none has been issued.
  static String? read([String? at]) {
    final file = File(at ?? path());
    if (!file.existsSync()) return null;
    final token = file.readAsStringSync().trim();
    return token.isEmpty ? null : token;
  }

  /// The key, issuing one on first use.
  static String ensure([String? at]) => read(at) ?? issue(at);

  /// Issues a new key, replacing any existing one, and returns it.
  ///
  /// Written user-only: it is a bearer key, and anything that can read the file
  /// can read the hours and write to the timesheet.
  static String issue([String? at]) {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    final file = File(at ?? path())..parent.createSync(recursive: true);
    file.writeAsStringSync('$token\n');
    _lockDown(file);
    return token;
  }

  /// Forgets the key, which shuts the network endpoint to every client.
  static void revoke([String? at]) {
    final file = File(at ?? path());
    if (file.existsSync()) file.deleteSync();
  }

  static void _lockDown(File file) {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    Process.runSync('/bin/chmod', ['600', file.path]);
  }
}
