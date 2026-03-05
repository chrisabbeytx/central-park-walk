#!/usr/bin/env python3
"""
Download Central Park OSM data: paths, drives, water, trees, buildings,
barriers, furniture, statues, bridges, tunnels, landuse, amenities,
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

# >;  recursively fetches all nodes referenced by ways and relations.
QUERY = f"""[out:json][timeout:180];
(
  // --- Paths: footways, drives, bridle paths, cycleways ---
  way["highway"~"^(footway|path|pedestrian|steps|cycleway|track|service|secondary|bridleway)$"]
    ({BBOX});

  // --- Park boundary ---
  relation["name"="Central Park"]
    ({BBOX});

  // --- Water ---
  way["natural"="water"]({BBOX});
  relation["natural"="water"]({BBOX});
  way["waterway"~"^(stream|river)$"]({BBOX});
  node["waterway"="waterfall"]({BBOX});

  // --- Trees ---
  node["natural"="tree"]({BBOX});

  // --- Buildings ---
  way["building"]({BBOX});

  // --- Barriers ---
  way["barrier"]({BBOX});
  node["barrier"]({BBOX});

  // --- Historic / artwork / monuments ---
  way["historic"]({BBOX});
  node["historic"]({BBOX});
  node["tourism"="artwork"]({BBOX});
  way["tourism"="artwork"]({BBOX});

  // --- Man-made structures (bridges, tunnels, etc.) ---
  way["man_made"]({BBOX});
  node["man_made"]({BBOX});

  // --- Furniture ---
  node["amenity"="bench"]({BBOX});
  way["amenity"="bench"]({BBOX});
  node["highway"="street_lamp"]({BBOX});
  node["amenity"="waste_basket"]({BBOX});

  // --- Amenities ---
  node["amenity"="fountain"]({BBOX});
  way["amenity"="fountain"]({BBOX});
  node["amenity"="drinking_water"]({BBOX});
  node["amenity"="toilets"]({BBOX});
  way["amenity"="toilets"]({BBOX});
  node["amenity"="restaurant"]({BBOX});
  node["amenity"="cafe"]({BBOX});
  way["amenity"="restaurant"]({BBOX});
  way["amenity"="cafe"]({BBOX});
  way["amenity"="theatre"]({BBOX});

  // --- Woodland / landuse ---
  way["natural"="wood"]({BBOX});
  relation["natural"="wood"]({BBOX});
  way["landuse"="forest"]({BBOX});
  relation["landuse"="forest"]({BBOX});
  way["leisure"="nature_reserve"]({BBOX});
  relation["leisure"="nature_reserve"]({BBOX});
  way["leisure"="garden"]({BBOX});
  relation["leisure"="garden"]({BBOX});
  way["landuse"="grass"]({BBOX});

  // --- Leisure / sport ---
  way["leisure"="pitch"]({BBOX});
  way["leisure"="playground"]({BBOX});
  way["leisure"="sports_centre"]({BBOX});
  way["leisure"="swimming_pool"]({BBOX});
  way["leisure"="track"]({BBOX});
  way["leisure"="dog_park"]({BBOX});

  // --- Natural features ---
  node["natural"="rock"]({BBOX});
  way["natural"="rock"]({BBOX});
  way["natural"="cliff"]({BBOX});
  way["natural"="wetland"]({BBOX});
  way["natural"="shrubbery"]({BBOX});

  // --- Tourism ---
  node["tourism"="attraction"]({BBOX});
  way["tourism"="attraction"]({BBOX});
  node["tourism"="information"]({BBOX});
  node["tourism"="viewpoint"]({BBOX});
);
out body;
>;
out skel qt;
"""

OUTPUT   = "central_park_osm.json"
B_OUTPUT = "buildings_osm.json"

# Primary endpoint; de.overpass-api.de used as fallback
URLS = [
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]

B_QUERY = f"""[out:json][timeout:180];
way["building"]({BBOX});
out body;
>;
out skel qt;
"""


def fetch(query: str, retries: int = 3) -> bytes:
    data = urllib.parse.urlencode({"data": query}).encode()
    for url in URLS:
        for attempt in range(1, retries + 1):
            try:
                req = urllib.request.Request(url, data=data, method="POST")
                req.add_header("User-Agent", "central-park-walk-godot/1.0")
                print(f"  {url} attempt {attempt}/{retries}…", flush=True)
                with urllib.request.urlopen(req, timeout=200) as resp:
                    return resp.read()
            except urllib.error.HTTPError as exc:
                print(f"  HTTP {exc.code}: {exc.reason}", file=sys.stderr)
                if exc.code == 429:
                    wait = 30 * attempt
                    print(f"  Rate-limited – waiting {wait}s", flush=True)
                    time.sleep(wait)
                else:
                    break   # try next URL
            except urllib.error.URLError as exc:
                print(f"  Network error: {exc.reason}", file=sys.stderr)
                time.sleep(5)
        print(f"  Failed on {url}, trying next…", file=sys.stderr)

    print("All endpoints exhausted.", file=sys.stderr)
    sys.exit(1)


def save(raw: bytes, path: str) -> dict:
    result = json.loads(raw)
    elems  = result.get("elements", [])
    counts = {"node": 0, "way": 0, "relation": 0}
    for e in elems:
        counts[e["type"]] = counts.get(e["type"], 0) + 1
    with open(path, "w") as fh:
        json.dump(result, fh)
    return counts


def main() -> None:
    print(f"Querying Overpass API for Central Park paths + trees…")
    print(f"  bbox: {BBOX}")
    counts = save(fetch(QUERY), OUTPUT)
    print(f"\n  nodes:     {counts['node']}")
    print(f"  ways:      {counts['way']}")
    print(f"  relations: {counts['relation']}")
    print(f"Saved → {OUTPUT}")

    print(f"\nQuerying buildings…")
    try:
        b_raw = fetch(B_QUERY)
        b_counts = save(b_raw, B_OUTPUT)
        print(f"\n  nodes:     {b_counts['node']}")
        print(f"  ways:      {b_counts['way']}")
        print(f"Saved → {B_OUTPUT}")
    except (json.JSONDecodeError, Exception) as exc:
        print(f"  WARNING: buildings query failed ({exc}), using existing {B_OUTPUT} if available",
              file=sys.stderr)


if __name__ == "__main__":
    main()
