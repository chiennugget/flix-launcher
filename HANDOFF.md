# Handoff

Open items and testing tips for the next Claude Code session. How the app works is in
`CLAUDE.md`; the owner's guide is `docs/owner.md`. Everything shipped is on `main`
(latest release Flix 1.0.41, with subtitles under Flix's controls from PR #19).

## Still open

1. **Check on a real iPhone.** The simulator's taps in the forced-landscape player drift
   out of sync, so these were only checked by script and screenshot:
   - Flix's controls on P1 and P2, playing and paused; "Use the site's controls", then
     "Flix controls".
   - Subtitles under Flix's controls (P1: JW player on stellarconductornexus.com; P2:
     vidcore.io): picking a language in Audio & Subtitles, the line sitting low and
     gliding above the scrubber when the controls show.
   - The owner said to skip P3–P5.
2. **P2 while loading:** the site's server button and "Fetching your content" spinner
   show under Flix's controls until a video exists. Left as is.
3. **A finished series** stays in Continue Watching at its last episode (only movies are
   hidden). Hiding it needs the season count.
4. **Feature: start the player faster** (not started). `WebWarmup` only loads a blank
   page. Idea: at launch, build a web view with the player's full configuration and load
   the site once in the background, then hand it to `PlayerScreen`. Own commit.
5. The owner once saw the player's Episodes panel ignore a season change; it didn't
   reproduce (Season 2 → 4 worked). Ask for steps if it comes back.

**Idea, ask the owner first:** a beta channel that publishes `claude/**` branch builds as
a pre-release with their own `apps-beta.json` (`build-ios.yml`, `make_source.py`), so
test builds reach SideStore without merging.

## Subtitle notes

- If subtitles fail on a device, the fallback is to catch the subtitle file and add it
  as a native track (`addTextTrack` + `VTTCue`). The owner prefers Flix not to fetch or
  draw subtitles itself.
- vidcore.io on a phone has no subtitle menu in the page until its own CC button is
  tapped, and a script `.click()` only sets its state. That's why Flix uses its saved
  `language` setting instead.
- The player embeds open directly in a browser for inspection:
  `https://vidcore.io/movie/<tmdb id>`, `https://vidcore.io/tv/<tmdb id>/<s>/<e>`,
  `https://vidy.st/movie/<tmdb id>`. The main site is behind a Cloudflare check.

## Testing in the simulator

- **Owner's rule:** don't keep videos playing for long checks. Read the page by script
  instead: a short `setInterval` probe posting to the `flixPage` handler, logged with
  `NSLog("FLIXDEBUG …")` and read with
  `xcrun simctl spawn <device> log stream --predicate 'eventMessage CONTAINS "FLIXDEBUG"'`.
  Quit the app afterwards and strip all `FLIXDEBUG` code before committing.
- **Settings:** "Use iPhone fullscreen player" must be off, or the site's player shows
  instead of Flix's. `defaults write` doesn't reach the app; quit it, edit
  `$(xcrun simctl get_app_container <device> io.github.chiennugget.flix data)/Library/Preferences/io.github.chiennugget.flix.plist`
  with `plutil`, then `xcrun simctl spawn <device> killall cfprefsd`. The same plist
  holds the per-title player (`player.tv:<id>`), handy for switching P1/P2 without taps.
- **Taps:** don't rotate the simulator by hand before testing the player; it forces
  landscape itself, and taps drift after rotations and relaunches. Wait for scrolling to
  stop before tapping a tile. Opening a title from Continue Watching is the most
  reliable path.
