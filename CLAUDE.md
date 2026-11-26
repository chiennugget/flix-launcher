# Notes for Claude

## Workflow (owner's standing instructions)
- **Auto-merge:** once a PR's "Build iOS app" check passes and it merges cleanly, squash-merge it without asking. Ask first only when something seems off: a red build, a merge conflict, review comments, or a change wider than what was asked.
- **Branches:** start each change from the latest `main`.
- **Releases:** only pushes to `main` publish. After merging, confirm that `main`'s build succeeded and report the version (`Flix 1.0.<run_number>`, tag `build-<run_number>`).
- **Handoff:** `HANDOFF.md` holds open items and testing tips for the next session; the `/handoff` skill updates it.

## Build and checks
There are no automated tests. The build is the compile check.
- **CI:** `.github/workflows/build-ios.yml` runs on a macOS runner on pushes to `main` and `claude/**` that touch `ios/**` or the workflow. Branch builds only compile and upload `Flix.ipa`/`apps.json` as artifacts. On `main` it also creates a GitHub release marked latest. SideStore follows `releases/latest/download/apps.json` (written by `ios/scripts/make_source.py`), so every merge to `main` reaches users' phones. A run that sits queued and gets cancelled never got a runner; re-run it once.
- **Local build:** Xcode and simulators are installed on the owner's Mac:
  ```bash
  cd ios && xcodegen generate && xcodebuild -project Flix.xcodeproj -scheme Flix \
    -destination 'platform=iOS Simulator,name=iPhone 17e' -derivedDataPath build build
  ```
  Local builds have no TMDB key; paste one in the app (My Flix → ☰ → Settings). Never commit it.
- **XcodeGen:** `ios/project.yml` is the project spec; no `.xcodeproj` is committed. Info.plist keys live in `project.yml` too.
- **Injected JavaScript** (`Scripts.video`, `Scripts.fullscreen`, `Scripts.focus` in `ios/Flix/Services/WebController.swift`) isn't checked by the build. Extract each script and run `node --check`:
  ```bash
  python3 -c "import re;s=open('ios/Flix/Services/WebController.swift').read();[open(f'/tmp/{n}.js','w').write(re.search(r'static let '+n+r' = #\"\"\"\n(.*?)\n\s*\"\"\"#',s,re.S).group(1)) for n in ['video','fullscreen','focus']]" && for f in video fullscreen focus; do node --check /tmp/$f.js; done
  ```
- **Domain checker:** `python scripts/check_domain.py` (needs `requests`). It rewrites `domain.json` in place, so revert the file unless that change is wanted.

## Architecture
The app is a native SwiftUI shell around the streaming site. TMDB provides the catalog (posters, seasons, search). The site itself only plays video, inside a `WKWebView`.

**Site address (`domain.json`, must stay at the repo root):** the address, mirrors, `pinned` and link templates (`paths`). Two copies of the same "follow redirects / 'now available at' banner, never switch when unsure" logic keep it current:
- `scripts/check_domain.py`, run every 4h by `check-domain.yml`, commits changes as `domain-bot`. It does nothing when `"pinned": true`, and it must keep unknown keys.
- `SiteService` + `DomainResolver` (`SiteService.swift`) run the same logic on every app launch. The app reads `domain.json` from GitHub Pages, then raw `main`, then a custom URL from Settings, and caches the result.
- Mirrors are listed in three places that must stay in sync: `domain.json` `mirrors`, `MIRRORS` in `scripts/check_domain.py`, and `SiteService.builtInMirrors`.
- `paths` templates (`{id}`, `{slug}`, `{season}`, `{episode}`, `{query}`, `{player}`) are filled by `Template.fill`; `Template.regex` parses them in reverse to spot episode changes inside the site. Changes must stay compatible with app versions already installed. Example: the `tv` template keeps `p=1` rather than `{player}`.

**Player (`PlayerScreen` + `WebController`):** presented via `.playerCover(...)` (`Components.swift`), a `fullScreenCover` with no system animation; `PlayerScreen` fades and zooms itself in. Close through `onClose`, not `dismiss`.
- `WebController` builds the web view, compiles `Resources/blocklist.json` into a content rule list once (`AdBlocker`), fences the main frame to site URLs and drops pop-ups.
- Message handlers: `flix` gets video events from every frame (videos over 60s only, so ads are ignored; these drive resume, progress and up-next). `flixPage` gets player count, fullscreen requests, `focused` and `subtitleLanguage`.
- "Player only" mode is `Scripts.focus` pinning the largest iframe or video full screen. With Flix's controls on, `Scripts.video` hides the site player's own controls in every frame (`data-flix-keep`), keeps its caption layer visible (`data-flix-cap`, found by behaviour) and places it with `placeCaptions`.
- Flix's Audio & Subtitles panel drives the site's own subtitle menu (`siteSubs()`), or for vidcore.io its saved `language` setting, which Flix also keeps in `Keys.siteSubtitleLanguage` because embed storage doesn't last between sessions.
- Player numbers (`?p=N`) are per title: `PlayerPrefs` remembers the one that worked. After 15s with no video, the screen offers the next player.

**Persistence:** SwiftData `LibraryItem` (My List and history) and `WatchProgress`, keyed by `PlayRequest.progressKey` (`movie:<id>` / `tv:<id>:s<S>e<E>`). `WatchProgress.sitePath` remembers the site page that played, so Play goes straight there next time. Settings use `@AppStorage` with `Keys.*` (`FlixApp.swift`).

**TMDB:** a key typed into Settings wins over `TMDBAPIKey` in Info.plist, which CI fills from the optional `TMDB_API_KEY` secret. The repo is public, so users type their own key.

**Orientation:** portrait everywhere except while the player is open (`Orientation.allow` / `.rotate`).

## Docs
- `README.md` is the install and usage guide the owner shares with friends (SideStore + LocalDevVPN, iloader, the TMDB key, 7-day re-signing, the iOS 27 fix). Keep it accurate when setup, settings or player controls change.
- `docs/owner.md` covers the address checker, link templates, builds and releases.
