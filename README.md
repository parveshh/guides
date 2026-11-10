# Guides

A native macOS menu bar utility for manual desktop guides, area measurements, inspecting supplied image files, and resizing windows. This is a local, personal app. It does not inspect CSS or Figma layers. Its optional corner magnifier uses Screen Recording access for a live, in-memory desktop crop; ordinary measurements need no permission. The optional window tool reads the chosen window’s title and frame through macOS Accessibility.

## Build and run

Use an Apple Silicon Mac with Xcode 26 or later providing Swift 6.2 or later. The deployment target is macOS 14; older OS versions and Intel Macs have not been validated. Select the full Xcode installation as the active developer directory. Initial package resolution requires network access; the app itself uses no network.

```sh
./scripts/test.sh
./scripts/build.sh
```

Open `build/DerivedData/Build/Products/Debug/Guides.app` in Finder, or open `Guides.xcodeproj`, choose the Guides scheme and My Mac, and run. The ruler icon appears in the menu bar. Opening the running app again from Finder opens its editor. This Debug build is locally signed for development; public distribution and notarization are outside this MVP.

KeyboardShortcuts is pinned to 3.0.1 in the Xcode workspace's resolved package file. The measurement core is a local Swift package with no external dependencies. Build output and caches stay in the ignored `build/` folder.

## Measure

1. Choose **Edit Guides** from the menu bar, or use **Control–Option–G**. Editing opens on the display under the pointer.
2. Pull down from the top ruler for a horizontal guide, or right from the left ruler for a vertical guide. Adjacent distances appear automatically. Click a distance to select it; a nearby readout shows its value and **Copy**. Shift-click two parallel guides to measure their total separation.
   A guide is a zero-width position at the centre of its line, and a gap is the difference between two positions; the line's width never enters the value. Guides and Area edges placed with the pointer snap to whole backing pixels, so they sit on a pixel boundary. Hold **Control** while dragging to place freely. While you drag, the line drops its dark halo so the pixels beside it stay visible. Snapping does not detect on-screen edges; you still line it up by eye.
3. Choose **Area** and drag a rectangle. Drag inside to move it; drag an edge or corner handle to resize it. Drawing elsewhere replaces the area in one undoable action. Choose Width, Height, or Both in the nearby readout before copying.
4. **Pin & work** keeps measurements visible and passes mouse and keyboard input to the app underneath. **Hide** removes the overlay. Use the activation shortcut again to edit retained measurements. While editing, the same shortcut pins them.

The compact charcoal toolbar keeps editing controls in one row when the display’s usable width is at least 1120 points, and two rows otherwise: a **Tools** menu, the Guides/Area/Annotate tools with icons, unit and scale, grid, reference image, undo/redo, then **Pin & work** and **Hide**. Selected tools and guides use pink; the selected measurement and Copy live in a separate nearby readout. A hint bar at the bottom of the display names the current tool and shows its keys, including your activation shortcut. Pin & work hides both interactive surfaces. Editing captures clicks across the display; pin or hide to interact with other apps.

Both rulers label screen-point coordinates every 100 points; vertical labels rotate to fit the narrow strip. Open the **Tools** menu in the toolbar or **Settings → Rulers** to choose **Solid** or **Transparent**. Transparent removes the ruler background; each number keeps its own dark chip and each tick a light halo, so both stay readable over light, dark and busy content. The choice applies to both rulers immediately and is saved locally; Solid is the default.

| While the canvas has keyboard focus | Action |
| --- | --- |
| H / V | Add a horizontal / vertical guide at the pointer |
| [ / ] | Select previous / next guide or area |
| Shift + [ / ] | Extend selection to a parallel guide; continue to select a nonadjacent pair |
| Arrow | Move selection by 1 screen point |
| Shift + Arrow | Move by 10 screen points |
| Option + Arrow | Move by 1 backing pixel |
| Control + drag | Place a guide or Area edge without pixel snapping |
| Delete | Delete selection |
| Command-C | Copy selected measurement |
| Command-Z / Shift-Command-Z | Undo / redo |
| Escape | Cancel a partial gesture, otherwise hide |

Click the canvas or an accessibility measurement element to focus measurement keys. Toolbar and text fields retain their normal native keyboard behavior. The accessibility tree exposes guide positions, selectable gaps, and the area; guide elements include a **Select with current guide** action for pairs. Full VoiceOver use still needs manual validation.

