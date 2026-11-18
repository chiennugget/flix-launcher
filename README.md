# Flix

**Flix** is an iPhone app that gives flixbaba a Netflix-style home screen: posters, search, **My List**, **Continue Watching**, resume points and autoplay for the next episode. It finds the site's current address on its own, blocks pop-ups and ads, and rotates for video.

It isn't on the App Store. You install it yourself with **SideStore**, which takes about 20 minutes the first time. Anyone can do it with their own iPhone, so feel free to send this page to a friend.

**Contents:** [What you need](#what-you-need) · [1. Install SideStore](#part-1--install-sidestore-one-time-15-min-needs-a-computer-once) · [2. Install Flix](#part-2--install-flix-2-min-on-your-iphone) · [3. Movie-info key](#part-3--add-a-free-movie-info-key-3-min) · [Keep it working](#keeping-it-working) · [If Flix expired or won't refresh](#if-flix-expired-or-wont-refresh) · [Using the app](#using-the-app) · [Troubleshooting](#troubleshooting)

---

## What you need

- An **iPhone on iOS 17 or newer** with a passcode set.
- **Your own Apple ID.** A free one works, and you don't need a paid developer account. Use your own: the app is signed with it, and nobody else ever sees it.
- **A computer, once:** Windows, Mac or Linux, plus a cable for the phone. It's only for the first install, and borrowing a friend's is fine.
- **About 20 minutes.**

You don't need a GitHub account. Everything below is free.

| Link | Address |
|---|---|
| **SideStore source (what you paste into SideStore)** | `https://github.com/chiennugget/flix-launcher/releases/latest/download/apps.json` |
| Newest Flix release | [github.com/chiennugget/flix-launcher/releases/latest](https://github.com/chiennugget/flix-launcher/releases/latest) |
| This repo | `https://github.com/chiennugget/flix-launcher` |
| Current site address file | `https://chiennugget.github.io/flix-launcher/domain.json` |

---

## Part 1 — Install SideStore (one time, ~15 min, needs a computer once)

SideStore installs Flix and keeps it signed with your Apple ID. You only need the computer for this part. After it, everything happens on the phone.

**On the iPhone first**

1. Make sure the phone has a **passcode**. The next steps fail without one.
2. Install **LocalDevVPN** from the App Store. SideStore uses it to talk to your phone. It's a local connection, not a real VPN service, and your traffic doesn't go anywhere.

**On the computer**

3. Download the **newest** **iloader** from its official page, [github.com/nab138/iloader](https://github.com/nab138/iloader) → **Releases**, picking the file for your computer. Older versions can't sign in to Apple anymore (see [troubleshooting](#troubleshooting)).
   - **Windows:** install **iTunes** from apple.com first (iloader needs its phone driver).
   - **Mac:** nothing extra.
   - **Linux:** install `usbmuxd` if it isn't there already.
4. Plug the iPhone in with a cable and tap **Trust** on the phone.
5. Open iloader → sign in with your **Apple ID** → choose **Install SideStore**. It installs SideStore and the pairing file it needs to reach your phone. If a two-factor code pops up on one of your Apple devices, approve it.

**Back on the iPhone (unplug now)**

6. **Settings** → **Privacy & Security** → **Developer Mode** → **On**. The phone restarts; after it does, tap **Turn On** to confirm.
7. **Settings** → **General** → **VPN & Device Management** → tap your Apple ID email → **Trust**.
8. Open **LocalDevVPN** → **Connect**. Then open **SideStore**, allow the prompts it asks for (including **Local Network**), and sign in with your Apple ID under its **Settings** tab.

> **On iOS 27?** SideStore may not reach the phone with LocalDevVPN's default settings. If you get a "device endpoint" or "tunnel peer IP" error anywhere below, do the [iOS 27 connection fix](#ios-27-connection-fix) once and continue.

---

## Part 2 — Install Flix (2 min, on your iPhone)

1. Connect **LocalDevVPN**, then open **SideStore** → **Sources** → **+** → paste:

   ```
   https://github.com/chiennugget/flix-launcher/releases/latest/download/apps.json
   ```

2. Open the **Flix** source → **Get**. Flix appears on your home screen with the red play icon.

*If adding the source fails:* in Safari, open the [newest release](https://github.com/chiennugget/flix-launcher/releases/latest) and download **Flix.ipa**. Then in SideStore go to **My Apps** → **+** and pick the file from Downloads.

---

## Part 3 — Add a free movie-info key (3 min)

Posters, descriptions, episode lists and search come from The Movie Database (TMDB). Everyone uses their own free key.

1. Sign up at [themoviedb.org](https://www.themoviedb.org/signup) and confirm your email.
2. Click your profile picture → **Settings** → **API** → **Create** → **Developer**, accept the terms and fill in the short form. For the app type, choose personal use, and any short description works ("personal movie list app").
3. Copy the **API Key** (the shorter one) or the **API Read Access Token** (the long one). Either one works.
4. In Flix: **Settings** tab → paste it into **Movie info (TMDB)**. The home screen fills with rows.

Tip: do steps 1–3 on the phone in Safari, so you can copy and paste straight into Flix.

> Owner only: you could save the key as a repo secret named `TMDB_API_KEY` (**Settings** → **Secrets and variables** → **Actions**) to build it into the app. Because this repo is public, anyone could pull the key out of a release, so typing it into the app is better.

---

## Keeping it working

- **Once a week:** apps signed with a free Apple ID **expire after 7 days**. Connect **LocalDevVPN**, open **SideStore** and tap **My Apps → Refresh All**. That restarts the 7 days. Setting a weekly phone reminder helps.
- **Updates:** when a new version comes out, it appears in SideStore. Connect LocalDevVPN, then tap **Update** next to Flix. Your list and progress stay.
- **App limit:** a free Apple ID allows **3 sideloaded apps at once**, and SideStore counts as one. That leaves room for Flix and one more.

---

## If Flix expired or won't refresh

If you went more than a week without refreshing, Flix (and often SideStore too) stops opening. Your list and progress are kept, so just get the signature renewed.

**If SideStore still opens:** connect **LocalDevVPN** → open **SideStore** → **My Apps** → **Refresh All**.

**If SideStore won't open either:** repeat Part 1 steps 3–5 with the **newest iloader** (it installs over the old copy), then refresh as above. If Flix still won't open, open the Flix source in SideStore and tap **Get** again.

**Common errors while refreshing**

| Error | Fix |
|---|---|
| "Session expired", or asks you to log in | **SideStore → Settings** → sign out of your Apple ID → sign back in → **Refresh All**. |
| Sign-in fails with **-22405**, **-80045** or "This action cannot be completed" | Apple changed its sign-in in Oct 2026. Update to the **newest iloader**, then use it to install a fresh SideStore and sign in again. Still failing: in iloader's settings run **Reset Anisette State** and **Delete Sorted Pairing**, then try again. Several failed tries in a row can lock you out for a few hours. |
| "Unable to reach the device endpoint", "tunnel peer IP is not yet reachable", `DeviceEndpointNotInitialized` | Do the [iOS 27 connection fix](#ios-27-connection-fix) below. On older iOS, first try disconnecting and reconnecting LocalDevVPN and restarting the phone. |
| "TCP port poll failed" | The **RemotePair Port** in the fix below is wrong. Look it up again (step 4), or try `49152`. |

### iOS 27 connection fix

LocalDevVPN 1.3 changed its addresses, and on iOS 27 SideStore can't reach the phone with the defaults. This fix comes from other SideStore users, not from SideStore itself, so it may change with future updates.

**In LocalDevVPN's settings**

1. **Tunnel IP:** `10.7.0.2/30`
2. **Device IP:** `10.7.0.0/24`
3. Tap **Disconnect**, then **Connect**.

**In SideStore**

4. **Settings → Experimental Features → Network Discovery → local → Remote Pairing** (`_remotepairing._tcp`) → tap the **IPv4** entry and note the **port** under "Connection" (a number like `52107`; yours will differ).
5. **Settings → Connection Config:** turn **Use Local VPN** **off**. LocalDevVPN does that job.
6. Set **Device IP / Endpoint** to `10.7.0.1`.
7. Set **RemotePair Port** to the port from step 4.

**Then**

8. Close SideStore completely and **restart the iPhone**.
9. Connect **LocalDevVPN** → open **SideStore** → **My Apps → Refresh All**.

---

## Using the app

- **Home:** Continue Watching, My List, Trending, Popular, Top Rated and genre rows. Pull down to refresh.
- **Title page:** **Play** / **Resume**, **My List**, and for movies **Mark Watched**. Shows get a season menu under **Episodes** and an episode list with progress bars; **long-press an episode** to mark it watched or unwatched, or use **⋯** next to **Episodes** to mark a whole season.
- **Search** tab: searches TMDB. It also has a *Search on the site* button.
- **🌐** (top right of Home): opens the site's home page.
- **In the player:** Play opens the episode with **only the video player** on screen and tries to start it.
  - **P1 ▾** switches between the site's players (Player 1, 2, 3…). If nothing plays within about 15 seconds, a **Try Player 2** button pops up. The app remembers which player worked for each show and starts there next time.
  - **✕** closes the player, **‹** goes back, **↻** reloads. In landscape and fullscreen these float over the video and fade out after a few seconds; tap the video to bring them back, or tap again to hide them.
  - **Episodes** (list icon) opens the show's seasons and episodes over the video; tap one to switch to it on the same player. **⏭** skips to the next episode.
  - **Up next:** 15 seconds before an episode ends, a 10-second countdown starts the next one on the same player. Tap **Play now** or **✕**. Turn it off in **Settings → Playback**.
  - The green **shield** counts pop-ups and redirects that were blocked.
  - **⋯** has **Show full page** (the whole flixbaba page, e.g. to pick episodes there), **Open in Brave**, **Copy link** and **Forget saved page**.

**What happens behind the scenes**

- **Address:** checked on every launch. **Settings → Site** shows the address and where it came from. Tap **Check again** to re-run it.
- **Blocking:** known ad and pop-under networks are blocked. New windows are dropped, and the page can't redirect you off the site.
- **Resume:** while a video plays, its position is saved every few seconds, and reopening the same movie or episode jumps back to it. This works for most players; if a player hides its video, the app still remembers which episode you were on.
- **Rotation:** portrait in menus, free rotation while the site is open.
- **Remembered pages:** the first time a video plays for a title, the app remembers that page, so next time Play goes straight there. If it remembered the wrong page, use **⋯ → Forget saved page**.

---

## Make Play open the exact page (owner, optional)

Until this is set, **Play** runs a site search for the title. To go straight to the right page, open any movie and any episode on the site, tap **⋯ → Copy link**, and look at the addresses.

If they contain the TMDB number (the one in a themoviedb.org address, e.g. `themoviedb.org/movie/550` → `550`), edit `paths` in `domain.json` on GitHub (✏️ pencil → **Commit changes**):

```json
"paths": {
  "movie": "/movie/{id}",
  "tv": "/tv/{id}/{season}/{episode}",
  "search": "/search?q={query}"
}
```

Use whatever shape the site actually uses. Placeholders:

| Placeholder | Becomes |
|---|---|
| `{id}` | TMDB number, e.g. `155` |
| `{slug}` | Title in lowercase with dashes, e.g. `the-dark-knight` |
| `{title}` | Title as written |
| `{year}` | Release year |
| `{season}` | Season number |
| `{episode}` | Episode number |
| `{query}` | Search text (search link only) |
| `{player}` | Player number (`p=` on flixbaba) |

Leave `movie` or `tv` empty (`""`) to keep using search for that type. `"player": "p"` names the link setting that picks the site's player, and `"players": 5` is how many the player menu offers when the page doesn't list them. The app picks up changes the next time it opens.

---

## When the address changes (owner)

**Usually: nothing to do.** The checker runs every 4 hours, and the app also checks the mirrors itself on launch. If you notice the site moved before either catches up, open **Actions** → **Check domain** → **Run workflow**.

**If both miss it** (manual fallback, works from your phone):

1. On GitHub, open `domain.json` → tap the ✏️ pencil.
2. Change `"domain"` to the new address (e.g. `"flixbaba.newone"`) and `"pinned"` to `true`.
3. **Commit changes.** In Flix, go to **Settings** → **Check again**.

`"pinned": true` stops the checker from changing it. Set it back to `false` when you want auto-checking again.

**Spotted a new mirror address?** Add it to `"mirrors"` in `domain.json` (the app reads this list) and to `MIRRORS` near the top of `check_domain.py` (the checker reads this one). More old addresses give both more places to find the "moved to" banner.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Flix won't open / "app no longer available" | Its 7-day signature ran out. See [If Flix expired or won't refresh](#if-flix-expired-or-wont-refresh). |
| SideStore says it can't connect | Connect **LocalDevVPN** first and keep Wi-Fi on. On iOS 27, do the [iOS 27 connection fix](#ios-27-connection-fix). |
| Apple ID sign-in fails in iloader or SideStore | Use the **newest iloader**. See the error table under [If Flix expired or won't refresh](#if-flix-expired-or-wont-refresh). |
| Home screen is empty with a key message | Add the TMDB key in **Settings** (Part 3). |
| "TMDB rejected the API key" | Re-copy the key from themoviedb.org. Paste the API Key *or* the Read Access Token, not both. |
| Play opens a search or 404 page | Pick the right result. It's remembered after the first play. Better: set `paths` (see above). |
| Play opens the wrong page every time | In the player: **⋯ → Forget saved page**, then play again. |
| Subtitles show twice, or no captions button in fullscreen | Use the player's own fullscreen button or Flix's ⤢ button; it keeps the site's player and its captions button. Make sure **Settings → Playback → Use iPhone fullscreen player** is off. |
| Video doesn't start / black screen | Tap **P1 ▾** and try another player. If the screen stays black, use **⋯ → Show full page**. |
| Doesn't resume where I left off | The player may hide its video from the app; the episode is still remembered. |
| Site won't load | **Settings → Check again**. If the address is wrong, use the manual fallback above. |
| Checker always says "No live address found" | The site may block GitHub's servers with a bot check. Use the manual fallback; the checker never overwrites the address when unsure. |
| GitHub build failed | **Actions** tab → **Build iOS app** → open the red run to see why. |

**Safety:** don't install anything or allow notifications the site asks for, and don't enter personal details on it.

---

## Backup: the Brave + Shortcut launcher

This was the setup before the app. It still works and needs no sideloading: one Shortcut icon that unlocks rotation and opens the current address in Brave with ads blocked.

**Brave (2 min).** Install **Brave** from the App Store. Then **⋯** → **Settings** → **Shields & Privacy**: **Trackers & ads blocking** → **Aggressive**, and **Block Pop-ups** → **On**. Leave **Block Scripts** off; it breaks the video player.

**The Shortcut (5 min).** **Shortcuts** → **+**, then add these actions in order:

| # | Action | Set it to |
|---|---|---|
| 1 | **Set Orientation Lock** | Tap *Toggle* → change to **Turn**, set to **Off** |
| 2 | **URL** | `https://chiennugget.github.io/flix-launcher/domain.json` |
| 3 | **Get Contents of URL** | (leave as is) |
| 4 | **Get Dictionary Value** | Get **Value** for key `domain` in *Contents of URL* |
| 5 | **Text** | `brave://open-url?url=https://` then the **Dictionary Value** variable, then `/` |
| 6 | **Open URLs** | (uses the Text above) |

Rename it **Flix** → **ⓘ** / share → **Add to Home Screen**. Run it once and choose **Always Allow** on the prompts.

**Re-lock rotation (2 min).** **Shortcuts** → **Automation** → **+** → **App** → **Brave** → tick only **Is Closed** → **Run Immediately** → **New Blank Automation** → **Set Orientation Lock** → **Turn** → **On** → **Done**.

**Web app icon (optional).** In Safari, open `https://chiennugget.github.io/flix-launcher/` → **Share** → **Add to Home Screen**. Launched from the Home Screen, it opens Brave at the current address. It can't unlock rotation.

| Problem | Fix |
|---|---|
| Shortcut opens Brave to a blank tab | Step 5 must read exactly `brave://open-url?url=https://` + variable + `/`. |
| "Couldn't connect" on step 3 | GitHub Pages isn't live. **Settings** → **Pages** → Source **Deploy from a branch**, **main**, **/ (root)**. |
| Screen doesn't rotate | Put the video in **fullscreen**. Step 1 must say **Turn Off**, not Toggle. |

---

## What's in this repo

| Path | What it is |
|---|---|
| `domain.json` | Current address, mirrors and link templates |
| `check_domain.py`, `.github/workflows/check-domain.yml` | The checker that updates `domain.json` every 4 hours |
| `ios/` | The iOS app (SwiftUI). `project.yml` describes the Xcode project |
| `.github/workflows/build-ios.yml` | Builds `Flix.ipa` and the SideStore source on each change to `ios/` |
| `index.html`, `manifest.webmanifest`, `icon-*.png` | The backup web launcher (GitHub Pages) |

**First-time GitHub setup (already done for this repo).** For a fresh copy:
1. Turn on **Settings** → **Pages** → **Deploy from a branch** → **main** / **(root)**.
2. Set **Settings** → **Actions** → **General** → *Workflow permissions* → **Read and write permissions**, so the checker and the app build can save their results.
