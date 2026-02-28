#!/usr/bin/env python3
"""
Download Central Park OSM data: footways, paths, cycleway, steps,
and the park boundary relation.

Saves raw Overpass JSON to central_park_osm.json.
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# Bounding box: south, west, north, east
BBOX = "40.7644,-73.9816,40.7994,-73.9492"

# We want:
#   • Ways tagged highway=footway/path/pedestrian/steps/cycleway/track
#   • The Central Park boundary relation
#   • Water bodies: closed ways and relations with natural=water
# >;  recursively fetches all nodes referenced by ways and relations.
QUERY = f"""[out:json][timeout:90];
(
  way["highway"~"^(footway|path|pedestrian|steps|cycleway|track)$"]
    ({BBOX});
  relation["name"="Central Park"]
    ({BBOX});
  way["natural"="water"]
    ({BBOX});
  relation["natural"="water"]
    ({BBOX});
);
out body;
>;
out skel qt;
"""

OUTPUT = "central_park_osm.json"
URL    = "https://overpass-api.de/api/interpreter"


def fetch(retries: int = 3) -> bytes:
    data = urllib.parse.urlencode({"data": QUERY}).encode()
    req  = urllib.request.Request(URL, data=data, method="POST")
    req.add_header("User-Agent", "central-park-walk-godot/1.0")

    for attempt in range(1, retries + 1):
        try:
            print(f"  attempt {attempt}/{retries}…", flush=True)
            with urllib.request.urlopen(req, timeout=120) as resp:
                return resp.read()
        except urllib.error.HTTPError as exc:
            print(f"  HTTP {exc.code}: {exc.reason}", file=sys.stderr)
            if exc.code == 429:
                wait = 30 * attempt
                print(f"  Rate-limited – waiting {wait}s", flush=True)
                time.sleep(wait)
            else:
                sys.exit(1)
        except urllib.error.URLError as exc:
            print(f"  Network error: {exc.reason}", file=sys.stderr)
            if attempt == retries:
                sys.exit(1)
            time.sleep(5)

    print("All retries exhausted.", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    print(f"Querying Overpass API for Central Park paths…")
    print(f"  bbox: {BBOX}")

    raw    = fetch()
    result = json.loads(raw)
    elems  = result.get("elements", [])

    counts = {"node": 0, "way": 0, "relation": 0}
    for e in elems:
        counts[e["type"]] = counts.get(e["type"], 0) + 1

    with open(OUTPUT, "w") as fh:
        json.dump(result, fh)

    print(f"\n  nodes:     {counts['node']}")
    print(f"  ways:      {counts['way']}")
    print(f"  relations: {counts['relation']}")
    print(f"\nSaved → {OUTPUT}")


if __name__ == "__main__":
    main()
