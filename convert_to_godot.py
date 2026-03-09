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
    "pedestrian": 12.0,   # Mall / Literary Walk ~40ft wide
    "footway":    3.5,
    "cycleway":   3.5,
    "path":       2.5,
    "steps":      3.0,
    "track":      3.0,
    "service":    8.0,    # Park loop drives (East/West/Center Drive)
    "secondary":  10.0,   # Major transverse roads
    "bridleway":  3.5,    # Equestrian bridle paths
}

TERRAIN_Z   = 15           # zoom level matching download_terrain.py
TERRAIN_DIR = "terrain_tiles"
LIDAR_DEM   = "lidar_data/central_park_dsm_enhanced_8k.tif"  # Structure-enhanced DSM (HH with trees removed)
GRID_W      = 8192         # heightmap output resolution (~0.6 m/cell)
GRID_H      = 8192
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

    # Light smooth (1 pass, size=2) — preserve fine features like stairs/walls
    try:
        from scipy.ndimage import uniform_filter
        elev_m = uniform_filter(elev_m, size=2)
        print(f"  Applied 1-pass light smooth (scipy, size=2)")
    except ImportError:
        print(f"  scipy not available, skipping smooth")

    W, H = GRID_W, GRID_H
    grid = elev_m.flatten().tolist()
    min_elev = min(grid)
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
        # Subtract min_elev so values start near 0
        flat_grid = [v - min_elev for v in hm_grid]
        hm_out = {
            "width":         GRID_W,
            "depth":         GRID_H,
            "world_size":    WORLD_SIZE,
            "origin_height": round(origin_height, 2),
        }
        # Binary format: uint32 width, uint32 height, float32 world_size,
        #   float32 origin_height, then width*height float32 values
        import struct
        with open("heightmap.bin", "wb") as fh:
            fh.write(struct.pack("<II", GRID_W, GRID_H))
            fh.write(struct.pack("<f", WORLD_SIZE))
            fh.write(struct.pack("<f", origin_height))
            fh.write(struct.pack(f"<{GRID_W * GRID_H}f", *flat_grid))
        hm_mb = os.path.getsize("heightmap.bin") / 1e6
        print(f"  Saved → heightmap.bin  ({hm_mb:.1f} MB)")
    else:
        hm_out = {}

    # -------------------------------------------------------------------
    # Paths  – points become [x, terrain_y, z]
    # -------------------------------------------------------------------
    paths_out  = []
    skipped_hw = 0
    skipped_pts = 0

    skipped_sidewalk = 0
    for wid, tags in ways_tags.items():
        hw = tags.get("highway")
        if hw not in HIGHWAY_WIDTH:
            skipped_hw += 1
            continue

        # Filter out city sidewalks and street crossings — not park paths
        footway_type = tags.get("footway", "")
        if footway_type in ("sidewalk", "crossing", "traffic_island"):
            skipped_sidewalk += 1
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
        # Preserve path name (East Drive, The Mall, etc.)
        path_name = tags.get("name", "")
        if path_name:
            entry["name"] = path_name
        # Preserve explicit OSM width
        osm_width = tags.get("width", "")
        if osm_width:
            try:
                entry["width"] = float(osm_width.replace("m", "").strip())
            except ValueError:
                pass
        if layer != 0:
            entry["layer"] = layer
        if is_bridge:
            entry["bridge"] = True
            bridge_name = tags.get("name", "")
            if bridge_name:
                entry["bridge_name"] = bridge_name
        if is_tunnel:
            entry["tunnel"] = True
            tunnel_name = tags.get("name", "")
            if tunnel_name:
                entry["tunnel_name"] = tunnel_name
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
    if skipped_sidewalk:
        print(f"  Paths: filtered out {skipped_sidewalk} sidewalks/crossings")

    # Retag Reservoir Running Track surface → tartan (distinctive cinder color)
    for p in paths_out:
        if "Running Track" in p.get("name", ""):
            p["surface"] = "tartan"

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
            wb = {"name": tags.get("name", ""),
                  "water_y": _centroid_height(pts),
                  "points": pts}
            wtype = tags.get("water", "")
            if wtype:
                wb["water_type"] = wtype  # reservoir, pond, lake, basin, etc.
            water_out.append(wb)

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
            wb = {"name": tags.get("name", ""),
                  "water_y": _centroid_height(pts),
                  "points": pts}
            wtype = tags.get("water", "")
            if wtype:
                wb["water_type"] = wtype
            water_out.append(wb)

    # --- Streams (linear waterways) ---
    streams_out = []
    for wid, tags in ways_tags.items():
        ww = tags.get("waterway", "")
        if ww not in ("stream", "river"):
            continue
        pts = []
        for nid in ways_nodes.get(wid, []):
            if nid in nodes_ll:
                x, z = project(*nodes_ll[nid])
                pts.append([x, round(terrain(x, z), 2), z])
        if len(pts) >= 2:
            streams_out.append({"name": tags.get("name", ""), "type": ww, "points": pts})
    if streams_out:
        print(f"  Streams: {len(streams_out)}")

    # -------------------------------------------------------------------
    # Buildings — real NYC footprints (preferred) + OSM in-park fallback
    # -------------------------------------------------------------------
    NYC_BUILDINGS_FILE = "nyc_buildings.geojson"
    buildings_out = []
    nyc_count = 0
    osm_count = 0

    # --- NYC Building Footprints (real measured data) ---
    if os.path.exists(NYC_BUILDINGS_FILE):
        with open(NYC_BUILDINGS_FILE) as fh:
            nyc_data = json.load(fh)
        for feat in nyc_data.get("features", []):
            props = feat.get("properties", {})
            geom = feat.get("geometry", {})
            h_ft = props.get("height_roof")
            if not h_ft or float(h_ft) <= 0:
                continue
            h_m = float(h_ft) * FT_TO_M
            # Extract footprint polygon — GeoJSON MultiPolygon or Polygon
            gtype = geom.get("type", "")
            if gtype == "MultiPolygon":
                rings = geom["coordinates"][0]  # first polygon
            elif gtype == "Polygon":
                rings = geom["coordinates"]
            else:
                continue
            outer = rings[0]  # outer ring: [[lon, lat], ...]
            if len(outer) < 4:
                continue
            # Project to world coordinates
            pts = []
            for coord in outer:
                lon, lat = coord[0], coord[1]
                pts.append(list(project(lat, lon)))
            # Remove duplicate closing point
            if len(pts) > 1 and pts[0] == pts[-1]:
                pts.pop()
            if len(pts) < 3:
                continue
            bld = {
                "points": pts,
                "height": round(h_m, 1),
                "base":   _centroid_height(pts),
            }
            # Ground elevation (feet NAVD88 → metres)
            ground_ft = props.get("ground_elevation")
            if ground_ft and float(ground_ft) > 0:
                bld["ground_elev"] = round(float(ground_ft) * FT_TO_M, 1)
            # Construction year → architectural era for style assignment
            yr = props.get("construction_year")
            if yr and int(yr) > 0:
                bld["year_built"] = int(yr)
            # Number of floors from height (NYC data doesn't have floor count,
            # but we can estimate: pre-war ~3.3m/floor, modern ~3.5m/floor)
            if yr and int(yr) > 0 and int(yr) < 1946:
                bld["num_floors"] = max(1, round(h_m / 3.3))
            else:
                bld["num_floors"] = max(1, round(h_m / 3.5))
            # BIN for cross-referencing
            bin_val = props.get("bin")
            if bin_val:
                bld["bin"] = str(bin_val)
            buildings_out.append(bld)
            nyc_count += 1
        print(f"  NYC buildings: {nyc_count} (real footprints + heights)")
    else:
        print(f"  WARNING: {NYC_BUILDINGS_FILE} not found — run download_buildings.py")

    # --- OSM buildings (fallback for in-park structures) ---
    # Collect NYC building centroids for dedup
    nyc_centroids = set()
    for bld in buildings_out:
        pts = bld["points"]
        cx = round(sum(p[0] for p in pts) / len(pts), 0)
        cz = round(sum(p[1] for p in pts) / len(pts), 0)
        nyc_centroids.add((cx, cz))

    def _osm_building_height(tags: dict) -> float:
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

    for wid, tags in ways_tags.items():
        if not tags.get("building"):
            continue
        nids = ways_nodes.get(wid, [])
        if len(nids) < 4 or nids[0] != nids[-1]:
            continue
        pts = _extract_polygon(nids)
        if len(pts) < 3:
            continue
        # Skip if we already have a NYC building at this location
        cx = round(sum(p[0] for p in pts) / len(pts), 0)
        cz = round(sum(p[1] for p in pts) / len(pts), 0)
        if (cx, cz) in nyc_centroids:
            continue
        bld = {
            "points": pts,
            "height": round(_osm_building_height(tags), 1),
            "base":   _centroid_height(pts),
        }
        bname = tags.get("name", "")
        if bname:
            bld["name"] = bname
        btype = tags.get("building", "yes")
        if btype != "yes":
            bld["building_type"] = btype
        bmat = tags.get("building:material", "")
        if bmat:
            bld["material"] = bmat
        bcolour = tags.get("building:colour", "")
        if bcolour:
            bld["colour"] = bcolour
        buildings_out.append(bld)
        osm_count += 1
    print(f"  OSM buildings: {osm_count} (in-park structures)")
    print(f"  Total buildings: {len(buildings_out)}")

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
    # Trees — NYC census (authoritative) + woodland fill + OSM
    #
    # Strategy:
    #   1. Load NYC census trees FIRST (real positions, species, DBH)
    #   2. Build woodland polygons from OSM natural=wood
    #   3. Fill woodland polygons with trees at ~4m spacing, SKIPPING
    #      cells near existing census trees (dedup)
    #   4. Add OSM individual tree nodes outside woodlands
    #   Census trees take priority — they have accurate species and positions.
    # -------------------------------------------------------------------
    import random as _random
    _rng_wood = _random.Random(42)

    # ── Foliage zones from Central Park Conservancy Fall Foliage Map ──
    # Each zone: [x_min, x_max, z_min, z_max, species_pool]
    # Street N → Z ≈ 1500 - (N - 66) * 75  (calibrated from OSM landmarks)
    # Species pools weighted by Conservancy's published dominant species per area.
    FOLIAGE_ZONES = [
        # 1. North Woods (W side, 101st-110th St)
        [-300, 700, -1800, -1125,
         ["elm", "oak", "oak", "maple", "maple", "deciduous", "deciduous", "conifer"]],
        # 2. Conservatory Garden (E side, 104th-106th St)
        [200, 600, -1500, -1350,
         ["deciduous", "deciduous", "deciduous", "maple", "maple"]],  # crabapple/magnolia → deciduous
        # 3. The Pool (W side, 100th-103rd St)
        [-600, 0, -1275, -1050,
         ["maple", "maple", "maple", "deciduous", "deciduous", "conifer"]],  # bald cypress, hickory, maples
        # 4. North Meadow (Mid-Park, 97th-102nd St)
        [-200, 600, -1200, -825,
         ["deciduous", "deciduous", "maple", "maple"]],  # dogwood, hickory, sugar maple
        # 5. Reservoir perimeter (Mid-Park, 85th-96th St)
        [-400, 300, -750, 75,
         ["deciduous", "deciduous", "deciduous", "deciduous"]],  # cherries → deciduous
        # 6. The Ramble (Mid-Park, 73rd-79th St)
        [-600, 0, 375, 975,
         ["oak", "oak", "maple", "deciduous", "deciduous", "deciduous", "conifer"]],
        # 7. The Mall / Literary Walk (Mid-Park, 66th-72nd St)
        [-700, -300, 1050, 1500,
         ["elm", "elm", "elm", "elm", "elm"]],  # American Elm canopy — signature trees
        # 8. Hallett Nature Sanctuary & The Pond (South, ~59th-62nd St)
        [-700, 100, 1650, 2050,
         ["oak", "oak", "birch", "deciduous", "deciduous", "deciduous"]],
    ]

    def _zone_species(x, z):
        """Return species pool for a given position, or None for default."""
        for zone in FOLIAGE_ZONES:
            if zone[0] <= x <= zone[1] and zone[2] <= z <= zone[3]:
                return zone[4]
        return None

    SPECIES_MAP = {
        # Deciduous — broad-leaved
        "quercus":     "oak",
        "acer":        "maple",
        "ulmus":       "elm",
        "betula":      "birch",
        "gleditsia":   "deciduous",  # honey locust (17% of park) — open, airy canopy
        "pyrus":       "deciduous",  # callery pear (10%)
        "ginkgo":      "deciduous",  # ginkgo (9%) — fan-shaped leaves, distinctive
        "platanus":    "deciduous",  # London plane (8%) — sycamore-like, tall
        "tilia":       "deciduous",  # linden/basswood
        "prunus":      "deciduous",  # cherry — spring blossoms
        "robinia":     "deciduous",  # black locust
        "celtis":      "deciduous",  # hackberry
        "fraxinus":    "deciduous",  # ash
        "liquidambar": "maple",      # sweetgum — star-shaped leaves, maple-like
        "cornus":      "deciduous",  # dogwood — small ornamental
        "magnolia":    "deciduous",  # magnolia
        "cercis":      "deciduous",  # redbud
        "malus":       "deciduous",  # crabapple
        "salix":       "deciduous",  # willow
        "fagus":       "deciduous",  # beech
        "carpinus":    "deciduous",  # hornbeam
        "zelkova":     "elm",        # zelkova — elm family, similar shape
        "sophora":     "deciduous",  # Japanese pagoda tree
        "catalpa":     "deciduous",  # catalpa — large leaves
        # Conifers
        "picea":       "conifer",
        "pinus":       "conifer",
        "abies":       "conifer",
        "tsuga":       "conifer",
        "juniperus":   "conifer",
        "thuja":       "conifer",
        "cedrus":      "conifer",
        "taxus":       "conifer",
        "metasequoia": "conifer",    # dawn redwood
        "cryptomeria": "conifer",    # Japanese cedar
    }

    def _point_in_poly(px, pz, poly):
        """Ray-casting point-in-polygon test. poly = list of (x, z)."""
        n = len(poly)
        inside = False
        j = n - 1
        for i in range(n):
            xi, zi = poly[i]
            xj, zj = poly[j]
            if ((zi > pz) != (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi):
                inside = not inside
            j = i
        return inside

    def _poly_area(poly):
        """Shoelace formula for polygon area."""
        n = len(poly)
        a = 0.0
        for i in range(n):
            j = (i + 1) % n
            a += poly[i][0] * poly[j][1]
            a -= poly[j][0] * poly[i][1]
        return abs(a) / 2.0

    def _in_any_wood(px, pz, polys):
        """Check if point is inside any woodland polygon."""
        for poly in polys:
            if _point_in_poly(px, pz, poly):
                return True
        return False

    # --- Step 1: Build woodland polygons ---
    wood_polys = []
    for e in elements:
        if e["type"] != "way":
            continue
        tags = e.get("tags", {})
        if tags.get("natural") != "wood":
            continue
        nds = e.get("nodes", [])
        if len(nds) < 3:
            continue
        pts = []
        for nid in nds:
            if nid in nodes_ll:
                lat, lon = nodes_ll[nid]
                x, z = project(lat, lon)
                pts.append((x, z))
        if len(pts) >= 3:
            wood_polys.append(pts)

    # Also resolve woodland relations (outer ways)
    for e in elements:
        if e["type"] != "relation":
            continue
        tags = e.get("tags", {})
        if tags.get("natural") != "wood":
            continue
        for member in e.get("members", []):
            if member.get("type") == "way" and member.get("role", "outer") == "outer":
                wid = member["ref"]
                if wid in ways_nodes:
                    nds = ways_nodes[wid]
                    pts = []
                    for nid in nds:
                        if nid in nodes_ll:
                            lat, lon = nodes_ll[nid]
                            x, z = project(lat, lon)
                            pts.append((x, z))
                    if len(pts) >= 3:
                        wood_polys.append(pts)

    wood_area = sum(a for p in wood_polys for a in [_poly_area(p)] if a >= 10.0)
    print(f"  Woodland polygons: {len(wood_polys)} ({wood_area:.0f} m²)")

    DEDUP_DIST = 3.0  # metres — avoid exact overlaps with census, keep woodland dense
    CELL = 10.0
    tree_hash: dict = {}

    # --- Step 2: NYC census trees FIRST (authoritative positions & species) ---
    NYC_TREES = "lidar_data/central_park_trees.json"
    nyc_count = 0
    if os.path.exists(NYC_TREES):
        with open(NYC_TREES) as fh:
            nyc_trees = json.load(fh)
        for t in nyc_trees:
            x, z = project(t["lat"], t["lon"])
            h = round(terrain(x, z), 2)
            sp_raw = t.get("species", "").lower()
            genus = sp_raw.split()[0] if sp_raw else ""
            archetype = SPECIES_MAP.get(genus, "deciduous")
            dbh = t.get("dbh", 0)
            trees_out.append({"pos": [round(x, 2), h, round(z, 2)], "species": archetype, "dbh": dbh})
            ck = (int(x // CELL), int(z // CELL))
            if ck not in tree_hash:
                tree_hash[ck] = []
            tree_hash[ck].append((x, z))
            nyc_count += 1
        print(f"  Trees: {nyc_count} from NYC census (all included)")

    # --- Step 3: Fill woodland polygons, skipping near census trees ---
    WOOD_SPACING = 4.0
    WOOD_JITTER = 1.5
    wood_added = 0
    for poly in wood_polys:
        xs = [p[0] for p in poly]
        zs = [p[1] for p in poly]
        xmin, xmax = min(xs), max(xs)
        zmin, zmax = min(zs), max(zs)
        area = _poly_area(poly)
        if area < 10.0:
            continue
        gx = xmin
        while gx <= xmax:
            gz = zmin
            while gz <= zmax:
                tx = gx + _rng_wood.uniform(-WOOD_JITTER, WOOD_JITTER)
                tz = gz + _rng_wood.uniform(-WOOD_JITTER, WOOD_JITTER)
                if _point_in_poly(tx, tz, poly):
                    # Skip if too close to an existing census tree
                    ck = (int(tx // CELL), int(tz // CELL))
                    too_close = False
                    for dx in range(-1, 2):
                        for dz in range(-1, 2):
                            for (ex, ez) in tree_hash.get((ck[0] + dx, ck[1] + dz), []):
                                if abs(ex - tx) < DEDUP_DIST and abs(ez - tz) < DEDUP_DIST:
                                    too_close = True
                                    break
                            if too_close:
                                break
                        if too_close:
                            break
                    if too_close:
                        gz += WOOD_SPACING
                        continue
                    h = round(terrain(tx, tz), 2)
                    zone_pool = _zone_species(tx, tz)
                    if zone_pool:
                        sp = _rng_wood.choice(zone_pool)
                    else:
                        sp = _rng_wood.choice(["oak", "maple", "elm", "deciduous", "deciduous", "deciduous", "deciduous", "conifer"])
                    dbh = _rng_wood.randint(8, 24)
                    trees_out.append({"pos": [round(tx, 2), h, round(tz, 2)], "species": sp, "dbh": dbh})
                    if ck not in tree_hash:
                        tree_hash[ck] = []
                    tree_hash[ck].append((tx, tz))
                    wood_added += 1
                gz += WOOD_SPACING
            gx += WOOD_SPACING
    print(f"  Trees: +{wood_added} from woodland polygons (natural=wood)")

    # --- Step 4: OSM individual tree nodes outside woodlands ---
    osm_added = 0
    for e in elements:
        if e["type"] != "node" or "lat" not in e:
            continue
        tags = e.get("tags", {})
        if tags.get("natural") != "tree":
            continue
        x, z = project(e["lat"], e["lon"])
        if _in_any_wood(x, z, wood_polys):
            continue
        ck = (int(x // CELL), int(z // CELL))
        duplicate = False
        for dx in range(-1, 2):
            for dz in range(-1, 2):
                for (tx, tz) in tree_hash.get((ck[0] + dx, ck[1] + dz), []):
                    if abs(tx - x) < DEDUP_DIST and abs(tz - z) < DEDUP_DIST:
                        duplicate = True
                        break
                if duplicate:
                    break
            if duplicate:
                break
        if not duplicate:
            h = round(terrain(x, z), 2)
            trees_out.append({"pos": [x, h, z], "species": "deciduous", "dbh": 12})
            if ck not in tree_hash:
                tree_hash[ck] = []
            tree_hash[ck].append((x, z))
            osm_added += 1
    print(f"  Trees: +{osm_added} from OSM individual nodes")
    print(f"  Trees total: {len(trees_out)}")

    # --- Step 5: Enrich with LiDAR heights from 6 Million Trees ---
    LIDAR_TREES = "lidar_data/6m_trees_central_park.json"
    if os.path.exists(LIDAR_TREES):
        with open(LIDAR_TREES) as fh:
            lidar_trees = json.load(fh)
        # Build spatial hash for LiDAR trees (10m cells)
        lidar_hash: dict = {}
        for lt in lidar_trees:
            lck = (int(lt["x"] // CELL), int(lt["z"] // CELL))
            if lck not in lidar_hash:
                lidar_hash[lck] = []
            lidar_hash[lck].append(lt)
        # Match each tree to nearest LiDAR point within 5m
        MATCH_DIST = 5.0
        matched = 0
        for tree in trees_out:
            tx, tz = tree["pos"][0], tree["pos"][2]
            tck = (int(tx // CELL), int(tz // CELL))
            best_d2 = MATCH_DIST * MATCH_DIST
            best_lt = None
            for dx in range(-1, 2):
                for dz in range(-1, 2):
                    for lt in lidar_hash.get((tck[0] + dx, tck[1] + dz), []):
                        d2 = (lt["x"] - tx) ** 2 + (lt["z"] - tz) ** 2
                        if d2 < best_d2:
                            best_d2 = d2
                            best_lt = lt
            if best_lt is not None:
                tree["lidar_h"] = round(best_lt["h"], 1)
                tree["crown_a"] = best_lt["a"]
                matched += 1
        print(f"  Trees: {matched}/{len(trees_out)} matched to LiDAR heights (6M Trees)")
    else:
        print(f"  Trees: LiDAR file not found ({LIDAR_TREES}), using DBH estimates only")

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
            statue = {
                "name": tags.get("name", ""), "type": stype,
                "position": [x, h, z],
            }
            # Preserve material, artist, inscription for future use
            mat = tags.get("material", "")
            if mat:
                statue["material"] = mat
            artist = tags.get("artist_name", "")
            if artist:
                statue["artist"] = artist
            inscription = tags.get("inscription", "")
            if inscription:
                statue["inscription"] = inscription
            statues_out.append(statue)
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
    # man_made=bridge and man_made=tunnel — structural outlines with names
    # Cross-reference with path bridges/tunnels for names and materials.
    # -------------------------------------------------------------------
    bridge_outlines = []
    tunnel_outlines = []
    for wid, tags in ways_tags.items():
        mm = tags.get("man_made", "")
        if mm == "bridge":
            nids = ways_nodes.get(wid, [])
            pts = []
            for nid in nids:
                if nid in nodes_ll:
                    x, z = project(*nodes_ll[nid])
                    pts.append([x, round(terrain(x, z), 2), z])
            if len(pts) >= 2:
                bo = {"name": tags.get("name", ""), "points": pts}
                structure = tags.get("bridge:structure", "")
                if structure:
                    bo["structure"] = structure  # arch, beam, humpback, etc.
                material = tags.get("material", "")
                if material:
                    bo["material"] = material
                bridge_outlines.append(bo)
        elif mm == "tunnel":
            nids = ways_nodes.get(wid, [])
            pts = []
            for nid in nids:
                if nid in nodes_ll:
                    x, z = project(*nodes_ll[nid])
                    pts.append([x, round(terrain(x, z), 2), z])
            if len(pts) >= 2:
                to = {"name": tags.get("name", ""), "points": pts}
                tunnel_outlines.append(to)
    if bridge_outlines:
        print(f"  Bridge outlines: {len(bridge_outlines)}")
    if tunnel_outlines:
        print(f"  Tunnel outlines: {len(tunnel_outlines)}")

    # -------------------------------------------------------------------
    # Rock outcrops — natural=rock (ways for outlines, nodes for points)
    # -------------------------------------------------------------------
    rocks_out = []
    for wid, tags in ways_tags.items():
        if tags.get("natural") != "rock":
            continue
        nids = ways_nodes.get(wid, [])
        if len(nids) < 3:
            continue
        pts = _extract_polygon(nids)
        if len(pts) >= 3:
            rocks_out.append({"name": tags.get("name", ""), "points": pts})
    for e in elements:
        if e["type"] != "node" or "lat" not in e:
            continue
        tags = e.get("tags", {})
        if tags.get("natural") == "rock":
            x, z = project(e["lat"], e["lon"])
            rocks_out.append({"name": tags.get("name", ""), "points": [[x, z]]})
    if rocks_out:
        print(f"  Rock outcrops: {len(rocks_out)}")

    # -------------------------------------------------------------------
    # Amenity points — fountains, toilets, restaurants, etc.
    # -------------------------------------------------------------------
    amenities_out = []
    for e in elements:
        if e["type"] != "node" or "lat" not in e:
            continue
        tags = e.get("tags", {})
        amenity = tags.get("amenity", "")
        if amenity in ("fountain", "drinking_water", "toilets", "restaurant", "cafe"):
            x, z = project(e["lat"], e["lon"])
            h = round(terrain(x, z), 2)
            amenities_out.append({
                "type": amenity,
                "name": tags.get("name", ""),
                "position": [x, h, z],
            })
    # Also from ways (fountain basins, restaurant buildings, etc.)
    for wid, tags in ways_tags.items():
        amenity = tags.get("amenity", "")
        if amenity in ("fountain", "toilets", "restaurant", "cafe", "theatre"):
            nids = ways_nodes.get(wid, [])
            pts_2d = [project(*nodes_ll[nid]) for nid in nids if nid in nodes_ll]
            if pts_2d:
                cx = sum(p[0] for p in pts_2d) / len(pts_2d)
                cz = sum(p[1] for p in pts_2d) / len(pts_2d)
                amenities_out.append({
                    "type": amenity,
                    "name": tags.get("name", ""),
                    "position": [cx, round(terrain(cx, cz), 2), cz],
                })
    if amenities_out:
        print(f"  Amenities: {len(amenities_out)}")

    # -------------------------------------------------------------------
    # Conservancy map data — playgrounds, restrooms, dining, facilities
    # Source: Central Park Conservancy downloadable maps (2025-2026)
    # Coordinates are approximate, derived from street/side designations.
    # Street N → Z ≈ 1500 - (N-66)*75; West edge X≈-750, East edge X≈350
    # -------------------------------------------------------------------

    # 21 playgrounds from Playground Map
    playgrounds = [
        # West side
        {"name": "Darlene & Julien Yoseoff Playground", "pos": [-500, -1800], "ages": "toddler, pre-school, school-age"},
        {"name": "Tarr Family Playground", "pos": [-600, -1050], "ages": "pre-school, school-age"},
        {"name": "Rudin Family Playground", "pos": [-650, -750], "ages": "pre-school, school-age"},
        {"name": "Tarr-Coyne Wild West Playground", "pos": [-650, -525], "ages": "pre-school, school-age"},
        {"name": "Safari Playground", "pos": [-650, -375], "ages": "toddler, pre-school"},
        {"name": "West 85th Street Playground", "pos": [-650, 75], "ages": "pre-school, school-age"},
        {"name": "Pinetum Playground", "pos": [-600, 75], "ages": "pre-school, school-age, teens, adults"},
        {"name": "Toll Family Playground", "pos": [-650, 150], "ages": "toddler, pre-school"},
        {"name": "Diana Ross Playground", "pos": [-650, 375], "ages": "pre-school, school-age"},
        {"name": "Tarr-Coyne Tots Playground", "pos": [-650, 1350], "ages": "toddler"},
        {"name": "Adventure Playground", "pos": [-650, 1425], "ages": "school-age"},
        {"name": "Heckscher Playground", "pos": [-400, 1725], "ages": "pre-school, school-age"},
        # East side
        {"name": "East 110th Street Playground", "pos": [400, -1800], "ages": "school-age"},
        {"name": "Bernard Family Playground", "pos": [400, -1650], "ages": "toddler, pre-school"},
        {"name": "Robert Bendheim Playground", "pos": [350, -1050], "ages": "pre-school, school-age"},
        {"name": "Margaret L. Kempner Playground", "pos": [350, -750], "ages": "pre-school, school-age"},
        {"name": "Ancient Playground", "pos": [300, 75], "ages": "pre-school, school-age"},
        {"name": "Smadbeck-Heckscher East Playground", "pos": [300, 525], "ages": "toddler, pre-school"},
        {"name": "James Michael Levin Playground", "pos": [300, 675], "ages": "pre-school, school-age"},
        {"name": "East 72nd Street Playground", "pos": [300, 1050], "ages": "school-age"},
        {"name": "Billy Johnson Playground", "pos": [300, 1425], "ages": "pre-school, school-age"},
    ]

    # Visitor centers and major facilities from General + Accessibility maps
    facilities = [
        {"name": "Charles A. Dana Discovery Center", "pos": [400, -1800], "type": "visitor_center"},
        {"name": "Belvedere Castle", "pos": [0, 525], "type": "visitor_center"},
        {"name": "Dairy Visitor Center & Gift Shop", "pos": [-500, 1425], "type": "visitor_center"},
        {"name": "Chess & Checkers House", "pos": [-450, 1500], "type": "facility"},
        {"name": "Columbus Circle Information Kiosk", "pos": [-900, 2025], "type": "visitor_center"},
        {"name": "North Meadow Recreation Center", "pos": [100, -1200], "type": "facility"},
        {"name": "Central Park Police Precinct", "pos": [-150, -450], "type": "building"},
        {"name": "Arsenal (NYC Parks HQ)", "pos": [350, 1575], "type": "building"},
        {"name": "Swedish Cottage Marionette Theatre", "pos": [-200, 600], "type": "building"},
        {"name": "Kerbs Boathouse", "pos": [-200, 900], "type": "building"},
        {"name": "Loeb Boathouse", "pos": [-300, 800], "type": "dining"},
        {"name": "Tavern on the Green", "pos": [-900, 1575], "type": "dining"},
        {"name": "Le Pain Quotidien (Mineral Springs)", "pos": [-700, 1200], "type": "dining"},
        {"name": "Central Park Zoo", "pos": [200, 1575], "type": "facility"},
        {"name": "Wollman Rink", "pos": [-600, 2100], "type": "facility"},
        {"name": "Lasker Pool/Rink", "pos": [800, -1950], "type": "facility"},
        {"name": "Delacorte Theater", "pos": [-200, 400], "type": "facility"},
        {"name": "SummerStage (Rumsey Playfield)", "pos": [-500, 1200], "type": "facility"},
        {"name": "North Gate House", "pos": [0, -600], "type": "building"},
        {"name": "South Gate House", "pos": [0, -375], "type": "building"},
    ]

    # Fall foliage zones — tree species by area (Conservancy Fall Foliage Map)
    foliage_zones = [
        {"name": "North Woods", "z_range": [-1800, -1125], "species": ["American Elm", "Black Cherry", "Pin Oak", "Red Maple", "Red Oak", "Scarlet Oak", "Sweetgum"]},
        {"name": "Conservatory Garden", "z_range": [-1500, -1350], "species": ["Crabapple", "Star Magnolia", "Stewartia"]},
        {"name": "The Pool", "z_range": [-1275, -1050], "species": ["Bald Cypress", "Hickory", "Red Maple", "Sugar Maple", "Sweetgum", "Tupelo"]},
        {"name": "North Meadow", "z_range": [-1200, -825], "species": ["Flowering Dogwood", "Hickory", "Sugar Maple"]},
        {"name": "Reservoir", "z_range": [-750, 75], "species": ["Kwanzan Cherry (west)", "Yoshino Cherry (east)"]},
        {"name": "The Ramble", "z_range": [375, 975], "species": ["Black Cherry", "Hickory", "Pin Oak", "Red Maple", "Red Oak", "Sassafras", "Sweetgum", "Tupelo"]},
        {"name": "The Mall", "z_range": [1050, 1500], "species": ["American Elm"]},
        {"name": "Hallett & The Pond", "z_range": [1650, 2050], "species": ["Black Cherry", "Ginkgo", "Gray Birch", "Hickory", "Pin Oak", "Sawtooth Oak", "Tupelo"]},
    ]

    print(f"  Conservancy data: {len(playgrounds)} playgrounds, {len(facilities)} facilities, {len(foliage_zones)} foliage zones")

    # -------------------------------------------------------------------
    # Landuse / leisure zones
    # -------------------------------------------------------------------
    landuse_out = []
    for wid, tags in ways_tags.items():
        zone_type = tags.get("leisure") or tags.get("landuse")
        if not zone_type:
            continue
        nids = ways_nodes.get(wid, [])
        if len(nids) < 4 or nids[0] != nids[-1]:
            continue
        pts = _extract_polygon(nids)
        if len(pts) >= 3:
            landuse_out.append({
                "name": tags.get("name", ""),
                "type": zone_type,
                "points": pts,
            })
    # Relation-based landuse/leisure
    for e in elements:
        if e["type"] != "relation":
            continue
        tags = e.get("tags", {})
        zone_type = tags.get("leisure") or tags.get("landuse")
        if not zone_type:
            continue
        members = e.get("members", [])
        outer_nids = []
        for m in members:
            if m.get("role") == "outer" and m.get("type") == "way":
                outer_nids.extend(ways_nodes.get(m["ref"], []))
        pts = _extract_polygon(outer_nids)
        if len(pts) >= 3:
            landuse_out.append({
                "name": tags.get("name", ""),
                "type": zone_type,
                "points": pts,
            })

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
        "streams":            streams_out,
        "trees":              trees_out,
        "buildings":          buildings_out,
        "barriers":           barriers_out,
        "statues":            statues_out,
        "benches":            benches_out,
        "lampposts":          lampposts_out,
        "trash_cans":         trash_cans_out,
        "landuse":            landuse_out,
        "bridge_outlines":    bridge_outlines,
        "tunnel_outlines":    tunnel_outlines,
        "rocks":              rocks_out,
        "amenities":          amenities_out,

        "playgrounds":        playgrounds,
        "facilities":         facilities,
        "foliage_zones":      foliage_zones,
    }

    with open("park_data.json", "w") as fh:
        json.dump(out, fh, separators=(",", ":"))

    size_kb = os.path.getsize("park_data.json") / 1024
    print(f"\nPaths:      {len(paths_out):5d}  (skipped {skipped_pts} with missing nodes)")
    print(f"Boundary:   {len(boundary_pts):5d}  points")
    print(f"Water:      {len(water_out):5d}  bodies")
    print(f"Streams:    {len(streams_out):5d}")
    print(f"Trees:      {len(trees_out):5d}")
    print(f"Buildings:  {len(buildings_out):5d}")
    print(f"Barriers:   {len(barriers_out):5d}")
    print(f"Statues:    {len(statues_out):5d}")
    print(f"Benches:    {len(benches_out):5d}")
    print(f"Lampposts:  {len(lampposts_out):5d}")
    print(f"Trash cans: {len(trash_cans_out):5d}")
    print(f"Landuse:    {len(landuse_out):5d}  zones")
    print(f"Bridges:    {len(bridge_outlines):5d}  outlines")
    print(f"Tunnels:    {len(tunnel_outlines):5d}  outlines")
    print(f"Rocks:      {len(rocks_out):5d}  outcrops")
    print(f"Amenities:  {len(amenities_out):5d}")
    print(f"\nSaved → park_data.json  ({size_kb:.0f} KB)")

    # Pre-bake path textures for fast Godot loading
    bridge_centroids = []
    for p in paths_out:
        if p.get("bridge") or int(p.get("layer", 0)) >= 1:
            pts = p["points"]
            bcx = sum(float(pt[0]) for pt in pts) / len(pts)
            bcz = sum(float(pt[2]) for pt in pts) / len(pts)
            bridge_centroids.append((bcx, bcz))
    prebake_paths(paths_out, bridge_centroids)


def prebake_paths(paths, bridge_centroids):
    """Pre-bake splat map + GPU path textures → binary files for fast Godot load."""
    import numpy as np
    import struct

    SPLAT_RES = 4096
    FEATHER = 1.2  # metres
    HALF = WORLD_SIZE / 2.0
    SCALE = SPLAT_RES / WORLD_SIZE

    # Same width/surface/priority tables as park_loader.gd
    HW_WIDTH = {
        "pedestrian": 12.0, "footway": 3.5, "cycleway": 3.5,
        "steps": 3.0, "track": 3.0, "service": 8.0,
        "secondary": 10.0, "bridleway": 3.5,
    }
    HW_PRIORITY = {
        "pedestrian": 0.05, "footway": 0.04, "steps": 0.03,
        "cycleway": 0.02, "path": 0.01, "track": 0.00,
    }

    def path_width(p):
        w = p.get("width", 0)
        if isinstance(w, (int, float)) and w > 0:
            return float(w)
        if isinstance(w, str) and w:
            try:
                wf = float(w)
                if wf > 0:
                    return wf
            except ValueError:
                pass
        return HW_WIDTH.get(p.get("highway", "path"), 2.5)

    def splat_mat_idx(hw, surface):
        surf_map = {
            "asphalt": 1, "concrete": 2, "concrete:plates": 3,
            "paving_stones": 4, "sett": 5, "unhewn_cobblestone": 6,
            "pebblestone": 7, "stone": 8, "rock": 9, "brick": 10,
            "compacted": 11, "fine_gravel": 12, "gravel": 13,
            "dirt": 14, "ground": 15, "grass": 17, "sand": 18,
            "earth": 19, "wood": 20, "metal": 21, "rubber": 22,
            "tartan": 23, "clay": 24, "mud": 25,
        }
        if surface in surf_map:
            return surf_map[surface]
        hw_map = {
            "pedestrian": 4, "footway": 11, "cycleway": 1,
            "path": 11, "steps": 8, "service": 1, "secondary": 1,
            "track": 29, "bridleway": 14,
        }
        return hw_map.get(hw, 16)

    def catmull_rom(pts, subdiv=4):
        """Catmull-Rom spline — same math as park_loader.gd."""
        if len(pts) < 3:
            return list(pts)
        out = []
        for i in range(len(pts) - 1):
            p0 = pts[max(i - 1, 0)]
            p1 = pts[i]
            p2 = pts[i + 1]
            p3 = pts[min(i + 2, len(pts) - 1)]
            x0, y0, z0 = float(p0[0]), float(p0[1]), float(p0[2])
            x1, y1, z1 = float(p1[0]), float(p1[1]), float(p1[2])
            x2, y2, z2 = float(p2[0]), float(p2[1]), float(p2[2])
            x3, y3, z3 = float(p3[0]), float(p3[1]), float(p3[2])
            for j in range(subdiv):
                t = j / subdiv
                t2 = t * t
                t3 = t2 * t
                vx = 0.5 * ((2*x1) + (-x0+x2)*t + (2*x0-5*x1+4*x2-x3)*t2 + (-x0+3*x1-3*x2+x3)*t3)
                vy = 0.5 * ((2*y1) + (-y0+y2)*t + (2*y0-5*y1+4*y2-y3)*t2 + (-y0+3*y1-3*y2+y3)*t3)
                vz = 0.5 * ((2*z1) + (-z0+z2)*t + (2*z0-5*z1+4*z2-z3)*t2 + (-z0+3*z1-3*z2+z3)*t3)
                out.append([vx, vy, vz])
        out.append(list(pts[-1]))
        return out

    def is_closed(pts):
        if len(pts) < 4:
            return False
        dx = float(pts[0][0]) - float(pts[-1][0])
        dz = float(pts[0][2]) - float(pts[-1][2])
        return (dx * dx + dz * dz) < 4.0

    def is_near_bridge(pts, bc_list):
        tcx = sum(float(p[0]) for p in pts) / len(pts)
        tcz = sum(float(p[2]) for p in pts) / len(pts)
        for bcx, bcz in bc_list:
            if math.hypot(tcx - bcx, tcz - bcz) < 60.0:
                return True
        return False

    # --- Filter ground paths (same logic as GDScript) ---
    ground_paths = []
    for p in paths:
        hw = p.get("highway", "path")
        layer = int(p.get("layer", 0))
        is_bridge = p.get("bridge", False) or layer >= 1
        is_tunnel = p.get("tunnel", False) or layer <= -1
        if is_bridge or hw == "steps":
            continue
        if is_tunnel and not is_near_bridge(p["points"], bridge_centroids):
            continue
        priority = HW_PRIORITY.get(hw, 0.01)
        ground_paths.append((priority, p))
    ground_paths.sort(key=lambda x: x[0])

    # --- Splat map: numpy vectorized rasterization ---
    print("  Pre-baking splat map (4096×4096)…")
    splat_mat = np.zeros((SPLAT_RES, SPLAT_RES), dtype=np.uint8)
    splat_cov = np.zeros((SPLAT_RES, SPLAT_RES), dtype=np.uint8)

    seg_count_splat = 0
    for _, p in ground_paths:
        hw = p.get("highway", "path")
        surf = p.get("surface", "")
        mat = splat_mat_idx(hw, surf)
        hw2 = path_width(p) * 0.5
        raw = p["points"]
        smoothed = catmull_rom(raw) if len(raw) >= 3 and hw != "steps" else raw
        # Subdivide to max 2.5m
        pts = []
        for i in range(len(smoothed)):
            pts.append(smoothed[i])
            if i < len(smoothed) - 1:
                dx = float(smoothed[i+1][0]) - float(smoothed[i][0])
                dz = float(smoothed[i+1][2]) - float(smoothed[i][2])
                seg_len = math.hypot(dx, dz)
                if seg_len > 2.5:
                    n = int(math.ceil(seg_len / 2.5))
                    for j in range(1, n):
                        t = j / n
                        pts.append([
                            float(smoothed[i][0]) + dx * t,
                            float(smoothed[i][1]) + (float(smoothed[i+1][1]) - float(smoothed[i][1])) * t,
                            float(smoothed[i][2]) + dz * t,
                        ])
        # Rasterize segments
        for i in range(len(pts) - 1):
            x0, z0 = float(pts[i][0]), float(pts[i][2])
            x1, z1 = float(pts[i+1][0]), float(pts[i+1][2])
            # Convert to pixel space
            px0 = (x0 + HALF) * SCALE
            pz0 = (z0 + HALF) * SCALE
            px1 = (x1 + HALF) * SCALE
            pz1 = (z1 + HALF) * SCALE
            pr = hw2 * SCALE
            feather = FEATHER * SCALE
            outer = pr + feather
            inner = max(pr - feather, 0.0)
            # Bounding box
            bmin_x = max(0, int(min(px0, px1) - outer))
            bmax_x = min(SPLAT_RES - 1, int(math.ceil(max(px0, px1) + outer)))
            bmin_z = max(0, int(min(pz0, pz1) - outer))
            bmax_z = min(SPLAT_RES - 1, int(math.ceil(max(pz0, pz1) + outer)))
            if bmax_x <= bmin_x or bmax_z <= bmin_z:
                continue
            # Vectorized distance computation
            zz, xx = np.mgrid[bmin_z:bmax_z+1, bmin_x:bmax_x+1]
            fpx = xx.astype(np.float32) + 0.5
            fpz = zz.astype(np.float32) + 0.5
            dx = px1 - px0
            dz = pz1 - pz0
            len_sq = dx * dx + dz * dz
            if len_sq < 0.001:
                dist_sq = (fpx - px0)**2 + (fpz - pz0)**2
            else:
                t = np.clip(((fpx - px0) * dx + (fpz - pz0) * dz) / len_sq, 0.0, 1.0)
                cx = px0 + t * dx
                cz = pz0 + t * dz
                dist_sq = (fpx - cx)**2 + (fpz - cz)**2
            outer_sq = outer * outer
            mask = dist_sq <= outer_sq
            dist = np.sqrt(dist_sq)
            range_inv = 1.0 / max(outer - inner, 0.001)
            s = np.clip((dist - inner) * range_inv, 0.0, 1.0)
            coverage = (1.0 - s * s * (3.0 - 2.0 * s)) * 255.0
            cov_byte = coverage.astype(np.uint8)
            # Apply where coverage exceeds existing
            region_cov = splat_cov[bmin_z:bmax_z+1, bmin_x:bmax_x+1]
            update = mask & (cov_byte >= region_cov)
            splat_mat[bmin_z:bmax_z+1, bmin_x:bmax_x+1][update] = mat
            splat_cov[bmin_z:bmax_z+1, bmin_x:bmax_x+1][update] = cov_byte[update]
            seg_count_splat += 1

    # Interleave to RG8 format: [mat, cov, mat, cov, ...]
    splat_data = np.zeros((SPLAT_RES, SPLAT_RES, 2), dtype=np.uint8)
    splat_data[:, :, 0] = splat_mat
    splat_data[:, :, 1] = splat_cov
    splat_bytes = splat_data.tobytes()
    with open("splat_map.bin", "wb") as f:
        f.write(struct.pack("<II", SPLAT_RES, SPLAT_RES))
        f.write(splat_bytes)
    print(f"  Splat map: {seg_count_splat} segments → splat_map.bin ({len(splat_bytes) / 1048576:.1f} MB)")

    # --- GPU path textures ---
    print("  Pre-baking GPU path textures…")
    SEG_TEX_W = 256
    GRID_CELL = 16.0
    GPU_GRID_W = 313
    LIST_TEX_W = 512

    # Collect open polyline segments (same filter as splat + skip closed polygons)
    segments = []  # [x0, z0, x1, z1, half_width, mat_idx]
    for _, p in ground_paths:
        hw = p.get("highway", "path")
        surf = p.get("surface", "")
        raw = p["points"]
        if is_closed(raw):
            continue
        hw2 = path_width(p) * 0.5
        mat = splat_mat_idx(hw, surf)
        smoothed = catmull_rom(raw) if len(raw) >= 3 else raw
        for si in range(len(smoothed) - 1):
            sx0 = float(smoothed[si][0])
            sz0 = float(smoothed[si][2])
            sx1 = float(smoothed[si + 1][0])
            sz1 = float(smoothed[si + 1][2])
            if (sx0 < -HALF and sx1 < -HALF) or (sx0 > HALF and sx1 > HALF):
                continue
            if (sz0 < -HALF and sz1 < -HALF) or (sz0 > HALF and sz1 > HALF):
                continue
            segments.append((sx0, sz0, sx1, sz1, hw2, mat))
    seg_count = len(segments)
    print(f"  GPU segments: {seg_count}")

    # Segment texture (RGBA32F, 2 rows per segment)
    seg_rows = ((seg_count + SEG_TEX_W - 1) // SEG_TEX_W) * 2
    if seg_rows < 2:
        seg_rows = 2
    seg_data = np.zeros((seg_rows, SEG_TEX_W, 4), dtype=np.float32)
    for si, seg in enumerate(segments):
        col = si % SEG_TEX_W
        row_base = (si // SEG_TEX_W) * 2
        seg_data[row_base, col] = [seg[0], seg[1], seg[2], seg[3]]
        seg_data[row_base + 1, col] = [seg[4], float(seg[5]), 0.0, 0.0]

    # Spatial grid binning
    from collections import defaultdict as dd
    grid_lists = dd(list)
    for si, seg in enumerate(segments):
        expand = seg[4] + FEATHER
        min_x = min(seg[0], seg[2]) - expand
        max_x = max(seg[0], seg[2]) + expand
        min_z = min(seg[1], seg[3]) - expand
        max_z = max(seg[1], seg[3]) + expand
        c0x = max(0, int((min_x + HALF) / GRID_CELL))
        c1x = min(GPU_GRID_W - 1, int((max_x + HALF) / GRID_CELL))
        c0z = max(0, int((min_z + HALF) / GRID_CELL))
        c1z = min(GPU_GRID_W - 1, int((max_z + HALF) / GRID_CELL))
        for cz in range(c0z, c1z + 1):
            for cx in range(c0x, c1x + 1):
                grid_lists[cz * GPU_GRID_W + cx].append(si)

    # Sort each cell by half_width descending
    for key in grid_lists:
        grid_lists[key].sort(key=lambda si: segments[si][4], reverse=True)

    # Flatten grid + list
    flat_list = []
    grid_data = np.zeros((GPU_GRID_W, GPU_GRID_W, 2), dtype=np.float32)
    for cz in range(GPU_GRID_W):
        for cx in range(GPU_GRID_W):
            key = cz * GPU_GRID_W + cx
            if key in grid_lists:
                cell = grid_lists[key]
                grid_data[cz, cx, 0] = float(len(flat_list))
                grid_data[cz, cx, 1] = float(len(cell))
                flat_list.extend(cell)

    list_count = len(flat_list)
    list_tex_h = max(1, math.ceil(list_count / LIST_TEX_W))
    list_data = np.zeros(LIST_TEX_W * list_tex_h, dtype=np.float32)
    for li, val in enumerate(flat_list):
        list_data[li] = float(val)

    # Save all three textures as binary
    with open("path_gpu.bin", "wb") as f:
        # Header
        f.write(struct.pack("<I", seg_count))
        f.write(struct.pack("<II", SEG_TEX_W, seg_rows))
        f.write(struct.pack("<II", GPU_GRID_W, GPU_GRID_W))
        f.write(struct.pack("<II", LIST_TEX_W, list_tex_h))
        f.write(struct.pack("<I", list_count))
        # Data
        f.write(seg_data.tobytes())
        f.write(grid_data.tobytes())
        f.write(list_data.tobytes())
    total_kb = (seg_data.nbytes + grid_data.nbytes + list_data.nbytes) / 1024
    print(f"  GPU textures: segs {SEG_TEX_W}×{seg_rows}, grid {GPU_GRID_W}×{GPU_GRID_W}, "
          f"list {LIST_TEX_W}×{list_tex_h} ({list_count} entries) → path_gpu.bin ({total_kb:.0f} KB)")


if __name__ == "__main__":
    main()
