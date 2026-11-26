# Handoff: Flix player notes

Notes for the next Claude Code session. Delete this file once the open items
below are done.

## Subtitles under Flix's controls (done, check P3–P5 and on a real iPhone)

Ideas 1 and 2 from the owner's plan (2026-11-26) are in `Scripts.video`
(`ios/Flix/Services/WebController.swift`). Flix still doesn't fetch or draw subtitles.
- **Caption layer stays visible.** While a video plays, an element in the lower part of
  the frame whose text changes to new words twice, with no buttons, sliders or inputs in
  or around it, is marked `data-flix-cap` (and later elements with the same class, since
  React re-creates them, unless many elements share that class). The hide rule sets
  `visibility: visible` on marked layers and their children. The native hide is narrowed
  to the panel and play buttons, so iOS can still draw subtitles inside the stream.
- **Placement (`placeCaptions`, run every frame while Flix's controls are on).** The
  site's layer still sits where its hidden control bar left room, and some players
  (P1's JW) move it again on a tap. Flix measures the text's natural bottom edge (minus
  its own `translate`) and eases the layer to 5% above the frame's bottom, or 27% while
  Flix's controls show. A new layer snaps; one on screen glides (~0.3 s), so there's no
  jumping. A reloaded player frame gets the current lift state when it announces itself.
- **Flix's Audio & Subtitles panel.**
  - Sites with their subtitle list in the page (vidy.st, desktop vidcore): `siteSubs()`
    finds it by its "Off" entry, lists its languages (ids 1000+), reads the current pick
    (the entry styled unlike the others) and presses entries with `.click()`.
  - vidcore.io on a phone (P2): the menu isn't in the page until its CC button is tapped
    (a script `.click()` only sets its state, nothing renders), and its video tracks stay
    empty until a language is picked. It loads the language saved in its own
    `localStorage` key `language` at start, so Flix saves the picked code there (names
    mapped with `Intl.DisplayNames`), reloads the player frame and seeks back to the same
    time (`sessionStorage` `flixResumeAt`). Off removes the key. The embed's storage
    doesn't last between player sessions, so Flix also keeps the pick in UserDefaults
    (`siteSubtitleLanguage`) and writes it back at document start in vidcore frames.
  - Otherwise the native tracks are used, as before.
- Checked on the iPhone 17e simulator (2026-11-26): P1 (stellarconductornexus.com, a JW
  player drawing `span.jw-sub-text`) and P2 (vidcore.io) show subtitles under Flix's
  controls, low when the controls are hidden and above the scrubber when they show. P3,
  P4, P5 not checked on iOS. Not checked on a real iPhone.
- vidy.st picks Chinese by default; the owner can now switch it from Flix's panel.
- Fallback if this fails on device: catch the subtitle file and add it as a native track
  (`addTextTrack` + `VTTCue`). The owner prefers not to.
- The local-only branch `claude/fix-subtitles` (earlier attempt) is superseded and can be
  deleted.
- Owner's testing rules: don't keep videos playing for long checks. Read the DOM by
  script (a short `setInterval` probe posting to `flixPage`, logged with
  `NSLog("FLIXDEBUG …")`, read via `xcrun simctl spawn <device> log stream --predicate
  'eventMessage CONTAINS "FLIXDEBUG"'`), then quit the app. Strip `FLIXDEBUG` code before
  committing. The player embeds also open directly in a browser
  (`https://vidcore.io/movie/<tmdb id>`, `https://vidy.st/movie/<tmdb id>`).

## Where things are

- **Everything shipped is on `main`**, latest release Flix 1.0.37 (PRs #15–#17 after
  the items below). PR #14 (https://github.com/chiennugget/flix-launcher/pull/14)
  was pointed at `main` and squash-merged as `d1b4a37`. It carried the Netflix-style
  redesign, the first round of bug fixes and the QA fixes below. Release build 33
  (version 1.0.33) was published from it.
- The old branches `claude/gifted-mccarthy-8cu84k` (redesign) and
  `claude/clever-brahmagupta-puan00` (fixes) are fully merged and can be deleted.
- Start new work from the latest `main` (see CLAUDE.md).

## Build and run locally

```bash
cd ios && xcodegen generate && xcodebuild -project Flix.xcodeproj -scheme Flix \
  -destination 'platform=iOS Simulator,name=iPhone 17e' -derivedDataPath build build
```

- Xcode and simulators are installed on the owner's Mac, so local builds work
  (CLAUDE.md's "builds only on CI" no longer holds).
- Local builds have no TMDB key. Paste one in the app (My Flix → ☰ → Settings) or write
  it into the simulator's defaults:
  `xcrun simctl spawn <device> defaults write io.github.chiennugget.flix tmdbKey <key>`.
  Never commit the key.
- There are no automated tests; the build is the only automatic check.
- Injected JavaScript (`Scripts.*` in `ios/Flix/Services/WebController.swift`) isn't
  compiled by Xcode: extract each `#"""…"""#` script and run `node --check` on it.

### Simulator pitfalls

- **Don't rotate the simulator by hand before testing the player.** The player forces
  landscape itself; if the device was rotated earlier, the screenshot frame and tap
  coordinates stop matching and taps land in the wrong place. Rotate back to portrait,
  or reboot the simulator, if taps in the player seem to do nothing.
- Wait for scroll animations to stop before tapping a tile, or the tap is eaten.
- Even from a fresh boot, taps in the forced-landscape player drift out of sync after a
  relaunch. A rotate right then left sometimes re-syncs; don't spend long on it.
- `defaults write` from the command line doesn't reach the app's settings. Edit the plist
  in the app container instead (app quit first):
  `$(xcrun simctl get_app_container <device> io.github.chiennugget.flix data)/Library/Preferences/io.github.chiennugget.flix.plist`
  with `plutil`, then `xcrun simctl spawn <device> killall cfprefsd`.

## Fixed in the QA pass (in 1.0.33)

- Home: filter switches happen in one step (no jitter); scroll back to top on filter
  change; the header background and pill hiding work on iOS 18+
  (`onScrollOffsetChange` in `Components.swift`); the hero card type-checks.
- Search: the keyboard no longer pushes the field under the clock or lifts the tab bar;
  recommendation errors show with Retry.
- Title pages: swipe-back on pushed pages (`UINavigationController` extension in
  `RootView.swift`); season switches keep the old list dimmed until the new one loads.
- Player: the site player's control bar and title are hidden while Flix's controls are
  on (`setSiteControlsHidden` / `__flixHideControls`, passed down to frames by
  `postMessage`); progress saves on pause, end, close and every 30 s; the loading cover's
  close button fits in landscape; "Try Player 2" isn't cut off.
- New & Hot shows the real error and hides empty headings; a blank profile name falls
  back to "You".

## Fixed in the second QA pass (PRs #15 and #16)

- Player: any site player's controls hide while Flix's are on, whatever its class names.
  Each frame marks its main video (or the iframe that holds it) and its parents with
  `data-flix-keep` and hides everything else. P3 (vidy.st, vidcore.io) showed both sets
  before. Data attributes, because the site's React code rewrites `className`.
- Player: the landscape floating bar lost its tap gesture, which blocked its buttons.
  Captions move up while Flix's controls are showing (`__flixLift`).
- Home: a category picked inside Series or Films keeps that choice. Finished movies leave
  Continue Watching (Home and My Flix).
- Search: cancelled requests no longer surface as errors; long queries stay on two lines.
- New & Hot: section jumps land below the header (`safeAreaPadding`, not a spacer).
- Settings: a whitespace-only profile name is trimmed. Mark Watched and mark season save
  at once. The site browser shows one close button while loading.

## Still open

1. **Check on a real iPhone** (the simulator's taps in the forced-landscape player keep
   drifting out of sync, even after a reboot): Flix's controls only on P1 to P5, playing
   and paused; "Use the site's controls", then "Flix controls" in the floating bar;
   captions moving up while the controls show.
2. **Subtitles**: check on an iPhone (see the top section).
3. **P2 while loading**: the site's server button and "Fetching your content" spinner
   show under Flix's controls until a video exists. Left as is.
4. **A finished series** stays in Continue Watching at its last episode (only movies are
   hidden). Hiding it needs the season count.
5. **Feature: start the player faster** (not started). `WebWarmup` only loads a blank
   page. Idea: at launch, build a web view with the player's full configuration and load
   the site once in the background, then hand it to `PlayerScreen`. Own commit.
6. Owner's report that the player's Episodes panel ignores a season change didn't
   reproduce (Season 2 → 4 worked). Ask the owner for steps if it comes back.

## Possible improvement

A beta channel: publish `claude/**` branch builds as a pre-release with their own
`apps-beta.json` (`.github/workflows/build-ios.yml`, `ios/scripts/make_source.py`), so
test builds reach SideStore without merging. Only an idea; ask the owner first.
