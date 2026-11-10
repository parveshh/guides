# Guides repository instructions

## Product and implementation

- Read `PLAN.md` before starting work. Preserve the confirmed personal MVP: manual guides and area measurement, explicit calibration, one active display, local settings, and fresh measurements after relaunch.
- Deliver the implementation slices in order. Keep every app slice buildable and each commit focused.
- Use Swift, AppKit for desktop windows/input, and SwiftUI for controls and settings. Keep geometry, conversions, and editing state independent of window code.
- Distinguish macOS screen points, backing pixels, calibrated design/CSS pixels, and rem. Never present a visual measurement as an inspected CSS or Figma property.
- Keep measurement and local image tools usable without privacy grants. The user authorized one app outside App Sandbox with optional Accessibility access for the post-MVP window resize tool; request that permission only from its explicit button. The user subsequently authorized a live corner magnifier with optional Screen Recording access; request that access only from its explicit button, capture only while the magnifier is active, and never save or transmit captured images. On 2026-11-09 the user approved the full-stack toolset roadmap in `PLAN.md`: Group A (front-end loop) may be implemented without new permissions. Groups B (capture-assisted tools) and C (local environment and network tools) are roadmap entries only. Do not implement any of their slices until its permission, capture and network contract is recorded in `PLAN.md`, the user has explicitly confirmed that slice, and that authorization is recorded here; stop and ask after Group A, and never self-authorize. Do not add other capture, network use, integrations, accounts, billing, or public distribution features.
- Update `PLAN.md` when implementation evidence changes an approach or a slice is completed. Preserve unrelated user changes.

## Documentation through Context7

Use the `ctx7` CLI whenever external technical documentation is needed for a library, framework, SDK, API, CLI tool, or cloud service, including familiar technologies. Read local repository documentation directly. Pure refactoring, business logic, scripts, and code review do not require a lookup unless an external API question arises.

1. Resolve first: `npx ctx7@latest library <official-name> "<full technical question>"`.
2. Select the best match using name, relevance, source reputation, snippet coverage, and benchmark score.
3. Fetch: `npx ctx7@latest docs <library-id> "<full technical question>"`.
4. Use the fetched documentation. Use a version-specific ID from resolution results when appropriate.

- Always resolve first unless the user supplied a valid `/org/project` ID.
- Use specific, complete queries and official punctuation. Never send secrets or private project content.
- Run at most three Context7 commands per question.
- Run Context7 outside the default sandbox. For DNS/network failures from a sandboxed invocation, rerun outside it instead of retrying inside.
- On quota failure, report it and suggest `npx ctx7@latest login` or `CONTEXT7_API_KEY`. Do not silently replace documentation with remembered API details.
- If documentation is insufficient, identify the gap and verify it against authoritative primary sources or the installed SDK. Record material consequences in the plan.

## Mandatory independent review before every commit

These instructions explicitly authorize a separate review agent for each authorized commit. The reviewer is read-only and must not edit files or commit.

1. Inspect the complete intended diff and remove unrelated changes.
2. Run relevant validation. Documentation changes require content, consistency, and reference checks; code requires appropriate tests/builds and native checks when applicable. Record unavailable hardware or UI checks honestly.
3. Stage the intended changes and request an independent reviewer to inspect the complete staged diff, relevant surrounding code, this file, and `PLAN.md`. For the first commit, review all staged files.
4. Require actionable findings with severity, location, impact, and suggested correction. Separate actionable defects from optional preferences.
5. Fix findings, rerun affected checks, stage the updates, and request independent review again. Repeat until there are no unresolved actionable findings.
6. Verify that the staged content exactly matches the reviewed snapshot and that `git diff --cached --check` passes. Any content change after review invalidates approval and requires renewed review. Check for unstaged changes too; never accidentally commit unreviewed work.
7. Commit only after these gates pass. Report the commit hash, changes, checks, and remaining verification limits, then continue to the next slice.

If independent review is unavailable or a finding/required validation cannot be resolved, stop before committing and report the blocker. Never claim an unperformed check or review passed. The user has authorized local commits for the planned implementation. On 2026-11-10 the user explicitly authorized pushing the reviewed source, documentation and app screenshots to the public repository https://github.com/parveshh/guides after checks and commit. This supersedes the earlier no-push rule for that repository only. Use normal pushes that preserve remote history; do not force-push. The user subsequently explicitly requested a downloadable app build release in that repository. This authorizes release packaging, version tagging and GitHub binary release publication after the same checks/review/commit gates. State the actual architecture, OS and signing/notarization status. It does not authorize an updater, new app permissions, credential creation or any Group B/C implementation.
