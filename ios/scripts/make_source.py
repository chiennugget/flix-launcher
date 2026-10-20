"""Writes apps.json, the SideStore/AltStore source that points at the newest build.

Usage: make_source.py <ipa> <version> <build> <tag> <out>
Reads GITHUB_REPOSITORY (owner/repo) from the environment.
"""

import json
import os
import sys
from datetime import datetime, timezone

ipa, version, build, tag, out = sys.argv[1:6]
repo = os.environ["GITHUB_REPOSITORY"]
owner = repo.split("/")[0]
download = f"https://github.com/{repo}/releases/download/{tag}/Flix.ipa"
size = os.path.getsize(ipa)
date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
description = (
    "Netflix-style home for your streaming site: finds its current address, "
    "blocks pop-ups and ads, and keeps My List, history and resume points."
)

source = {
    "name": "Flix",
    "identifier": f"io.github.{owner.lower()}.flix.source",
    "sourceURL": f"https://github.com/{repo}/releases/latest/download/apps.json",
    "apps": [
        {
            "name": "Flix",
            "bundleIdentifier": f"io.github.{owner.lower()}.flix",
            "developerName": owner,
            "subtitle": "Your streaming site, Netflix-style.",
            "localizedDescription": description,
            "iconURL": f"https://raw.githubusercontent.com/{repo}/main/icon-512.png",
            "tintColor": "#e5484d",
            # Older AltStore versions read these top-level fields.
            "version": version,
            "versionDate": date,
            "downloadURL": download,
            "size": size,
            "versions": [
                {
                    "version": version,
                    "buildVersion": build,
                    "date": date,
                    "downloadURL": download,
                    "size": size,
                    "minOSVersion": "17.0",
                    "localizedDescription": f"Build {build}",
                }
            ],
            "appPermissions": {"entitlements": [], "privacy": {}},
        }
    ],
    "news": [],
}

with open(out, "w") as f:
    json.dump(source, f, indent=2)
print(f"Wrote {out} for {version} ({build}), {size} bytes")
