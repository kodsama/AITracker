/// MCP (Model Context Protocol) server for AITracker.
///
/// Exposes the engine over JSON-RPC 2.0 on either stdio (client-spawned) or a
/// localhost TCP socket (the desktop app's always-on endpoint), so an assistant
/// can read the hours it helped spend and file them.
library;

export 'src/mcp_server.dart';
export 'src/tools.dart';
export 'src/transport.dart';
