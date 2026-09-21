MCP server
==========

The engine is exposed over JSON-RPC 2.0 (protocol revision 2025-06-18) on two
transports: stdio, for a client that spawns the binary, and a localhost TCP
socket, which the desktop app opens while it is running.

Running it
----------

```
dart run aitracking_mcp:aitracking_mcp              # stdio
dart run aitracking_mcp:aitracking_mcp --tcp --port 8788
```

In stdio mode nothing but JSON-RPC is written to stdout; diagnostics go to
stderr.

Client configuration
--------------------

`docs/mcp-client-config.json` is ready to paste into an MCP client:

```json
{
  "mcpServers": {
    "aitracking": {
      "command": "dart",
      "args": ["run", "aitracking_mcp:aitracking_mcp"],
      "cwd": "/path/to/AITracking"
    }
  }
}
```

Compiling the binary first (`dart compile exe packages/mcp/bin/aitracking_mcp.dart`)
makes it start faster; point `command` at the result and drop `args`.

Tools
-----

| Tool | What it does |
| --- | --- |
| `list_hours` | The blocks in a window, each with its key, project and hours. |
| `summarize_hours` | Totals by project and by day. |
| `list_unmapped` | Directories holding hours no rule covers. |
| `sync_workinghours` | File the blocks as WorkingHours units. Previews unless `dry_run` is false. |
| `sync_diarium` | Write the daily journal entry. Previews unless `dry_run` is false. |
| `export_spreadsheet` | Write the CSV and the workbook. |
| `get_config` | The configuration and where it lives. |
| `set_project_rule` | Map a directory onto a project. |
| `edit_blocks` | Reassign, rename or strike out blocks by key, in one batch. |

Every window takes `days`, or `since` and `until` as ISO dates. Both sync tools
take `quit_app`: without it, a running WorkingHours or Diarium is a refusal,
because the app would write its own copy of the database back over the new rows.

Results are returned both as text and as `structuredContent`, and a tool that
fails comes back as a tool error rather than a protocol error, so the model can
read what went wrong and try something else.
