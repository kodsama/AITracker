import 'dart:convert';

import 'tools.dart';

/// A minimal, dependency-free implementation of the Model Context Protocol
/// (JSON-RPC 2.0) sufficient for tool serving: `initialize`, `tools/list`,
/// `tools/call`, `ping`, and the `initialized` notification.
///
/// The server is transport-agnostic: [handle] takes one decoded JSON-RPC
/// message and returns the response map (or null for notifications). A stdio or
/// TCP transport wraps it.

/// Version advertised when no host app supplies its own.
const kMcpDefaultVersion = '0.1.0';

/// Serves a tool catalog to an MCP client.
class McpServer {
  /// Creates a server exposing [tools].
  McpServer({
    required this.tools,
    this.name = 'aitracker',
    this.title = 'AI Tracker',
    this.version = kMcpDefaultVersion,
    this.protocolVersion = '2025-06-18',
    this.requiredToken,
  });

  /// A server for one connection, with its own authentication state.
  ///
  /// Every socket has to present the key itself, so the transport hands each
  /// client a session rather than sharing one server's state.
  McpServer session() => McpServer(
    tools: tools,
    name: name,
    title: title,
    version: version,
    protocolVersion: protocolVersion,
    requiredToken: requiredToken,
  );

  /// The tool catalog.
  final List<McpTool> tools;

  /// Advertised server name.
  final String name;

  /// Human-readable app name. Several local apps can serve MCP on neighbouring
  /// ports, so a client needs to see which one it actually reached.
  final String title;

  /// Advertised server version.
  final String version;

  /// Protocol revision used when the client doesn't request one.
  final String protocolVersion;

  /// Key a client must present on `initialize`. Null lets everything through,
  /// which is what stdio does.
  final String? requiredToken;

  bool _authenticated = false;

  /// Whether this session may call tools.
  bool get authenticated => requiredToken == null || _authenticated;

  /// Handles one decoded JSON-RPC request. Returns the response map, or null
  /// when the message is a notification (no `id`) needing no reply.
  Future<Map<String, Object?>?> handle(Map<String, Object?> request) async {
    final id = request['id'];
    final method = request['method'];
    final params =
        (request['params'] as Map?)?.cast<String, Object?>() ?? const {};

    // Notifications carry no id and never get a response.
    if (id == null) return null;

    if (method == 'initialize' && requiredToken != null) {
      final presented = extractToken(params);
      _authenticated = presented != null && presented == requiredToken;
      if (!_authenticated) {
        return _err(
          id,
          -32001,
          'Unauthorized: present the AI Tracker key as '
          'initialize.params.api_key. Settings shows it under MCP.',
        );
      }
    }
    if (!authenticated) {
      return _err(id, -32001, 'Unauthorized: call initialize with the key');
    }

    switch (method) {
      case 'initialize':
        return _ok(id, {
          'protocolVersion':
              (params['protocolVersion'] as String?) ?? protocolVersion,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': name, 'title': title, 'version': version},
        });

      case 'ping':
        return _ok(id, const {});

      case 'tools/list':
        return _ok(id, {
          'tools': [
            for (final t in tools)
              {
                'name': t.name,
                'description': t.description,
                'inputSchema': t.inputSchema,
              },
          ],
        });

      case 'tools/call':
        return _call(id, params);

      default:
        return _err(id, -32601, 'Method not found: $method');
    }
  }

  Future<Map<String, Object?>> _call(
    Object id,
    Map<String, Object?> params,
  ) async {
    final toolName = params['name'] as String?;
    final args =
        (params['arguments'] as Map?)?.cast<String, Object?>() ?? const {};
    final tool = tools.where((t) => t.name == toolName).firstOrNull;
    if (tool == null) {
      return _err(id, -32602, 'Unknown tool: $toolName');
    }
    try {
      final result = await tool.run(args);
      final isError = result['ok'] == false;
      return _ok(id, {
        'content': [
          {
            'type': 'text',
            'text': const JsonEncoder.withIndent('  ').convert(result),
          },
        ],
        'structuredContent': result,
        'isError': isError,
      });
    } on Object catch (e) {
      // A thrown tool is reported as a tool error (not a protocol error) so the
      // model sees it and can recover.
      return _ok(id, {
        'content': [
          {'type': 'text', 'text': 'tool "$toolName" failed: $e'},
        ],
        'isError': true,
      });
    }
  }

  Map<String, Object?> _ok(Object id, Map<String, Object?> result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  Map<String, Object?> _err(Object id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

/// Pulls the key out of `initialize` params. Clients differ on where they put
/// a bearer, so the three shapes in the wild are all read.
String? extractToken(Map<String, Object?> params) {
  final direct = params['apiKey'] ?? params['api_key'];
  if (direct is String && direct.isNotEmpty) return direct;
  final auth = params['authentication'];
  if (auth is Map) {
    final token = auth['token'] ?? auth['apiKey'] ?? auth['api_key'];
    if (token is String && token.isNotEmpty) return token;
  }
  return null;
}
