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

Launch into the menu bar without a dashboard or Dock icon. Menu: Edit Guides (initial shortcut Control-Option-G), Measure Area, Hide Measurements, Clear Measurements (current display), Settings, Quit. Editing shows thin top/left rulers and a compact floating strip with Guides/Area, unit, scale/calibration, a separate selected-value/Copy readout, Pin & work, and Hide. Settings contain the activation shortcut, default rem base (16px), and Solid/Transparent ruler backgrounds. The toolbar's Tools menu also opens the background choice.

| ID | Story | Acceptance |
| --- | --- | --- |
| G01 | Activate without changing workspace. | Menu opens editing on the pointer's display; the shortcut toggles Editing/Pinned and resumes the chosen tool; no privacy prompt. |
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
- Both rulers show screen-point coordinates every 100 points. Vertical numbers rotate to fit the narrow ruler. Solid is the default background; Transparent removes it and keeps each number on its own dark chip with haloed ticks. This shared appearance preference applies immediately to both rulers and persists across launches.
- Opaque label backgrounds and contrasting outlines work without sampling the screen. Prioritize selected labels when crowded and keep the selected value in its nearby readout.
- Activating another display hides the old overlay and opens that display's independent in-memory session. Measurements never cross displays.

Excluded from the MVP: image-file inspection, screenshots/capture, loupe, colour picker, automatic snapping, presets, integrations, accounts, billing, automatic updates, and public distribution.

## Architecture and measurement contract

Use Swift 6, AppKit, and SwiftUI with macOS 14 as the deployment target. Validate on the current Apple Silicon Mac; wider compatibility certification is later work.

