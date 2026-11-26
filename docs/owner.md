# Owner notes

How this repo keeps Flix working: the site address, link formats, builds and releases. Friends installing Flix only need the [README](../README.md).

## What's in this repo

| Path | What it is |
|---|---|
| `ios/` | The iOS app (SwiftUI, iOS 17). `ios/project.yml` describes the Xcode project. |
| `domain.json` | Current site address, mirrors and link templates. The app reads it on every launch, so it stays at this path. |
| `scripts/check_domain.py` | The checker that updates `domain.json` every 4 hours (`.github/workflows/check-domain.yml`). |
| `ios/scripts/make_source.py` | Writes `apps.json`, the SideStore source, for each release. |
| `.github/workflows/build-ios.yml` | Builds `Flix.ipa` on every change to `ios/`. On `main` it also publishes a release. |
| `CLAUDE.md`, `HANDOFF.md`, `.claude/` | Notes and the `/handoff` skill for Claude Code sessions. |

## Builds and releases

- Every push to `main` that touches `ios/` builds **Flix 1.0.N** (N is the run number) and publishes it as the latest release, tagged `build-N`.
- SideStore reads `https://github.com/chiennugget/flix-launcher/releases/latest/download/apps.json`, so every release reaches everyone's phone as an update.
- Builds on `claude/**` branches only compile; they don't publish.
- A build failed? **Actions** → **Build iOS app** → open the red run to see why.
- **TMDB key:** you could save one as a repo secret named `TMDB_API_KEY` (**Settings** → **Secrets and variables** → **Actions**) to build it into the app. The repo is public, so anyone could pull it out of a release; typing it into the app is better.

## When the address changes

**Usually: nothing to do.** The checker runs every 4 hours, and the app also checks the mirrors itself on launch. If you notice the site moved before either catches up, open **Actions** → **Check domain** → **Run workflow**.

**If both miss it** (manual fallback, works from your phone):

1. On GitHub, open `domain.json` → tap the ✏️ pencil.
2. Change `"domain"` to the new address (e.g. `"flixbaba.newone"`) and `"pinned"` to `true`.
3. **Commit changes.** In Flix, go to **Settings** → **Check again**.

`"pinned": true` stops the checker from changing it. Set it back to `false` when you want auto-checking again.

**Spotted a new mirror address?** Add it to `"mirrors"` in `domain.json` (the app reads this list) and to `MIRRORS` near the top of `scripts/check_domain.py` (the checker reads this one). The app also tries its own built-in list (`SiteService.builtInMirrors`); add new ones there with the next app change. More old addresses give both more places to find the "moved to" banner.

If the checker always says "No live address found", the site may be blocking GitHub's servers with a bot check. Use the manual fallback; the checker never changes the address when it isn't sure.

## Make Play open the exact page (optional)

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

## First-time GitHub setup

Already done for this repo. For a fresh copy:

1. **Settings** → **Pages** → **Deploy from a branch** → **main** / **(root)**. The app reads `domain.json` through GitHub Pages first.
2. **Settings** → **Actions** → **General** → *Workflow permissions* → **Read and write permissions**, so the checker and the app build can save their results.
