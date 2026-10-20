"""Finds the site's current address and saves it to domain.json.

Run by GitHub Actions every few hours. It only changes domain.json when it is
confident: the current address has redirected or shows a "now available at"
banner, and the new address loads as the real site. If anything is unclear
(site down, bot check, no clear answer) it leaves the saved address alone.

Manual override: set "pinned": true in domain.json and this script does nothing.
"""

import json
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import requests

CONFIG = Path(__file__).with_name("domain.json")

# Old addresses that usually point to the newest one. The saved address is
# always checked first; add more here if you spot them.
MIRRORS = [
    "flixbaba.com",
    "flixbaba.cx",
    "flixbabax.com",
    "flixbaba.mov",
    "flixbaba.best",
]

NAME = "flixbaba"
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    ),
    "Accept-Language": "en-US,en;q=0.9",
}

DOMAIN_RE = r"([a-z0-9-]*" + NAME + r"[a-z0-9-]*\.[a-z]{2,24})"
BANNER_RE = re.compile(
    r"now\s+(?:available|moved)\s+(?:at|to)\s*(?:<[^>]*>\s*)*" + DOMAIN_RE,
    re.IGNORECASE,
)
TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)
MAX_HOPS = 4


def clean(domain):
    d = (domain or "").strip().lower()
    d = re.sub(r"^https?://", "", d).split("/")[0]
    return d[4:] if d.startswith("www.") else d


def probe(domain):
    """Load a domain. Returns (final_domain, status, html) or None on failure."""
    try:
        r = requests.get(f"https://{domain}/", headers=HEADERS, timeout=20, allow_redirects=True)
    except requests.RequestException as e:
        print(f"  {domain}: unreachable ({type(e).__name__})")
        return None
    final = clean(urlparse(r.url).hostname or domain)
    print(f"  {domain}: HTTP {r.status_code} -> {final}")
    return final, r.status_code, r.text[:400_000]


def banner_target(html):
    m = BANNER_RE.search(html or "")
    return clean(m.group(1)) if m else None


def looks_like_site(status, html):
    """True if the page is the real site, not a parked page or a bot check."""
    if status != 200:
        return False
    m = TITLE_RE.search(html or "")
    return bool(m and NAME in m.group(1).lower())


def pointer(domain, result):
    """Where this domain says the site moved to, or None."""
    if not result:
        return None
    final, status, html = result
    target = banner_target(html)
    if target and target != domain:
        return target
    if final != domain and NAME in final:
        return final
    return None


def resolve(start):
    """Follow redirects/banners from start until reaching a live, unmoved site."""
    seen, domain = set(), start
    for _ in range(MAX_HOPS):
        if domain in seen:
            return None
        seen.add(domain)
        result = probe(domain)
        if not result:
            return None
        nxt = pointer(domain, result)
        if nxt is None:
            _, status, html = result
            return domain if looks_like_site(status, html) else None
        domain = nxt
    return None


def main():
    cfg = json.loads(CONFIG.read_text())
    current = clean(cfg.get("domain"))

    if cfg.get("pinned"):
        print(f"Pinned to {current}; skipping auto-check.")
        return 0

    print(f"Saved address: {current}")
    result = probe(current) if current else None

    if result:
        _, status, html = result
        if pointer(current, result) is None and looks_like_site(status, html):
            print("Saved address is still the live site. No change.")
            return 0

    # The saved address moved or is down: see where the address chain leads.
    votes = Counter()
    for start in [current] + [m for m in MIRRORS if m != current]:
        if not start:
            continue
        found = resolve(start)
        if found:
            votes[found] += 1

    if not votes:
        print("No live address found (site down or blocked). Keeping saved address.")
        return 0

    best, count = votes.most_common(1)[0]
    print(f"Candidates: {dict(votes)}")
    if best == current:
        print("Saved address confirmed. No change.")
        return 0

    cfg["domain"] = best
    cfg["updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    CONFIG.write_text(json.dumps(cfg, indent=2) + "\n")
    print(f"Updated: {current} -> {best}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
