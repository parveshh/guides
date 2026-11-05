# Guides menu bar MVP

## Product direction and research

Guides is a small native macOS utility for measuring visible spacing and dimensions across desktop apps. Its first workflow is: activate, place guides or draw an area, read a measurement, copy it, and continue working.

Confirmed choices: a personal prototype; Guides and Area tools; manual placement; explicit scale calibration and rem conversion; one active display at a time; settings persist, measurements start fresh after quitting. The primary audience is a developer checking a browser, Figma design, screenshot, or desktop interface.

| Evidence | Implication |
| --- | --- |
| [PixelSnap](https://pixelsnap.com/) provides detection, guide distances, snapping, screenshots, and design-tool integrations. | Validate a useful personal workflow before broad feature parity. |
| [xScope](https://xscopeapp.com/guide) combines rulers, guides, frames, overlays, and inspection tools. | Keep the initial interface small and expand from demonstrated needs. |
| [Free Ruler](https://github.com/pascalpp/FreeRuler) provides floating rulers, units, and keyboard controls. | Lightweight manual measurement is useful without automatic detection. |
| [Figma](https://help.figma.com/hc/en-us/articles/360039956974-Measure-distances-between-layers) measures layer bounds, which can differ from visible strokes/text. | Describe output as manual visual measurements, never inferred Auto Layout padding or CSS properties. |

Success: after learning the controls, measure and copy a typical gap within ten seconds, then return to the underlying app without losing focus or fighting the overlay. Token matching is a future hypothesis to validate through use.

## MVP interface and stories

Launch into the menu bar without a dashboard or Dock icon. Menu: Edit Guides (initial shortcut Control-Option-G), Measure Area, Hide Measurements, Clear Measurements (current display), Settings, Quit. Editing shows thin top/left rulers and a compact floating strip with Guides/Area, unit, scale/calibration, selected value and Copy, Pin, and Hide. Settings contain the activation shortcut and default rem base (16px).

| ID | Story | Acceptance |
| --- | --- | --- |
| G01 | Activate without changing workspace. | Menu/shortcut opens editing on the pointer's display; repeated activation focuses the editor; no privacy prompt. |
| G02 | Pull guides onto visible boundaries. | Top ruler creates horizontal guides, left creates vertical; H/V adds at pointer while editing; select, drag, delete, and nudge. |
| G03 | Read spacing immediately. | Adjacent parallel guides show distances; Shift-select two parallel guides for total separation; reordered/coincident guides never produce negative distances. |
| G04 | Check displayed width and height. | Drag an area in either direction, move/resize it; one rectangle per display coexists with guides; replacement is one undoable action. |
| G05 | Convert to development units. | Screen points, backing pixels, calibrated design/CSS px, rem; scale updates values without moving geometry; assumptions remain visible. |
| G06 | Copy useful values. | Copy a gap, area width, height, or both; Command-C copies the selection while editing; individual calibrated values use 24px or 1.5rem. |
| G07 | Keep measurements while working underneath. | Pin makes the entire overlay click-through and relinquishes keyboard focus; editing controls disappear; menu/shortcut resumes editing. |
| G08 | Recover and resume. | Undo/redo creation, movement, deletion, replacement, clear; hiding retains sessions; quitting discards geometry/calibration and retains settings. |

Interaction defaults:

- Arrows move one screen point; Shift moves ten; Option moves one backing pixel.
- Escape cancels the unfinished gesture or otherwise hides the overlay.
- Click a measurement to select it and expose Copy. Pinned mode retains a noninteractive scale badge.
- Opaque label backgrounds and contrasting outlines work without sampling the screen. Prioritize selected labels when crowded and keep the selected value in the control strip.
- Activating another display hides the old overlay and opens that display's independent in-memory session. Measurements never cross displays.

Excluded from the MVP: image-file inspection, screenshots/capture, loupe, colour picker, automatic snapping, presets, integrations, accounts, billing, automatic updates, and public distribution.

## Architecture and measurement contract

Use Swift 6, AppKit, and SwiftUI with macOS 14 as the deployment target. Validate on the current Apple Silicon Mac; wider compatibility certification is later work.

- AppKit application delegate, status item/menu, lifecycle, clipboard, and display notifications.
- A borderless transparent NSPanel with an AppKit drawing/input view; SwiftUI editing controls and settings.
- Pin KeyboardShortcuts 3.0.1 through Swift Package Manager. It supports sandboxing and documents no permission dialogs; its [manifest](https://raw.githubusercontent.com/sindresorhus/KeyboardShortcuts/3.0.1/Package.swift) requires Swift tools 6.2. See its [documentation](https://github.com/sindresorhus/KeyboardShortcuts).
- UserDefaults for preferences; sessions and undo history only in memory.
- One Xcode app project and unit tests. Keep geometry/conversions independent of window code. Small application controller, overlay controller, session store, measurement engine, and preferences store; no plugin framework.
- Enable App Sandbox without network or capture entitlements.

| State | Appearance | Input |
| --- | --- | --- |
| Hidden | Menu bar only | No interception |
| Editing | Measurements, rulers, controls | Local measurement gestures and editing keys |
| Pinned | Measurements and scale badge | Mouse/keyboard return to underlying app |

Create the panel with a fixed [nonactivating style](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel), allow key status during editing, and relinquish it when pinned/hidden. Use [ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents) for click-through. Use public collection behaviors including canJoinAllSpaces and [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications), with full-screen/Stage Manager behavior verified in the first native milestone. Handle editing events locally; no global keyboard monitoring or capture.

Internal interfaces, with no public API/server/companion protocol:

- Guide: identity, axis, display-local position.
- Area: identity and normalized rectangle.
- Display session: guides, optional area, selection, unit, calibration, undo history. The activation command chooses Guides or Area.
- Calibration: screen points per design pixel, root font size, and assumed versus supplied scale.
- Measurement result: unrounded value, unit, manual origin, calibration context.

Input updates the session; the engine derives measurements; the overlay renders them; clipboard formatting consumes the same results.

### Coordinates and units

Store geometry in display-local logical points with top-left origin. Convert global AppKit coordinates through the selected display's actual frame, including negative desktop coordinates. Use AppKit backing conversions for pixel readouts. [Backing scale](https://developer.apple.com/documentation/appkit/nswindow/backingscalefactor) is not necessarily physical display pixel geometry; label the unit Backing px.

| Unit | Meaning |
| --- | --- |
| Screen pt | Logical macOS distance; fresh-session default |
| Backing px | Distance in overlay backing coordinates |
| Design/CSS px | Screen distance converted using supplied scale |
| rem | Calibrated pixels divided by supplied root font size |

For screen distance d, scale s in screen points per design pixel, and root size r: designPx = d / s; rem = designPx / r.

Calibration accepts either view scale (50%, 100%, 200%, etc.) or a selected gap/area dimension plus its known pixel size. Design px/rem requires confirming scale, initially proposed as 100%. Known-size calibration handles combined browser/canvas scaling. [Browser zoom affects pixel relationships](https://developer.mozilla.org/en-US/docs/Web/API/Window/devicePixelRatio); never infer automatic equivalence. [rem depends on root font size](https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Styling_basics/Values_and_units), which remains visible/editable.

Reject nonpositive or nonfinite calibration. Keep geometry unrounded; display point/pixel values to two decimals and rem to four, trimming zeros. Copy displayed precision. Screen-point copies use descriptive text such as `32 screen pt`, avoiding CSS pt confusion.

Only one overlay is visible; constrain gestures to their starting display. On disconnect or resolution/backing change, hide the affected overlay and clear that display's geometry/calibration; retain unaffected sessions/preferences. Never silently reinterpret a measurement after display reconfiguration.

## Reviewed implementation slices

Each slice is implemented, checked, independently reviewed, corrected/re-reviewed until clean, and committed before the next. Review exact staged content; changes after approval require new review. Report hash, checks, and limitations. No remote push.

| Slice | Deliverable | Validation | Status |
| --- | --- | --- | --- |
| 1 | Git main; PLAN.md; AGENTS.md; ignores | Document consistency, scope, references, staged diff | Committed c274f64 after clean independent review |
| 2 | Xcode project; menu; hotkey; overlay; Hidden/Editing/Pinned | Build, activation, click-through, focus, full-screen, no privacy prompts | Committed 18ccf2b after clean re-review; limits in TESTING.md |
| 3 | Pull/drag guides; adjacent distances; copy screen pt | Geometry, coordinate conversions, known measurements | Committed 879a498 after clean independent review |
| 4 | Selection; nonadjacent pairs; nudges; delete; undo/redo; clear/hide retention | Editing state and keyboard behavior | Committed 45759ac after clean re-review |
| 5 | Move/resize/replace rectangle; dimension copying | Reverse drag, cancellation, replacement, coexistence | Committed 7ddbf92 after clean re-review |
| 6 | Backing px, design px, rem; calibration; settings | Conversion examples, validation, formatting, persistence | Committed adea314 after clean independent review |
| 7 | Display lifecycle; readability; accessibility; build instructions | Full acceptance matrix and explicit unverified scenarios | Implemented; 34 core tests and native workflow checks; acceptance limits in TESTING.md |

### Test and acceptance matrix

Implementation notes: the pure core is a local Swift package consumed by the Xcode app, allowing headless `swift test` runs. Debug targets the current Apple Silicon architecture. Reopening Guides from Finder enters editing as an alternative activation path. Giving the panel a title in slice 6 enabled native screenshots and pointer checks that were unavailable in earlier slices. Global-hotkey and hardware/system scenarios remain explicit final manual acceptance items in `TESTING.md`. Core checks and observable native behaviors remain per-slice gates.

Automated: guide reorder/coincidence/deletion/undo; normalized reverse rectangles; cancelled replacement retains old area; coordinate conversion for screens above/left of primary; 32pt yields 64 backing px at 2x; 64pt at 200% yields 32px/2rem at 16px root; 16pt at 50% also yields 32px; invalid calibration cannot affect state/copy; state transitions, display invalidation, and clipboard formatting.

Native: entire workflow without Screen Recording, Accessibility, or Input Monitoring grants; known browser/Figma dimensions at multiple calibrated zooms; click/type/scroll/app-switch underneath pinned overlays; Spaces/full-screen/Stage Manager; sleep/wake and display reconnection; mixed displays where available; light/dark/dense labels; keyboard navigation and accessibility; no idle polling/continuous redraw. Record unavailable hardware/scenarios as unverified rather than passed.

Supply a local app and reproducible build/run instructions. Public signing/notarization, store submission, and updater are later work.

### Final implementation evidence

- Display sessions are keyed by the in-process [NSScreen display ID](https://developer.apple.com/documentation/appkit/nsscreen/devicedescription), not size or desktop origin. Same-sized displays remain independent; resolution/backing changes and disconnects invalidate only affected sessions. Screen configuration changes use [AppKit notifications](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification); sleep/wake uses the workspace notification center. There is no polling loop.
- The canvas exposes stable accessibility elements with select/pair actions. Bracket keys provide direct selection and Shift-brackets extend a parallel pair without pointer input. A narrow display uses an extra toolbar row; the toolbar respects the screen's usable top inset. Extreme formatted text truncates visually instead of drawing beyond label backgrounds; copying retains the formatted value.
- The vertical ruler extends to the full overlay height. A user screenshot exposed that using the usable display height incorrectly left a gap above the Dock region; only controls and hints need that lower safe inset.
- Swift 6 requires an explicit isolation bridge for the legacy accessibility callback. Only a Sendable action closure crosses that boundary; AppKit objects remain on the main thread. The bridge uses the [Swift migration guide's isolation pattern](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/IncrementalAdoption.md) and compiled under strict concurrency.
- Native acceptance now covers ruler placement, a known guide gap, keyboard nudging/undo/pair selection, reverse area creation/resizing, percentage and known-size calibration, accessible selection, clipboard output, pinned input, and activation from a full-screen Finder window. Hardware/OS coverage is deliberately limited to the current Mac; outstanding scenarios remain explicit in `TESTING.md`.

## Expansion roadmap

| Stage | Features | Trigger |
| --- | --- | --- |
| Everyday utility | Dropped-image dimensions/metadata, saved layouts, simple grids | Repeated personal need; distinguish original image size from displayed size |
| Developer context | Project profiles, spacing tokens, CSS-variable copying, reference overlays | Reduce work between measurement and correction |
| Capture-assisted tools | Loupe, colour, edge snapping, annotated screenshots | Workflow justifies permission/processing complexity |
| Exact integrations | Browser computed styles, Figma properties, comparison/review bundles | Source properties beyond manual visual measurement |
| Public release | Compatibility testing, onboarding, signed/notarized distribution, updates, commercial decisions | Evidence of usefulness beyond personal prototype |

The MVP is complete when its two tools are accurate, quick to operate, and easy to dismiss.
