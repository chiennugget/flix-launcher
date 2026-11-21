# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workflow (owner's standing instructions)
- **Auto-merge:** once a PR's "Build iOS app" check passes and it merges cleanly, squash-merge it without asking. Ask first only when something seems off: a red build, a merge conflict, review comments, or a change wider than what was asked.
- **Branches:** start each change from the latest `main`.
- **Releases:** only pushes to `main` publish. After merging, confirm that `main`'s build succeeded and report the version (`Flix 1.0.<run_number>`, tag `build-<run_number>`).

## Build and checks
There's no local Swift toolchain or test suite. CI is the compile check.
- **iOS build:** `.github/workflows/build-ios.yml` runs on a macOS runner on pushes to `main` and `claude/**` that touch `ios/**` or the workflow. Branch builds only compile and upload `Flix.ipa`/`apps.json` as workflow artifacts. On `main` the build also creates a GitHub release marked `--latest`. SideStore follows `releases/latest/download/apps.json`, which `ios/scripts/make_source.py` writes, so every merge to `main` reaches users' phones. If a run sits queued and gets cancelled, it never got a runner; re-run it once.
- **XcodeGen:** `ios/project.yml` is the project spec, and no `.xcodeproj` is committed. Info.plist keys live in `project.yml` too (`GENERATE_INFOPLIST_FILE: NO`).
- **Injected JavaScript** (`Scripts.video`, `Scripts.fullscreen`, `Scripts.focus` in `ios/Flix/Services/WebController.swift`) isn't checked by the build. Extract each script and run `node --check`:
  ```bash
  python3 -c "import re,sys;s=open('ios/Flix/Services/WebController.swift').read();[open(f'/tmp/{n}.js','w').write(re.search(r'static let '+n+r' = #\"\"\"\n(.*?)\n\s*\"\"\"#',s,re.S).group(1)) for n in ['video','fullscreen','focus']]" && for f in video fullscreen focus; do node --check /tmp/$f.js; done
  ```
- **Domain checker:** run `python check_domain.py` (needs `requests`). It rewrites `domain.json` in place, so revert the file unless that change is wanted.

## Architecture
The app is a native SwiftUI shell around the streaming site. TMDB provides the catalog (posters, seasons, search). The site itself only plays video, inside a `WKWebView`.

**Site address (`domain.json`):** this file holds the address, mirrors, `pinned` and link templates (`paths`). Two independent copies of the same "follow redirects / 'now available at' banner, never switch when unsure" logic keep it current:
- `check_domain.py`, run every 4h by `check-domain.yml`, commits changes as `domain-bot`. It does nothing when `"pinned": true`, and it must keep unknown keys.
- `SiteService` + `DomainResolver` (`SiteService.swift`) run the same logic on every app launch. The app reads `domain.json` from GitHub Pages, then raw `main`, then a custom URL from Settings. It caches the result in UserDefaults.
- Mirrors are listed in three places that must stay in sync: `domain.json` `mirrors`, `MIRRORS` in `check_domain.py`, and `SiteService.builtInMirrors`.
- `paths` templates (`{id}`, `{slug}`, `{season}`, `{episode}`, `{query}`, `{player}`) are filled by `Template.fill`. `Template.regex` also parses them in reverse to spot episode changes inside the site. Changes must stay compatible with app versions already installed. Example: the `tv` template keeps `p=1` rather than `{player}`.

**Player (`PlayerScreen` + `WebController`):** presented via `.playerCover($visit)` (`Components.swift`). It is a `fullScreenCover` with no system animation over a clear background, and `PlayerScreen` fades and zooms itself in. Close through `onClose`, not `dismiss`.
- `WebController` builds the web view. It compiles `Resources/blocklist.json` into a content rule list once at launch (`AdBlocker`), fences the main frame to site URLs and drops pop-ups.
- It injects three scripts and receives messages on two handlers:
  - `flix`: video events from every frame, sent only for videos longer than 60s, so ads are ignored. These drive resume, progress and up-next.
  - `flixPage`: player count, fullscreen requests and `focused`.
- "Player only" mode is `Scripts.focus` pinning the largest iframe or video full screen. Fullscreen requests from the page are intercepted, and the app rotates and hides its own bar instead.
- A loading cover hides redirects and the page rearranging. It lifts on the first video event, on `focused`, or on `didFinish` with no further redirect, and always within 8s.
- Player numbers (`?p=N`) are per title: `PlayerPrefs` in UserDefaults remembers the one that worked. After 15s with no video, the screen offers the next player.

**Persistence:** SwiftData `LibraryItem` (My List and history) and `WatchProgress`, keyed by `PlayRequest.progressKey` (`movie:<id>` / `tv:<id>:s<S>e<E>`), with helpers in `Library`. `WatchProgress.sitePath` remembers the exact site page that played, so Play goes straight there next time. Settings use `@AppStorage` with `Keys.*` (`FlixApp.swift`).

**TMDB:** a key typed into Settings wins over `TMDBAPIKey` in Info.plist, which CI fills from the optional `TMDB_API_KEY` secret. The repo is public, so users are told to type their own key.

**Orientation:** `AppDelegate.orientations` is a global mask. The app stays portrait everywhere except while the player is open (`Orientation.allow` / `.rotate`).

## Docs
`README.md` is the user-facing install guide that the owner shares with friends. It covers SideStore + LocalDevVPN, iloader, the TMDB key, the 7-day re-signing, and the iOS 27 connection fix. Keep it accurate when setup, settings or player controls change. `index.html` / `manifest.webmanifest` are the old Brave + Shortcut web launcher on GitHub Pages, which also serves `domain.json`.
