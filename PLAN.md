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

Launch into the menu bar without a dashboard or Dock icon. Menu: Edit Guides (initial shortcut Control-Option-G), Measure Area, Hide Measurements, Clear Measurements (current display), Settings, Quit. Editing shows thin top/left rulers and a compact floating strip with Guides/Area, unit, scale/calibration, a separate selected-value/Copy readout, Pin & work, and Hide. Settings contain the activation shortcut, default rem base (16px), and Solid/Transparent ruler backgrounds. The toolbar's ruler icon also opens the background choice.

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
- Both rulers show screen-point coordinates every 100 points. Vertical numbers rotate to fit the narrow ruler. Solid is the default background; Transparent leaves only outlined numbers and ticks. This shared appearance preference applies immediately to both rulers and persists across launches.
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
- The original MVP enabled App Sandbox. The user-approved window resize expansion now uses one app outside App Sandbox because Apple does not support cross-app Accessibility APIs inside it. Measurement and image inspection still need no privacy grants; window resizing uses an optional, explicit Accessibility permission. No capture or network features are added.

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

Status: implemented; 66 core tests and the native Debug build pass. Native checks cover settings presentation, text selection/entry, zero-spacing rejection, offset origin, grid/Area coexistence without snapping, calibration gating, density pause/recovery and pinned click/type-through. Full VoiceOver, hardware display switching, very narrow native layouts and exhaustive appearance combinations remain manual limits in TESTING.md. The mandatory independent-review gate applies before committing.

### Planned expansion: annotations and rectangle spotlight

Add an **Annotate** tool for pointing out interface details during reviews and demonstrations. Its first slice supports arrows, straight lines and rectangles. A rectangle can act as a spotlight: the desktop inside stays live and undimmed while the rest of the active display darkens. This is a visual overlay, not content detection or a screen capture.

| ID | Story | Acceptance |
| --- | --- | --- |
| A01 | Mark a detail with an arrow or line. | Choose Arrow or Line and drag between endpoints. Select, move, adjust endpoints, nudge and delete it. Offer a small colour palette and stroke-width choices; arrowheads remain readable at either drag direction. |
| A02 | Frame and highlight a region. | Drag a Rectangle in any direction, then move or resize it with handles. **Spotlight** is enabled by default for a new rectangle; switch it off for an ordinary outline. The interior remains fully undimmed and the exterior darkens immediately. |
| A03 | Control the spotlight. | One rectangle at a time is the active spotlight on the active display. Drawing or assigning another replaces the previous spotlight assignment in one undoable action; other annotations remain. Adjust dim opacity from 0–80%, initially 55%. The rectangle border and annotation controls stay visible above the dim layer. |
| A04 | Continue using the highlighted app. | **Pin & work** keeps annotations and dimming visible while the entire overlay, including the clear rectangle, passes input through. Editing captures input to manipulate shapes; a clear interior is only a visual opening during editing. Hide or Escape removes annotations and dimming together; Escape first cancels an unfinished gesture. |
| A05 | Correct and retain work predictably. | Undo/redo creation, drag/resize, deletion, spotlight assignment, dim-opacity and style changes. One drag is one history action. Deleting the active spotlight restores normal brightness. Clear Annotations removes only annotations and spotlight, preserving guide/area measurements. Hiding retains the session; quitting discards annotations and spotlight. |
| A06 | Keep annotations separate from measurements. | Annotation rectangles do not replace the measured Area or change calibration. Measurements and annotations can coexist; annotation editing selects only annotation objects. The spotlight clears only its dim mask and does not erase guides or other overlays inside the rectangle. |

Scope and defaults:

- Use the existing one-active-display model. Dim only that display; other displays remain unchanged. Annotations stay fixed in screen coordinates and do not track windows or their contents.
- Keep per-display annotation state in memory. Switching displays hides the old overlay and restores the selected display’s session; disconnect/resolution/backing-scale changes invalidate affected annotation geometry and spotlight using the existing measurement lifecycle rules.
- Provide keyboard selection, nudging, deletion and labelled accessibility controls. Expose the selected shape and spotlight state. Keep toolbar/readouts above the dim mask and prefer placing controls outside the highlighted rectangle where space allows.
- Text labels, ellipses, freehand drawing, multiple simultaneous spotlight openings, saved annotation layouts and screenshot/export are later candidates. The first slice uses no capture or additional privacy grant; existing optional window-resize permission remains unrelated.

Implementation outline: store annotation identities, shape geometry, styles and active spotlight identity separately from the measurement document in GuidesCore. Use one annotation-editing history to make shape and spotlight changes atomic. Render the exterior dim mask, annotation strokes and controls in that order, reusing the existing overlay presentation and input-routing behavior. Normalize reverse-drag rectangles and clip geometry to the active display. Look up current platform drawing/input documentation through Context7 when implementing; this planning update introduces no new API dependency.

Validation before review: geometry and hit-testing for every drag direction; endpoint/handle edits; zero-sized/cancelled rectangles; spotlight replacement and deletion through undo/redo; dim-mask interior/exterior and edge-of-display cases; coexistence with guides/Area; display invalidation; native click-through inside and outside the spotlight; hide/pin/resume, colour/opacity readability and keyboard/accessibility checks. Verify the underlying app stays live inside the clear region. Record unavailable display/assistive-technology checks explicitly.

Status: planned only. Window resizing, spacing tokens and simple grids were selected first; annotations remain a candidate for a future reviewed slice in the order below.

### Subsequent candidates, in priority order

1. **Reference overlays:** import an image as a manually aligned, adjustable-opacity reference; keep reference coordinates separate from measurement calibration. Defer capture-assisted comparison.
2. **Annotations and spotlight:** arrows, lines and rectangles; a live, undimmed rectangular focus region with adjustable dimming outside it. See the stories above.

Saved layouts and project profiles remain candidates after those workflows prove useful. Each candidate needs its own acceptance details and reviewed implementation slice; none is implicitly implemented by the image inspector.

| Stage | Features | Trigger |
| --- | --- | --- |
| Everyday utility | Dropped-image dimensions/metadata, saved layouts, simple grids | Repeated personal need; distinguish original image size from displayed size |
| Developer context | Project profiles, spacing tokens, CSS-variable copying, reference overlays | Reduce work between measurement and correction |
| Capture-assisted tools | Loupe, colour, edge snapping, annotated screenshots | Workflow justifies permission/processing complexity |
| Exact integrations | Browser computed styles, Figma properties, comparison/review bundles | Source properties beyond manual visual measurement |
| Public release | Compatibility testing, onboarding, signed/notarized distribution, updates, commercial decisions | Evidence of usefulness beyond personal prototype |

The MVP is complete when its two tools are accurate, quick to operate, and easy to dismiss.
