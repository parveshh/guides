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

## Slice 5

- PASS: 21 core tests (including all 8 resize handles) and native Debug build. Area tests cover reverse drags, display clamping, preserved size when moving, crossing the opposite corner, edge resizing, invalid input, nudging, and undoable replacement/deletion alongside guides.
- IMPLEMENTED: area selection/move/resize, Width/Height/Both copying, and Escape restoring the pre-gesture document. Zero-size completed gestures restore the previous area rather than destroying it. The shared core document now represents both guides and an area.
- Review correction: resize hit testing chooses the nearest handle, with exact-handle regression cases on 1pt, 5pt, and 10pt rectangles; handles only display in Area mode.
- UNVERIFIED: native rectangle pointer accuracy and handle visibility; included in final manual acceptance.

## Slice 6

- PASS: 29 core tests and native Debug build. Conversion coverage includes 2x backing pixels, 50%/200% scale, known-distance calibration, explicit confirmation gating, invalid/nonfinite/overflow inputs, consistent display/clipboard formatting, and local preference recovery/restoration.
- PASS: native scale popover rejects 0%, accepts 200%, and updates the visible scale context. A ruler drag pair at y=300 and y=500 shows 6.25rem with a 16px root; selecting its label exposes the same value and enables Copy. A 320 by 160 screen-point area shows 10 × 5 rem at that calibration.
- Visual verification improvement: naming the panel made screenshots available. Its screenshot confirmed the guide gap, ruler positions, and readable measurement label; the tool picker label was cramped, so its redundant visible title was removed.
- IMPLEMENTED: all four units, known-size/percentage calibration, Width/Height/Both output in the selected unit, shared root size in Settings/calibration, and local preference validation. Calibration stays in memory and does not silently assume CSS equivalence.
- UNVERIFIED: clipboard round trip in another native app, all calibration input focus paths, mixed-monitor backing scales, and the remaining system scenarios listed above.

Do not equate a successful build or a visible accessibility tree with a completed visual acceptance test.
