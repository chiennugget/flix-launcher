# Flix launcher — setup guide

One home screen icon that finds flixbaba's current address, unlocks rotation, and opens it in Brave with ads blocked. When you close Brave, portrait lock turns back on.

**How it fits together**

- **GitHub** hosts a tiny web app plus `domain.json`, the file that holds the current address.
- **A checker** runs on GitHub every 4 hours, follows the "now available at…" banners and redirects, and updates `domain.json` when the site moves.
- **Your Shortcut** reads `domain.json`, turns rotation lock off, and opens the site in Brave.
- **An automation** turns rotation lock back on when Brave closes.

Throughout this guide, replace `USERNAME` with your GitHub username.

---

## Part 1 — GitHub (about 10 min, easiest on a computer)

1. **Create the repo.** On github.com: **+** → **New repository** → name it `flix-launcher` → **Public** → **Create repository**.
2. **Upload the files.** Click **uploading an existing file**, then drag in everything from the unzipped folder: `index.html`, `domain.json`, `manifest.webmanifest`, `icon-180.png`, `icon-512.png`, `check_domain.py`, `README.md`. Click **Commit changes**.
3. **Add the checker workflow.** The `.github` folder is hidden on most computers, so create it by hand: **Add file** → **Create new file** → type the name `.github/workflows/check-domain.yml` (the slashes make the folders) → paste in the contents of that file from the zip → **Commit changes**.
4. **Turn on the website.** **Settings** → **Pages** → under *Build and deployment*, Source: **Deploy from a branch**, Branch: **main**, folder **/ (root)** → **Save**. After a minute or two, the page is live at `https://USERNAME.github.io/flix-launcher/`.
5. **Test the checker once.** **Actions** tab → enable workflows if asked → **Check domain** → **Run workflow**. It should finish green with "Saved address is still the live site."

> If the run fails with a permission error on `git push`: **Settings** → **Actions** → **General** → *Workflow permissions* → **Read and write permissions** → **Save**, then run it again.

---

## Part 2 — Brave (2 min, on your iPhone)

1. Install **Brave** from the App Store if you don't have it.
2. In Brave: **⋯** → **Settings** → **Shields & Privacy**:
   - **Trackers & ads blocking** → **Aggressive**
   - **Block Pop-ups** → **On**
3. Leave **Block Scripts** off. It breaks the video player.

---

## Part 3 — The Shortcut (5 min, on your iPhone)

Open **Shortcuts** → **+** (new shortcut). Add these actions in order (tap the search bar at the bottom to find each one):

| # | Action | Set it to |
|---|---|---|
| 1 | **Set Orientation Lock** | Tap *Toggle* → change to **Turn**, set to **Off** |
| 2 | **URL** | `https://USERNAME.github.io/flix-launcher/domain.json` |
| 3 | **Get Contents of URL** | (leave as is; it uses the URL above) |
| 4 | **Get Dictionary Value** | Get **Value** for key `domain` in *Contents of URL* |
| 5 | **Text** | `brave://open-url?url=https://` then insert the **Dictionary Value** variable, then `/` |
| 6 | **Open URLs** | (uses the Text above) |

Then:

1. Rename the shortcut (tap the name at the top) to **Flix**.
2. Tap the **ⓘ** / share button → **Add to Home Screen**. Tap the icon to change it if you like (you can pick `icon-180.png` saved to Photos).
3. Run it once. Allow the permission prompts (accessing `github.io`, opening Brave) and choose **Always Allow** so it doesn't ask again.

---

## Part 4 — Re-lock rotation when you're done (2 min)

**Shortcuts** → **Automation** tab → **+** → **App**:

1. **Choose** → **Brave** → **Done**.
2. Tick **Is Closed** only (untick *Is Opened*).
3. Select **Run Immediately** and turn off *Notify When Run*.
4. **Next** → **New Blank Automation** → add **Set Orientation Lock** → **Turn** → **On** → **Done**.

"Closed" means leaving Brave (going to the home screen or another app), so portrait lock comes back as soon as you leave.

---

## Part 5 (optional) — The web app icon

The Shortcut is your main icon. The web app is a backup that shows the current address and has buttons to open it in Brave:

1. In **Safari**, open `https://USERNAME.github.io/flix-launcher/`
2. **Share** → **Add to Home Screen**. It gets the red play icon.

Launched from the Home Screen, it auto-opens Brave at the current address. It can't unlock rotation (only Shortcuts can), so use it when you just want to check the address.

---

## When the address changes

**Usually: nothing to do.** The checker runs every 4 hours. If you notice the site moved before it catches up, open **Actions** → **Check domain** → **Run workflow**.

**If the checker misses it** (manual fallback, works from your phone):

1. On GitHub, open `domain.json` → tap the ✏️ pencil.
2. Change `"domain"` to the new address (e.g. `"flixbaba.newone"`) and `"pinned"` to `true`.
3. **Commit changes.** Your Shortcut uses it within a couple of minutes.

`"pinned": true` stops the checker from changing it. Set it back to `false` once you want auto-checking again.

**Spotted a new mirror address?** Add it to the `MIRRORS` list near the top of `check_domain.py`. More old addresses give the checker more places to find the "moved to" banner.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Shortcut opens Brave to a blank tab | Check step 5. The text must read exactly `brave://open-url?url=https://` + variable + `/`. |
| "Couldn't connect" on step 3 | GitHub Pages isn't live yet. Wait a few minutes after Part 1 step 4. |
| Screen doesn't rotate | Make sure the video is in **fullscreen**. Check that step 1 says **Turn Off**, not Toggle. |
| Ads still get through | Confirm Shields are **Aggressive**. Close any tab that pops up rather than tapping inside it. |
| Checker always says "No live address found" | The site may be blocking GitHub's servers with a bot check. Use the manual fallback above; the checker never overwrites the address when it's unsure. |

**Safety:** don't install anything or allow notifications the site asks for, and don't enter personal details on it.
