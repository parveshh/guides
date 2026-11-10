# Guides native design QA

## Current redesign: selected context bar, 10 November 2026

Source visual truth: [first displayed ImageGen concept](docs/design/ui-exploration-2026-11-10/01-context-bar.png), selected by the user. Implementation: the existing native AppKit/SwiftUI app, using system fonts and SF Symbols.

### Evidence and normalization

- Source image: 1487×1058 pixels. Native view-rendering viewport: 1440×1024 screen points, emitted as 1440×1024 pixels (one output pixel per screen point). The source is normalized to that viewport for [full comparison](docs/design/context-bar/qa-full-comparison.png); this is a proportional comparison, not a pixel-diff claim. CSS viewport/density settings do not apply to this native app.
- State: Annotate active, a pink rectangle selected, spotlight off. [Native full view with Style](docs/design/context-bar/annotate-with-style.png) combines Guides' own canvas and popover view caches at their actual native window positions. Only synthetic light/blue/dark backdrop bands are used; no desktop pixels are captured. The OS-owned popover shell/arrow is outside its content-view cache.
- [Focused comparison](docs/design/context-bar/qa-focused-comparison.png) places the reference and native bars together at normalized component widths, then compares the Style content. The actual native Style content is 320×448 pixels. [Measurement strip](docs/design/context-bar/toolbar-measure.png), [annotation strip](docs/design/context-bar/toolbar-annotate.png), [760-point compact layout](docs/design/context-bar/compact-annotate.png) and [pinned view](docs/design/context-bar/pinned.png) cover the other changed surfaces.

### Comparison history and fixes

1. [Initial measurement render](docs/design/context-bar/qa-before-measure.png): Grid clipped to “G…”. Explicit intrinsic sizing now keeps Grid and Reference labels visible. Earlier host-size logs also exposed stale dimensions after switching modes/widths; separate constrained hosting views now settle to the content size in both dimensions.
2. [Initial annotation render](docs/design/context-bar/qa-before-annotate.png): the native Menu omitted its custom colour well. Replaced it with a visible swatch button and a small palette popover, preserving every existing colour.
3. The focused Style comparison exposed truncated explanatory text and a system-pink colour that differed from the toolbar accent. Multiline fixed-height text now wraps completely; annotation pink and editing handles use the shared pink. The native popover initially overlapped the selected shape while its hosting view grew; establishing its content size before showing it, with a small lower-edge anchor, now places it below the rectangle. The final full comparison visibly confirms the correction.
4. Re-rendered the final app and opened both combined comparisons. No actionable P0/P1/P2 visual finding remains in these rendered states.

### Required fidelity surfaces

- **Fonts and typography:** native system font, 13-point control labels, 15-point app name and 16-point Style heading retain the reference's weight hierarchy at a compact native size. Labels and wrapped Style explanations are readable without truncation in the observed states.
- **Spacing and layout:** a stable charcoal main bar and a narrower detached tool strip follow the selected hierarchy. The main host is 892–893×70 points, including shadow padding; the annotation host is 551×62. At 760 points the main bar splits to 515×108 and the annotation strip stays readable. The settled host/content sizes match, including returning to wide layout. The Style popover sits below the selected rectangle. Both bars disappear when pinned.
- **Colours and tokens:** opaque charcoal, white labels, pink active mode and a quieter pink subordinate selection follow the reference. Annotation pink now uses the same accent. Transparent remains a labelled checkerboard choice; nothing samples the screen for colour or contrast.
- **Image quality and assets:** this surface needs no raster assets in the app. Standard SF Symbols and native editable controls supply the reference's icons and shapes. The underlying browser documentation page belongs to the measured app, so it is represented by a synthetic contrast fixture rather than added to Guides.
- **Copy and content:** Pin & work includes “Click through to your app”. Only relevant units/scale or annotation controls are shown. Style preserves explicit Screen pt stroke units, all palette choices, spotlight defaults, dimming, Delete, and Apply/Cancel. Clear Annotations is in Tools. The shorter annotation hint focuses on the current gesture, pinning and Escape; keyboard behavior and accessibility help retain selection/nudge/delete shortcuts.