## Units and calibration

- **Screen pt** means macOS logical points. It is deliberately copied as `32 screen pt`, not CSS `pt`.
- **Backing px** means pixels in the overlay's backing coordinates, which need not equal physical panel pixels.
- **Design px** and **rem** require explicit calibration. Set the view scale (100% means one screen point per design pixel), or select a gap/area dimension and supply its known pixel size. Update calibration whenever the measured app, canvas zoom, or browser zoom changes.
- **rem** divides calibrated pixels by the root font size. The default is 16px, configurable in Settings or calibration and saved locally.

For example, 64 screen points at 200% scale is `32px`, or `2rem` with a 16px root. The app measures visible boundaries; it cannot infer exact padding, layout tokens, or source properties.

### Copy as CSS or Tailwind

Next to **Copy**, the readout's **Copy as** menu copies the selected measurement as a CSS declaration or a Tailwind arbitrary-value class. Each menu item shows the exact text it copies.

| Selection | CSS | Tailwind |
| --- | --- | --- |
| Guide gap | `gap: 24px;` | `gap-[24px]` |
| Area Width | `width: 320px;` | `w-[320px]` |
| Area Height | `height: 48px;` | `h-[48px]` |
| Area Both | `width: 320px;` and `height: 48px;` on two lines | `w-[320px] h-[48px]` |
| Area Radius | `border-radius: 8px;` | `rounded-[8px]` |

These always use explicitly calibrated values: design px, or rem when the unit is rem, at the precision the readout shows. With Screen pt or Backing px selected they still copy design px. Until you use **Set scale** the menu offers nothing to copy and says why. Tailwind output never uses named scale classes such as `w-80`, because Guides cannot see your theme. The text is a formatted manual measurement, not an inspected CSS property; in particular a guide gap is offered as `gap` only as a starting point, since it could equally be a margin or padding. **Copy** and Command-C are unchanged.

Only one display is active at a time. Each display retains its own in-memory measurements, history, and calibration. Disconnecting a display or changing its logical size/backing scale clears that display's session and hides its overlay. Rearranging displays preserves their local measurements. Sleep hides the overlay; wake rechecks display configuration. Quitting starts all measurements and calibration fresh; the shortcut, root font size, ruler appearance, spacing-scale preferences and explicitly saved layouts remain. Layouts never load automatically.

## Measure rounded corners

Choose **Measure Corner Radius** from the menu bar, or draw/select an **Area** and choose **Radius** in its readout. Fit the Area’s bounds to the visible window or panel edges, excluding its shadow. Enter a radius in **screen points** and choose **Apply**, or use **− / +** for one-point adjustments until the rounded outline matches the corner. Decimal values are supported. Copy returns the radius in the selected measurement unit; Design px/rem require explicit calibration. For example, a 32-screen-point radius at 200% calibration is 16px, or 1rem with a 16px root.

This fits equal circular arcs at the four corners. Treat it as a manual estimate when the actual shape uses continuous curves or unequal/elliptical corners. Radius ranges from zero (square) to half the shorter Area side. Moving retains it; shrinking the bounds caps it to the new limit, and drawing a replacement Area starts at zero. Undo/redo, deletion, Pin & work and saved layouts include the radius. Width/Height/Both still report the bounds; radius mode has no spacing-token suggestion. Saved libraries are written as version 2; version 1 libraries still load with square Areas, while older app builds reject version 2 instead of dropping the radius.

Use **Border** to make the outline see-through (35% by default) or hide it completely at 0%. Handles and readouts stay visible. This viewing preference lasts only for the current run and is not saved in layouts.

Choose **Magnifier…**, select a corner and **4× / 8× / 16×**, then **Start Magnifier**. If needed, use **Request Screen Recording…** and allow Guides in macOS settings, then **Check Access**; macOS may require a relaunch. Access is optional and is never requested at launch. The preview excludes Guides itself, magnifies the desktop with a fitted pink curve, and provides **±0.25 screen-point** radius and bounds-position adjustments. Zoom is measured in screen points; backing pixels remain distinct.

Capture runs only after Start while the preview is open. Stop, Close, changing tools/selection, hiding/pinning, display changes and sleep stop it and discard the image. Reopening does not resume capture. Images stay in memory and are never saved, copied or transmitted. Ordinary radius fitting remains available without Screen Recording.

