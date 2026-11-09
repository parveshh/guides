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

Manual follow-up: open the built app, use the controls in README, and exercise the remaining rows on the relevant hardware. No permission grants are needed by the measurement tools. The later window-resize expansion requires optional Accessibility access. Guides has no screen capture features. Do not equate a successful build or a visible accessibility tree with a completed visual acceptance test.

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

## Option 2 redesign and desktop interaction

- PASS: 46 core tests and native Debug build. Four new placement tests cover display edges, area/handle avoidance, toolbar clearance and a narrow display. A discovered top-edge collision was corrected.
- PASS: native visual comparison with docs/design/focus-rail.png shows a neutral charcoal toolbar, pink selection, readable full tool labels, and both numbered rulers. The first comparison exposed truncated Guides/Area labels; intrinsic sizing fixed them. A later check confirms Pin & work fits too.
- PASS: the selected-gap readout appeared beside the measurement in the earlier native comparison. Pin hides interactive controls; Finder accepted keyboard selection underneath. The final build's Pin & work button also removes the toolbar from the accessibility tree.
- LIMIT: concurrent desktop changes interrupted automated key/drag attempts. The physical shortcut toggle, the new area dimension buttons, final readout Copy round trip, narrow-display rendering and full VoiceOver navigation remain manual checks. Core geometry/formatting and existing copy handlers pass. No unperformed interaction is counted as passed.
- Visual evidence and intended departures from the mock are recorded in design-qa.md.
- Review correction: area dimension buttons announce Select width/height/both, matching their selection-only action; Copy remains a separate action.

## Window resize expansion

- PASS: 53 core tests. Seven new tests cover integer bounds and malformed/overflow inputs, screen-point semantics, no service call for invalid sizes, actual clamped values, Restore retaining the exact target, recovery after an unverified write, denied/missing/stale/unsupported targets and rejection of late results after closing. These use a deterministic service double; they do not prove AX writes work in another app.
- PASS: native Debug build with no app-source warnings; signature has no App Sandbox entitlement, as selected by the user. The relaunched app retains the Transparent ruler preference.
- PASS, permission-denied view: native screenshot and AX tree show the explanatory access panel, Request/Check buttons, app picker and 2560×1440 fields. Capture/Resize/Restore are disabled and the whole layout is readable. No permission grant was performed by automation.
- PASS: after the user enabled Accessibility, Finder accepted 1280×720 screen points; native screenshot dimensions (2560×1440 at 2x) corroborated the window size. ChatGPT's existing 2560×1440 request showed a clamped result of 2560×1347, and Restore confirmed its previous 1920×1080 frame.
- FOUND / FIX VERIFIED on 2026-11-06: Finder Restore twice left its size at 1280×720 after back-to-back size and position writes. A later screenshot ruled out only an early read; setting the original 1203×908 size alone succeeded, ruling out size limits. Restore now waits for size to settle before setting position. This OS/application interaction has no faithful unit-test seam in the service double; the native resize/restore loop is its regression check.
- PASS, permission recovery: System Settings showed Guides on while Check Access remained denied, including after relaunch of the unchanged build. With explicit user approval, removed only Guides’ entry and re-added the exact build/DerivedData/Build/Products/Debug/Guides.app. Check Access then showed Accessibility access enabled and read the selected window’s metadata. No resizing was performed during repair.
- PASS on 2026-11-06, resumed by user: Finder resized from 1203×908 to 1280×720 and Restore reported the original size and position restored, with Restore disabled afterwards. Out-of-range inputs showed validation without a resize. Closing the chosen Finder window produced a stale-target message; choosing a fresh window recovered. Temporary test windows were closed. The native Debug build and all 53 core tests pass. Native AX text-setting did not reliably update SwiftUI bindings, so the successful resize used the 1280×720 preset.
- Remaining platform coverage: multiple browsers, full-screen and nonstandard windows, mixed-DPI displays, permission revocation, unresponsive apps, older macOS, and a real migration from the previously sandboxed build.


## Spacing token expansion

