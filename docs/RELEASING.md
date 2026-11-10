# Building a preview release

The downloadable preview is a universal Release build for macOS 14 and later. It includes Apple Silicon and Intel code. It is ad hoc signed, without a Developer ID identity or notarization ticket. Do not describe it as notarized or as a signed installer.

## Build and check

Use Xcode 26 or later with Swift 6.2 or later, selected as the active developer directory.

```sh
./scripts/test.sh
./scripts/release.sh
```

The script builds both architectures, verifies the bundle signature, packages the app with `ditto`, extracts it and verifies the extracted copy. It writes a versioned ZIP and SHA-256 checksum to the ignored `build/releases/` folder. The version comes from `Config/Info.plist`. It does not create a tag or upload anything.

Before publishing, inspect the ZIP contents, confirm the app version/minimum OS and both binary architectures, check that DEBUG-only fixture code is absent, and launch the extracted app on available hardware. Record the actual checks and limits in `TESTING.md`. A local launch does not validate a browser download's Gatekeeper prompt.

## Publish

Follow the repository's independent review and commit gates first. Push the reviewed commit and a matching version tag using normal pushes. Create a draft GitHub release from the existing remote tag, attach the ZIP and checksum, and use the matching file in `docs/releases/` as its notes. Check the uploaded asset names, sizes and hashes before publishing it as a **pre-release**. Do not overwrite an existing published version.

Keep the download and first-open instructions in the README and release notes consistent with the actual signing status. This preview uses Apple's per-app **Open Anyway** flow; never disable Gatekeeper or remove quarantine in the packaging script. Future Developer ID signing/notarization needs a valid certificate and the owner's Apple Developer credentials; none are stored in this repository.

References: [Apple packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [universal macOS binaries](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary), [opening apps safely](https://support.apple.com/en-us/102445), and [GitHub CLI releases](https://cli.github.com/manual/gh_release_create).