- AppKit application delegate, status item/menu, lifecycle, clipboard, and display notifications.
- A borderless transparent NSPanel with an AppKit drawing/input view; SwiftUI editing controls and settings.
- Pin KeyboardShortcuts 3.0.1 through Swift Package Manager. It supports sandboxing and documents no permission dialogs; its [manifest](https://raw.githubusercontent.com/sindresorhus/KeyboardShortcuts/3.0.1/Package.swift) requires Swift tools 6.2. See its [documentation](https://github.com/sindresorhus/KeyboardShortcuts).
- UserDefaults for preferences; sessions and undo history only in memory.
- One Xcode app project and unit tests. Keep geometry/conversions independent of window code. Small application controller, overlay controller, session store, measurement engine, and preferences store; no plugin framework.
- The original MVP enabled App Sandbox. The user-approved window resize expansion now uses one app outside App Sandbox because Apple does not support cross-app Accessibility APIs inside it. Measurement and image inspection still need no privacy grants; window resizing uses an optional, explicit Accessibility permission. This expansion adds no capture or network features; the later, explicitly authorized corner magnifier is the sole capture exception.

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
| 7 | Display lifecycle; readability; accessibility; build instructions | Full acceptance matrix and explicit unverified scenarios | Committed 3bd867b after clean re-review; acceptance limits in TESTING.md |
| Follow-up | Numbered vertical ruler; saved Solid/Transparent appearance | Native rendering, style switching, guide dragging, preference restoration | Committed 7d82014 after clean independent review |

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

The original [Plan Guides App conversation](chatgpt-conversation://6aec388a-457c-83eb-b585-076e78de88c1) was reread in full for the next slice. Image inspection already appears in both that conversation and this roadmap. It adds an immediately useful developer workflow without depending on capture or integrations. The accepted manual-measurement MVP remains intact; the following work extends it in separate reviewed commits.

### Selected next slice: local image inspector

| ID | Story | Acceptance |
| --- | --- | --- |
| I01 | Inspect a supplied image without leaving the menu bar utility. | Inspect Image in the menu bar or toolbar ruler menu opens a separate compact window; Open Image, one-file drag/drop, and explicit Paste Image accept local inputs. Opening the inspector hides and retains desktop measurements. |
| I02 | Read original asset dimensions. | Width, height, reduced aspect ratio, format, byte size, and alpha-channel presence are derived from Image I/O metadata. EXIF orientation is applied; encoded dimensions are shown when orientation differs. DPI and ruler calibration do not change pixel counts. |
| I03 | Copy values for development. | Copy Dimensions, Width, and Height use the displayed original pixel values. A bounded, orientation-correct preview is clearly labelled as scaled. |
| I04 | Understand import limits and recover. | Clipboard representations are labelled separately from original files. Multi-image files show primary-image metadata and image count; no animation. Invalid/missing/oversized inputs show an error and retain the prior successful image. Cancel leaves it unchanged; Clear/close discards it and cancels pending results. No image state is persisted. |

Implementation: an Image I/O reader and serial loader actor in GuidesCore; a dedicated AppKit window, open panel and pasteboard/drag handling; SwiftUI preview and metadata controls. Read at most 100 MiB of encoded input (plus one byte to detect overflow), produce a preview bounded to 800 pixels on its longest edge, and perform file reading/decoding off the main actor. Newer requests supersede older results. This bounds input/preview size; it is not a promise of constant memory use inside system image decoders. File promises, remote URLs, vectors such as SVG/PDF, batch inspection, metadata editing, and pixel-level transparency detection are outside this slice. PNG/TIFF clipboard data is inspected as provided, not normalized through NSImage.

Documentation: Context7 resolved AppKit to `/websites/developer_apple_appkit` and supplied image/pasteboard and drag registration references. Two Image I/O resolution queries returned unrelated libraries; the AppKit query also had limited open-panel detail. The missing APIs were checked against the installed SDK and Apple's [Image I/O image sources](https://developer.apple.com/documentation/imageio/cgimagesource), [orientation-aware thumbnails](https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailwithtransform), and [user-selected read-only file entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-only). Add only that file entitlement to the existing sandbox; no screen capture or broad disk access.

Status: committed as bd877ea after clean independent re-review. 42 core tests, native Debug build, and the native open/paste/copy/recovery/lifecycle checks passed. Cross-app drag and full VoiceOver remain manual checks in TESTING.md. Review fixes invalidate rejected pending imports and ignore Caps Lock for inspector shortcuts; native validation also corrected preview-driven window growth.

### Selected follow-up: option 2 toolbar redesign

The user selected the second displayed image, saved as [focus-rail.png](docs/design/focus-rail.png). Use its opaque charcoal single-row toolbar, pink tool selection/guides, light solid rulers, and separate Copy readout beside the selected gap. Keep the surface neutral instead of wallpaper-tinted material. The underlying mock layout is context, not a new app dashboard; the actual desktop remains visible beneath the overlay.

Preserve all measurement behavior: both tools, units and explicit calibration, area Width/Height/Both copying, undo/redo, ruler appearance and image-inspector access, keyboard editing and accessibility, hiding and click-through pinning. When no copyable measurement is selected, show no empty readout. Pinned mode hides all interactive controls and retains the noninteractive measurement/scale labels. Narrow displays use a second toolbar row. The readout clamps to display bounds, avoids the toolbar when space allows, and prefers placement outside area resize handles. Exact text is copied even when unusually long values must truncate visually.

Implementation: shared visual styles, custom native SwiftUI buttons with selection traits, an independently positioned NSHostingView for the measurement readout, and tested pure placement geometry. Context7's official SwiftUI references verified [ButtonStyle](https://developer.apple.com/documentation/swiftui/buttonstyle), [selection accessibility](https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected), [color scheme](https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme), and [hosting sizing options](https://developer.apple.com/documentation/swiftui/nshostingview/sizingoptions). Existing AppKit window/input handling stays in place.

Validation: 46 core tests cover the existing features plus readout placement at edges, next to areas, below the toolbar and on narrow displays. A top-edge collision discovered by the new tests was fixed with a toolbar-clearance fallback. The first native visual comparison found compressed tool labels; their intrinsic sizing was corrected. The native re-check confirms full Guides/Area and Pin & work labels, the neutral toolbar and numbered rulers. Earlier native inspection confirmed the selected-gap readout. Pin removes interactive controls and Finder accepts input underneath. Automated UI input was interrupted by concurrent desktop changes, so the final physical hotkey toggle and area readout interactions remain manual checks. See design-qa.md and TESTING.md; independent review is the final commit gate.

The user reported that editing prevented work in other apps. The action is now labelled **Pin & work**, its help and the canvas hint explain click interception, and the activation shortcut toggles Editing/Pinned. Explicit menu activation still enters editing.

### Selected expansion: window resizing

The user asked to resize a browser to a specified size such as 2560 × 1440 and chose one Guides app with optional Accessibility access. This explicitly extends the permission-free MVP; the original measuring tools remain available without that grant.

| ID | Story | Acceptance |
| --- | --- | --- |
| W01 | Choose a concrete window. | Resize Window in the menu bar and toolbar tools menu opens a separate window and hides measurements. Default to the most recent regular external app; show app/title/last-read size. Explicitly use the app’s front window. Later app switching never silently retargets Resize or Restore. |
| W02 | Request an exact outer-window size. | Width/height accept whole screen-point values 1–16384; presets include 1280×720, 1440×900, 1920×1080 and 2560×1440. Apply only on Resize Window. Read back the resulting size; explain constraints or unavailable verification instead of claiming success. |
| W03 | Recover from a resize. | Preserve the frame before the latest attempt for the same AX window; Restore requests its size and position and verifies both. Partial/unconfirmed writes retain recovery. Changing target or closing clears the UI session; nothing is saved. |
| W04 | Keep access optional and failures understandable. | Request Accessibility only from the explicit button. Check Access retries without prompting. Missing, closed, minimised, nonstandard or non-resizable windows fail with actionable feedback. Remote calls use one-second per-message timeouts on a serial actor; controls prevent duplicate operations and closing rejects late results. |

Unit contract: AXPosition and AXSize use global macOS **points**, with a top-left origin on the menu-bar display; no backing-scale conversion is applied. Whole-window dimensions include browser chrome and do not establish CSS viewport size, browser zoom or monitor pixel resolution. A 2560×1440 preset is a request, not a promise that an oversized window will be allowed. This slice does not change display resolution or add browser integrations. Use browser responsive tools for an exact CSS viewport.

Implementation: tested request/model types in GuidesCore, a dedicated Accessibility service actor, and an AppKit window with SwiftUI controls. Only the selected window’s metadata and frame are read. A one-time migration imports the known root-size, ruler-appearance and shortcut preferences from the former sandbox domain when the new domain has no value. No image paths, window history or calibration persist.

Research: Context7 resolved Application Services to `/websites/developer_apple_applicationservices`; its three-command allowance supplied [read attributes](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue), [write attributes](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue), [settable checks](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable), [IPC timeouts](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) and [explicit trust prompts](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions). The docs did not resolve sandbox/coordinate details; Apple’s [sandbox limitations](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) and installed AXAttributeConstants.h verified them. [Browser outer dimensions](https://developer.mozilla.org/en-US/docs/Web/API/Window/outerWidth) include chrome. The legacy C prompt-option constant is imported with `@preconcurrency` and used only on the UI actor.

Status: implemented; 53 core tests and native Debug build pass. The updated app launches with the previously saved Transparent ruler choice. Native inspection confirms the optional-permission UI and disabled actions before access. After the user enabled access, Finder resized to 1280×720; ChatGPT reported a 2560×1440 request clamped to 2560×1347 and restored to 1920×1080. Finder exposed a restore sequencing issue: back-to-back size/position writes left its size unchanged, while a size-only request to the original 1203×908 succeeded. Restore now waits for the size update (up to three 200ms checks) before writing position, then verifies the full frame. The user initially paused the corrected native check; on 2026-11-06 they resumed it. Finder resized from 1203×908 to 1280×720 and Restore confirmed the original size and position. Invalid dimensions were rejected without resizing, and a closed target reported its stale state and recovered by selecting a fresh window. A later permission check reproduced System Settings showing Guides enabled while the running app returned untrusted, even after relaunch. The app uses an ad-hoc, cdhash-specific designated requirement, consistent with Apple’s [code identity documentation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). With explicit user approval, removing only Guides’ stale entry and adding the exact current build restored access; Check Access now shows Accessibility access enabled. No resize was performed during this repair. Committed as 96c27e5 after clean independent review. The corrected native checks, 53 core tests and Debug build passed; broader platform coverage remains in TESTING.md.

### Selected expansion: spacing tokens

The user selected this slice after finishing window resizing on 2026-11-06. Compare visual measurements against a user-supplied local spacing scale; never infer the CSS or Figma token actually used by another app.

| ID | Story | Acceptance |
| --- | --- | --- |
| S01 | Supply a local scale. | Spacing Tokens in the menu bar and toolbar tools menu opens a separate editor, hiding and retaining measurements. Accept one `--name: 8px;` declaration per line, with optional semicolons, nonnegative decimal px values up to 1000000, at most 64 tokens and 16 KiB of text. Names are case-sensitive, at most 64 characters, and use an ASCII letter or underscore after `--`, then ASCII letters/digits/underscore/hyphen. Duplicate names and unsupported syntax are rejected without altering the saved scale. Equal-valued aliases are allowed. |
| S02 | Compare calibrated distances. | A selected guide gap or area Width/Height compares its unrounded distance in design pixels only after explicit calibration, regardless of display unit. Both dimensions prompts a single-dimension choice. Scale changes update suggestions without moving geometry; rem root and backing scale do not change px token values. |
| S03 | Understand nearest matches. | Show the nearest token, measured design px and signed difference. Absolute tolerance is configurable from 0–100 design px, initially 1; zero requires an exact match apart from floating-point arithmetic noise. Outside-tolerance results remain visible but cannot copy a variable. Equal-distance ties and equal-valued aliases are labelled ambiguous and never pick automatically. |
| S04 | Copy and retain predictably. | Copy Variable copies `var(--name)` only for a unique nearest match within tolerance. Existing Copy and Command-C retain measurement output. Save Scale applies atomically and persists scale/tolerance; Cancel/close discards the draft. Clear Draft only changes the draft; saving it removes suggestions. Relaunch retains scale/tolerance while measurements and calibration start fresh. |

Implementation: immutable validated scale and pure matcher in GuidesCore, saved through GuidesPreferences. A dedicated AppKit/SwiftUI editor keeps a draft until Save. The existing nearby measurement readout shows suggestions and a separate copy action. An empty scale is the default; Use Example is explicit. No CSS-file import, project profiles, automatic snapping, new permission or integration is added.

Research: Context7 supplied Apple's [TextEditor binding documentation](https://developer.apple.com/documentation/swiftui/texteditor). Native checks exposed that the accessory app has no Edit menu supplying standard text commands. Context7's AppKit answer covered text responders but not window key equivalents; installed NSResponder.h/NSText.h/NSTextView.h and the existing image-inspector window verified the required methods. The spacing editor handles Select All, Copy, Cut, Paste, Undo/Redo and Close while forwarding other shortcuts to SwiftUI. Native Select All/Paste/Undo/Redo/Command-S checks passed.

Status: committed as d07bcd6 after clean independent review. 60 core tests/Debug build passed; native checks verify editor validation, saved-scale relaunch, fresh geometry/calibration, explicit-calibration and dimension gating, exact 200% conversion, `var(--space-gap)` clipboard output, ambiguity disabling variable copy, and the expanded readout layout. Full VoiceOver, mixed-display and narrow-display native coverage remain manual limits in TESTING.md. The standard independent-review gate applies to this completed implementation.

### Selected expansion: simple spacing grid

The next roadmap slice adds a square spacing grid to the existing overlay. It is a manual visual reference on the active display and never claims to inspect an app's CSS grid or snap measurements.

| ID | Story | Acceptance |
| --- | --- | --- |
| Q01 | Show and configure a grid. | The toolbar grid button opens settings; the tools menu offers Show/Hide Grid. Apply spacing, unit, origin X/Y and opacity atomically; invalid drafts retain the previous grid. Cancel discards the draft. Defaults: hidden, 8 screen pt, origin (0,0), 25% opacity. |
| Q02 | Use explicit units and origin. | Square cells use Screen pt, Backing px, calibrated Design px or rem independently of the measurement readout's unit. Design/rem require the existing explicit calibration. Origin is always display-local screen points from its top-left corner, within the display bounds. The lattice extends in both directions from its origin. A contrasting origin marker and a spacing/origin badge remain visible. |
| Q03 | Keep drawing bounded and understandable. | Spacing accepts positive finite values up to 1000000 in the selected unit; opacity is 10–80%. Require at least 4 screen pt between lines and at most 2048 lines per axis. A later scale/root change that makes rendering invalid pauses only the grid and displays a reason; valid settings recover it. Never silently draw a coarser grid. |
| Q04 | Work alongside measurements. | Draw grid lines behind rulers/guides/Area without adding hit targets or snapping. Pin & work retains the grid while all overlay input passes through; Hide removes it with measurements. Clear Measurements and measurement undo leave grid settings intact. Calibration changes cell spacing around the fixed origin while leaving manual measurement geometry untouched. |
| Q05 | Respect display sessions. | Retain grid configuration during hide/pin/resume and display switching. Grid settings and origin are session-only, independent on each display. Display disconnect or size/backing changes invalidate the affected grid with its measurement session; quitting starts with a hidden default grid. No permission, capture, integration or saved layout is added. |

Implementation: validated GridConfiguration and bounded GridGeometry in GuidesCore; DisplaySession stores the configuration. The controller resolves geometry on existing refresh events. AppKit draws contrasting lines, origin and badge; SwiftUI provides the draft editor. Text commands are shared with the spacing-token window so field edits keep native Select All/Copy/Cut/Paste/Undo behavior. Rendering has no timer or idle polling.

Research: Context7 resolved AppKit and supplied Apple's [NSBezierPath stroke](https://developer.apple.com/documentation/appkit/nsbezierpath) and [clipping](https://developer.apple.com/documentation/appkit/nsbezierpath/clip(_:)) APIs. A native check found that presenting grid settings from inside the tools menu did not show the popover. The final direct toolbar button follows the [SwiftUI popover example](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)); the toolbar is 40 points wider with its existing compact layout threshold adjusted. Existing panel click-through and graphics-state handling are reused.

Status: committed as 73c7696 after clean independent review; 66 core tests and the native Debug build pass. Native checks cover settings presentation, text selection/entry, zero-spacing rejection, offset origin, grid/Area coexistence without snapping, calibration gating, density pause/recovery and pinned click/type-through. Full VoiceOver, hardware display switching, very narrow native layouts and exhaustive appearance combinations remain manual limits in TESTING.md.

### Selected expansion: reference image overlay

The next roadmap slice uses one local raster image as a manually aligned reference per display. Its screen-point placement and source pixels are independent of measurement calibration and do not inspect CSS or track application windows.

| ID | Story | Acceptance |
| --- | --- | --- |
| R01 | Import a local reference. | The toolbar Reference image button opens controls and a one-file image picker. Fit a successful image within 80% of the display without upscaling, at 50% opacity. Use orientation-correct primary-image pixels and retain the previous reference after invalid/cancelled replacement. Decode off the UI thread with the existing 100 MiB encoded limit and a preview bounded to 4096 pixels per edge; no capture, network, clipboard or drag-import expansion. |
| R02 | Size and position explicitly. | Apply X/Y and width in display-local screen points, preserving source aspect ratio. Width and height must each remain 1–32768 screen pt, with at least 1 pt intersecting the display on each axis. Opacity is 10–100%. Show source dimensions separately; ignore image DPI and measurement scale. Fit to display resets the draft. Invalid drafts and Cancel retain current placement. |
| R03 | Align without editing measurements. | Apply & align on canvas enables reference-only drag and arrow nudging (1 screen pt, Shift 10 pt, Option 1 backing px). Undo/redo affects reference placement in this mode; a drag is one action. Escape cancels a drag, then exits alignment; Guides/Area resume measurement editing. Placement history is capped at 100 and reset on image replacement/removal; import/removal itself is not undoable. |
| R04 | Compare while working. | Reference pixels draw behind grid, rulers and measurements. Show reference controls visibility; Remove Reference releases its session image. Pin & work retains visible content and passes all input through; Hide hides everything. Clear Measurements does not remove the reference. No automatic snapping, pixel-diff claims, rotation or independent aspect stretching. |
| R05 | Keep lifecycle local and predictable. | Each display retains its image/placement/history only for this run. Display invalidation clears the affected reference; quitting saves no image path or placement. Hide, pin, switching displays or removal cancel pending work, and late results cannot repopulate a cleared or different display. |

Implementation: reference geometry/history and cancellable loading live in GuidesCore. The overlay shares the existing Image I/O loader with a larger bounded preview, an AppKit file sheet and drawing, and SwiftUI draft controls. Placement changes do not affect guide/Area state or calibration. Replacing the image ends any in-flight alignment gesture and resets the editor draft to the new image. Only one decoded preview per populated display is retained; placement history never retains previous imported images.

Research: Context7 supplied Apple's [CGImage-backed NSImage initializer](https://developer.apple.com/documentation/appkit/nsimage/init(cgimage:size:)-8oznv), [flipped image drawing with opacity](https://developer.apple.com/documentation/appkit/nsimage/draw(in:from:operation:fraction:respectflipped:hints:)), and [asynchronous file sheet](https://developer.apple.com/documentation/appkit/nssavepanel/beginsheetmodal(for:completionhandler:)) APIs. Image I/O orientation and bounded preview logic reuse the tested image-inspector path.

Status: committed as 9605026 after clean independent review. 73 core tests and the native Debug build pass. Native checks confirm file import, orientation/transparency, draft validation, precise sizing/opacity, drag/nudge/undo, measurement/calibration independence, failed-replacement recovery, pinned typing, grid layering and reference-only removal. See TESTING.md for remaining hardware/accessibility checks. Independent review is required before committing.

### Selected expansion: annotations and rectangle spotlight

Add an **Annotate** tool for pointing out interface details during reviews and demonstrations. Its first slice supports arrows, straight lines and rectangles. A rectangle can act as a spotlight: the desktop inside stays live and undimmed while the rest of the active display darkens. This is a visual overlay, not content detection or a screen capture.

| ID | Story | Acceptance |
| --- | --- | --- |
| A01 | Mark a detail with an arrow or line. | Choose Arrow or Line and drag between endpoints. Select, move, adjust endpoints, nudge and delete it. Offer a small colour palette and stroke-width choices; arrowheads remain readable at either drag direction. |
| A02 | Frame and highlight a region. | Drag a Rectangle in any direction, then move or resize it with handles. **Spotlight** is enabled by default for a new rectangle; switch it off for an ordinary outline. The interior remains fully undimmed and the exterior darkens immediately. |
| A03 | Control the spotlight. | One rectangle at a time is the active spotlight on the active display. Drawing or assigning another replaces the previous spotlight assignment in one undoable action; other annotations remain. Adjust dim opacity from 0–80%, initially 55%. The rectangle border (unless Transparent is selected) and annotation controls stay visible above the dim layer. |
| A04 | Continue using the highlighted app. | **Pin & work** keeps annotations and dimming visible while the entire overlay, including the clear rectangle, passes input through. Editing captures input to manipulate shapes; a clear interior is only a visual opening during editing. Hide or Escape removes annotations and dimming together; Escape first cancels an unfinished gesture. |
| A05 | Correct and retain work predictably. | Undo/redo creation, drag/resize, deletion, spotlight assignment, dim-opacity and style changes. One drag is one history action. Deleting the active spotlight restores normal brightness. Clear Annotations removes only annotations and spotlight, preserving guide/area measurements. Hiding retains the session; quitting discards annotations and spotlight. |
| A06 | Keep annotations separate from measurements. | Annotation rectangles do not replace the measured Area or change calibration. Measurements and annotations can coexist; annotation editing selects only annotation objects. The spotlight clears only its dim mask and does not erase guides or other overlays inside the rectangle. |

Scope and defaults:

- Use the existing one-active-display model. Dim only that display; other displays remain unchanged. Annotations stay fixed in screen coordinates and do not track windows or their contents.
- Keep per-display annotation state in memory. Switching displays hides the old overlay and restores the selected display’s session; disconnect/resolution/backing-scale changes invalidate affected annotation geometry and spotlight using the existing measurement lifecycle rules.
- Provide keyboard selection, nudging, deletion and labelled accessibility controls. Expose the selected shape and spotlight state. Keep toolbar/readouts above the dim mask and prefer placing controls outside the highlighted rectangle where space allows.
- Text labels, ellipses, freehand drawing, multiple simultaneous spotlight openings, saved annotation layouts and screenshot/export are later candidates. The first slice uses no capture or additional privacy grant; existing optional window-resize permission remains unrelated.

Implementation: AnnotationSession owns shapes, selection, spotlight, cancellable gestures and a 100-action document history in GuidesCore, separate from measurement state. The shared presentation enum is now OverlayTool to include Annotate. A dedicated second toolbar row offers Select/Arrow/Line/Rectangle; completed drawing switches to Select. Style & spotlight uses an Apply/Cancel draft with five colours, 2/4/6-screen-point strokes and 5% dimming steps. Style defaults apply to future shapes; document undo restores existing shape styling and dimming. The existing activation path, display lifecycle and pinned input behavior are reused.

Rendering: draw the reference image, exterior dim mask, grid/rulers/measurements, then annotation strokes and handles; controls/readouts remain above the canvas. The mask uses an even-odd compound path, so it never clears another overlay's pixels. Rectangle dimensions and line/arrow lengths must be at least one screen point at gesture completion; invalid or cancelled gestures restore the prior document and spotlight. Shapes are clipped to the display. The toolbar prefers a position outside the spotlight when available and stays stationary during a drag.

Research: Context7 supplied Apple's [even-odd winding rule](https://developer.apple.com/documentation/appkit/nsbezierpath/windingrule-swift.enum/evenodd), [path fill](https://developer.apple.com/documentation/appkit/nsbezierpath/fill()), [stroke](https://developer.apple.com/documentation/appkit/nsbezierpath/stroke()) and [round line caps](https://developer.apple.com/documentation/appkit/nsbezierpath/linecapstyle-swift.enum). No new privacy API or capture path is added.

Validation before review: geometry and hit-testing for every drag direction; endpoint/handle edits; zero-sized/cancelled rectangles; spotlight replacement and deletion through undo/redo; dim-mask interior/exterior and edge-of-display cases; coexistence with guides/Area; display invalidation; native click-through inside and outside the spotlight; hide/pin/resume, colour/opacity readability and keyboard/accessibility checks. Verify the underlying app stays live inside the clear region. Record unavailable display/assistive-technology checks explicitly.

Status: committed as 7281ae2 after clean independent review, with 84 passing core tests and a successful native Debug build. Native checks verify shape/endpoint editing, spotlight replacement and undo/redo, style/dimming, click/type-through inside and outside the spotlight, measurement coexistence, clearing and fresh relaunch. Independent review found two UI defects: selected measurement values disappeared in Annotate and pinned mode advertised editing keys. Both are fixed and checked in the rebuilt app. Remaining hardware, assistive-technology and hidden-window observation limits are recorded in TESTING.md.

### Annotation colour follow-up

The user requested colour selection for rectangles, lines and other annotations. Expose the existing five-colour palette directly in the annotation toolbar as labelled swatch buttons with a selection checkmark. A swatch updates the selected shape and future drawing colour immediately, preserving each shape's stroke width, spotlight assignment and dimming. Choosing a drawing tool clears the previous shape selection, making the palette show and change only the future drawing colour. Existing-shape changes use one undo action; changing only the future default creates no document history. The Apply/Cancel style popover remains available. On compact displays the palette and Delete/Clear controls occupy another row.

Implementation and validation: committed as 4727839 after clean independent review. A colour-only AnnotationSession operation, shared AppKit/SwiftUI colour mapping and accessible buttons. Context7 verified Apple's [NSColor conversion](https://developer.apple.com/documentation/swiftui/color/init(nscolor:)) and [selected accessibility trait](https://developer.apple.com/documentation/swiftui/accessibilitytraits/isselected). All 86 core tests and the native Debug build pass. Native checks confirm default colour before drawing, independent rectangle/line/arrow recolouring, selected swatches, undo/redo and retained spotlight settings. Independent review identified a mismatch between the checked swatch and future colour after undo or selecting an older shape; clearing selection when choosing a drawing tool fixes it, with regression and native checks. Compact-display and full VoiceOver checks remain manual.

### Transparent annotation colour

The user requested Transparent as an additional colour choice. Add it to the toolbar and style popover for rectangles, lines and arrows. A checkerboard swatch distinguishes it from White. Transparent suppresses both the coloured stroke and its dark contrast outline, including arrowheads; selection handles remain available only during editing. Geometry, hit testing, keyboard/accessibility selection, spotlight assignment, dimming, colour defaults and undo/redo retain their existing behavior. A transparent rectangle can provide a borderless spotlight while pinned.

Implementation and validation: an additional AnnotationColor case and a rendering guard; no new persistence, permissions or APIs for capture. Context7 verified SwiftUI [circular clipping](https://developer.apple.com/documentation/swiftui/view/clipshape(_:style:)) for the checkerboard swatch. All 86 core tests and the native Debug build pass. Extended colour tests exercise transparent rectangles/lines/arrows, spotlight preservation, hit selection, nudging, history and restoring a visible colour. Native checks confirm the swatch and style value, borderless spotlight with editing handles, undo/redo, hidden pinned strokes/handles and recolouring a retained transparent line. Full VoiceOver and compact-display checks remain manual. Independent review of the exact staged change is required before committing.

### Selected expansion: saved layouts

The user selected saved layouts next. Save named setups locally and restore them only through an explicit Load action; relaunch still starts with fresh measurements and unconfirmed calibration.

| ID | Story | Acceptance |
| --- | --- | --- |
| L01 | Save the current setup. | Saved Layouts is available from the menu bar and toolbar tools menu. Save guides, measured Area, grid configuration, annotation geometry/styles/defaults and spotlight/dimming for the active display. Trim names, require 1–80 characters and unique names ignoring case. Save creates a new snapshot; edits to the canvas do not update it automatically. |
| L02 | Restore precise geometry. | Show the layout's screen-point size, backing factor and content counts. Load only on a display with the same size and backing factor; never scale or clamp saved geometry silently. Replace the current display's guides/Area/grid/annotations atomically and start fresh tool histories. Reset measurement units to Screen pt and calibration to unconfirmed; Design px/rem grids pause until Set scale is explicitly used again. Reference images and global preferences are outside the snapshot. |
| L03 | Recover after loading. | Undo Layout Load restores the previous display setup, calibration and tool histories, without changing its current reference image or global rem-base preference. Keep one recovery snapshot for the latest load in this run. Only its matching display can restore it; display invalidation clears it. Expose this separately from each tool's ordinary undo. |
| L04 | Manage saved work. | Select, rename and delete layouts. Delete has one-level Undo Delete during this run; rename keeps identity/content. Invalid names or failed writes leave the library unchanged. |
| L05 | Persist safely and locally. | Store one versioned JSON library in Application Support using atomic writes. Validate complete archives before accepting them; unreadable, corrupt or newer-version files are retained and block mutations with a visible error and Retry. Limit to 100 layouts, 1000 guides and 1000 annotations per layout, and an 8 MiB archive. No auto-load, reference-file persistence, capture, cloud sync, import/export or project profiles in this slice. |

Validation: round-trip all supported content including Transparent, spotlight/defaults and grids; explicit calibration reset; exact display compatibility; invalid/corrupt/future-version and write-failure preservation; naming and delete recovery; fresh relaunch; atomic load/recovery and unaffected reference/global settings. Native checks cover save/list/load/rename/delete/undo, geometry restoration and calibration gating. Independent review of the final exact staged diff is the commit gate.

Implementation: immutable Codable snapshot records validate before rebuilding domain state with fresh object IDs. LayoutLoadRecovery owns the single previous session independently of measurement and annotation history. SavedLayoutsStore validates complete archives before publishing them and changes its observable library only after an atomic disk write succeeds. The manager binds to the active display configuration at opening and rechecks it for each capture/load/recovery. Stored display bounds are finite, positive and capped at 100000 screen points per axis and a 16× backing factor; out-of-bounds guides, areas, annotations, origins and unknown enum values are rejected. Signed CGRect extents are checked directly before restoration to prevent silent normalization/clamping.

Research: Context7 verified Apple's [Application Support directory](https://developer.apple.com/documentation/foundation/url) and [atomic data writing option](https://developer.apple.com/documentation/foundation/nsdata/writingoptions). No privacy API or capture path is added.

Implementation is complete. Validation: 96 core tests pass and the native Debug build succeeds. Native save/list/rename/delete/Undo Delete, disk persistence across relaunch, empty fresh canvas, explicit restoration of exact guide/Area geometry and a transparent spotlight, Design px grid calibration gating, post-load editing/ordinary undo and Undo Layout Load are verified. Recovery restores the prior 125% scale and tool history, and can also recover an empty pre-load setup. The test layout was removed after checks. Real display switching/reconnection and full VoiceOver remain manual limits. Independent review found that load recovery retained an obsolete reference preview; recovery now stores a reference-free session, and a weak-reference regression test verifies release after replacement/removal. Commit gate: clean independent re-review of the exact staged diff.

### Selected expansion: manual corner radius

The user selected rounded-window radius measurement. Extend Area with a circular corner radius: fit its bounds to the window, choose Radius in the readout, then enter a radius in screen points or adjust it by one-point buttons while matching the visible curve. Measure Corner Radius in the menu opens the same workflow. Draw one rounded outline with equal circular radii at all four corners. This is a manual circular-fit estimate; continuous/superelliptic corners, shadows and unequal/elliptical corner radii are not automatically measured. Manual fitting requires no capture, detection or additional privacy permission; the optional magnifier follow-up is specified below.

Acceptance: radius is finite and 0 through half the shorter Area side; invalid input leaves geometry unchanged. Copy/readout convert the radius through existing Screen pt/Backing px/explicitly calibrated Design px/rem units. Width/height/both remain independent, radius has no spacing-token suggestion, and calibration still uses known width/height. Move retains radius; shrinking bounds caps it to the new geometric limit; drawing a new Area resets it to zero. Radius changes, resize, delete and clear use ordinary measurement history. Pin keeps the rounded outline and radius label click-through; hide, display sessions/invalidation and fresh relaunch retain their existing rules.

Saved layouts include the radius. Write archive version 2 to prevent older builds silently dropping it; read version 1 with a missing radius as zero. Validate stored radius before reconstruction, and preserve it through load recovery. Reference images and annotations remain separate. Validation covers bounds/nonfinite values, resize/move/history, unit conversions and legacy/current/corrupt archives, then native fitting, validation, copy, undo, pin and save/load. Exact staged independent review remains the commit gate.

Research: Context7 verified Apple’s [rounded path radii and clamping rules](https://developer.apple.com/documentation/appkit/nsbezierpath/appendroundedrect(_:xradius:yradius:)). The core validates the circular radius against both dimensions before drawing. Native checks verified valid/invalid radius input, one-point adjustment, clipboard conversion at 200% calibration, undo/redo, click-through pinning and saved-radius restoration after an empty fresh launch. The final combined precision change is reviewed below.

### Radius precision follow-up: transparency and live magnifier

The user explicitly selected a live desktop magnifier with optional Screen Recording access, extending the earlier no-capture scope only for this tool. Add a 0–100% Area outline opacity control (initially 35%) while fitting radius; apply it to both contrast and coloured strokes. Zero hides the border, while editing handles/readouts remain available. Opacity is a per-run viewing aid, not a measurement or saved-layout property.

Provide a corner magnifier with corner selection and 4×/8×/16× screen-point zoom, a pixelated live crop and the fitted circular outline drawn over it at the same coordinates. Include quarter-point radius adjustments. Capture only while the user explicitly starts the visible magnifier; stop and release images on dismissal, pin/hide, tool/selection/display changes, sleep and errors. Exclude Guides’ own application windows to prevent recursion. Request Screen Recording only from its dedicated button; denied or revoked access leaves normal measurement usable. No capture is saved, copied, uploaded or restored at launch. Keep at most one current preview; reject late frames after stop or request changes. Use macOS 14 ScreenCaptureKit region capture with bounded output and a modest refresh cadence.

Validation: pure crop/coordinate geometry, display edges and backing factors; injected capture lifecycle tests for stop/late result/error/restart; native permission-denied controls, transparent border, live alignment and lifecycle checks when permission is granted. Update current no-capture descriptions to reflect only this explicitly authorized exception. Independent review covers the complete radius feature including this follow-up before committing.

Research: Context7 resolved ScreenCaptureKit to `/websites/developer_apple_screencapturekit` but returned only general capture references. Installed macOS SDK headers verified `SCScreenshotManager.captureImage`, application-excluding display filters, and `SCStreamConfiguration.sourceRect` in display-local logical points. Capture uses the selected display, excludes this process, omits audio/cursor, bounds output to 512 pixels and refreshes no faster than one completed request plus 250 ms. An injectable core controller invalidates late frames/errors across request revisions and stop/restart.

Implementation is complete. Validation: 103 core tests pass, including crop geometry and asynchronous capture lifecycle regressions. Native Debug build passes without app-source warnings. Native opacity at 0/35/100%, fractional controls, readable zoom/readout, no-access gating and fresh-launch defaults pass. Testing caught and fixed premature dismissal when adjusting a selected Area with Guides active. After the user authorized Screen Recording, live captures aligned with a separate known 300×200-screen-point, 32-point-radius fixture: top-left/top-right at 8×, bottom-left at 4× and bottom-right at 16×. Guides windows are excluded even where the preview covers the target. Start, Stop, close/reopen and active tool-switch dismissal pass; reopening stays stopped until explicitly started. Permission revocation, real display changes and sleep/wake remain manual limits. Final exact staged independent review remains the commit gate.

### Subsequent candidates

Saved layouts and corner radius are complete. On 2026-11-09 the user widened the direction to a developer toolset for full-stack developers and approved the roadmap below. Each later candidate needs its own acceptance details and reviewed implementation slice; none is implicitly implemented by earlier tools.

### Full-stack toolset roadmap

Groups are delivered in order, one reviewed slice per item. Group A needs no new permission and starts now. Groups B and C are approved for the roadmap only: each slice must first record its own permission, capture and network contract here and be explicitly confirmed by the user, with that authorization recorded in `AGENTS.md`, before implementation.

| Group | Slice | Summary |
| --- | --- | --- |
| A. Front-end loop | A1 Project profiles | Named local sets of rem base and spacing scale, applied explicitly. Later slices add their settings to the profile. |
| | A2 Copy formats (done) | Copy a measurement as CSS declarations (`width`, `height`, `border-radius`, gap) and Tailwind classes, from calibrated values only. |
| | A3 Breakpoints and device presets | User-supplied breakpoint markers on the top ruler; device sizes in Resize Window. |
| | A4 Column grid | Columns, gutters and margins alongside the square grid. |
| | A5 Calculators | `clamp()` fluid sizing, px/rem/em/vw conversion, aspect-ratio lock for Area. |
| | A6 Image inspector extras | `@2x`/`srcset` size calculator and base64 data URI copy. |
| | A7 Annotation extras | Text labels and ellipses. |
| B. Capture-assisted tools | B1 Colour picker | Sample a pixel; copy hex/rgb/hsl/oklch; WCAG contrast between two samples. |
| | B2 Edge snapping | Snap guides and Area to detected edges; detect element bounds. |
| | B3 Annotated screenshot export | Save the visible overlay with the desktop beneath it to a user-chosen file. |
| | B4 Reference pixel diff | Compare the reference image with the live screen region. |
| C. Local environment and network tools | C1 Port monitor | List local listening ports and their processes; stop a chosen process after confirmation. |
| | C2 HTTP request tester | Send a user-written request to a user-supplied host and show the response. |
| | C3 Webhook inspector | Receive and display requests on a local port. |
| | C4 DNS and TLS checks | Resolve a user-supplied host and show certificate details. |

Constraints carried into Groups B and C:

- Group B reuses the existing optional Screen Recording grant, requested only from an explicit button, and captures only while its tool is active. B3 is the first feature that writes a captured image; it saves only to a file the user chooses, on an explicit action.
- Group C is the first network use. Requests go only to hosts the user types, on an explicit action; nothing is sent in the background, and there are no accounts, telemetry or cloud storage. C1 and C3 stay on this Mac.
- Measurement, image inspection and every Group A tool remain usable without any new privacy grant or network access; A3 device presets live inside Resize Window, which keeps its existing optional Accessibility requirement.

Deferred by the user on 2026-11-09: a local developer utilities panel (JSON/JWT/Base64/hash, UUID, timestamps, cron, regex, diff, SQL formatting, clipboard-aware opening). It is not scheduled.

### Slice A1: project profiles

Save the settings that differ between projects under a name and apply them explicitly. A profile is a local snapshot of preferences, not an inspected project configuration; it never reads a repository, CSS file or design file.

| ID | Story | Acceptance |
| --- | --- | --- |
| P01 | Save the current project settings. | Project Profiles in the menu bar and toolbar tools menu opens a separate window, hiding and retaining measurements. Save Current stores the rem base and the spacing scale with its tolerance. Trim names, require 1–80 characters and unique names ignoring case. Saving creates a new snapshot; later preference edits do not update it. |
| P02 | Switch projects explicitly. | Apply Profile replaces the rem base and spacing scale together through the existing preferences, so open sessions update as they do from Settings and Spacing Tokens. Geometry, calibration scale, ruler appearance, shortcut and saved layouts are untouched. A profile equal to the current settings is labelled as matching and has nothing to apply. Nothing applies automatically at launch; the applied values persist as ordinary preferences. |
| P03 | Recover from an apply. | Undo Apply restores the rem base and spacing scale from before the latest apply, once, during this run, replacing any rem-base or token edits made since that apply. It remains available after the applied profile is deleted. |
| P04 | Manage and persist safely. | Select, rename and delete profiles; delete has one-level Undo Delete during this run. Store one versioned JSON library at `~/Library/Application Support/Guides/profiles.json` with atomic writes. Validate complete archives before accepting them; unreadable, corrupt or newer-version files are retained and block changes with a visible error and Retry. Limit to 50 profiles and a 2 MiB library. Invalid names or failed writes leave the library unchanged. |

Implementation: `ProjectProfileContent` and `ProjectProfilesStore` in GuidesCore follow the saved-layout store pattern and reuse its name rules. Content is validated through the existing `SpacingScale` parser and the positive-finite rem-base rule before it can reach preferences. A dedicated AppKit/SwiftUI window reuses the shared text commands. The Spacing Tokens editor and Project Profiles close each other when opened, so a stale token draft cannot overwrite an applied profile; an unsaved token draft is discarded as it is on Cancel. No new permission, capture, network use, import/export or sync is added. Later Group A slices (breakpoints, device presets, column grid) add their settings to the profile with an archive version bump.

Validation: 109 core tests pass, including six new profile tests for content round-trip and invalid rem bases, library save/rename/delete/undo across fresh stores, apply and undo with preference notifications, retained corrupt/future/oversized libraries, all-or-nothing archive validation and failed writes. The native Debug build passes and the rebuilt app launches. Native interaction with the new window is unverified: the unindexed development build could not be driven by the available automation, so the manual checks are listed in TESTING.md. Commit gate: clean independent review of the exact staged diff.

### Visual overhaul before A2

The user asked for a visual overhaul that looks great and is easy to understand, and reported that ruler numbers were unreadable with the Transparent ruler background. This is a presentation-only change: geometry, units, calibration, copy output, persistence, permissions and keyboard behavior are unchanged, and the confirmed charcoal/pink direction from [focus-rail.png](docs/design/focus-rail.png) is kept.

| ID | Change | Acceptance |
| --- | --- | --- |
| V01 | Readable transparent rulers. | With no ruler background, every 100-point number sits on its own opaque dark chip and ticks use a dark core over a light halo. Numbers and ticks read over light, mid-tone and dark content without sampling the screen. Solid rulers keep dark numbers on a light strip, with shorter minor ticks and a mid tick every 50 points. |
| V02 | Visible guides and labels. | Guides, gap connectors and the Area outline draw a 1-screen-point pink core (2 when selected) over a soft dark halo, replacing a hairline inside a heavy black outline. Positions and hit targets are unchanged. Labels use one chip style with proportional text and tabular digits; the selected label is filled pink. Area handles are round, white with a pink edge. |
| V03 | Self-explanatory toolbar. | The tools menu is labelled Tools; Guides, Area and Annotate and the annotation tools carry icons and sit on segmented tracks; controls show hover and pressed states and have tooltips. Pin & work is visually emphasised. The single-row toolbar now hugs its content (1082 points measured) instead of filling a fixed 1000-point bar, so its hit area matches what is drawn; displays with less than 1120 points of usable width use the two-row layout. Heights grow by 4–12 points for the segmented tracks. Placement rules are unchanged. |
| V04 | Scannable hints. | The long status sentence becomes a hint bar that names the current mode and shows key caps with short actions, including the user's actual activation shortcut. On narrow displays the editing-key hints are dropped first; the mode name, the pin hint and Escape stay, and the mode name truncates last. Pinned mode shows a short pinned summary. |
| V05 | Consistent tool windows. | Settings, Spacing Tokens, Project Profiles, Saved Layouts, Resize Window and Inspect Image share a header (icon, title, one-line purpose), grouped cards, empty states and a quiet caveat note. Every existing control, label, accessibility label, limit and caveat is retained. The menu bar menu gains Measure/Tools section headers and icons. |

Implementation: shared tokens and button styles in `OverlayStyle.swift`, `ToolWindowStyle.swift` for window scaffolding, and `OverlayCanvas+Hints.swift` for the hint bar. `KeyboardShortcuts.Shortcut.description`, verified in the pinned 3.0.1 package source, supplies the shortcut text. The toolbar's hosting view reports its intrinsic content size so the controller can size the bar to its content, and notifies the controller when SwiftUI publishes a new ideal size a turn after a layout switch. A DEBUG-only `--design-snapshots <directory>` launch argument renders the app's own overlay and tool-window views through AppKit's display cache over a synthetic light/mid/dark backdrop, then quits. It captures nothing from the screen, needs no permission and is compiled out of Release builds.

Validation: 109 core tests and the native Debug build pass. Snapshot renders before and after the change confirm V01–V05 on the current display, and the snapshot run reports matching toolbar host and content widths (1082 points); reference renders are saved in `docs/design/overhaul/`. Snapshots do not exercise popovers, menus, hover, real pointer input, compact displays or VoiceOver; those remain manual checks in TESTING.md. Commit gate: clean independent review of the exact staged diff.

### Pixel snap before A2

On 2026-11-10 the user reported that measuring an element such as a web-page button was not accurate, asked for sticky guides and asked whether the line's width affects the value. Offered a permission-free pixel snap or the gated capture-based edge snapping (B2), the user chose **pixel snap only**. B2 stays gated and unimplemented.

Measurement contract, unchanged: a guide is a zero-width position and a gap is the difference between two positions. The drawn line is centred on its position and its width never enters a value.

| ID | Story | Acceptance |
| --- | --- | --- |
| X01 | Place guides on pixel boundaries. | A guide pulled from a ruler, dragged, or added with H/V lands on the nearest whole backing pixel of the active display (every half screen point at 2×). Two snapped guides therefore measure a whole number of backing pixels. |
| X02 | Place Area edges on pixel boundaries. | Drawing and resizing snap the dragged corner or edge. Moving puts the top-left corner exactly on a boundary and keeps the size, so an Area with a whole-pixel size has all four edges on boundaries. Display-edge clamping still wins. |
| X03 | Opt out per gesture. | Holding Control during the drag places freely, as before. The hint bar names this. Keyboard nudges, radius and magnifier quarter-point adjustments, saved layouts and existing geometry are not altered or re-snapped. |
| X04 | See what is being aligned. | While a guide or the Area is being dragged it draws as a bare 1-screen-point core without the dark halo, so the pixels beside the measured position stay visible. The halo and selected weight return on release. |

Implementation: `PixelSnapping` in GuidesCore is arithmetic on overlay coordinates using the display's backing factor; `OverlayCanvas` applies it to guide and Area pointer input only. Annotations, the reference image and the grid are untouched. It reads nothing from the screen, detects no edges and needs no permission; finding the visible edge is still done by eye. No external API was involved, so no Context7 lookup was needed.

Validation: 114 core tests pass, including five new tests for 1×/2×/3× rounding, idempotence and display bounds, invalid input, whole-pixel gaps between snapped guides, and snapped Area moves at the display edge. The native Debug build passes. Pointer behaviour in the running app is unverified by automation; the manual checks are in TESTING.md. Independent review found that a snapped Area move could land one floating-point step off the boundary, and that the halo dropped on press instead of on drag; the move now sets the snapped origin directly, with an exact-equality test, and the bare core appears only once the pointer moves. On a 1× display a 1-point line centred on a pixel boundary is antialiased across two pixels; that drawing is unchanged and unverified here. Commit gate: clean independent review of the exact staged diff.

### Slice A2: copy formats

On 2026-11-10 the user confirmed the visual overhaul and pixel snap and asked to start A2. Copy the selected measurement in a form that pastes straight into a stylesheet or a class list. The output is a formatted manual visual measurement. It is not an inspected CSS property, and Guides does not know which property the measured distance really is.

| ID | Story | Acceptance |
| --- | --- | --- |
| C01 | Copy a CSS declaration. | **Copy as → CSS** copies `width: 320px;`, `height: 48px;`, `border-radius: 8px;` or `gap: 24px;` for the selected Area Width, Height, Radius or guide gap. Area **Both** copies the width and height declarations on two lines. |
| C02 | Copy a Tailwind class. | **Copy as → Tailwind** copies arbitrary-value utilities: `w-[320px]`, `h-[48px]`, `rounded-[8px]`, `gap-[24px]`; Both copies `w-[320px] h-[48px]`. Named scale classes such as `w-80` are never produced, because that would assume a Tailwind theme Guides cannot see. |
| C03 | Use calibrated values only. | Both formats use design px from the explicit calibration, or rem when the measurement unit is rem, at the precision the readout shows (px two decimals, rem four, trailing zeros trimmed). Screen pt and Backing px selections still produce design px. Until the scale is explicitly set the menu offers no copy action, only an inert line explaining why; nothing is copied from an assumed scale. |
| C04 | Keep the origin visible and existing copy unchanged. | The menu is headed as a manual measurement and each item shows the exact text it copies. Copy, Command-C and Copy Variable keep their current output. A guide gap is offered as `gap` only as a starting point; the menu says so. Nothing is persisted and no profile setting is added. |

Implementation: `CopyFormat`, `CopySubject` and `CopyFormatter` in GuidesCore convert through the existing `MeasurementEngine`, so gating and rounding match the readout. The readout gains one **Copy as** menu beside Copy. No new permission, capture, network use or persistence; the project-profile archive stays at version 1.

Validation: 120 core tests pass, including six new formatter tests for every subject in both formats, explicit-calibration gating in every unit, px versus rem, readout precision and invalid distances. The native Debug build passes. Independent review found that the uncalibrated menu would also have shown an empty section header, that the wider button row could truncate long values at the 460-point readout cap, and that the gating test covered only two subjects; the menu branches are now exclusive, the cap is 520 points, and the test covers every subject. The menu itself is unverified by hand; the checks are listed in TESTING.md. Commit gate: clean independent review of the exact staged diff.

Research: Context7 (`/websites/tailwindcss`) confirmed the arbitrary-value forms [`w-[<value>]`](https://tailwindcss.com/docs/width), [`h-[<value>]`](https://tailwindcss.com/docs/height), [`rounded-[<value>]`](https://tailwindcss.com/docs/border-radius) and [`gap-[<value>]`](https://tailwindcss.com/docs/gap), each emitting the value unchanged.

Earlier staging, retained for context:

| Stage | Features | Trigger |
| --- | --- | --- |
| Everyday utility | Dropped-image dimensions/metadata, saved layouts, simple grids | Repeated personal need; distinguish original image size from displayed size |
| Developer context | Project profiles, spacing tokens, CSS-variable copying, reference overlays | Reduce work between measurement and correction |
| Capture-assisted tools | Loupe, colour, edge snapping, annotated screenshots | Workflow justifies permission/processing complexity |
| Exact integrations | Browser computed styles, Figma properties, comparison/review bundles | Source properties beyond manual visual measurement |
| Public release | Compatibility testing, onboarding, signed/notarized distribution, updates, commercial decisions | Evidence of usefulness beyond personal prototype |

The MVP is complete when its two tools are accurate, quick to operate, and easy to dismiss.