- PASS: 60 core tests, including seven new tests covering strict bounded declaration parsing, malformed/duplicate entries, calibration gating and overflow, 25–200% zoom conversion independent of rem root, exact tolerance boundaries without display rounding, equal-distance ties and aliases, and preference persistence including tiny decimal tolerances and malformed stored data.
- PASS: native Debug build. Xcode emits its existing unrelated simulator-version and no-AppIntents metadata notices; no app-source warnings.
- PASS: menu entry opens a readable, labelled editor. Unsupported `--bad: 8rem;` is rejected while keeping the editor open; a custom two-token scale saves successfully.
- PASS: native Command-A, Paste, Undo, Redo and Command-S in the editor after adding window-level text commands. Before that fix, standard shortcuts were absent because the accessory app has no Edit menu. Existing unrelated windows' text shortcuts were not changed by this slice.
- PASS: relaunch restores the custom scale and tolerance while the overlay has no measurements and asks to Set scale. A 64×80 screen-point area initially disables Copy Variable; 200% calibration prompts Width/Height selection; Width shows an exact 32-design-px token and enables copying. A temporary TextEdit document confirmed the clipboard contained `var(--space-gap)`; its paste was undone and the temporary document left empty.
- PASS: equal-valued aliases show both names as ambiguous, with Copy Variable disabled. Native screenshot confirms the expanded readout fits below the area and keeps normal Copy separate. Clear Draft followed by Cancel retained the saved scale on reopening; Clear Draft followed by Save then removed the temporary test declarations.
- LIMIT: native tolerance-boundary, rem-unit and guide-gap interactions are covered by shared conversion/matcher unit tests, but have not each been repeated through the UI. Full VoiceOver, very long-name/narrow-display native layouts, mixed-display switching and original measurement acceptance limits remain manual checks. No unperformed native check is counted as passed.


## Simple spacing grid expansion

- PASS: 66 core tests. Six grid tests cover configuration bounds, all four unit conversions and explicit calibration, fractional and offset origins extending in both directions, exact display edges, density/line-budget and nonfinite/overflow rejection, recalibration around the same origin, and independent display sessions/reset/coexistence with measurement state.
- PASS: native Debug build with no app-source warnings; existing simulator-version and AppIntents metadata notices are unrelated to this macOS target.
- PASS: the final direct Grid settings toolbar button shows labelled spacing/unit/origin/opacity controls. Native Select All and typing work in its spacing field. Zero spacing leaves the draft open with an error and does not enable an invalid grid.
- PASS: a 32-screen-point grid at origin (100,150) renders with a contrasting marker and visible origin/spacing badge. Creating a 65×81-point Area preserves those exact dimensions with no snapping, and its readout remains usable over the grid. Transparent ruler appearance remains unchanged.
- PASS: applying Design px without calibration is rejected and Cancel retains the previous screen-point grid. After explicit 200% calibration, an 8-design-px grid applies. Changing to 25% shows Grid paused with a density explanation, leaving the measured Area unchanged; returning to 200% recovers the grid.
- PASS: Pin & work removes editing controls but retains the grid, origin and measurement labels. Clicking and typing in an empty TextEdit document succeeds underneath; the temporary text was undone. No privacy grant was requested for grid use.
- LIMIT: full VoiceOver use, real mixed-display switching/reconnection, very narrow displays, every opacity/background combination, and native rem/backing-pixel grids remain manual checks. Core tests cover the corresponding conversion and session rules; native checks above are not claims of exhaustive hardware coverage.


## Reference image overlay expansion

