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
LIDAR_DEM   = "lidar_data/central_park_dem.tif"  # LiDAR DEM (preferred)
GRID_W      = 2048         # heightmap output resolution (~2.4 m/cell)
GRID_H      = 2048
WORLD_SIZE  = 5000.0       # metres – must match main.gd ground plane size
FT_TO_M     = 0.3048006096  # US Survey Foot → metres


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
# Terrain heightmap – LiDAR DEM (preferred) or Terrarium PNG tiles (fallback)
# ---------------------------------------------------------------------------
def build_height_grid_lidar() -> tuple[list, float, float] | tuple[None, float, float]:
    """
    Read the clipped LiDAR DEM (WGS84, 2048×2048) and return:
        (flat_grid, min_elev, origin_height)
    Elevation values are in metres (converted from US Survey Feet).
    Returns (None, 0, 0) if file missing or GDAL unavailable.
    """
    if not os.path.exists(LIDAR_DEM):
        return None, 0.0, 0.0
    try:
        from osgeo import gdal
        import numpy as np
    except ImportError:
        print("  GDAL/numpy not available – skipping LiDAR DEM", file=sys.stderr)
        return None, 0.0, 0.0

    ds = gdal.Open(LIDAR_DEM)
    if ds is None:
        return None, 0.0, 0.0
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue()
    data = band.ReadAsArray()
    rows, cols = data.shape
    print(f"  LiDAR DEM: {cols}×{rows} pixels, nodata={nodata}")

    # Values are in US Survey Feet → convert to metres
    valid_mask = data != nodata if nodata is not None else np.ones_like(data, dtype=bool)
    elev_m = np.where(valid_mask, data * FT_TO_M, 0.0).astype(np.float64)
    elev_m = np.maximum(elev_m, 0.0)  # clamp negative (underwater) to 0
    print(f"  Valid pixels: {valid_mask.sum()}/{data.size} ({100*valid_mask.sum()/data.size:.1f}%)")
    print(f"  Elevation range: {elev_m[valid_mask].min():.2f} – {elev_m[valid_mask].max():.2f} m")

    # Fill nodata via iterative nearest-neighbor expansion
    invalid = ~valid_mask
    fill = elev_m.copy()
    for _ in range(300):
        if not invalid.any():
            break
        padded = np.pad(fill, 1, mode='edge')
        neighbors = np.zeros_like(fill)
        counts = np.zeros_like(fill)
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            s = padded[1 + dy:rows + 1 + dy, 1 + dx:cols + 1 + dx]
            sv = np.pad(~invalid, 1, mode='constant', constant_values=False)[1 + dy:rows + 1 + dy, 1 + dx:cols + 1 + dx]
            neighbors += np.where(sv, s, 0)
            counts += sv.astype(float)
        can_fill = invalid & (counts > 0)
        fill[can_fill] = neighbors[can_fill] / counts[can_fill]
        invalid[can_fill] = False
    elev_m = fill
    print(f"  Unfilled after fill: {invalid.sum()}")

    # Resample to GRID_W × GRID_H if needed
    if cols != GRID_W or rows != GRID_H:
        print(f"  Resampling {cols}×{rows} → {GRID_W}×{GRID_H}")
        from PIL import Image
        img = Image.fromarray(elev_m.astype(np.float32), mode='F')
        img = img.resize((GRID_W, GRID_H), Image.BILINEAR)
        elev_m = np.array(img, dtype=np.float64)

    # Light Gaussian smooth (2 passes) — LiDAR is already high quality,
    # just reduce 1-foot quantization artifacts at our 2.4m grid spacing
    W, H = GRID_W, GRID_H
    grid = elev_m.flatten().tolist()
    buf = [0.0] * (W * H)
    for _pass in range(2):
        for zi in range(1, H - 1):
            b = zi * W
            bm = (zi - 1) * W
            bp = (zi + 1) * W
            for xi in range(1, W - 1):
                buf[b + xi] = (
                    grid[b + xi]       * 0.25 +
                    grid[b + xi - 1]   * 0.125 +
                    grid[b + xi + 1]   * 0.125 +
                    grid[bm + xi]      * 0.125 +
                    grid[bp + xi]      * 0.125 +
                    grid[bm + xi - 1]  * 0.0625 +
                    grid[bm + xi + 1]  * 0.0625 +
                    grid[bp + xi - 1]  * 0.0625 +
                    grid[bp + xi + 1]  * 0.0625
                )
        for xi in range(W):
            buf[xi] = grid[xi]
            buf[(H - 1) * W + xi] = grid[(H - 1) * W + xi]
        for zi in range(H):
            buf[zi * W] = grid[zi * W]
            buf[zi * W + W - 1] = grid[zi * W + W - 1]
        grid, buf = buf, grid
    print(f"  Applied 2-pass Gaussian smooth")

    min_elev = min(grid)
    # Origin height: centre of grid
    origin_height = grid[(H // 2) * W + W // 2] - min_elev

    print(f"  Final: min={min_elev:.2f} m  max={max(grid):.2f} m  "
          f"origin_above_min={origin_height:.2f} m")
    ds = None
    return grid, min_elev, origin_height


def build_height_grid_terrarium() -> tuple[list, float, float] | tuple[None, float, float]:
    """Fallback: build heightmap from Terrarium PNG tiles."""
    try:
        from PIL import Image
    except ImportError:
        print("  PIL not found – skipping terrain", file=sys.stderr)
        return None, 0.0, 0.0

    bbox = dict(south=40.7644, north=40.7994, west=-73.9816, east=-73.9492)
    x0, y1 = latlon_to_tile(bbox["south"], bbox["west"], TERRAIN_Z)
    x1, y0 = latlon_to_tile(bbox["north"], bbox["east"], TERRAIN_Z)

    missing = [f"{TERRAIN_DIR}/{TERRAIN_Z}_{x}_{y}.png"
               for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)
               if not os.path.exists(f"{TERRAIN_DIR}/{TERRAIN_Z}_{x}_{y}.png")]
    if missing:
        print(f"  {len(missing)} tile(s) missing – run download_terrain.py", file=sys.stderr)
        return None, 0.0, 0.0

    TILE_PX = 256
    raster_w = (x1 - x0 + 1) * TILE_PX
    raster_h = (y1 - y0 + 1) * TILE_PX
    raster = [0.0] * (raster_w * raster_h)

    print(f"  Loading {(x1-x0+1)*(y1-y0+1)} Terrarium tiles → {raster_w}×{raster_h} raster…")
    for ty in range(y0, y1 + 1):
        for tx in range(x0, x1 + 1):
            path = f"{TERRAIN_DIR}/{TERRAIN_Z}_{tx}_{ty}.png"
            img = Image.open(path).convert("RGB")
            raw = img.tobytes()
            col0 = (tx - x0) * TILE_PX
            row0 = (ty - y0) * TILE_PX
            for py in range(TILE_PX):
                for px in range(TILE_PX):
                    off = (py * TILE_PX + px) * 3
                    r, g, b = raw[off], raw[off + 1], raw[off + 2]
                    h = r * 256 + g + b / 256 - 32768
                    h = max(h, 0.0)
                    raster[(row0 + py) * raster_w + (col0 + px)] = h

    n = 2 ** TERRAIN_Z

    def latlon_to_raster(lat, lon):
        lat_r = math.radians(lat)
        fx = (lon + 180) / 360 * n
        fy = (1 - math.log(math.tan(lat_r) + 1 / math.cos(lat_r)) / math.pi) / 2 * n
        return (fx - x0) * TILE_PX, (fy - y0) * TILE_PX

    def sample_raster(rx, ry):
        rx = max(0.0, min(rx, raster_w - 1.001))
        ry = max(0.0, min(ry, raster_h - 1.001))
        ix, iy = int(rx), int(ry)
        fx, fy = rx - ix, ry - iy
        h00 = raster[iy * raster_w + ix]
        h10 = raster[iy * raster_w + ix + 1]
        h01 = raster[(iy + 1) * raster_w + ix]
        h11 = raster[(iy + 1) * raster_w + ix + 1]
        return h00*(1-fx)*(1-fy) + h10*fx*(1-fy) + h01*(1-fx)*fy + h11*fx*fy

    half = WORLD_SIZE / 2.0
    cell = WORLD_SIZE / (GRID_W - 1)
    rx_col, ry_row = [], []
    for xi in range(GRID_W):
        lon = REF_LON + ((-half + xi * cell) / METRES_PER_DEG_LON)
        fx = (lon + 180.0) / 360.0 * n
        rx_col.append(max(0.0, min((fx - x0) * TILE_PX, raster_w - 1.001)))
    for zi in range(GRID_H):
        lat = REF_LAT + (-(-half + zi * cell) / METRES_PER_DEG_LAT)
        lat_r = math.radians(lat)
        fy = (1.0 - math.log(math.tan(lat_r) + 1.0 / math.cos(lat_r)) / math.pi) / 2.0 * n
        ry_row.append(max(0.0, min((fy - y0) * TILE_PX, raster_h - 1.001)))

    ix_col = [int(r) for r in rx_col]
    fx_col = [r - int(r) for r in rx_col]
    iy_row = [int(r) for r in ry_row]
    fy_row = [r - int(r) for r in ry_row]

    grid = [0.0] * (GRID_W * GRID_H)
    rw = raster_w
    print(f"  Sampling {GRID_W}×{GRID_H} grid…")
    for zi in range(GRID_H):
        iy, fy = iy_row[zi], fy_row[zi]
        iy1 = min(iy + 1, raster_h - 1)
        row0, row1 = iy * rw, iy1 * rw
        base = zi * GRID_W
        for xi in range(GRID_W):
            ix, fx = ix_col[xi], fx_col[xi]
            h = (raster[row0 + ix] * (1 - fx) * (1 - fy) + raster[row0 + ix + 1] * fx * (1 - fy) +
                 raster[row1 + ix] * (1 - fx) * fy + raster[row1 + ix + 1] * fx * fy)
            grid[base + xi] = max(h, 0.0)

    W, H = GRID_W, GRID_H
    buf = [0.0] * (W * H)
    for _pass in range(5):
        for zi in range(1, H - 1):
            b, bm, bp = zi * W, (zi - 1) * W, (zi + 1) * W
            for xi in range(1, W - 1):
                buf[b + xi] = (grid[b + xi] * 0.25 + grid[b + xi - 1] * 0.125 +
                    grid[b + xi + 1] * 0.125 + grid[bm + xi] * 0.125 +
                    grid[bp + xi] * 0.125 + grid[bm + xi - 1] * 0.0625 +
                    grid[bm + xi + 1] * 0.0625 + grid[bp + xi - 1] * 0.0625 +
                    grid[bp + xi + 1] * 0.0625)
        for xi in range(W):
            buf[xi] = grid[xi]; buf[(H-1)*W + xi] = grid[(H-1)*W + xi]
        for zi in range(H):
            buf[zi*W] = grid[zi*W]; buf[zi*W + W - 1] = grid[zi*W + W - 1]
        grid, buf = buf, grid
    print(f"  Applied 5-pass Gaussian smooth")

    min_elev = min(grid)
    origin_rx, origin_ry = latlon_to_raster(REF_LAT, REF_LON)
    origin_height = sample_raster(origin_rx, origin_ry) - min_elev
    print(f"  Elevation: min={min_elev:.1f} m  max={max(grid):.1f} m  "
          f"origin_above_min={origin_height:.1f} m")
    return grid, min_elev, origin_height


def build_height_grid() -> tuple[list, float, float]:
    """Try LiDAR DEM first, then Terrarium tiles."""
    print("  Trying LiDAR DEM…")
    grid, min_elev, origin_height = build_height_grid_lidar()
    if grid is not None:
        return grid, min_elev, origin_height
    print("  LiDAR not available, trying Terrarium tiles…")
    return build_height_grid_terrarium()


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
    # Terrain heightmap (LiDAR preferred, Terrarium fallback)
    # -------------------------------------------------------------------
    have_terrain = os.path.exists(LIDAR_DEM) or os.path.isdir(TERRAIN_DIR)
    if have_terrain:
        print("Building terrain height grid…")
        hm_grid, min_elev, origin_height = build_height_grid()
        have_terrain = hm_grid is not None
    else:
        hm_grid, min_elev, origin_height = None, 0.0, 0.0

    terrain = make_sampler(hm_grid, min_elev)

    if have_terrain:
        # 3 decimal places (~1mm) — sufficient for terrain, saves ~15-20MB vs 6 decimals
        flat_grid = [round(v - min_elev, 3) for v in hm_grid]
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
            bridge_name = tags.get("name", "")
            if bridge_name:
                entry["bridge_name"] = bridge_name
        if is_tunnel:
            entry["tunnel"] = True
        # Staircase metadata (previously discarded)
        if hw == "steps":
            sc = tags.get("step_count", "")
            if sc:
                try:
                    entry["step_count"] = int(sc)
                except ValueError:
                    pass
            if tags.get("handrail") in ("yes", "both", "left", "right"):
                entry["handrail"] = tags["handrail"]
            inc = tags.get("incline", "")
            if inc:
                entry["incline"] = inc
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
    # Single-pass node extraction: trees, statues, benches, lampposts, trash
    # (Previously 5 separate loops over elements — now 1)
    # -------------------------------------------------------------------
    BARRIER_HEIGHTS = {
        "wall": 1.2, "retaining_wall": 1.8, "fence": 1.5,
        "hedge": 1.2, "guard_rail": 0.9, "city_wall": 2.5,
    }
    COMPASS = {"N": 0, "NE": 45, "E": 90, "SE": 135,
               "S": 180, "SW": 225, "W": 270, "NW": 315}

    trees_out = []
    statues_out = []
    benches_out = []
    lampposts_out = []
    trash_cans_out = []

    # -------------------------------------------------------------------
    # Trees — NYC Parks Forestry census (preferred) or OSM nodes (fallback)
    # -------------------------------------------------------------------
    NYC_TREES = "lidar_data/central_park_trees.json"
    if os.path.exists(NYC_TREES):
        with open(NYC_TREES) as fh:
            nyc_trees = json.load(fh)
        # Map genus/species to tree archetype for Godot
        SPECIES_MAP = {
            "quercus":     "oak",
            "acer":        "maple",
            "ulmus":       "elm",
            "picea":       "conifer",
            "pinus":       "conifer",
            "abies":       "conifer",
            "tsuga":       "conifer",
            "juniperus":   "conifer",
            "thuja":       "conifer",
            "cedrus":      "conifer",
            "taxus":       "conifer",
        }
        for t in nyc_trees:
            x, z = project(t["lat"], t["lon"])
            h = round(terrain(x, z), 2)
            sp_raw = t.get("species", "").lower()
            genus = sp_raw.split()[0] if sp_raw else ""
            archetype = SPECIES_MAP.get(genus, "deciduous")
            dbh = t.get("dbh", 0)
            trees_out.append({"pos": [x, h, z], "species": archetype, "dbh": dbh})
        print(f"  Trees: {len(trees_out)} from NYC Parks Forestry census")
    else:
        # Fallback: OSM tree nodes
        for e in elements:
            if e["type"] != "node" or "lat" not in e:
                continue
            tags = e.get("tags", {})
            if tags.get("natural") == "tree":
                x, z = project(e["lat"], e["lon"])
                h = round(terrain(x, z), 2)
                trees_out.append({"pos": [x, h, z], "species": "deciduous", "dbh": 12})
        print(f"  Trees: {len(trees_out)} from OSM (fallback)")

    for e in elements:
        if e["type"] != "node" or "lat" not in e:
            continue
        tags = e.get("tags", {})
        if not tags:
            continue
        x, z = project(e["lat"], e["lon"])
        h = round(terrain(x, z), 2)

        # Statues / monuments / artworks
        stype = None
        if tags.get("historic") in ("memorial", "monument"):
            stype = tags["historic"]
        elif tags.get("tourism") == "artwork":
            stype = tags.get("artwork_type", "statue")
        elif tags.get("man_made") == "obelisk":
            stype = "obelisk"
        if stype:
            statues_out.append({
                "name": tags.get("name", ""), "type": stype,
                "position": [x, h, z],
            })
            continue

        # Benches
        if tags.get("amenity") == "bench":
            direction = 0.0
            raw_dir = tags.get("direction", "")
            if raw_dir:
                try:
                    direction = float(raw_dir)
                except ValueError:
                    direction = float(COMPASS.get(raw_dir.upper(), 0))
            benches_out.append([x, h, z, direction])
            continue

        # Lampposts
        if tags.get("highway") == "street_lamp":
            lampposts_out.append([x, h, z])
            continue

        # Trash cans
        if tags.get("amenity") == "waste_basket":
            trash_cans_out.append([x, h, z])

    # -------------------------------------------------------------------
    # Barriers  – walls, fences, retaining walls (ways only)
    # -------------------------------------------------------------------
    barriers_out = []

    # -------------------------------------------------------------------
    # Single-pass way extraction: barriers, statues, benches (from ways)
    # -------------------------------------------------------------------
    for wid, tags in ways_tags.items():
        # Barriers
        btype = tags.get("barrier")
        if btype in BARRIER_HEIGHTS:
            nids = ways_nodes.get(wid, [])
            pts = []
            for nid in nids:
                if nid in nodes_ll:
                    x, z = project(*nodes_ll[nid])
                    pts.append([x, round(terrain(x, z), 2), z])
            if len(pts) >= 2:
                h = BARRIER_HEIGHTS[btype]
                raw_h = tags.get("height", "")
                if raw_h:
                    try:
                        h = float(raw_h.replace("m", "").strip())
                    except ValueError:
                        pass
                barriers_out.append({
                    "type": btype, "height": round(h, 1),
                    "points": pts, "material": tags.get("material", ""),
                })
            continue

        # Statues from ways (monuments mapped as areas)
        stype = None
        if tags.get("historic") in ("memorial", "monument"):
            stype = tags["historic"]
        elif tags.get("man_made") == "obelisk":
            stype = "obelisk"
        if stype:
            nids = ways_nodes.get(wid, [])
            pts_2d = [list(project(*nodes_ll[nid])) for nid in nids if nid in nodes_ll]
            if len(pts_2d) >= 2:
                cx = sum(p[0] for p in pts_2d) / len(pts_2d)
                cz = sum(p[1] for p in pts_2d) / len(pts_2d)
                statues_out.append({
                    "name": tags.get("name", ""), "type": stype,
                    "position": [cx, round(terrain(cx, cz), 2), cz],
                })
            continue

        # Benches from ways (centroids)
        if tags.get("amenity") == "bench":
            nids = ways_nodes.get(wid, [])
            pts_2d = [project(*nodes_ll[nid]) for nid in nids if nid in nodes_ll]
            if pts_2d:
                cx = sum(p[0] for p in pts_2d) / len(pts_2d)
                cz = sum(p[1] for p in pts_2d) / len(pts_2d)
                benches_out.append([cx, round(terrain(cx, cz), 2), cz, 0.0])

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
        "barriers":           barriers_out,
        "statues":            statues_out,
        "benches":            benches_out,
        "lampposts":          lampposts_out,
        "trash_cans":         trash_cans_out,
    }

    with open("park_data.json", "w") as fh:
        json.dump(out, fh, separators=(",", ":"))

    size_kb = os.path.getsize("park_data.json") / 1024
    print(f"\nPaths:      {len(paths_out):5d}  (skipped {skipped_pts} with missing nodes)")
    print(f"Boundary:   {len(boundary_pts):5d}  points")
    print(f"Water:      {len(water_out):5d}  bodies")
    print(f"Trees:      {len(trees_out):5d}")
    print(f"Buildings:  {len(buildings_out):5d}")
    print(f"Barriers:   {len(barriers_out):5d}")
    print(f"Statues:    {len(statues_out):5d}")
    print(f"Benches:    {len(benches_out):5d}")
    print(f"Lampposts:  {len(lampposts_out):5d}")
    print(f"Trash cans: {len(trash_cans_out):5d}")
    print(f"\nSaved → park_data.json  ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
