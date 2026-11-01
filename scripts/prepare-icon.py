#!/usr/bin/env python3
"""Download official Strava artwork and create PreferenceLoader icons."""
import json
from pathlib import Path
import subprocess
import urllib.request

resources = Path(__file__).resolve().parents[1] / "prefs" / "Resources"
resources.mkdir(parents=True, exist_ok=True)
source = resources / "strava-official-artwork"
error = None
for country in ("gb", "us"):
    try:
        query = "https://itunes.apple.com/lookup?id=426826309&country=" + country
        request = urllib.request.Request(query, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=30) as response:
            results = json.load(response).get("results", [])
        if not results or int(results[0].get("trackId", -1)) != 426826309:
            raise RuntimeError("Strava App Store lookup returned no matching app")
        artwork = (results[0].get("artworkUrl512") or
                   results[0].get("artworkUrl100") or
                   results[0].get("artworkUrl60"))
        if not artwork:
            raise RuntimeError("No artwork URL")
        request = urllib.request.Request(artwork, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=30) as response:
            source.write_bytes(response.read())
        if source.stat().st_size < 1000:
            raise RuntimeError("Artwork image was unexpectedly small")
        break
    except Exception as exc:
        error = exc
else:
    raise SystemExit("Could not get official Strava icon: " + str(error))

for filename, size in (("icon.png", 29), ("icon@2x.png", 58), ("icon@3x.png", 87)):
    target = resources / filename
    subprocess.run(
        ["sips", "-s", "format", "png", "-z", str(size), str(size),
         str(source), "--out", str(target)],
        check=True, stdout=subprocess.DEVNULL,
    )
    dimensions = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(target)],
        check=True, capture_output=True, text=True,
    ).stdout
    if ("pixelWidth: " + str(size)) not in dimensions or (
        "pixelHeight: " + str(size)
    ) not in dimensions or target.stat().st_size < 100:
        raise SystemExit("Settings icon missing or invalid: " + filename)
    print(filename, "ready:", target.stat().st_size, "bytes")
source.unlink(missing_ok=True)