- PASS: 73 core tests. New coverage checks aspect-preserving fit without upscaling, finite/size/opacity bounds, partial off-screen reachability, grouped drag history, independent display sessions, failed imports retaining the prior image, cancelled/superseded imports rejecting late results, and the 4096-pixel preview cap while the inspector retains its 800-pixel default.
- PASS: native Debug build. Existing simulator-version and AppIntents metadata notices remain unrelated; no app-source warnings.
- PASS: toolbar Reference image controls and the file sheet load a local 400×240 PNG with no privacy prompt. Its default centered 400×240-point placement is 50% opacity. An invalid zero-width draft remains open with an error; applying width 600 at (300,250) yields 600×360 points at 75% opacity. Native screenshot confirms correct quadrant orientation and transparent center, with the alignment border and readable controls.
- PASS: a drag by (60,40), Right, then Shift-Down produces (361,300). Three Command-Z operations restore (300,250); Escape returns to measurement mode. A new 64×80-point Area can be created over the image without moving it. Setting measurement calibration to 200% preserves reference position, size and opacity.
- PASS: replacing with invalid image data reports an error and retains the prior filename/position/size; the Area remains intact. Pin & work hides controls and passes typing through to an empty TextEdit test document; the test text was undone back to empty. Reopening Guides from Finder restores the reference and measurement.
- PASS: a 32-point grid and the Area draw above the reference while pinned. Remove Reference removes the test image while preserving the grid and 64×80-point Area.
- PASS: final-build relaunch starts with no reference, grid, measurements or calibration. Reimport and alignment update the status position from (1720,960) to (1721,960) after Right; removing it returns to a clean reference-free session.
- LIMIT: physical activation shortcut, full VoiceOver, mixed-display/disconnect and sleep/wake hardware behavior, very narrow displays, native EXIF variants/large files and every opacity/background combination remain manual checks. Unit tests cover shared decoder orientation, bounds and lifecycle races; no unperformed native check is counted as passed.


## Annotations and rectangle spotlight expansion

- PASS: 84 core tests. Eleven annotation tests cover all rectangle drag directions, spotlight replacement/deletion/clear through undo/redo, invalid/cancelled geometry, line/arrow endpoint editing, movement/clamping/resizing, topmost hit testing and selected handles, arrowhead direction, atomic style/dimming history, keyboard-scale nudges, independent display sessions and toolbar placement outside the spotlight.
- PASS: native Debug build. Existing simulator-version and AppIntents metadata notices remain unrelated; no app-source warnings.
- PASS: Annotate opens the separate second toolbar row and hides the measurement readout. A reverse drag from (1000,800) to (300,300) creates a 700×500 spotlight at 55% dimming. Screenshot confirms the clear interior, dimmed exterior, eight handles, readable controls, and the pre-existing 64×80 measured Area still visible inside.
- PASS: native drag by (100,50) plus Right yields (401,350), with annotation-specific undo restoring the prior position without altering the measurement. Selecting the rectangle exposes its resize handles; a bottom-right handle drag changes its size. Applying Cyan and 80% dimming changes both, and one Command-Z restores Pink and 55% dimming.
- PASS: a reverse/up-left arrow renders its head at the endpoint; dragging that endpoint changes the selected bounds. A line can be drawn and its endpoint adjusted. Creating a second rectangle replaces the spotlight while retaining the first rectangle and both other shapes; Command-Z restores the previous spotlight and Shift-Command-Z restores the replacement.
- PASS: the rebuilt app starts with no annotations, spotlight or measurements. In the final build, Pin & work hides editing controls and TextEdit accepts clicks and temporary typing through a nearly full-display clear opening. Repeating with a 19×19 opening at the display's top-left confirms input through the dimmed exterior. Each test string was undone back to an empty document.
- PASS: deleting the active rectangle turns spotlight off; undo restores it. Reopening the overlay retains the session. Clear Annotations leaves zero annotations and spotlight off while retaining the 40-point guide gap and 64×80-point Area. The test app was quit after checks to discard temporary geometry.
- PASS: independent review identified two UI defects, both corrected and checked in the rebuilt app: selected Area and guide-gap numeric labels remain visible in Annotate, and the pinned hint says “Activation shortcut to edit” instead of advertising editing keys.
- LIMIT: full VoiceOver, physical activation shortcut, real mixed-display/reconnect and sleep/wake behavior, very narrow displays and exhaustive colour/stroke/background combinations remain manual acceptance items. Hide/Escape and reopen were exercised, but UI automation reopens the accessory window during observation, so hidden-window persistence is not independently established by those observations. Core tests cover corresponding geometry/session rules; they do not establish hardware or assistive-technology coverage.

## Annotation colour toolbar follow-up