## Save layouts

Choose **Saved Layouts…** from the menu bar or toolbar’s **Tools** menu. Name the current setup and choose **Save Current**. This saves the active display’s guides, measured Area, grid, annotations, colours (including Transparent), style defaults and spotlight/dimming. Names are trimmed, 1–80 characters and unique ignoring case. Saving creates a snapshot; later canvas edits do not update it automatically.

Select a saved entry to **Load Layout**, **Rename** or **Delete** it. The list shows its screen-point size, backing factor and content counts. Loading requires exactly the same screen-point dimensions and backing factor; another display with those properties can load it. Geometry is never scaled to fit. Loading replaces guides/Area/grid/annotations, clears tool histories and selection, and resets units to Screen pt and calibration to unconfirmed. Design px/rem grids pause until you use **Set scale** again. Reference images and global preferences are unaffected.

**Undo Layout Load** restores the setup, calibration and tool histories from before the latest load in this run, discarding subsequent canvas edits. It preserves the current reference image and global rem base. Recovery applies only to its original display and is cleared if that display’s size/backing factor changes or it disconnects. Ordinary Command-Z handles edits made after loading. **Undo Delete** recovers the most recently deleted layout during this run, provided its name and library capacity are still available.

The library is stored locally at `~/Library/Application Support/Guides/layouts.json`, with atomic writes. Limits are 100 layouts, 1000 guides and 1000 annotations per layout, and 8 MiB total. An unreadable, invalid or newer-version library is retained and blocks changes; correct the file externally, then use **Retry**. Relaunch always starts with an empty overlay and fresh calibration. Saved layouts do not include reference files, calibration, preferences or project profile settings; there is no sync or import/export UI.

## Switch project profiles

Choose **Project Profiles…** from the menu bar or toolbar’s **Tools** menu. Enter a name and choose **Save Current** to store the current rem base and spacing tokens with their tolerance. Select a profile and choose **Apply Profile** to replace both settings together; **Undo Apply** restores the values from before the latest apply during this run, replacing any rem-base or token edits made since that apply. A profile that already equals the current settings is labelled as matching. Rename and Delete act on the selected profile, with one-level **Undo Delete**.

Profiles are snapshots: editing the rem base or tokens afterwards does not change a saved profile, and nothing is applied at launch. Applying does not touch measurements, calibration scale, ruler appearance or saved layouts. Opening Project Profiles closes an open Spacing Tokens editor and discards its unsaved draft, and the reverse.

The library is stored locally at `~/Library/Application Support/Guides/profiles.json`, with atomic writes, limited to 50 profiles and 2 MiB. An unreadable, invalid or newer-version library is retained and blocks changes; correct the file externally, then use **Retry**. There is no sync or import/export UI, and profiles never read a repository, CSS file or design file.

## Compare spacing tokens

Choose **Spacing Tokens…** from the menu bar or toolbar’s **Tools** menu. Enter one declaration per line, such as `--space-2: 8px;`, or choose **Use Example**, then **Save Scale** (Command-S). Standard Select All, Copy, Cut, Paste, Undo/Redo and Close shortcuts work in this editor. Closing or **Cancel** discards unsaved edits; **Clear Draft** followed by Save removes the scale.

Use up to 64 tokens with nonnegative decimal `px` values (0–1000000). Names start with `--` and an ASCII letter or underscore, followed by ASCII letters, digits, underscores or hyphens, up to 64 characters total. Names are case-sensitive and unique; equal-valued aliases are allowed. This accepts a declaration list, without selectors, braces, comments, `rem`, expressions or CSS-file imports. The scale and tolerance are saved locally.

Select a guide gap or an area’s **Width** or **Height** and explicitly set its calibration. The nearby readout compares the unrounded measurement in design pixels against your scale, even if the measurement display uses Screen pt, Backing px or rem. It shows an exact or nearest suggestion and the difference from that token. The tolerance is an absolute distance in design pixels, initially 1; 0 requires an exact match and 100 is the maximum.

**Copy Variable** copies a reference such as `var(--space-2)` for a unique nearest match within tolerance. Ties, aliases with the same value and outside-tolerance suggestions cannot copy a variable automatically. **Copy** and Command-C still copy the measured value. Suggestions compare your supplied scale with a visual measurement; they do not inspect the app’s CSS or identify its actual design tokens.

## Annotate and spotlight

