MCP server
==========

The engine is exposed over JSON-RPC 2.0 (protocol revision 2025-06-18) on two
transports: stdio, for a client that spawns the binary, and a localhost TCP
socket, which the desktop app opens while it is running.

Running it
----------

```
dart run aitracker_mcp:aitracker_mcp              # stdio
dart run aitracker_mcp:aitracker_mcp --tcp --port 8788
```

In stdio mode nothing but JSON-RPC is written to stdout; diagnostics go to
stderr.

Client configuration
--------------------

`docs/mcp-client-config.json` is ready to paste into an MCP client:

```json
{
  "mcpServers": {
    "aitracker": {
      "command": "dart",
      "args": ["run", "aitracker_mcp:aitracker_mcp"],
      "cwd": "/path/to/AITracker"
    }
  }
}
```

Compiling the binary first (`dart compile exe packages/mcp/bin/aitracker_mcp.dart`)
makes it start faster; point `command` at the result and drop `args`.

Tools
-----

| Tool | What it does |
| --- | --- |
| `list_hours` | The blocks in a window, each with its key, project and hours. |
| `summarize_hours` | Totals by project and by day. |
| `list_unmapped` | Directories holding hours no rule covers. |
| `sync_all` | File the blocks everywhere enabled in one call. |
| `sync_workinghours` | File the blocks as WorkingHours units. Previews unless `dry_run` is false. |
| `sync_diarium` | Write the daily journal entry. Previews unless `dry_run` is false. |
| `export_spreadsheet` | Write the CSV and the workbook. |
| `list_catalog` | The projects, tags, customers and journal tags the two apps already hold. |
| `set_project_link` | Map a project onto those: ledger name, customer, unit tags, journal tag, colour. |
| `rename_project` | Rename, and carry the name into WorkingHours or Diarium if asked. |
| `sync_project_colors` | Push the mapped colours into WorkingHours. |
| `get_config` | The configuration and where it lives. |
| `set_project_rule` | Map a directory onto a project. |
| `edit_blocks` | Reassign, rename or strike out blocks by key, in one batch. |

Every window takes `days`, or `since` and `until` as ISO dates. The sync tools
take `quit_app`: without it, a running WorkingHours or Diarium is a refusal,
because the app would write its own copy of the database back over the new rows.

Results are returned both as text and as `structuredContent`, and a tool that
fails comes back as a tool error rather than a protocol error, so the model can
read what went wrong and try something else.
