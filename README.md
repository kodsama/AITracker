<img src="assets/logo/aitracker-256.png" width="96" alt="">

AITracker
==========

Time spent with an AI coding assistant is time worked, and none of it reaches
the timesheet. AITracker reads the transcripts the assistant already writes,
turns them into blocks of attention, and files them into
[WorkingHours](https://workinghoursapp.com), [Diarium](https://diariumapp.com),
a CSV, or an Excel workbook.

Nothing is measured twice: parallel sessions in two repositories share one wall
clock, and time a timesheet already holds is never written over.

What it does
------------

Claude Code keeps a JSONL transcript per session under `~/.claude/projects`,
every line stamped with a time and the directory the session was working in.
The Gemini and Antigravity CLIs keep a history file of the same shape. Cursor
and Antigravity write no transcript at all and keep their history in the
`state.vscdb` that every VS Code fork has, so those are read out of SQLite
instead. All of it goes once into a local archive that is never pruned, and
everything else is computed from the archive: the hours, the tokens, the
graphs, the unmapped time. An assistant that drops its own logs after a month
takes nothing with it.

Two things about the editors are worth knowing. Cursor writes the folder on a
conversation only from its 2026.4 release; anything older names it nowhere in
the database, so those conversations are left out rather than guessed at, and
the log says how many. Cursor also stopped recording token counts locally
around the same time and now writes zeroes, so its hours arrive without tokens.

Everything is pulled once. A transcript is read from the byte it was last read
to, an editor's database from the newest event already held, and nothing that
has been archived is ever fetched again. The blocks made from those events are
worked out per day and kept as well, and a scan fills in every day the archive
covers rather than only the window on screen, so asking for a year later reads
what is already stored instead of working out three hundred days on the spot.

The archive holds the events rather than the blocks, so the idle gap stays a
setting: change it and the whole history is read again through the new one,
rather than leaving a seam at the day you changed it. Days are worked out once
per set of thresholds and kept, so a year on screen reads a few thousand rows
instead of a million events.

The graphs draw hours, tokens, or one chart of each: two quantities that far
apart never share an axis. Anywhere you can click through to, back and forward
will take you out of again, on the buttons or on ⌘[ and ⌘]. The window you were
last in is the window it opens on.

Which model answered is recorded per turn and shown beside the hours and the
tokens, counted in turns rather than minutes: a stretch of attention can have
had two models in it, and there is no honest way to split the minutes between
them.

From those events:

- Consecutive events closer together than the idle gap are one block of work.
- A gap credits nothing, so lunch is not billed.
- When two repositories are open at once, a minute goes to one of them, never
  to both.
- Blocks are trimmed against what the target store already holds, split at
  midnight, and dropped when they are too short to be real work.

A rule maps a directory onto a project, and the project name carries the
customer: `Byte Buddies - idbuddy`. What no rule covers is listed rather than
silently dropped.

The app
-------

`Hours` shows the blocks, the totals per project and what is unmapped. Select
any number of rows to reassign, rename or strike them out in one go; the edits
are kept beside the measurement and survive re-reading the transcripts.

`Graphs` draws the same hours: stacked bars over the period, a day at a time, a
week at a time or a month at a time depending on how wide the window is, and a
calendar underneath where each day takes the colour of the project that owned
most of it and darkens with the hours. Pick the window from Today, Yesterday,
this or last week, this or last month, the last two, this or last quarter, this
semester, this year, or two dates of your own. The palette is fixed and
validated for colour-vision separation, and every project is named in the legend
and the hover card, so nothing is carried by colour alone.

`Projects` holds the rules, in the order they are tried, and offers a one-click
rule for every directory that has hours and no project. Under them sits the
mapping: what each project is called in WorkingHours, the customer tag that
ledger files it under, the tags to put on each work unit, its Diarium tag, and
its colour. Every one of those fields suggests what the apps already hold and
lets you type something new. Renaming asks which of the three should follow, so
a project can deliberately read one way here and another in the ledger, and the
mapping remembers they are the same work.

`Settings` has the idle gap, the shortest block worth counting, the sinks, and
the MCP endpoint.

Sync runs both ways and previews first. The dialog shows what WorkingHours has
had done to the units this tool wrote there, moved to another project, renamed
or trimmed, and what each target would be given; nothing is written or taken
until you press the button. A correction taken back is kept as a hand edit, so
the next scan does not undo it.

Sinks
-----

**WorkingHours** has no API, so its SQLite store is written directly, which is
[what the forum ends up recommending](https://forum.workinghoursapp.com/d/1832).
That store is the live one, and it is whole-file synced to the cloud, so a write
only happens while the app is closed, never while a timer is running, and always
after the database has been copied. Missing projects are created with the
currency the rest of the ledger uses, the customer tag the mapping names, and
the colour it was given. Each unit is marked `aitracker` in its details and
carries the mapped tags.

Project colours can be pushed the other way too, so a project is drawn the same
in both apps.

**Diarium** gets one entry a day, stamped at a fixed time so a later run
rewrites its own entry instead of stacking duplicates, tags and all. An entry
you wrote at that minute is stepped over, never edited. Diarium also reads WorkingHours by
itself, so the WorkingHours sink alone already shows up in the journal.

**CSV and Excel** are rewritten from the transcripts on every run: one row per
block with the date, the clock times, the hours as a number, the company, the
project and the repository. Unmapped blocks are included with an empty project
column, because a spreadsheet is where you go to find what the rules missed.

Command line
------------

```
dart run aitracker_cli:aitracker preview --days 30
dart run aitracker_cli:aitracker sync --days 30            # preview
dart run aitracker_cli:aitracker sync --days 30 --apply --quit-apps
dart run aitracker_cli:aitracker config
```

`launchd/ai.aitracker.nightly.plist` runs the sync every night; it closes the
apps for the write and starts them again afterwards. The transcripts are pruned
after about a month, so a scheduled run is what keeps the history.

MCP
---

The same engine is served over the Model Context Protocol, so an assistant can
read the hours it helped spend and file them. `docs/mcp.md` has the tools and
the client configuration. The desktop app can also serve it on a local socket
while it is open.

Configuration
-------------

`~/Library/Application Support/AITracker/config.json`, or `$AITRACKER_CONFIG`.
Hand edits live beside it in `overrides.json`, the MCP key in `mcp-token`, and
the archive in `history.db`. Everything the app writes is in that one folder,
which is also the whole of what to back up.

Building
--------

```
dart pub get
dart test packages/engine packages/mcp packages/cli
cd app && flutter test
bash tool/coverage.sh                   # all four packages against the gate, then the API check
bash tool/build-calendar-helper.sh      # the EventKit helper the calendar needs
bash tool/run-app.sh                    # builds and launches, refusing a stale bundle
```

The helper lands in `~/.local/bin`, or in the folder you pass the script. It is
looked for there, in `/usr/local/bin` and beside the app; keep it anywhere else
and the calendar section in Settings takes the path.

`tool/run-app.sh` rather than `flutter build macos` on its own: renaming the
product once left Xcode exiting 0 while copying nothing into the bundle, so the
app that opened was hours old. The script checks the code inside the bundle is
newer than the build and cleans once if it is not.

macOS only for now: both target apps are macOS, and the store paths are theirs.
The engine itself has nothing platform-specific in it beyond those paths.

The app runs unsandboxed. It reads another app's container and writes another
app's database, which is exactly what the sandbox exists to prevent, so this is
a build for the machine it runs on rather than for the App Store.

Licence
-------

GPL-3.0. See `LICENSE`.