Choose **Annotate** in the toolbar or menu bar. Select **Arrow**, **Line**, or **Rectangle** and drag on the active display. A finished shape switches to **Select**: drag its body to move it, its endpoints to edit a line/arrow, or the eight handles to resize a rectangle. Use brackets to cycle through shapes, arrows to nudge, Shift for 10 screen points, Option for one backing pixel, and Delete to remove the selected shape.

Click a **Colour swatch** in the annotation toolbar to immediately recolour the selected rectangle, line or arrow and set the colour for new shapes. Pink, Yellow, Cyan, White, Orange and **Transparent** are available; a checkmark identifies the selected colour. Choosing Arrow, Line or Rectangle deselects the previous shape, so the swatches show and change the colour for your next drawing. With no shape selected, only the new-shape colour changes. Colour changes preserve stroke width and spotlight settings and support Command-Z/Shift-Command-Z for the selected shape.

The checkerboard **Transparent** swatch hides the annotation stroke, including its outline, while keeping the shape editable and any rectangle spotlight active. Selected shapes still show editing handles; Pin & work hides those handles. Use the bracket keys to select an invisible shape and choose a visible colour to show it again.

New rectangles are spotlights by default: their interior stays live and undimmed while the exterior darkens. Only one rectangle is the active spotlight; a new spotlight replaces that assignment without removing older shapes. **Style & spotlight…** also offers the colour palette, 2/4/6-screen-point strokes, a spotlight toggle, and 0–80% exterior dimming (initially 55%). Apply updates the selected shape and style defaults; Cancel discards the draft. With no selected rectangle, the spotlight toggle controls new rectangles. The toolbar moves outside the spotlight when there is room, after the drag ends.

Command-Z and Shift-Command-Z undo/redo annotation changes in Annotate mode. Each drag or applied style/dimming change is one action; history retains up to 100 actions. **Clear** in the annotation row clears only annotations and spotlight. Guide/Area measurements, calibration, grid and reference image remain independent; measurement undo resumes when you choose Guides or Area.

**Pin & work** keeps shapes and dimming visible while input passes through the entire overlay, including the spotlight. Editing captures input inside the clear region too. Escape first cancels an unfinished gesture, otherwise hides the overlay. Hide retains annotations; quitting or invalidating a display discards that display's session. Annotations stay in display coordinates and do not track windows. No capture or additional permission is used.

## Use a spacing grid

Open the **grid icon** in the editing toolbar, enable **Show grid**, and set square-cell spacing, unit, origin and opacity. **Apply** updates the grid; **Cancel** discards changes. The ruler tools menu also offers **Show Grid / Hide Grid**. The origin marker and bottom badge identify the grid's spacing and position.

Grid units are independent of the measurement readout. Design px and rem require **Set scale** first; changing calibration or the rem base changes those grid cells around their fixed origin. Origin X/Y are always screen points from the active display's top-left corner. For example, 8 Design px at 200% scale makes 16-screen-point cells. Backing px uses the active display's backing factor.

Spacing must be positive and no more than 1000000 in the chosen unit; opacity is 10–80%. To avoid an unreadably dense overlay, the resulting spacing must be at least 4 screen points and generate no more than 2048 lines per axis. If a later calibration change exceeds those limits, a **Grid paused** badge explains how to recover. No grid lines are silently omitted.

Guides and Area stay usable without snapping to the grid (they snap only to backing pixels). **Pin & work** keeps the grid visible and passes input to the app below; **Hide** removes the whole overlay. Clear Measurements and measurement undo leave the grid alone. Grid settings are kept per display for the current session; quitting or invalidating a display starts its grid fresh and hidden.

## Align a reference image

Open the **Reference image** button (overlapping photos) in the editing toolbar, then **Open Image…**. Choose one local raster image. It starts centered, fitted within 80% of the display without upscaling, at 50% opacity. PNG/JPEG/TIFF/GIF/HEIC and other Image I/O raster formats use their orientation-correct primary image; animated files do not animate. Invalid or cancelled replacements keep the previous reference.

Reopen the reference controls to set **X**, **Y**, **Width** in screen points, and **Opacity** (10–100%). The aspect ratio stays fixed; both displayed dimensions must be 1–32768 screen points. Negative positions allow cropping at display edges while keeping at least one point visible. **Fit to display** resets the draft; **Apply** saves it and **Cancel** discards it. These dimensions describe the displayed reference, independently of source image pixels, image DPI, backing scale and measurement calibration.

