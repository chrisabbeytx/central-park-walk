#!/usr/bin/env python3
"""
Download Mapzen/AWS Terrarium terrain tiles for Central Park at zoom 15.

Tiles are cached to terrain_tiles/ — safe to re-run at any time.
Run this once, then run convert_to_godot.py to bake heights into the data files.
"""

import math
import os
import sys
import time
import urllib.request

Z    = 15
BBOX = dict(south=40.7644, north=40.7994, west=-73.9816, east=-73.9492)
URL  = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
DIR  = "terrain_tiles"


def latlon_to_tile(lat: float, lon: float, z: int) -> tuple[int, int]:
    n     = 2 ** z
    x     = int((lon + 180) / 360 * n)
    lat_r = math.radians(lat)
    y     = int((1 - math.log(math.tan(lat_r) + 1 / math.cos(lat_r)) / math.pi) / 2 * n)
    return x, y


x0, y1 = latlon_to_tile(BBOX["south"], BBOX["west"], Z)
x1, y0 = latlon_to_tile(BBOX["north"], BBOX["east"], Z)
tiles   = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]

os.makedirs(DIR, exist_ok=True)
print(f"Terrain tiles  zoom={Z}  x={x0}–{x1}  y={y0}–{y1}  total={len(tiles)}")

for idx, (x, y) in enumerate(tiles, 1):
    path = f"{DIR}/{Z}_{x}_{y}.png"
    if os.path.exists(path):
        print(f"  [{idx:2d}/{len(tiles)}] cached   {Z}/{x}/{y}")
        continue

    url = URL.format(z=Z, x=x, y=y)
    for attempt in range(1, 4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "central-park-walk/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            with open(path, "wb") as f:
                f.write(data)
            print(f"  [{idx:2d}/{len(tiles)}] ok       {Z}/{x}/{y}  ({len(data) // 1024} KB)")
            break
        except Exception as e:
            print(f"  [{idx:2d}/{len(tiles)}] attempt {attempt} failed: {e}", file=sys.stderr)
            if attempt < 3:
                time.sleep(2 * attempt)
    time.sleep(0.15)  # be polite to S3

print("Done.")
