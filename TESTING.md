# Guides verification

Run `./scripts/test.sh` for core tests and `./scripts/build.sh` for the native Apple Silicon Debug app. Xcode and Swift Package Manager need their normal compiler cache access and network access for the pinned package's initial resolution. The app is at `build/DerivedData/Build/Products/Debug/Guides.app`.

## Slice 2

- PASS: native Debug build; core presentation lifecycle test; code-signature validation and sandbox entitlement inspection.
- PASS: app launch from Finder and reopen into editing, without a Guides privacy prompt. The default hotkey was observed opening the overlay once, but targeted synthetic keyboard input is not a reliable global-hotkey test.
- PASS: Pin removes editing controls; a subsequent click selects an item in Finder underneath; arrow-key navigation changes Finder selection while the overlay remains pinned.
- UNVERIFIED: sustained global-hotkey reliability, visual screenshot of the transparent panel, full-screen/Spaces/Stage Manager behavior, other Mac models and OS versions. The native UI tool can inspect/click the panel's accessibility controls but reports no capturable window for screenshots. These remain final manual acceptance items, not claimed passes.
- Toolchain notes: Xcode's iOS simulator service mismatch is unrelated to this macOS target. App Intents metadata extraction is skipped because Guides has no App Intents dependency. No app-source compiler warnings remain.
- Review correction: Escape is routed at the editing panel before focused toolbar controls consume it, so it shares the canvas cancellation/hide path regardless of first responder. Native toolbar-focus verification remains a manual acceptance item.

Future slices add geometry and interaction tests here. Do not equate a successful build or a visible accessibility tree with a completed visual acceptance test.
