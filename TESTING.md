# Guides verification

Run `./scripts/test.sh` for core tests and `./scripts/build.sh` for the native Apple Silicon Debug app. Xcode and Swift Package Manager need their normal compiler cache access and network access for the pinned package's initial resolution. The app is at `build/DerivedData/Build/Products/Debug/Guides.app`.

## Slice 2

- PASS: native Debug build; core presentation lifecycle test; code-signature validation and sandbox entitlement inspection.
- PASS: app launch from Finder and reopen into editing, without a Guides privacy prompt. The default hotkey was observed opening the overlay once, but targeted synthetic keyboard input is not a reliable global-hotkey test.
- PASS: Pin removes editing controls; a subsequent click selects an item in Finder underneath; arrow-key navigation changes Finder selection while the overlay remains pinned.
- UNVERIFIED: sustained global-hotkey reliability, visual screenshot of the transparent panel, full-screen/Spaces/Stage Manager behavior, other Mac models and OS versions. The native UI tool can inspect/click the panel's accessibility controls but reports no capturable window for screenshots. These remain final manual acceptance items, not claimed passes.
- Toolchain notes: Xcode's iOS simulator service mismatch is unrelated to this macOS target. App Intents metadata extraction is skipped because Guides has no App Intents dependency. No app-source compiler warnings remain.
- Review correction: Escape is routed at the editing panel before focused toolbar controls consume it, so it shares the canvas cancellation/hide path regardless of first responder. Native toolbar-focus verification remains a manual acceptance item.

## Slice 3

- PASS: 5 core tests (including 3 display-coordinate cases); native Debug build. Tests cover negative and elevated display origins, reverse/coincident guide distances, axis separation, clamping, nonfinite input, and clipboard precision/unit wording.
- IMPLEMENTED: ruler drags create guides, dragging moves them, adjacent distances render and can be selected/copied; Escape restores a cancelled gesture.
- UNVERIFIED: visual ruler placement and pointer accuracy on the native transparent canvas. These remain part of the final native acceptance pass; automated geometry checks are not a substitute for it.

## Slice 4

- PASS: 13 core tests and native Debug build. Added tests for nonadjacent same-axis selection, pair nudging at display edges, subpoint movement, one history entry per drag, selection changes excluded from history, redo invalidation, and undoable delete/clear.
- IMPLEMENTED: H/V at pointer, arrow/Shift/Option nudging, Delete, Command-Z/Shift-Command-Z, toolbar undo/redo, and clear. A partial gesture is cancelled before changing mode or history. Hidden sessions retain their completed document.
- Review correction: a tested core key router rejects Command/Control fallthrough (including Command-H/V), restricts guide/delete modifiers, and defines arrow-step precedence.
- UNVERIFIED: native keyboard behavior across all focus contexts and manual pointer/label accuracy; retained for the final acceptance pass.

Do not equate a successful build or a visible accessibility tree with a completed visual acceptance test.
