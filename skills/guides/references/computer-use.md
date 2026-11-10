# Computer use

Use the session's supported computer-use API and its returned documentation. Prefer attaching to the exact running `appPath` returned by CLI `status` or `launch`, using `cua.getApp(verifiedAppPath)` with `cua_repl`. If CLI access is unavailable, inspect the computer-use app inventory and attach to the existing Guides app before considering a launch. Avoid opening a different installed/downloaded/development copy, and never use a force-new-instance option. Inspect the returned accessibility state before acting. Fetch fresh state after actions and use screenshots for visible alignment; do not reuse old element indexes or hard-code screenshot coordinates. Do not substitute shell-driven UI scripting when computer use is available.

Guides is a menu-bar app without a Dock icon. The ruler menu's **Edit Guides**, **Measure Area** and **Annotate** activate their tools on the pointer's display. The default activation shortcut is Control–Option–G, but it is configurable and toggles Editing/Pinned. Prefer an explicit tool/menu or CLI `show` if the current state or shortcut is uncertain. Reopening the app can enter editing.

## Measure and calibrate

1. Arrange the target view before activating Guides. Check the active display; Guides uses one display at a time. Read the screenshot tool's coordinate conventions before using coordinates as screen points; backing-scaled images are not automatically logical points.
2. For a gap, drag down from the top ruler for horizontal guides, or right from the left ruler for vertical guides. H/V adds at the pointer while the canvas has focus. Align the line centers to the visible edges, excluding shadows when measuring bounds. Click a gap to select its cyan pair; Shift-click parallel guides for a nonadjacent pair. For supplied coordinates, the CLI is more precise than dragging.
3. For a box, choose **Area** and drag in either direction; move its body or resize with handles. Choose Width, Height or Both in the readout. Fit Radius manually for rounded corners; the fit assumes equal circular corners and is an estimate for other curves.
4. **Set scale…** opens View scale / Known size. Enter the supplied percentage, or select a gap/Area width or height and enter its known design-pixel size. Check the rem base and Apply. Select **Unit** afterward if necessary. Never apply 100% merely to enable copying.
5. Read the selected value and context. **Copy**/Command-C copies plain output; **Copy as** offers calibrated CSS/Tailwind. **Copy Variable** needs a unique token match. CLI `read` is useful for verification without overwriting the user's clipboard.

Arrow keys move selected geometry 1 screen pt, Shift moves 10 pt, Option moves 1 backing px. Delete removes selected geometry. Command-Z/Shift-Command-Z undo/redo in the active tool. Brackets cycle selection; Shift-brackets extend a parallel pair. Click the canvas for editing keys, keeping text fields' normal behavior in mind.

Drag a width gap's label up/down or a height gap's label left/right to move only the label and nearby Copy panel. The guide positions/value stay fixed. Escape cancels a drag; otherwise it hides, or first exits reference alignment.

## Other existing tools

| Goal | Current route and important behavior |
| --- | --- |
| Annotate or spotlight | Annotate → Arrow/Line/Rectangle → drag. Drawing switches to Select. Rectangle spotlight is on by default; Style changes stroke, spotlight and outside dimming with Apply/Cancel. Only one active spotlight. Transparent hides strokes while retaining editability and spotlight |
| Grid | **Grid settings** in the smaller strip for Guides/Area. Spacing/unit/origin/opacity apply together; origin is screen points. Design/rem needs calibration; dense or invalid grids pause |
| Reference image | **Reference image** → Open Image…; choose one supplied local raster. Adjust position, aspect-preserving width/opacity, then Apply or Apply & align on canvas. Escape exits alignment; reference does not track windows |
| Spacing tokens / breakpoints | Tools → Spacing Tokens… / Breakpoints…. Enter plain declarations or named px widths, then save. No stylesheet import. Breakpoint ruler zero is the display's left edge |
| Profiles / layouts | Tools → Project Profiles… / Saved Layouts…. Applying profiles changes explicit global settings. Layout loads replace geometry only on a matching display and reset calibration; Undo Layout Load is separate from ordinary undo |
| Inspect local image | Tools → Inspect Image… → Open Image / drop one / Paste Image. Source pixels and EXIF orientation are independent of the scaled preview; encoded input limit is 100 MiB. No remote URL or batch import |
| Resize a chosen window | Tools → Resize Window…. Use its dedicated Accessibility button only when authorized and needed, choose app and Use App’s Front Window, verify title, apply size, then read accepted size. Restore Previous Frame recovers the last attempt. Whole-window screen points include browser chrome |
| Optional corner preview | Area → Radius → Magnifier…. Dedicated Request Screen Recording… / Check Access if needed; explicitly Start Magnifier. Stop/close when finished; capture stops on pin/hide/tool/display changes. Never export the preview |

Useful accessibility labels include **Measurements**, **Guides**, **Area**, **Annotate**, **Tools and ruler appearance**, **Unit**, **Set scale…**, **Grid settings**, **Reference image**, **Copy as CSS or Tailwind**, **Pin & work**, and **Hide**. Treat these as discovery hints; the current observed tree is authoritative. Menus/popovers can renumber controls. Follow the computer-use API's completion-summary requirement when that part of the work is finished.

End with **Pin & work** if visible marks should remain, or **Hide** when done. Pin makes the entire overlay click-through, including a spotlight's clear interior and dimmed exterior. Verify the outcome and report any unresolved placement uncertainty.
