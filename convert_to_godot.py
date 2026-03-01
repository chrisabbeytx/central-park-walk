#!/usr/bin/env python3
"""
Convert central_park_osm.json → park_data.json + heightmap.json

Projects OSM lat/lon into local metres relative to the centre of Central Park,
using the same coordinate convention as the Godot scene:

    origin  = (REF_LAT, REF_LON)  ≈ centre of Central Park
    +X axis = East
    −Z axis = North   (Godot's default forward is −Z)

If terrain_tiles/ is present (run download_terrain.py first), the converter
also writes heightmap.json and embeds real terrain heights (metres, relative to
the lowest point in the dataset) into every feature:

    paths[]     – points now [x, terrain_y, z]  (3 values)
    trees[]     – points now [x, terrain_y, z]  (3 values)
    water[]     – points stay [x, z] but each body gains "water_y"
    buildings[] – points stay [x, z] but each building gains "base"
"""

import json
import math
import os
import sys
from collections import defaultdict

# ---------------------------------------------------------------------------
# Projection constants  (tuned for ~40.78 ° N)
# ---------------------------------------------------------------------------
REF_LAT            = 40.7829
REF_LON            = -73.9654
METRES_PER_DEG_LAT = 110_540.0
METRES_PER_DEG_LON = 111_320.0 * math.cos(math.radians(REF_LAT))   # ≈ 84 264 m/°

HIGHWAY_WIDTH = {
    "pedestrian": 6.0,
    "footway":    3.0,
    "cycleway":   3.5,
    "path":       2.5,
    "steps":      2.5,
    "track":      3.0,
}

TERRAIN_Z   = 15           # zoom level matching download_terrain.py
TERRAIN_DIR = "terrain_tiles"
GRID_W      = 256          # heightmap output resolution
GRID_H      = 256
WORLD_SIZE  = 5000.0       # metres – must match main.gd ground plane size


def project(lat: float, lon: float) -> tuple[float, float]:
    """Return (x, z) in metres, origin = REF_LAT / REF_LON."""
    x =  (lon - REF_LON) * METRES_PER_DEG_LON
    z = -(lat - REF_LAT) * METRES_PER_DEG_LAT
    return (round(x, 2), round(z, 2))


def latlon_to_tile(lat: float, lon: float, z: int) -> tuple[int, int]:
    n     = 2 ** z
    tx    = int((lon + 180) / 360 * n)
    lat_r = math.radians(lat)
    ty    = int((1 - math.log(math.tan(lat_r) + 1 / math.cos(lat_r)) / math.pi) / 2 * n)
    return tx, ty


