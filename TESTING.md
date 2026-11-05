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

## Slice 7 and final acceptance

Environment: Apple Silicon, macOS 27.0.1 (26A434), Xcode 26.6 (17F113), Swift 6.3.3. The app targets macOS 14; this is not an older-OS compatibility certification.

- PASS: 34 core tests. New cases cover equal-size display independence, retained geometry/history/calibration, shared root updates, changed backing scale/resolution, disconnect/reconnect, unchanged configuration refresh, and keyboard selection/pair traversal.
- PASS: native Debug build with strict Swift concurrency. App source compiles without warnings. Code-signature and sandbox inspection are included in the final checks.
- PASS: fresh native launch starts with empty measurements, unconfirmed calibration and Screen pt. Ruler drags to y=300/500 expose a 200pt gap; Up moves the second guide to 499, Command-Z restores 500, and bracket/Shift-bracket selects the pair.
- PASS: Copy puts `200 screen pt` on the clipboard, verified by pasting into Finder's temporary Go to Folder field and cancelling. Finder accepts keyboard input while Guides is pinned.
- PASS: accessible measurement elements are enabled and their press/pair actions select the measurement. An initial disabled-state issue was found and corrected during native checks. The canvas also exposes the selected value through the toolbar.
- PASS: reverse area drag creates 320 × 160pt; dragging the lower-right handle produces 340 × 180pt; undo restores the original. Known-width calibration of 320pt to 160px gives 200% scale and 160 × 80px output. Guides remain alongside the rectangle.
- PASS, limited scenario: Finder entered full screen; reopening Guides produced its editing controls and retained measurements. Pin worked and Finder was restored to its original windowed state. This does not establish all Spaces/full-screen configurations.
- PASS: screenshots confirm ruler/guide positions, contrasting guide/area outlines, labels, and area handles. The scale control was given a fixed width after a screenshot exposed compression. Per-app screenshots flatten transparent regions, so they do not establish readability against every underlying desktop surface.
- PASS, user-reported correction: the vertical ruler used the usable display height and stopped above the Dock region. Its drawing and hit-testing rectangle now extends to the overlay's bottom edge; controls and hints still use safe desktop insets. A rebuilt native screenshot confirms the full height, and dragging from y=2130 in the formerly missing region creates a vertical guide at x=200.

| Acceptance area | Status / remaining manual exercise |
| --- | --- |
| Coordinate conversion and all units | Automated pass, including negative display origins, fractional steps, scale/rem examples and invalid input |
| Guide/area editing and history | Automated pass; native core path passed; cancel a drag with Escape and dense overlapping handles/labels still need manual exercise |
| Activation and permissions | Finder activation passed without a Guides privacy prompt; repeated physical global shortcut and shortcut recorder conflicts remain unverified |
| Hidden/Pinned/focus | Native pinned click and keyboard pass; physical Escape from every control, hide/resume and app-switch focus stress remain manual |
| Clipboard | Native screen-point round trip passed; all unit/dimension strings tested in core |
| Settings/relaunch | Valid/invalid preference persistence tested in isolated defaults; native fresh geometry/calibration observed; settings-window editing/shortcut persistence remain manual |
| Multiple displays | Core switching/invalidation passed; actual mixed-DPI displays, unplug/replug, resolution changes, display rearrangement and menu-bar relocation unverified |
| Full screen / Spaces | One Finder full-screen activation path exercised; multiple Spaces, Stage Manager, multiple full-screen apps and pinned visibility through transitions unverified |
| Sleep/wake | Notification handlers implemented; actual sleep/wake scenario unverified |
| Accessibility/readability | Native AX select/pair actions passed; full VoiceOver navigation, light/dark/busy desktop backgrounds and narrow-display layout unverified |
| Lifecycle/performance | Event-driven implementation with no timers or capture loop; prolonged idle resource measurements unverified |
| Compatibility | Current Apple Silicon Mac only; macOS 14–26, other Macs, Intel and distribution signing unverified/out of personal MVP scope |

Manual follow-up: open the built app, use the controls in README, and exercise the remaining rows on the relevant hardware. No permission grants or screen capture features are needed by Guides. Do not equate a successful build or a visible accessibility tree with a completed visual acceptance test.

## Numbered rulers and appearance follow-up

- PASS: 34 core tests and native Debug build. Preference tests now cover the Solid default, saved Transparent and Solid values, change notifications, and invalid-value fallback without disturbing the saved rem base.
- PASS: native screenshot shows vertical labels from 100 through 2100 at the same 100-point cadence and font size as the top ruler. Rotated labels fit the 24-point strip and the ruler retains its full height.
- PASS: the toolbar ruler menu changes Solid → Transparent → Solid immediately; its accessibility value follows the selected appearance. A screenshot confirms transparent backgrounds on both axes with outlined numbers and ticks. Dragging from the transparent vertical ruler at y=2130 still creates a guide at x=200.
- Settings also exposes the same saved preference. Full Settings-window/VoiceOver use and readability over every desktop background remain manual checks; native screenshots flatten transparent regions. Solid was restored after testing.

## Image inspector expansion

- PASS: 42 core tests and native Debug build with no app-source warnings. New tests cover source pixels independent of DPI, all eight EXIF orientations and preview dimensions, reduced aspect ratio, alpha metadata, original byte count, copy formatting, bounded previews, clipboard representation labels, multi-image TIFFs, malformed input, file reading, missing/directory/remote inputs, oversized file rejection, and cancellation.
- PASS: controllable-loader regression proves that rejecting an import invalidates an older pending result while retaining the last completed image, and that Clear/close prevents a late result from repopulating the model. This addresses the independent review's P2 finding.
- PASS: native Open Image reads a sandbox-selected 1200 × 800 PNG at 144 DPI as 1200 × 800 pixels, 3:2, 19,783 bytes and alpha present. Corrupt PNG replacement displays an error and preserves the prior image. No capture/privacy grant was requested.
- PASS: image-only paste from Preview shows Clipboard image, PNG and 19,795 clipboard bytes. Finder file copy/paste instead shows the original filename and 19,783 file bytes. Native Copy Dimensions round trip into Finder gives `1200 × 800 px`.
- PASS: cancelling Open Image retains the image; Clear removes it; Command-W followed by reopening the inspector starts empty. The bounded preview and metadata controls now fit the 560 × 660 content window. Native inspection initially exposed window growth caused by hosting intrinsic size; fixed sizing and a GeometryReader preview corrected it, including repeated imports.
- PASS: code signature validation and read-only user-selected file sandbox entitlement inspection. No network or capture entitlement added.
- Native automation initially could not reach the menu bar via SystemUIServer. The toolbar ruler menu now also offers Inspect Image, and native checks used that entry. The menu bar entry remains implemented. Cross-application file drag/drop, VoiceOver navigation, older macOS versions, and slow-decoder stress on large real files remain manual checks; they are not claimed as native passes.
