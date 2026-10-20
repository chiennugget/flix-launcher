# Flix — setup guide

**Flix** is an iPhone app that gives flixbaba a Netflix-style home screen: posters, search, **My List**, **Continue Watching** and resume points. It finds the site's current address by itself, blocks pop-ups and ads, and rotates for video. You don't need Brave or Shortcuts.

**How it fits together**

- **GitHub** (this repo) holds `domain.json`, the file with the site's current address.
- **A checker** runs on GitHub every 4 hours. It follows the "now available at…" banners and redirects, and updates `domain.json` when the site moves.
- **GitHub Actions** builds the app whenever its code in `ios/` changes and posts it under **Releases**.
- **SideStore** installs the app on your iPhone and keeps it signed with your own free Apple ID. No Mac needed.
- **The app** reads `domain.json`. If that address looks dead, it checks the mirrors itself.

| Link | Address |
|---|---|
| This repo | `https://github.com/chiennugget/flix-launcher` |
| Current address file | `https://chiennugget.github.io/flix-launcher/domain.json` |
| SideStore source | `https://github.com/chiennugget/flix-launcher/releases/latest/download/apps.json` |

---

## Part 1 — Install SideStore (one time, ~15 min, needs a computer once)

SideStore is the app that installs Flix. The first install needs a computer: Windows, Mac or Linux, and a friend's is fine. After that, everything happens on the phone.

**On the iPhone first**

1. Make sure the phone has a **passcode**. The next step fails without one.
2. Install **LocalDevVPN** from the App Store. SideStore uses it to talk to your phone. It's a local connection, not a real VPN service, and your traffic doesn't go anywhere.

**On the computer**

3. Download **iloader** from its official page, [github.com/nab138/iloader](https://github.com/nab138/iloader) → **Releases**, picking the file for your computer.
   - **Windows:** install **iTunes** from apple.com first (iloader needs its phone driver).
   - **Mac:** nothing extra.
   - **Linux:** install `usbmuxd` if it isn't there already.
4. Plug the iPhone in with a cable and tap **Trust** on the phone.
5. Open iloader → sign in with your **Apple ID** → choose **Install SideStore**. It installs SideStore and sets up the files it needs to connect to your phone.

**Back on the iPhone (unplug now)**

6. **Settings** → **Privacy & Security** → **Developer Mode** → **On**. The phone restarts; after it does, tap **Turn On** to confirm.
7. **Settings** → **General** → **VPN & Device Management** → tap your Apple ID email → **Trust**.
8. Open **LocalDevVPN** → **Connect**. Then open **SideStore**, allow the prompts it asks for, and sign in with your Apple ID under its **Settings** tab.

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

Posters, descriptions, episode lists and search come from The Movie Database (TMDB).

1. Sign up at [themoviedb.org](https://www.themoviedb.org/signup) and confirm your email.
2. Go to **Settings** → **API** → **Create** → **Developer**, and fill in the short form (personal use).
3. Copy the **API Key** or the **API Read Access Token**. Either one works.
4. In Flix: **Settings** tab → paste it into **Movie info (TMDB)**. The home screen fills with rows.

> You could instead save it as a repo secret named `TMDB_API_KEY` (**Settings** → **Secrets and variables** → **Actions**) so it's built into the app. Because this repo is public, anyone could pull the key out of a release, so typing it into the app is better.

---

## Using the app

- **Home:** Continue Watching, My List, Trending, Popular, Top Rated and genre rows. Pull down to refresh.
- **Title page:** **Play** / **Resume**, **My List**, and for shows, a season picker and episode list with progress bars.
- **Search** tab: searches TMDB. It also has a *Search on the site* button.
- **🌐** (top right of Home): opens the site's home page.
- **In the player:**
  - **✕** closes the player.
  - **‹ ›** go back and forward, and **↻** reloads.
  - The green **shield** counts pop-ups and redirects that were blocked.
  - **⋯** has **Open in Brave**, **Copy link** and **Forget saved page**.

**What happens behind the scenes**

- **Address:** checked on every launch. **Settings → Site** shows the address and where it came from. Tap **Check again** to re-run it.
- **Blocking:** known ad and pop-under networks are blocked. New windows are dropped, and the page can't redirect you off the site.
- **Resume:** while a video plays, its position is saved every few seconds, and reopening the same movie or episode jumps back to it. This works for most players; if a player hides its video, the app still remembers which episode you were on.
- **Rotation:** portrait in menus, free rotation while the site is open.
- **Remembered pages:** the first time a video plays for a title, the app remembers that page, so next time Play goes straight there. If it remembered the wrong page, use **⋯ → Forget saved page**.

---

## Make Play open the exact page (optional, recommended)

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

Leave `movie` or `tv` empty (`""`) to keep using search for that type. The app picks up changes the next time it opens.

---

## Keeping it working

- **Every 7 days:** apps signed with a free Apple ID expire after a week. SideStore renews them in the background. About once a week, connect **LocalDevVPN** and open **SideStore** (or tap **My Apps → Refresh All**). If Flix ever won't open, do this.
- **Updates:** when the app code changes, a new version appears in SideStore. Connect LocalDevVPN, then tap **Update**.
- **App limit:** a free Apple ID allows **3 sideloaded apps at once**, and SideStore counts as one. That leaves room for Flix and one more.

---

## When the address changes

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
| Flix won't open / "app no longer available" | Its 7-day signature ran out. Connect LocalDevVPN → open SideStore → **Refresh All**. |
| SideStore says it can't connect | Connect **LocalDevVPN** first. Stay on Wi-Fi or mobile data. |
| Home screen is empty with a key message | Add the TMDB key in **Settings** (Part 3). |
| "TMDB rejected the API key" | Re-copy the key from themoviedb.org. Paste the API Key *or* the Read Access Token, not both. |
| Play opens a search or 404 page | Pick the right result. It's remembered after the first play. Better: set `paths` (see above). |
| Play opens the wrong page every time | In the player: **⋯ → Forget saved page**, then play again. |
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