# ---------------------------------------------------------------------------
# Terrain heightmap – built from Terrarium PNG tiles
# ---------------------------------------------------------------------------
def build_height_grid() -> tuple[list, float, float]:
    """
    Stitch terrain tiles, sample on a GRID_W×GRID_H world grid, and return:
        (flat_grid, min_elev, origin_height)
    All three are in raw metres above sea level; callers subtract min_elev.
    Returns (None, 0, 0) if tiles are missing.
    """
    try:
        from PIL import Image
    except ImportError:
        print("  PIL not found – skipping terrain (pip install pillow)", file=sys.stderr)
        return None, 0.0, 0.0

    bbox = dict(south=40.7644, north=40.7994, west=-73.9816, east=-73.9492)
    x0, y1 = latlon_to_tile(bbox["south"], bbox["west"], TERRAIN_Z)
    x1, y0 = latlon_to_tile(bbox["north"], bbox["east"], TERRAIN_Z)

    # Check all tiles are present
    missing = [f"{TERRAIN_DIR}/{TERRAIN_Z}_{x}_{y}.png"
               for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)
               if not os.path.exists(f"{TERRAIN_DIR}/{TERRAIN_Z}_{x}_{y}.png")]
    if missing:
        print(f"  {len(missing)} tile(s) missing – run download_terrain.py", file=sys.stderr)
        return None, 0.0, 0.0

    TILE_PX   = 256
    raster_w  = (x1 - x0 + 1) * TILE_PX
    raster_h  = (y1 - y0 + 1) * TILE_PX
    raster    = [0.0] * (raster_w * raster_h)

    print(f"  Loading {(x1-x0+1)*(y1-y0+1)} terrain tiles → {raster_w}×{raster_h} raster…")
    for ty in range(y0, y1 + 1):
        for tx in range(x0, x1 + 1):
            path = f"{TERRAIN_DIR}/{TERRAIN_Z}_{tx}_{ty}.png"
            img  = Image.open(path).convert("RGB")
            raw  = img.tobytes()          # flat RGBRGB…
            col0 = (tx - x0) * TILE_PX
            row0 = (ty - y0) * TILE_PX
            for py in range(TILE_PX):
                for px in range(TILE_PX):
                    off = (py * TILE_PX + px) * 3
                    r, g, b = raw[off], raw[off + 1], raw[off + 2]
                    h = r * 256 + g + b / 256 - 32768   # Terrarium decode
                    h = max(h, 0.0)  # clamp ocean/river pixels to sea level
                    raster[(row0 + py) * raster_w + (col0 + px)] = h

    # Raster sampler with bilinear interpolation
    n = 2 ** TERRAIN_Z

    def latlon_to_raster(lat: float, lon: float) -> tuple[float, float]:
        lat_r = math.radians(lat)
        fx    = (lon + 180) / 360 * n
        fy    = (1 - math.log(math.tan(lat_r) + 1 / math.cos(lat_r)) / math.pi) / 2 * n
        return (fx - x0) * TILE_PX, (fy - y0) * TILE_PX

    def sample_raster(rx: float, ry: float) -> float:
        rx  = max(0.0, min(rx, raster_w - 1.001))
        ry  = max(0.0, min(ry, raster_h - 1.001))
        ix, iy = int(rx), int(ry)
        fx, fy = rx - ix, ry - iy
        ix1, iy1 = ix + 1, iy + 1
        h00 = raster[iy  * raster_w + ix ]
        h10 = raster[iy  * raster_w + ix1]
        h01 = raster[iy1 * raster_w + ix ]
        h11 = raster[iy1 * raster_w + ix1]
        return h00*(1-fx)*(1-fy) + h10*fx*(1-fy) + h01*(1-fx)*fy + h11*fx*fy

    # Sample GRID_W × GRID_H world grid (row-major: row=z, col=x)
    half = WORLD_SIZE / 2.0
    cell = WORLD_SIZE / (GRID_W - 1)
    grid = [0.0] * (GRID_W * GRID_H)
    for zi in range(GRID_H):
        for xi in range(GRID_W):
            x_w = -half + xi * cell
            z_w = -half + zi * cell
            lat  = REF_LAT + (-z_w / METRES_PER_DEG_LAT)
            lon  = REF_LON + ( x_w / METRES_PER_DEG_LON)
            rx, ry = latlon_to_raster(lat, lon)
            grid[zi * GRID_W + xi] = sample_raster(rx, ry)

    min_elev = min(grid)

    # Height at world origin (player spawn)
    origin_rx, origin_ry = latlon_to_raster(REF_LAT, REF_LON)
    origin_height = sample_raster(origin_rx, origin_ry) - min_elev

    print(f"  Elevation: min={min_elev:.1f} m  max={max(grid):.1f} m  "
          f"origin_above_min={origin_height:.1f} m")
    return grid, min_elev, origin_height


def make_sampler(grid: list, min_elev: float):
    """Return a function  sample(x_world, z_world) → height above min_elev."""
    if grid is None:
        return lambda x, z: 0.0
    half = WORLD_SIZE / 2.0

    def sample(x_w: float, z_w: float) -> float:
        u   = (x_w + half) / WORLD_SIZE
        v   = (z_w + half) / WORLD_SIZE
        xi  = u * (GRID_W - 1)
        zi  = v * (GRID_H - 1)
        xi0 = max(0, min(int(xi), GRID_W - 2))
        zi0 = max(0, min(int(zi), GRID_H - 2))
        fx  = xi - xi0
        fz  = zi - zi0
        h00 = grid[zi0       * GRID_W + xi0    ] - min_elev
        h10 = grid[zi0       * GRID_W + xi0 + 1] - min_elev
        h01 = grid[(zi0 + 1) * GRID_W + xi0    ] - min_elev
        h11 = grid[(zi0 + 1) * GRID_W + xi0 + 1] - min_elev
        return h00*(1-fx)*(1-fz) + h10*fx*(1-fz) + h01*(1-fx)*fz + h11*fx*fz

    return sample