Intentional native adaptations: the app keeps its smaller native control size and automatic Select-after-drawing behavior; the mock leaves Rectangle active. Style is taller because existing dimming, defaults, caveat and atomic Apply/Cancel remain available. The reference's decorative drag grip is omitted because the toolbar keeps the existing automatic placement behavior. These differences preserve working behavior and avoid false affordances.

### Validation and limits

The native Debug build and all 127 existing core tests pass. The DEBUG fixture opens a real NSPopover and asserts opening/reopening plus dismissal after selection change, tool switch and Pin. Both strips are rendered at 1440 and 760 points, including the compact-to-wide transition. These are native view/controller checks, not physical input tests.

Live automation attached to an older running copy and returned its old control tree. Its Escape/Hide calls produced no reported change, so it supplies no interaction evidence for this build. Pointer/keyboard operation, popover Apply/Cancel and palette interaction, VoiceOver, real display changes and full-screen/Stage Manager remain manual checks in [TESTING.md](TESTING.md). The comparison passes the rendered design scope; those interaction/platform limits remain explicit.

Implementation checklist: selected structure implemented; native rendering and controller lifecycle checked; visual findings fixed and compared again; exact staged independent review remains the commit gate.

final result: passed

## Previous reviews (retained)

Source: [selected Option 2](docs/design/focus-rail.png). Implementation is native AppKit/SwiftUI, using system fonts and SF Symbols. No website or simulated dashboard was added.

## Comparison history

1. Compared the saved reference and native overlay screenshots inline in the same computer-use call. The toolbar and separate selected-gap readout followed the charcoal/pink direction. Found compressed Guides/Area labels; fixed their intrinsic sizing. A pure layout test also found a top-edge toolbar collision; added a clearance fallback.
2. Rebuilt and compared the reference with the final native toolbar on 5 November 2026. Guides, Area, Screen pt, Set scale, Pin & work and Hide are fully visible. Both rulers retain full-length numbered ticks. The final screenshot used the user's Transparent appearance; Solid was observed in the earlier comparison.
3. Clicked Pin & work and observed all interactive controls removed from the accessibility tree. Earlier native checks confirmed Finder input underneath the pinned overlay.

Evidence: screenshots were displayed inline by computer use; no saved native capture path is available. The source is 1536 × 1024; native captures reflect the current display/backing scale (including 7680 × 3240). Comparison is by component proportions and appearance, not a pixel-diff claim. Transparent regions flatten to white in per-app captures.

## Result

Passed for the toolbar, ruler appearance and observed selected-gap readout. Charcoal surfaces, pink tool/guide accents, separated Copy readout and native controls are implemented. No actionable visual defect remains in the observed surfaces.

Intentional adaptations: compact native sizing, a second toolbar row on narrow displays, area Width/Height/Both choices, and clearer Pin & work wording. The mock's triangular readout pointer is omitted; the connector and nearby placement retain association.

Remaining manual coverage: area readout interaction, final Copy round trip, physical global shortcut toggle, narrow display rendering, busy backgrounds and full VoiceOver. Concurrent desktop input interrupted further automated gestures. These are recorded as limitations, not visual passes.

## Visual overhaul (9 November 2026)

Source: the user's request for a clearer, better-looking interface and a report that Transparent ruler numbers were unreadable. The charcoal/pink direction above is retained.

Method: the DEBUG `--design-snapshots <directory>` launch argument renders the overlay and each tool window from the app's own views over a synthetic light/mid-blue/dark backdrop. Before and after renders were compared side by side. Reference renders: [guides, solid rulers](docs/design/overhaul/guides-solid.png), [transparent rulers](docs/design/overhaul/guides-transparent.png), [toolbar with annotation row](docs/design/overhaul/toolbar-annotate.png), [hint bar](docs/design/overhaul/hint-bar.png) and [tool window](docs/design/overhaul/tool-window.png).

Findings fixed during comparison: transparent ticks first rendered as doubled lines on light content (dark halo around a white core), corrected to a dark core over a light halo; the Settings window clipped its last section, corrected by a taller window; toolbar heights were raised for the segmented tracks. Independent review then found the restyled toolbar 64 points wider than its fixed 1000-point host; the toolbar now hugs its content, and the snapshot run prints host and content widths so a recurrence is visible. It also forces a two-row to one-row transition and reports the settled width, which exposed and now guards a one-turn-stale width.

Not covered by renders: popovers, menus, hover, compact displays, light appearance and VoiceOver. See TESTING.md.
