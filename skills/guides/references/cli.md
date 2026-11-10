# Direct CLI

The bundled `scripts/guides` launcher sends commands to the running, CLI-enabled Guides app. Commands need macOS 14+ and Guides 0.2.0 or later; single-instance startup and native `launch` require 0.2.1 or later. The release ZIP includes the app, a standalone launcher, this skill and INSTALL.txt without requiring a source checkout. No computer-use tool is needed for CLI commands. Without desktop tools, use supplied coordinates or guide the user through visual alignment; never invent a screen measurement.

Find the launcher relative to this skill's directory, regardless of the shell's working directory. Invoke its absolute path, or use `guides` if installed on PATH. It resolves `GUIDES_APP` first, then a sibling app in the release package, an app at the package root beside `skills`, a Debug build in this source checkout, `/Applications/Guides.app`, `~/Applications/Guides.app`, and a Release build in this checkout. `GUIDES_APP` is a path to the `.app` bundle, not its executable. The native executable also accepts `--cli COMMAND ...`.

```sh
guides launch
guides status
guides displays
guides show guides 1
guides gap vertical 300 364
guides calibrate 200
guides unit design-px
guides read css
guides pin
```

Replace `1` with an actual ID from `displays`. `status.state.appPath` identifies the app that answered; launcher selection does not retarget a running instance. `launch` reuses an already-running Guides app, even at another path, and returns `ok`, `pid`, `appPath` and `alreadyRunning`. It preserves that session's geometry, calibration, tool and pinned/hidden state; when absent it launches the selected app and waits a bounded time for startup. Other commands do not start a GUI. The wrapper rejects `launch` against an older selected executable lacking the single-instance capability marker; existing measurement commands can still connect to an older running server. If changing builds is necessary, explain that quitting loses unsaved session geometry. Never force-kill it or force-start another copy to obtain a desired version.

After a cold launch, the app may need a moment to register the command channel. Retry read-only `status` with a short bounded wait before sending a mutation. Codex's execution sandbox can block local Mach port lookup even when the app is running. If the connection is still missing and the current build is known to be running, use the execution tool's normal approved outside-sandbox path for the CLI and verify with `status`. Do not change Guides' privacy permissions or disable sandbox protections globally. If that execution path is unavailable, use available computer use or explain the connection limit.

## Commands

| Command | Behavior |
| --- | --- |
| `--help` | Local usage; no app connection |
| `launch` | Open Guides or reuse the running app; return PID/path and whether it was already running |
| `status` / `displays` | State or attached display IDs, dimensions and backing factors; no geometry changes |
| `show [guides\|area\|annotate] [DISPLAY_ID]` | Enter editing; with no ID choose the pointer's display, as the UI does |
| `guide horizontal\|vertical POSITION` | Add/select one guide at a screen-point coordinate |
| `gap horizontal\|vertical FIRST SECOND` | Add/select two parallel guides; vertical guides measure a width, horizontal guides a height |
| `area X Y WIDTH HEIGHT [RADIUS]` | Replace/select the measured Area with positive dimensions inside the display; radius defaults to 0 |
| `select GUIDE_ID [GUIDE_ID]` | Select one guide or a parallel pair using returned UUIDs |
| `select area [width\|height\|both\|radius]` | Select the existing Area and readout dimension; defaults to Both |
| `unit screen-pt\|backing-px\|design-px\|rem` | Change the readout unit; design/rem require calibration |
| `calibrate PERCENT [ROOT_PX]` | Explicit scale; optional root is saved in Settings and applies globally |
| `read [plain\|css\|tailwind\|variable]` | Return selected text in `value`; no clipboard access. Code formats need calibration; variable needs a unique spacing-token match |
| `delete` / `clear` | Delete selected measurements / clear all guides and measured Area on the active display; do not remove annotations/grid/reference |
| `undo` / `redo` | Measurement history only; calibration, units and selection alone do not create history |
| `pin` / `hide` | Click-through overlay / hide while retaining the session |

Measurement editing requires Editing with Guides or Area active and reference alignment off. Resume using `show guides ID` or `show area ID`, using the active ID from status so the pointer does not accidentally switch displays. `read` can read retained measurements while pinned/hidden, provided Annotate/reference alignment is not active. Use computer use for moving existing geometry, annotation editing, known-size calibration, grid/reference tools, libraries, image inspection and window resizing.

Measurement editing also rejects while a pointer gesture is active (`state.gestureActive`). Let the user or computer-use operation finish or cancel the drag, then recheck state before retrying; a rejected CLI edit must not cancel that gesture.

All app replies are one JSON object. Success is `{"ok":true,"state":{...}}`, with `value` for reads or `displays` for display listing. State includes `displayID`, `mode`, `tool`, coordinates, guide UUIDs, Area/radius, selected IDs/dimension, unit, backing factor, calibration, root and undo flags. Errors are `{"ok":false,"error":"..."}`. Exit codes: 0 success/help, 1 app/transport failure, 2 invalid command arguments. Launcher errors go to stderr with exit 1. A successful response confirms app state; it does not prove alignment to an external visual target.

The command channel is local Mach messaging scoped to the login user. Other processes in the same login session can issue these commands. It has no network listener or remote endpoint and cannot access arbitrary files or invoke arbitrary app methods. A timeout can happen after execution; do not automatically replay a mutation. Query state and reconcile it with the intended geometry first.
