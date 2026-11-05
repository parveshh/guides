# Guides

A native macOS menu bar utility for manual desktop guides and area measurements. This is a local, personal MVP. It does not capture the screen or inspect CSS, Figma layers, or other apps' data.

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
2. Pull down from the top ruler for a horizontal guide, or right from the left ruler for a vertical guide. Adjacent distances appear automatically. Click a distance to select and copy it. Shift-click two parallel guides to measure their total separation.
3. Choose **Area** and drag a rectangle. Drag inside to move it; drag an edge or corner handle to resize it. Drawing elsewhere replaces the area in one undoable action. Choose Width, Height, or Both before copying.
4. **Pin** keeps measurements visible and passes mouse and keyboard input to the app underneath. **Hide** removes the overlay. Activate again to edit retained measurements.

| While the canvas has keyboard focus | Action |
| --- | --- |
| H / V | Add a horizontal / vertical guide at the pointer |
| [ / ] | Select previous / next guide or area |
| Shift + [ / ] | Extend selection to a parallel guide; continue to select a nonadjacent pair |
| Arrow | Move selection by 1 screen point |
| Shift + Arrow | Move by 10 screen points |
| Option + Arrow | Move by 1 backing pixel |
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

Only one display is active at a time. Each display retains its own in-memory measurements, history, and calibration. Disconnecting a display or changing its logical size/backing scale clears that display's session and hides its overlay. Rearranging displays preserves their local measurements. Sleep hides the overlay; wake rechecks display configuration. Quitting starts all measurements and calibration fresh; the shortcut and root font preference remain.

## Verification and scope

See [TESTING.md](TESTING.md) for executed checks and the remaining manual acceptance matrix, including global-shortcut reliability, mixed displays, full-screen/Spaces/Stage Manager, sleep/wake, and VoiceOver. A successful build is not evidence that those hardware scenarios passed.

[PLAN.md](PLAN.md) contains the product stories, research, seven implementation slices, and later expansion ideas. [AGENTS.md](AGENTS.md) requires current documentation through Context7 and an independent read-only review of every exact commit snapshot. No capture tools, integrations, accounts, billing, or public release infrastructure are included.
