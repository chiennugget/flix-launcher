# Notes for Claude

## Workflow (owner's standing instructions)
- **Auto-merge:** once a PR's "Build iOS app" check passes and it merges cleanly, squash-merge it without asking. Ask first only when something seems off: a red build, a merge conflict, review comments, or a change wider than what was asked.
- **Branches:** start each change from the latest `main`.
- **Releases:** pushing to `main` builds `Flix.ipa` and publishes the release SideStore installs from. After merging, confirm that build succeeded and report the version.

## Project
- **iOS app:** `ios/` (SwiftUI, iOS 17). `ios/project.yml` is the XcodeGen spec. Builds only on GitHub Actions (`.github/workflows/build-ios.yml`, macOS runner). There's no local Swift toolchain, so CI is the compile check.
- **`domain.json`:** the site address, mirrors and link templates (`paths`). The app reads it from `main` on launch.
  - The checker (`check_domain.py`, every 4h) rewrites it; it must keep unknown keys.
  - Changes must stay compatible with app versions already installed. Example: the `tv` template keeps `p=1` rather than `{player}`.
- **Injected JavaScript** (`Scripts.video`, `Scripts.focus` in `WebController.swift`) isn't checked by the build. Syntax-check it with `node --check` after extracting.
