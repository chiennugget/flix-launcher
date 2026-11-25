# Handoff: bug fixes on the redesign

Notes for a Claude Code session running on the owner's Mac, picking up from
a cloud session that couldn't run the app. Delete this file once the work
below is done.

## Where things are

- **Redesign:** branch `claude/gifted-mccarthy-8cu84k` (Netflix-style UI). Not merged into `main` yet.
- **Bug fixes:** branch `claude/clever-brahmagupta-puan00`, on top of the redesign.
  PR: https://github.com/chiennugget/flix-launcher/pull/14 (base: the redesign branch).
  The owner wants to test first, so **don't merge it**. This overrides CLAUDE.md's
  auto-merge rule for this work.
- CI build 29 for that PR was cancelled before it ran (no macOS runner); it was re-run once.
  The fixes have **never been compiled**. Build in Xcode first and fix any errors.

## Build and run locally

```bash
cd ios && xcodegen generate && open Flix.xcodeproj
```

Or from the command line, for the simulator:

```bash
cd ios && xcodegen generate && xcodebuild -project Flix.xcodeproj -scheme Flix \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath build build
```

- Local builds have no TMDB key. Paste one in the app: My Flix → ☰ → Settings.
- `xcrun simctl io booted screenshot shot.png` takes a screenshot. Rotate the simulator
  with ⌘← / ⌘→ to check landscape.
- Injected JavaScript (`Scripts.*` in `ios/Flix/Services/WebController.swift`) isn't
  compiled by Xcode: extract each script and run `node --check` on it.

## Already fixed in PR #14 (check these in the simulator)

1. **Title page art pinned while scrolling** (`TitleDetailView.swift`): it was a pinned
   section header, so text slid over it and under the clock. The art now scrolls with
   the page, a black strip sits behind the status bar, and close/back floats at the top right.
2. **Uneven black bars around the video in landscape** (`WebController.swift`): the web
   view now reports no safe area (`EdgeToEdgeWebView`) and uses
   `contentInsetAdjustmentBehavior = .never`. **Needs checking**: open an episode,
   rotate, and compare the left and right bars.
3. **Switching players lost the resume point** (`PlayerScreen.swift`, `resetVideoState`
   clears `resumedKey`).
4. The page reloads if iOS ends the web process; the web controller's callbacks are
   cleared on teardown.
5. Stale episodes after a season switch (title page and player strip); the player strip
   now has a failed state and Retry.
6. Retry when TMDB fails on the title page; New & Hot recovers after an offline launch;
   failed searches clear old results; the categories close button clears the tab bar;
   confirmation before "Forget remembered links"; VoiceOver labels.

## To do next (owner's reports, not started)

The owner asked to test PR #14 first. Ask before starting these.

1. **The player shows the site's controls as well as Flix's.** Lead: the video plays in
   a cross-origin player iframe whose control bar comes from the player (JW Player,
   Video.js, Plyr…). `Scripts.focus` only hides the main page. Hide that control bar
   inside the frames while Flix's controls are on (`Scripts.video` runs in every frame),
   and show it again for "Use the site's controls".
2. **Changing the season in the player's Episodes panel doesn't change the list.**
   Lead (unconfirmed): `PlayerScreen` redraws about every 500 ms from video "tick"
   events, which may reset the season `Menu`/`Picker` in `EpisodesPanel`
   (`PlayerPanels.swift`). First check whether PR #14 changed anything, then reproduce
   it in the simulator.
3. **Tapping Series/Films on Home makes the page jitter**: things jump off screen, then
   come back. Lead: `setFilter` animates with a spring while the pills use
   `.move(edge: .leading)` transitions. Meanwhile `HomeModel.load` empties
   `rows`/`hero`, the scroll content shrinks, and `scrolled(to:)` toggles
   `pillsHidden` (`HomeView.swift`). Reproduce it, then switch filters in one clean step.
4. **Feature: start the player faster.** `WebWarmup` only loads a blank page at launch,
   which didn't help. Idea: at launch, build a web view with the player's full
   configuration (content rules, user scripts) and load the site once in the background
   (DNS/TLS, cache, cookies or bot check). Then hand that view to `PlayerScreen` when
   the first title is played. Make this its own commit.

## Possible improvement

A beta channel: publish `claude/**` branch builds as a pre-release with their own
`apps-beta.json` (`.github/workflows/build-ios.yml`, `ios/scripts/make_source.py`), so
test builds reach SideStore without merging. This is only an idea; ask the owner first.
