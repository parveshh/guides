# Building a preview release

The downloadable preview is a universal Release build for macOS 14 and later. It includes Apple Silicon and Intel code. It is ad hoc signed, without a Developer ID identity or notarization ticket. Do not describe it as notarized or as a signed installer.

## Build and check

Use Xcode 26 or later with Swift 6.2 or later, selected as the active developer directory.

```sh
./scripts/test.sh
./scripts/release.sh
```

The script builds both architectures, verifies the bundle signature and CLI protocol marker, then packages **Guides.app**, the standalone **guides** launcher, **skills/guides** and **INSTALL.txt** with `ditto`. It extracts the package, verifies the extracted app, checks the launcher/skill and runs CLI help without starting the GUI. It writes a versioned ZIP and SHA-256 checksum to the ignored `build/releases/` folder. The version comes from `Config/Info.plist`; supply matching `docs/releases/VERSION.md` and `docs/releases/VERSION-install.txt`. It does not create a tag or upload anything.

Before publishing, inspect the ZIP contents, confirm the app version/minimum OS and both binary architectures, check that DEBUG-only fixture code is absent, and launch the extracted app on available hardware. Record the actual checks and limits in `TESTING.md`. A local launch does not validate a browser download's Gatekeeper prompt.

For the CLI release, also run `python3 scripts/test-cli.py /absolute/path/to/extracted/Guides.app`. It refuses an existing command server, uses a fresh test process and preserves pre-existing app sessions. Test both extracted launcher locations (`./guides --help` and `./skills/guides/scripts/guides --help`) from a folder without a source checkout or installed app dependency. Check that the copied skill tree matches the reviewed source and the ZIP retains executable permissions. An agent's execution sandbox may need its normal approval path to reach the local Mach port.

## Publish

Follow the repository's independent review and commit gates first. Push the reviewed commit and a matching version tag using normal pushes. Create a draft GitHub release from the existing remote tag, attach the ZIP and checksum, and use the matching file in `docs/releases/` as its notes. Check the uploaded asset names, sizes and hashes before publishing it as a **pre-release**. Do not overwrite an existing published version.

Use `--verify-tag`, `--draft`, `--prerelease` and `--latest=false` when creating the draft. Download its uploaded assets into a separate directory, verify the checksum and compare their hashes to the local reviewed artifacts before publishing with `--draft=false --prerelease --latest=false`. Verify the remote tag resolves to the release commit and the published release has the expected assets. Keep the existing signing status explicit.

Keep the download and first-open instructions in the README and release notes consistent with the actual signing status. This preview uses Apple's per-app **Open Anyway** flow; never disable Gatekeeper or remove quarantine in the packaging script. Future Developer ID signing/notarization needs a valid certificate and the owner's Apple Developer credentials; none are stored in this repository.

References: [Apple packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [universal macOS binaries](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary), [opening apps safely](https://support.apple.com/en-us/102445), and [GitHub CLI releases](https://cli.github.com/manual/gh_release_create).