- PASS: 86 core tests and the native Debug build. New coverage checks colour changes on every annotation type, one-action undo/redo, untouched other shapes, retained stroke/spotlight/dimming, future colour changes without document history, and drawing after undo or selecting an older shape.
- PASS: native toolbar exposes five named colour swatches with a selected accessibility trait. Choosing Yellow before drawing creates a yellow rectangle. Cyan immediately recolours it; Command-Z restores Yellow and Shift-Command-Z restores Cyan. Stroke remains 4 screen points and spotlight remains active at 55% throughout.
- PASS: the next line inherits Cyan and can be changed to Orange without changing the rectangle. The next arrow inherits Orange and can be changed to White independently. A screenshot confirms the three different strokes and visible palette; the selected White control exposes its checkmark and selected accessibility trait. Test annotations were cleared and the app quit afterwards.
- PASS: final-build review regression: recolour a Pink rectangle Cyan, undo to Pink, then choose Line. Selection clears, the Cyan swatch is checked and the new line is Cyan. Selecting the older Pink rectangle then choosing Arrow and Orange leaves that rectangle Pink and creates an Orange arrow. Test shapes were cleared and the app quit again.
- LIMIT: the compact extra row and full VoiceOver traversal were not exercised on hardware. The normal-width layout and accessible labels/selection were checked on the current display.

## Transparent annotation colour

- PASS: 86 core tests and the native Debug build. The colour-editing test now exercises Transparent on rectangles, lines and arrows, preserving other shapes, stroke width, spotlight/dimming and history. Transparent shapes remain hit-selectable and nudgeable; visible colour can still be assigned to new shapes independently.
- PASS: native Transparent swatch is named and selected in the accessibility tree; Style & spotlight shows Colour: Transparent. A 600×500-point rectangle retains its 55% spotlight while its coloured stroke and dark outline disappear. Eight editing handles remain visible. Undo restores Pink and redo restores Transparent.
- PASS: subsequent lines and arrows inherit Transparent. Pin & work leaves the borderless spotlight visible with no rectangle border, line, arrow or editing handles. Reopening retains all three shapes; selecting the invisible line through accessibility and choosing Cyan restores its visible-colour state while the others remain Transparent. Test shapes were cleared and the app quit.
- LIMIT: compact-display layout and full VoiceOver traversal remain manual checks. The normal-width toolbar, native drawing and accessibility labels/selection were checked on the current display.

## Saved layouts

- PASS: 96 core tests, including round-trip content for guides, Area, grid, arrow/line/rectangle styles, Transparent, spotlight/dimming and future defaults; fresh selection/history/calibration; exact display compatibility; rejected corrupt geometry/styles/spotlight; all-or-nothing archive validation; duplicate IDs/names, capacity and file-size limits; rename/delete recovery and persistence across fresh stores; failed-write preservation; load/recovery atomicity and display invalidation; current reference and global rem-base preservation.
- PASS: native Debug build, with only the existing unrelated simulator-version and AppIntents notices.
- PASS: toolbar Saved Layouts opens a readable, labelled manager. Save Current records two guides, a 64×80-point Area, a transparent 200×150 rectangle spotlight at (600,400), and an enabled 80-Design-px grid. Select All/type/Rename preserves the content; Delete empties the list and Undo Delete restores the same layout.
- PASS: Load Layout restores guides at 812.76953125 and 1277.23828125 screen points and the 64×80 Area. The transparent rectangle retains its 55% spotlight. Units reset to Screen pt, Set scale is required, the Design px grid pauses with an explanation, and both tool histories start empty. Undo Layout Load restores the previous 125% calibration, visible grid, selection and history.
- PASS: quitting/relaunching starts with no measurements, grid or annotations, and unconfirmed calibration. The renamed layout remains listed; explicit Load restores the saved setup. Nudging the loaded Area creates an ordinary undo action; Command-Z undoes it. Undo Layout Load restores the empty pre-load setup even after editing. The test-only saved layout was deleted and Guides closed after checks.
- PASS: independent review found an obsolete reference image retained by the load recovery snapshot. Recovery now excludes reference images; a weak-reference regression confirms that replacing/removing the current image releases its decoded preview while layout recovery remains available.
- LIMIT: real mixed-display/backing-factor switching, disconnect/reconnect, sleep/wake, full VoiceOver, very narrow displays and oldest-supported macOS remain manual checks. Core tests cover exact compatibility and recovery invalidation; they do not establish hardware or assistive-technology coverage. Corrupt/newer/oversized archive and failed-write paths are tested through the store, not by damaging the real native library.

## Manual corner radius

