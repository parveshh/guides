# Documentation screenshots

These images show Guides' actual AppKit/SwiftUI views on a neutral sample background. They are view-cache renders, cropped for readability. They are not ImageGen mockups or captures of the user's desktop. The app's normal capture permissions and behaviour are unchanged.

Generated on 10 November 2026. Sample measurements and the `--card: 320px;` token are fixture data, not properties inspected from another app.

| Image | Shows | Output size |
| --- | --- | --- |
| [guides.png](guides.png) | Selected 400-screen-point width, cyan guides, movable label and Copy panel | 940×496 |
| [area.png](area.png) | A calibrated 320×200 Area, width selected, and a matching sample token | 440×480 |
| [annotate.png](annotate.png) | Selected rectangle and Style controls; Spotlight is off | 380×675 |

## Regenerate the source renders

From the repository root, build the Debug app and run its local view fixture:

```sh
./scripts/build.sh
build/DerivedData/Build/Products/Debug/Guides.app/Contents/MacOS/Guides \
  --design-snapshots build/docs-snapshots --documentation-background
```

The fixture exits when finished. It uses a neutral background, fixed sample settings and a focused Area example. It skips settings/library windows. Without `--documentation-background`, the existing contrast-test bands and wider validation fixtures remain unchanged. Both options exist only in Debug builds.

The source images are 1440×1024, with one output pixel per screen point. Crop them using these pixel boxes, measured from the top-left corner as `(left, top, right, bottom)`. No resizing or colour changes were applied.

| Source under `build/docs-snapshots/` | Crop | Saved image |
| --- | --- | --- |
| `gap-label-width.png` | `(250, 24, 1190, 520)` | `guides.png` |
| `3-area-tokens.png` | `(580, 350, 1020, 830)` | `area.png` |
| `4-annotate-with-style.png` | `(530, 300, 910, 975)` | `annotate.png` |

The Style image composites the app's own popover content at its actual window position. The OS-owned popover shell and arrow are outside that content-view cache.
