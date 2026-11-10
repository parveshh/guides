---
name: guides
description: Operate the native macOS Guides app through its direct CLI or computer use to place guides, measure visible gaps and areas, calibrate units, read development values, annotate and use its existing local tools. Use for the Guides app, not generic guides or source-level CSS inspection.
---

# Guides

Use Guides to measure or mark the visible interface on one display. Prefer its CLI for explicit coordinates, state queries and repeatable measurement edits. Use computer use to find visible boundaries, fit geometry by eye, operate annotations or use tools not exposed by the CLI. The skill is usable from Codex CLI as `$guides`; desktop control depends on the tools available in that session.

Read [references/cli.md](references/cli.md) for direct commands, launch/setup and output. For on-screen interaction, also read [references/computer-use.md](references/computer-use.md).

## Measurement contract

- Geometry is display-local macOS screen points from the top-left. A width is not a screenshot's pixel width. Backing pixels, calibrated design/CSS pixels and rem are distinct units.
- The CLI places exact supplied coordinates. Pointer placement snaps to backing-pixel boundaries; Control-drag places freely. Neither detects edges or inspects an underlying app.
- Confirm a user-supplied view scale or known-size calibration before Design px, rem, CSS or Tailwind output. Do not infer scale from a Retina display, screenshot, browser window size or apparent zoom. A confirmed 100% means one screen point per design pixel.
- `designPx = screenPoints / (scalePercent / 100)` and `rem = designPx / rootPixels`. Recheck calibration after app, zoom, display or layout-load changes. For example, 64 screen pt at 200% is 32px or 2rem with a 16px root.
- Describe results as visual measurements or geometry placed at supplied coordinates. Never claim Guides discovered an exact CSS property, DOM bound or Figma layer value. A copied `gap` declaration still needs the user's layout context.

## Working sequence

1. Establish the target display, object/boundaries and requested unit. Use current UI evidence for visual targets; supplied coordinates need no screen inspection. If necessary context is missing, ask only for that context and continue independent setup.
2. Query `status` and `displays` before changes. If the execution sandbox blocks local Mach messaging, follow the CLI reference's normal execution-approval route; no Guides privacy grant is needed. Reuse the running session; inspect its `appPath`, active display, mode and existing geometry. Do not quit/relaunch or clear the user's measurements just to connect a different build.
3. Activate the chosen display/tool explicitly, then place/edit/select the requested geometry. Preserve unrelated guides and settings. Area replaces the single existing Area; undo can recover it. `gap` adds and selects two guides in one undoable action.
4. Set only the calibration/root that the user supplied or confirmed. Read the selected value in the requested format. CLI `read` returns JSON without touching the clipboard; use the UI Copy action when the user wants clipboard output.
5. Verify the returned geometry/value and visible alignment where relevant. After an uncertain transport failure, query status before retrying a mutation so an added guide or gap is not duplicated.
6. Use **Pin & work** when the marks should remain while the user works underneath, or **Hide** when finished. Editing intercepts clicks. Report the value, unit, calibration and any placement uncertainty concisely.

## Local tools and permissions

Measurements, grids, annotations and supplied local-image tools need no app privacy grants. Resize Window optionally uses Accessibility for an explicitly chosen window; its sizes are whole-window screen points, not CSS viewport dimensions. The corner magnifier optionally uses Screen Recording only while explicitly started; stop it when done, and never save, copy or transmit its preview.

Request Guides permissions only from the respective tool's dedicated button, only when the user wants that optional tool and grants are needed. Follow the current computer-use tool's approval/handoff rules for OS prompts. Keep normal measurement usable after denial. Never add an AppleScript/System Events workaround, capture command or network service to complete a skill request.

Hide/pin retain per-display sessions. Quitting clears measurements, calibration and reference images; saved layouts load explicitly and reset calibration. Settings, profiles and layout libraries stay local. Use existing UI tools as shipped; the roadmap is not a list of available commands.