# ---------------------------------------------------------------------------
# Boundary ring assembly
# ---------------------------------------------------------------------------
def assemble_ring(outer_way_ids: list, ways_nodes: dict) -> list:
    endpoint_map: dict = defaultdict(list)
    for wid in outer_way_ids:
        nodes = ways_nodes.get(wid)
        if not nodes:
            continue
        endpoint_map[nodes[0]].append((wid, nodes))
        endpoint_map[nodes[-1]].append((wid, nodes[::-1]))

    first_id = next((w for w in outer_way_ids if w in ways_nodes), None)
    if first_id is None:
        return []

    ring = list(ways_nodes[first_id])
    used = {first_id}

    for _ in range(len(outer_way_ids) + 2):
        tail     = ring[-1]
        advanced = False
        for wid, nodes in endpoint_map.get(tail, []):
            if wid not in used:
                ring.extend(nodes[1:])
                used.add(wid)
                advanced = True
                break
        if not advanced:
            break

    return ring


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    src = "central_park_osm.json"
    if not os.path.exists(src):
        print(f"ERROR: {src} not found – run download_osm.py first.", file=sys.stderr)
        sys.exit(1)

    with open(src) as fh:
        raw = json.load(fh)
    elements = raw.get("elements", [])

    b_src = "buildings_osm.json"
    if os.path.exists(b_src):
        with open(b_src) as fh:
            b_raw = json.load(fh)
        elements = elements + b_raw.get("elements", [])
        print(f"Merged {len(b_raw.get('elements', []))} elements from {b_src}")

    # Index raw data
    nodes_ll:   dict[int, tuple] = {}
    ways_tags:  dict[int, dict]  = {}
    ways_nodes: dict[int, list]  = {}
    relations:  list             = []

    for e in elements:
        t = e["type"]
        if t == "node" and "lat" in e:
            nodes_ll[e["id"]] = (e["lat"], e["lon"])
        elif t == "way":
            ways_tags[e["id"]]  = e.get("tags", {})
            ways_nodes[e["id"]] = e.get("nodes", [])
        elif t == "relation":
            relations.append(e)

    # -------------------------------------------------------------------
    # Terrain heightmap
    # -------------------------------------------------------------------
    have_terrain = os.path.isdir(TERRAIN_DIR)
    if have_terrain:
        print("Building terrain height grid…")
        hm_grid, min_elev, origin_height = build_height_grid()
        have_terrain = hm_grid is not None
    else:
        hm_grid, min_elev, origin_height = None, 0.0, 0.0

    terrain = make_sampler(hm_grid, min_elev)

    if have_terrain:
        flat_grid = [round(v - min_elev, 2) for v in hm_grid]
        hm_out = {
            "width":         GRID_W,
            "depth":         GRID_H,
            "world_size":    WORLD_SIZE,
            "origin_height": round(origin_height, 2),
        }
        # Data goes in a separate file to keep park_data.json manageable
        hm_data_out = {"width": GRID_W, "depth": GRID_H,
                       "world_size": WORLD_SIZE,
                       "origin_height": round(origin_height, 2),
                       "data": flat_grid}
        with open("heightmap.json", "w") as fh:
            json.dump(hm_data_out, fh, separators=(",", ":"))
        hm_kb = os.path.getsize("heightmap.json") / 1024
        print(f"  Saved → heightmap.json  ({hm_kb:.0f} KB)")
    else:
        hm_out = {}

    # -------------------------------------------------------------------
    # Paths  – points become [x, terrain_y, z]
    # -------------------------------------------------------------------
    paths_out  = []
    skipped_hw = 0
    skipped_pts = 0

    for wid, tags in ways_tags.items():
        hw = tags.get("highway")
        if hw not in HIGHWAY_WIDTH:
            skipped_hw += 1
            continue

        pts = []
        for nid in ways_nodes.get(wid, []):
            if nid in nodes_ll:
                x, z = project(*nodes_ll[nid])
                pts.append([x, round(terrain(x, z), 2), z])

        if len(pts) < 2:
            skipped_pts += 1
            continue

        layer   = int(tags.get("layer",  0))
        is_bridge  = tags.get("bridge")  in ("yes", "viaduct", "aqueduct")
        is_tunnel  = tags.get("tunnel")  in ("yes", "building_passage", "culvert")
        entry = {"highway": hw, "surface": tags.get("surface", ""), "points": pts}
        if layer != 0:
            entry["layer"] = layer
        if is_bridge:
            entry["bridge"] = True
        if is_tunnel:
            entry["tunnel"] = True
        paths_out.append(entry)

    # -------------------------------------------------------------------
    # Boundary  (stays 2D – used for invisible walls only)
    # -------------------------------------------------------------------
    boundary_pts: list = []
    cp_rel = None

    for rel in relations:
        if rel.get("tags", {}).get("name") == "Central Park":
            cp_rel = rel
            break
    if cp_rel is None and relations:
        cp_rel = relations[0]

    if cp_rel:
        members   = cp_rel.get("members", [])
        outer_ids = [m["ref"] for m in members
                     if m["type"] == "way" and m.get("role") == "outer"]
        if not outer_ids:
            outer_ids = [m["ref"] for m in members if m["type"] == "way"]
        for nid in assemble_ring(outer_ids, ways_nodes):
            if nid in nodes_ll:
                boundary_pts.append(list(project(*nodes_ll[nid])))
        if boundary_pts and boundary_pts[0] == boundary_pts[-1]:
            boundary_pts.pop()
    else:
        print("  WARNING: No boundary relation found – park walls will be skipped.")

    # -------------------------------------------------------------------
    # Water bodies  – points stay [x, z]; body gains "water_y"
    # -------------------------------------------------------------------
    water_out = []

    def _extract_polygon(node_ids: list) -> list:
        pts = []
        for nid in node_ids:
            if nid in nodes_ll:
                pts.append(list(project(*nodes_ll[nid])))
        if len(pts) > 1 and pts[0] == pts[-1]:
            pts.pop()
        return pts

    def _centroid_height(pts_2d: list) -> float:
        if not pts_2d:
            return 0.0
        cx = sum(p[0] for p in pts_2d) / len(pts_2d)
        cz = sum(p[1] for p in pts_2d) / len(pts_2d)
        return round(terrain(cx, cz), 2)

    for wid, tags in ways_tags.items():
        if tags.get("natural") != "water":
            continue
        nids = ways_nodes.get(wid, [])
        if len(nids) < 4 or nids[0] != nids[-1]:
            continue
        pts = _extract_polygon(nids)
        if len(pts) >= 3:
            water_out.append({"name": tags.get("name", ""),
                               "water_y": _centroid_height(pts),
                               "points": pts})

    for rel in relations:
        tags = rel.get("tags", {})
        if tags.get("natural") != "water":
            continue
        members   = rel.get("members", [])
        outer_ids = [m["ref"] for m in members
                     if m["type"] == "way" and m.get("role") in ("outer", "")]
        if not outer_ids:
            outer_ids = [m["ref"] for m in members if m["type"] == "way"]
        pts = _extract_polygon(assemble_ring(outer_ids, ways_nodes))
        if len(pts) >= 3:
            water_out.append({"name": tags.get("name", ""),
                               "water_y": _centroid_height(pts),
                               "points": pts})

    # -------------------------------------------------------------------
    # Buildings  – points stay [x, z]; building gains "base"
    # -------------------------------------------------------------------
    def building_height(tags: dict) -> float:
        h = tags.get("height", "")
        if h:
            try:
                return float(h.replace("m", "").strip())
            except ValueError:
                pass
        levels = tags.get("building:levels", "")
        if levels:
            try:
                return float(levels) * 3.5
            except ValueError:
                pass
        return 10.0

    buildings_out = []
    for wid, tags in ways_tags.items():
        if not tags.get("building"):
            continue
        nids = ways_nodes.get(wid, [])
        if len(nids) < 4 or nids[0] != nids[-1]:
            continue
        pts = _extract_polygon(nids)
        if len(pts) >= 3:
            buildings_out.append({
                "points": pts,
                "height": round(building_height(tags), 1),
                "base":   _centroid_height(pts),
            })

    # -------------------------------------------------------------------
    # Trees  – points become [x, terrain_y, z]
    # -------------------------------------------------------------------
    trees_out = []
    for e in elements:
        if e["type"] == "node" and e.get("tags", {}).get("natural") == "tree" and "lat" in e:
            x, z = project(e["lat"], e["lon"])
            trees_out.append([x, round(terrain(x, z), 2), z])

    # -------------------------------------------------------------------
    # Write park_data.json
    # -------------------------------------------------------------------
    out = {
        "ref_lat":            REF_LAT,
        "ref_lon":            REF_LON,
        "metres_per_deg_lat": METRES_PER_DEG_LAT,
        "metres_per_deg_lon": round(METRES_PER_DEG_LON, 2),
        "heightmap":          hm_out,
        "paths":              paths_out,
        "boundary":           boundary_pts,
        "water":              water_out,
        "trees":              trees_out,
        "buildings":          buildings_out,
    }

    with open("park_data.json", "w") as fh:
        json.dump(out, fh, separators=(",", ":"))

    size_kb = os.path.getsize("park_data.json") / 1024
    print(f"\nPaths:      {len(paths_out):5d}  (skipped {skipped_pts} with missing nodes)")
    print(f"Boundary:   {len(boundary_pts):5d}  points")
    print(f"Water:      {len(water_out):5d}  bodies")
    print(f"Trees:      {len(trees_out):5d}")
    print(f"Buildings:  {len(buildings_out):5d}")
    print(f"\nSaved → park_data.json  ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
