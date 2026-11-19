# Compare a Figma frame with a browser implementation

Use the existing Guides CLI and computer use. Keep a working list of the visible relationships in the requested frame or component. Each entry needs a component name, two identifiable edges and an axis. Use the same landmarks on both sides, for example “Account card, inner left border to avatar left edge.”

## Establish comparable views

1. Identify the design frame and implementation state. Match the content, breakpoint, expanded controls and scroll section. Compare the design frame width in design px with the implementation's content viewport width in CSS px. A tiled browser's outer width includes chrome. If tiling triggers another breakpoint, use responsive preview or compare the panes in succession at the target viewport. Flag any remaining differences in state or viewport.
2. Establish each pane's scale independently. Use a confirmed effective scale or a separately known span in that pane. For a known span, divide its measured screen points by its known design or CSS pixels. Record the landmark and scale for each pane. Choose a reference independent of the feature being tested. Calibrating the implementation against a card's *expected Figma width* would erase a real card-width defect. If scale evidence is missing, keep raw distances in screen pt and mark the px comparison unresolved.
3. Check the coordinate space of the computer-use view. A pane-local image needs a verified mapping to display-local screen points, including its origin and scale, before its edges can be passed to the CLI. If that mapping is unavailable, align the Guides rulers visually with the native computer-use route. Reobserve landmarks after scrolling, moving a window or switching sections. Recheck scale after zoom or display changes.

## Choose the measurement workspace

Read the running app’s `status`. With `state.guideGroups == true` and a group-capable launcher, use the [group CLI commands](cli.md#guide-groups). After showing the target display, list groups. Reuse a region only when its bounds and intended pane match. Otherwise create a non-overlapping region around each visible content pane and retain the returned IDs. A user can also draw each region using **+ Group**. If a create reply is uncertain, inspect the list and reconcile the new ID and frame before retrying.

Use each pane’s independently confirmed scale. For example, issue `group ID calibrate 200` for the Figma group and `group ID calibrate 100` for the implementation group, then `group ID unit design-px` for each. Omit the optional rem root to preserve the shared preference. When a pane has no confirmed scale, stay in screen pt. Subtract the group frame’s display x or y from each observed display coordinate before sending `group ID gap`. For each pair use `group ID read` and confirm the expected ID, scale and unit in the reply. Refresh the region and landmarks after moving or scrolling a pane.

## Measure the frame

Work from outside in. Inventory frame margins, section alignment and vertical gaps, then each component's four inner insets, width and height, row and column gaps, and icon-to-label spacing wherever the edges are visible. For repeated items, track each requested instance. If the user asks for every gap, continue through the requested frame section by section and list occluded, ambiguous, missing or unmatched items. A sampled row covers only that row.

For each entry, measure the design and implementation separately. Within each addressed workspace, use `gap vertical X1 X2` for a width or horizontal separation and `gap horizontal Y1 Y2` for a height or vertical separation. Two gap pairs also measure a box without replacing the user's existing Area. For alignment, compare offsets from corresponding parent edges. For text, name the visible ink edges when those are all you can see. Line boxes and transparent padding may have no visible edge.

**Older builds.** When native groups are unavailable, use the display workspace. In each successful gap reply, find the two `state.guides` whose IDs match `state.selectedGuideIDs`. The absolute difference between their `position` values is the distance in screen pt in any readout unit. This workspace has one calibration, so keep the two pane scales in the audit and divide each raw distance by its own scale. Leave the display calibration and rem preference intact. Verify the pair on screen. To avoid accumulating lines, undo a temporary gap immediately after recording it while it is still the latest edit and only when the session has had no intervening edits. Follow the [CLI reference](cli.md) for uncertain replies.

## Report and recheck

Report the signed difference as **implementation minus design**. A positive spacing delta means the implementation has more space. Use any tolerance the user supplied. Otherwise report the observed delta and flag edges whose placement uncertainty could change the conclusion. State both scales, the viewport and the measured, unresolved and outstanding counts. Never turn an unmatched or unreadable pair into a zero.

This example uses separately confirmed scales of 0.5 screen pt/design px and 1 screen pt/CSS px.

| Relationship | Figma | Implementation | Difference |
| --- | --- | --- | --- |
| Card inner border to avatar, horizontal | 12 screen pt → 24 px | 32 screen pt → 32 px | +8 px |
| Avatar to label, horizontal | 4 screen pt → 8 px | 8 screen pt → 8 px | 0 px |

If implementation edits are requested and its source is available, trace the discrepant relationship to the owning component or shared style before changing it. A visible +8 px inset alone cannot identify which declaration caused it. Reopen the same state and remeasure the affected rows and neighboring layout after the change. Report before and after values and any outstanding differences.