**Apply & align on canvas** enables dragging the reference and arrow-key nudging. Shift moves 10 screen points; Option moves one backing pixel. Command-Z/Shift-Command-Z undo/redo reference placement in alignment mode, with one action per drag. Escape cancels a drag, then exits alignment; choosing **Guides** or **Area** returns to measuring. Measurement undo remains separate. Replacing/removing an image resets its placement history and cannot itself be undone.

**Show reference** can hide the image without removing it; **Remove Reference** removes only the image. Grid and measurements draw above it. **Pin & work** keeps the reference visible while input goes to the underlying app, and **Hide** hides the whole overlay. Each display keeps its own reference for this run; quitting or invalidating the display discards it. No image paths or placements are saved.

Input is limited to 100 MiB; the rendered preview is bounded to 4096 pixels on its longest edge and may look softer when enlarged. This is a manual visual reference, not a pixel-diff or inspected CSS property. Importing requires no capture or Accessibility grant.

## Inspect an image

Choose **Inspect Image…** from the menu bar or the toolbar’s **Tools** menu. Use **Open Image…** (Command-O), drop one local image into the window, or choose **Paste Image** (Command-V). Finder file copies preserve original file metadata; image-only clipboard copies are explicitly labelled as a clipboard representation, whose format and size can differ from the original file.

The inspector shows original pixel dimensions with orientation applied, aspect ratio, format, byte size, and alpha-channel presence. **Copy Dimensions**, **Copy Width**, and **Copy Height** copy those values. DPI, desktop zoom, and ruler calibration do not change them. The preview is scaled; it is not an on-screen size measurement. An alpha channel indicates the ability to store transparency, not whether individual pixels are transparent.

Imports use macOS Image I/O (including PNG, JPEG, TIFF, GIF and HEIC), up to 100 MiB per input. Multi-image files show only their primary image and total image count, without animation. SVG/PDF, remote URLs, file promises, and batch inspection are outside this slice. An import error retains the previous image. **Clear**, closing the window, or quitting discards it; images and file paths are not saved. The inspector reads only supplied inputs, with no capture permission or network feature. The app now runs outside App Sandbox to support optional window resizing.

## Resize a window

Choose **Resize Window…** from the menu bar or the toolbar’s **Tools** menu. Select an app and **Use App’s Front Window**. Check its title, enter width and height in **screen points** (or choose a preset), then **Resize Window**. The tool reads back the accepted size and reports constraints. **Restore Previous Frame** restores the size and position saved before the latest resize attempt on that same window. Refreshing the target or closing the tool discards its recovery session.

A 2560 × 1440 window includes browser toolbars and borders. It is not a 2560 × 1440 CSS viewport or a monitor-resolution change. Browser zoom and display scaling also affect that comparison. Use browser responsive design tools when the requirement is an exact website viewport. Apps may restrict large or small windows; Guides reports the actual result.

Window resizing requires **Guides** to be enabled in **System Settings → Privacy & Security → Accessibility**. Use the tool’s **Request Accessibility Access** button, grant access yourself, then **Check Access**. This locally signed development build may lose access after rebuilding. If the switch is on but Check Access still reports denied, remove only Guides from the privacy list, use + to add the current `build/DerivedData/Build/Products/Debug/Guides.app`, enable it, then Check Access again. On the tested macOS 27 system, the privacy list is named **Device Control and Data Access**. Measurement and image tools remain usable without this permission. The user-selected packaging is one app outside App Sandbox, with no network features; the separate corner magnifier is the only optional capture tool. Existing known local preferences are imported once from the former sandbox store without overwriting newer values.

## Verification and scope

See [TESTING.md](TESTING.md) for executed checks and the remaining manual acceptance matrix, including global-shortcut reliability, mixed displays, full-screen/Spaces/Stage Manager, sleep/wake, and VoiceOver. A successful build is not evidence that those hardware scenarios passed.

[PLAN.md](PLAN.md) contains the product stories, research, seven implementation slices, and later expansion ideas. [AGENTS.md](AGENTS.md) requires current documentation through Context7 and an independent read-only review of every exact commit snapshot. No screenshot/export tools beyond the optional in-memory corner magnifier, integrations, accounts, billing, or public release infrastructure are included.
