# Guides

A small macOS menu bar app for measuring and marking what you see on screen.

Place guides, measure an area, copy a value, then **Pin & work** to keep the overlay visible while using the app underneath. Useful when checking a browser, a design, an image or a desktop interface.

![Guides with a selected width measurement and its Copy panel](docs/screenshots/guides.png)

*Native app views on a sample background. Selected guides and their measurement are cyan.*

## What it does

- **Measure spacing:** place horizontal or vertical guides and read the gaps between them.
- **Measure an area:** read width, height and a manually fitted corner radius.
- **Move measurement labels:** drag a width label up/down or a height label left/right without moving its guides.
- **Copy for development:** plain values, CSS declarations, Tailwind classes and matching spacing-token variables.
- **Mark a detail:** draw arrows, lines or rectangles; use a rectangle as a spotlight.
- **Compare and reuse:** a spacing grid, local reference images, saved layouts, project profiles and breakpoint markers.
- **Use local tools:** inspect an image's dimensions or resize a chosen app window.

Guides measures visible distances manually. It does not read CSS, Figma layers or the source properties of another app.

## Download and open

Download the app ZIP from [Guides 0.1.0 preview](https://github.com/parveshh/guides/releases/tag/v0.1.0). Choose **Guides-0.1.0-macOS-universal.zip**, rather than the source-code archives.

The build includes **Apple Silicon and Intel** code and requires **macOS 14 or later**. Runtime checks were performed on Apple Silicon; Intel and older supported macOS versions still need testing. Xcode is not needed to run the download.

1. Unzip the download and drag **Guides.app** to **Applications**.
2. Quit any older copy of Guides, then open the installed app.
3. Look for the ruler icon in the menu bar. Guides has no Dock icon.

This preview is **ad hoc signed, not Developer ID signed or notarized**. macOS may block its first launch. If you trust this download, try opening it once, then use **System Settings → Privacy & Security → Open Anyway** and confirm **Open**. See [Apple's instructions](https://support.apple.com/en-us/102445). No security settings are changed by the app or build script.

The release includes a SHA-256 checksum and [release notes](docs/releases/0.1.0.md). To update, quit Guides and replace the app in Applications with the new copy.

## Build from source

You need **Xcode 26 or later with Swift 6.2 or later**. Select the full Xcode installation as your active developer directory. The development build script targets Apple Silicon; the release script builds both architectures.

```sh
git clone https://github.com/parveshh/guides.git
cd guides
./scripts/test.sh
./scripts/build.sh
```

Open `build/DerivedData/Build/Products/Debug/Guides.app` in Finder. A ruler icon appears in the menu bar; there is no Dock icon. You can also open `Guides.xcodeproj`, select **Guides → My Mac**, and run it in Xcode.

Initial dependency downloads need an internet connection. Guides itself has no network features.

To package the same universal preview locally, run `./scripts/release.sh`. It creates the app ZIP and checksum in `build/releases/` and does not publish them. See the [release build notes](docs/RELEASING.md).

## Your first measurement

1. Press **Control–Option–G**, or choose **Edit Guides** from the menu bar icon.
2. Pull guides from the top or left ruler onto the edges you want to compare.
3. Click a distance. Its two guides turn cyan; choose **Copy** in the nearby panel.
4. Choose **Pin & work** to click and type in the app underneath. Use the shortcut again to resume editing.
5. Choose **Hide** to put the overlay away.

For CSS pixels or rem, use **Set scale** first. The default **Screen pt** unit means macOS logical points, not CSS pixels.

Read the [usage guide](docs/USAGE.md) for controls, calibration, all tools and keyboard shortcuts.

## Things to try

| Use case | Workflow |
| --- | --- |
| Check spacing between two buttons | Place guides at the facing edges, select the gap and copy it. |
| Measure a card or dialog | Draw an Area; choose Width, Height or Both. |
| Check a rounded corner | Fit an Area to the bounds, then adjust Radius by eye. |
| Point something out during a review | Draw an arrow or spotlight rectangle, then Pin & work. |
| Check an image asset | Open Inspect Image to read and copy its original pixel dimensions. |
| Try a different window size | Choose a target in Resize Window, apply a preset and check the reported size. |

See [step-by-step examples](docs/USAGE.md#examples).

## Local data and optional access

Normal measurements, annotations, grids and supplied-image tools work without privacy grants.

- **Resize Window** optionally uses Accessibility access for the window you choose.
- **Corner Magnifier** optionally uses Screen Recording while you explicitly run the preview. Its images stay in memory and are never saved, copied or sent.
- Permissions are requested only from their tool's dedicated button.

Settings, spacing scales, breakpoints, profiles and saved layouts stay on your Mac. Measurements, calibration, label positions and reference images start fresh after quitting. Saved layouts load only when you choose them.

## Development status

Guides is an early preview. The core has **139 passing tests**, with native view and event-handler checks. Physical input, VoiceOver and some display/OS scenarios still need manual verification; see [TESTING.md](TESTING.md).

- [Usage guide and examples](docs/USAGE.md)
- [Validation and remaining checks](TESTING.md)
- [Product plan and roadmap](PLAN.md)
- [Implementation and review instructions](AGENTS.md)
- [Screenshot source notes](docs/screenshots/README.md)

The app uses Swift, AppKit and SwiftUI. Its geometry and editing core is a local Swift package; [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) is pinned to 3.0.1. Build output is kept in the ignored `build/` folder.
