# Guides native design QA

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
