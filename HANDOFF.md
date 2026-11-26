# Handoff: subtitles under Flix's controls (next task)

Notes for the next Claude Code session. Delete this file once the open items
below are done.

## Next task: make subtitles show under Flix's controls (owner's decision)

**Do ideas 1 and 2 together, in one PR.** The owner chose this on 2026-11-26. Subtitles
must show in Flix's own player, not only with the site's controls or the iPhone's
full-screen player, and Flix must not fetch or draw subtitles itself.

What's known:
- No player shows subtitles under Flix's controls (owner, on device, 1.0.37).
- The site player's own subtitles **work**: with "Use the site's controls" the owner can
  turn them on. Switching back to Flix's controls makes them disappear.
- Cause of the disappearing: the hide rule from 1.0.35 (`data-flix-keep` in
  `Scripts.video`) hides everything in the player frame except the video and its
  parents, including the site's caption text. The site players use generated class names
  (MUI, e.g. `mui-1iv6od4`), so `capSel` and name guesses like `[class*="ubtitle"]` miss it.
- Flix's Audio & Subtitles panel only sets a native `textTrack.mode = 'showing'`. On P2/P3
  that track stays empty (`cues.length == 0` for minutes), because the site player loads
  its own subtitle file and draws lines in the page. So the panel does nothing visible.

The plan:
1. **Keep the site's caption layer visible under Flix's controls.** Find it by behaviour,
   not name: a non-interactive element (no buttons/inputs/sliders inside or around it)
   whose text changes while the video plays, in the lower part of the frame. Mark it
   `data-flix-cap` and keep it visible (children inherit a hidden parent's visibility,
   so the rule must set `visibility: visible` on it and its children). Keep hiding the rest.
2. **Make Flix's Audio & Subtitles panel drive the site player's own subtitle menu.**
   From JS in the player frame, open the site player's CC/settings menu and click the
   language Flix's panel picked (`.click()` works while the menu is hidden). List the
   site menu's languages in Flix's panel instead of the empty native tracks. Per-player
   selectors are needed; start with P2 and P3 (vidcore.io / vidy.st MUI players).
3. Fallback (only if 1+2 fail): catch the subtitle file the site downloads and add it as a
   native track (`addTextTrack` + `VTTCue`). Last resort: mirror caption text into a
   SwiftUI layer. The owner prefers not to.

Testing rules from the owner: **don't keep videos playing** for long checks. Prefer
reading the DOM by script (a short `setInterval` probe posting to the `flixPage` handler,
logged with `NSLog("FLIXDEBUG …")` and read via
`xcrun simctl spawn <device> log stream --predicate 'eventMessage CONTAINS "FLIXDEBUG"'`),
then quit the app (`xcrun simctl terminate`). Strip all `FLIXDEBUG` code before committing.

A local-only branch `claude/fix-subtitles` (commit `43cc038`, not pushed) holds the earlier
attempt: `[data-flix-cap]` made visible again, the native
`::-webkit-media-controls` hide narrowed to the panel and play buttons, the name-guess
caption marking, and a FLIXDEBUG probe. Reuse what helps; don't merge it as is.

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
2. **Subtitles**: see "Next task" above.
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