- PASS: 100 core tests. New tests cover radius bounds and nonfinite rejection, move/resize/replacement behavior, ordinary measurement history, calibrated copy formatting, archive v2 persistence, legacy v1 zero-radius migration, invalid archive radius rejection and layout-load recovery.
- PASS: native Debug build. Existing simulator-version and AppIntents notices are unrelated to this macOS target.
- PASS: native final radius controls fit a 300×200-screen-point Area with radius 32. Apply and Return focus measurement keys; Command-Z restores zero and redo restores 32. An out-of-range 101 is rejected without changing the radius; +/− produce 33/32.
- PASS: explicit 200% calibration shows 16px for radius 32 screen points. Command-C and paste into the radius draft verify the exact clipboard text; the valid draft was restored afterwards. Screenshot confirms rounded arcs and readable controls.
- PASS: saved-radius layout survives relaunch; the fresh canvas is empty, explicit Load restores the 300×200 Area and radius 32 with Screen pt units and calibration unconfirmed. Pin & work permits temporary typing into an empty TextEdit document; typing was undone. Only the test layout was removed after checks.
- LIMIT: full VoiceOver, mixed-display behavior, physical activation shortcut and minimum-display layout remain manual limits.

## Radius transparency and live magnifier

- PASS: 103 core tests and native Debug build. New tests map each circular corner into a 256-point preview at 4×/8×/16×, clamp display edges, handle 1×/2× backing scales and reject invalid input. Injected capture tests verify explicit start, stop/discard, late frame/error rejection, request revision changes and restart after errors.
- PASS: native radius outline reaches 0% (border hidden, handles retained), 100% and 35%; magnifier opacity updates both controls and the canvas. Quarter-point radius adjustment changes 32 to 32.25. With access absent, Start Magnifier is disabled while radius/bounds controls and Close remain usable; no permission prompt appears on opening.
- PASS: rebuilt preview shows the full 16× selector and 32.25 screen pt readout. Native regression verifies quarter-point changes keep the preview open with a selected Area in Guides mode, while switching tools dismisses it. Relaunch resets outline opacity to 35% and preview remains stopped.
- PASS: after explicit user authorization, macOS shows Screen Recording enabled for Guides and Start becomes available. A separate native fixture provides a known 300×200-screen-point rectangle with a 32-point circular radius and distinct corner colours. Live top-left/top-right crops at 8×, bottom-left at 4× and bottom-right at 16× align with the fitted curve. Guides windows are absent from the crop, including where the preview covers the target corner.
- PASS: Stop clears the live image; Start resumes it. Closing an active preview and reopening shows the stopped placeholder and Start button. Switching tools while capturing dismisses the preview, and reopening again stays stopped. The preview was closed and the test fixture/Guides test session shut down after checks.
- LIMIT: permission revocation, real display changes and sleep/wake remain hardware/manual checks. Native checks cover all four corners and all three zoom levels, not every corner/zoom combination. No captured images were saved or copied.

## Project profiles

- PASS: 109 core tests, including profile content round-trip and rejected nonpositive/nonfinite rem bases; save/rename/delete/Undo Delete and persistence across fresh stores; name validation without file changes; Apply replacing rem base and spacing scale together with one notification each; Undo Apply restoring both, including after the applied profile is deleted; missing-profile and no-recovery errors; retained corrupt, newer-version and oversized libraries that block writes until Retry; all-or-nothing archive validation for invalid rem base, token syntax, tolerance, duplicate IDs/names and capacity; failed-write preservation.
- PASS: native Debug build, with only the existing unrelated simulator-version notice. The rebuilt app launches and stays running as a menu bar item.
- UNVERIFIED: every native interaction with the Project Profiles window. The unindexed development build could not be targeted by the available desktop automation, and scripted menu access lacked Accessibility permission. Manually check: both menu entries open the window and hide measurements; Save Current, selection, Rename, Delete and Undo Delete; Apply Profile updates the rem readout and token suggestions of an existing measurement; the matching label and disabled Apply; Undo Apply; Select All/Copy/Paste/Undo and Command-W in the name fields; Escape closes; opening Spacing Tokens closes Project Profiles and the reverse; profiles persist across relaunch while nothing applies automatically.
- LIMIT: full VoiceOver and oldest-supported macOS remain manual checks. Corrupt/newer/oversized archive and failed-write paths are tested through the store, not by damaging the real native library.
