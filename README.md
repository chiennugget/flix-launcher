# Flix

**Flix** is an iPhone app that gives flixbaba a Netflix-style home screen: posters, search, **My List**, **Continue Watching**, resume points and autoplay for the next episode. It finds the site's current address on its own, blocks pop-ups and ads, and rotates for video.

It isn't on the App Store. You install it yourself with **SideStore**, which takes about 20 minutes the first time. Anyone can do it with their own iPhone, so feel free to send this page to a friend.

**Contents:** [What you need](#what-you-need) · [1. Install SideStore](#part-1--install-sidestore-one-time-15-min-needs-a-computer-once) · [2. Install Flix](#part-2--install-flix-2-min-on-your-iphone) · [3. Movie-info key](#part-3--add-a-free-movie-info-key-3-min) · [Keep it working](#keeping-it-working) · [If Flix expired or won't refresh](#if-flix-expired-or-wont-refresh) · [Using the app](#using-the-app) · [Troubleshooting](#troubleshooting)

Running this repo? See the [owner notes](docs/owner.md).

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
4. In Flix: **My Flix** tab → **☰** (top right) → paste it into **Movie info (TMDB)**. The home screen fills with rows.

Tip: do steps 1–3 on the phone in Safari, so you can copy and paste straight into Flix.

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

**Tabs**
- **Home:** Continue Watching, My List, Top 10 and genre rows. **Series**, **Films** and **Categories** filter the rows. **🌐** (top right) opens the site.
- **New & Hot:** Coming Soon, Everyone's Watching and the Top 10s.
- **Search:** searches The Movie Database. It also has a *Search on the site* button.
- **My Flix:** your list and history. **☰** (top right) opens **Settings**.

**Title page:** **Play** / **Resume**, **My List**, and **Mark Watched** for movies. Shows have a season menu and an episode list with progress bars. **Long-press an episode** to mark it watched, or use the season's **⋯** to mark a whole season.

**The player.** Play opens the episode with only the video on screen. Tap the video to show or hide Flix's controls:
- **✕** closes, **⟲10 / ⟳10** skip, the middle button plays and pauses, and the bar on the left sets brightness.
- **P1** (top right) switches between the site's players. If nothing plays after about 15 seconds, **Not playing? Try Player 2** appears. The app remembers which player worked for each show.
- **🔓** locks the screen against accidental taps.
- Bottom row: **Speed**, **Episodes** (switch episode without leaving), **Audio & Subtitles** and **Next Episode**.
- **Subtitles:** pick a language under **Audio & Subtitles**. They show under Flix's controls and move up while the controls are visible. If a player has no list there, choose **Use the site's controls** to use the site's own menu; tap **Flix controls** to come back.
- **Up next:** near the end of an episode, a 10-second countdown starts the next one. Turn it off in **Settings → Playback**.
- **⋯** has **Show full page**, **Reload**, **Open in Brave**, **Copy link** and **Forget saved page for this**.

**Behind the scenes**
- **Address:** checked on every launch. **Settings → Site** shows the address; **Check again** re-runs it.
- **Blocking:** known ad and pop-up networks are blocked, new windows are dropped, and the page can't send you off the site.
- **Resume:** your position is saved while a video plays, and reopening it jumps back there.
- **Remembered pages:** the first time a title plays, the app remembers its page, so Play goes straight there next time. If it remembered the wrong one, use **⋯ → Forget saved page for this**.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Flix won't open / "app no longer available" | Its 7-day signature ran out. See [If Flix expired or won't refresh](#if-flix-expired-or-wont-refresh). |
| SideStore says it can't connect | Connect **LocalDevVPN** first and keep Wi-Fi on. On iOS 27, do the [iOS 27 connection fix](#ios-27-connection-fix). |
| Apple ID sign-in fails in iloader or SideStore | Use the **newest iloader**. See the error table under [If Flix expired or won't refresh](#if-flix-expired-or-wont-refresh). |
| Home screen is empty with a key message | Add the TMDB key in **Settings** (Part 3). |
| "TMDB rejected the API key" | Re-copy the key from themoviedb.org. Paste the API Key *or* the Read Access Token, not both. |
| Play opens a search or 404 page | Pick the right result. It's remembered after the first play. |
| Play opens the wrong page every time | In the player: **⋯ → Forget saved page for this**, then play again. |
| Subtitles show twice, or the site's player appears instead of Flix's | Turn off **Settings → Playback → Use iPhone fullscreen player**. |
| No subtitles in Flix's player | **Audio & Subtitles** → pick a language. If the list is empty, try another player (**P1**) or **Use the site's controls**. |
| Video doesn't start / black screen | Tap **P1** and try another player. If the screen stays black, use **⋯ → Show full page**. |
| Doesn't resume where I left off | The player may hide its video from the app; the episode is still remembered. |
| Site won't load | **Settings → Check again**. If the address is still wrong, the owner can set it by hand ([owner notes](docs/owner.md#when-the-address-changes)). |

**Safety:** don't install anything or allow notifications the site asks for, and don't enter personal details on it.
