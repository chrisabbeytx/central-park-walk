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
    "service":    8.0,    # Park loop drives (East/West/Center Drive)
    "secondary":  10.0,   # Major transverse roads
    "bridleway":  3.5,    # Equestrian bridle paths
}

TERRAIN_Z   = 15           # zoom level matching download_terrain.py
TERRAIN_DIR = "terrain_tiles"
LIDAR_DEM   = "lidar_data/central_park_dem_4k.tif"  # LiDAR DEM 4096x4096 (~1.2 m/cell)
GRID_W      = 4096         # heightmap output resolution (~1.2 m/cell)
GRID_H      = 4096
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

    # Light Gaussian smooth (2 passes) via scipy — reduces quantization artifacts
    try:
        from scipy.ndimage import uniform_filter
        for _ in range(2):
            elev_m = uniform_filter(elev_m, size=3)
        print(f"  Applied 2-pass Gaussian smooth (scipy)")
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
            bld = {
                "points": pts,
                "height": round(building_height(tags), 1),
                "base":   _centroid_height(pts),
            }
            # Preserve building name and type for landmark identification
            bname = tags.get("name", "")
            if bname:
                bld["name"] = bname
            btype = tags.get("building", "yes")
            if btype != "yes":
                bld["building_type"] = btype
            # Material and colour for facade rendering
            bmat = tags.get("building:material", "")
            if bmat:
                bld["material"] = bmat
            bcolour = tags.get("building:colour", "")
            if bcolour:
                bld["colour"] = bcolour
            roof_shape = tags.get("roof:shape", "")
            if roof_shape and roof_shape != "flat":
                bld["roof_shape"] = roof_shape
            buildings_out.append(bld)

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
    # Trees — woodland polygons + NYC census (outside woodlands) + OSM
    #
    # Strategy:
    #   1. Build woodland polygons from OSM natural=wood
    #   2. Fill woodland polygons with trees at ~4m spacing
    #   3. Add NYC census trees that are OUTSIDE woodland polygons
    #   4. Add OSM individual tree nodes outside woodlands
    #   This avoids double-counting: woodland areas get dense fill,
    #   non-woodland areas get real census positions.
    # -------------------------------------------------------------------
    import random as _random
    _rng_wood = _random.Random(42)

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

    wood_area = sum(_poly_area(p) for p in wood_polys if _poly_area(p) >= 10.0)
    print(f"  Woodland polygons: {len(wood_polys)} ({wood_area:.0f} m²)")

    # --- Step 2: Fill woodland polygons with trees ---
    DEDUP_DIST = 5.0
    CELL = 10.0
    tree_hash: dict = {}
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
                    h = round(terrain(tx, tz), 2)
                    sp = _rng_wood.choice(["oak", "maple", "elm", "deciduous", "deciduous", "deciduous", "deciduous", "conifer"])
                    dbh = _rng_wood.randint(8, 24)
                    trees_out.append({"pos": [round(tx, 2), h, round(tz, 2)], "species": sp, "dbh": dbh})
                    ck = (int(tx // CELL), int(tz // CELL))
                    if ck not in tree_hash:
                        tree_hash[ck] = []
                    tree_hash[ck].append((tx, tz))
                    wood_added += 1
                gz += WOOD_SPACING
            gx += WOOD_SPACING
    print(f"  Trees: {wood_added} from woodland polygons (natural=wood)")

    # --- Step 3: NYC census trees OUTSIDE woodlands ---
    NYC_TREES = "lidar_data/central_park_trees.json"
    nyc_count = 0
    nyc_skipped = 0
    if os.path.exists(NYC_TREES):
        with open(NYC_TREES) as fh:
            nyc_trees = json.load(fh)
        for t in nyc_trees:
            x, z = project(t["lat"], t["lon"])
            # Skip trees in woodland areas — those areas are already filled
            if _in_any_wood(x, z, wood_polys):
                nyc_skipped += 1
                continue
            h = round(terrain(x, z), 2)
            sp_raw = t.get("species", "").lower()
            genus = sp_raw.split()[0] if sp_raw else ""
            archetype = SPECIES_MAP.get(genus, "deciduous")
            dbh = t.get("dbh", 0)
            trees_out.append({"pos": [x, h, z], "species": archetype, "dbh": dbh})
            ck = (int(x // CELL), int(z // CELL))
            if ck not in tree_hash:
                tree_hash[ck] = []
            tree_hash[ck].append((x, z))
            nyc_count += 1
        print(f"  Trees: +{nyc_count} from NYC census (outside woodlands, {nyc_skipped} skipped)")

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
    # Landuse zones — gardens, grass, pitches, playgrounds, etc.
    # These are area polygons for terrain texture differentiation.
    # -------------------------------------------------------------------
    LANDUSE_TAGS = {
        # tag_key: tag_value -> zone_type
        ("leisure", "garden"):         "garden",
        ("leisure", "pitch"):          "pitch",
        ("leisure", "playground"):     "playground",
        ("leisure", "swimming_pool"):  "pool",
        ("leisure", "sports_centre"):  "sports",
        ("leisure", "track"):          "track",
        ("leisure", "dog_park"):       "dog_park",
        ("landuse", "grass"):          "grass",
        ("leisure", "nature_reserve"): "nature_reserve",
        ("natural", "wood"):           "wood",
        ("landuse", "forest"):         "forest",
    }
    landuse_out = []
    for wid, tags in ways_tags.items():
        for (tk, tv), zone_type in LANDUSE_TAGS.items():
            if tags.get(tk) == tv:
                nids = ways_nodes.get(wid, [])
                if len(nids) < 4 or nids[0] != nids[-1]:
                    break
                pts = _extract_polygon(nids)
                if len(pts) >= 3:
                    landuse_out.append({
                        "type": zone_type,
                        "name": tags.get("name", ""),
                        "points": pts,
                    })
                break
    # Also resolve landuse relations (outer ways)
    for rel in relations:
        tags = rel.get("tags", {})
        for (tk, tv), zone_type in LANDUSE_TAGS.items():
            if tags.get(tk) == tv:
                members = rel.get("members", [])
                outer_ids = [m["ref"] for m in members
                             if m["type"] == "way" and m.get("role", "outer") == "outer"]
                if outer_ids:
                    pts = _extract_polygon(assemble_ring(outer_ids, ways_nodes))
                    if len(pts) >= 3:
                        landuse_out.append({
                            "type": zone_type,
                            "name": tags.get("name", ""),
                            "points": pts,
                        })
                break
    if landuse_out:
        print(f"  Landuse zones: {len(landuse_out)}")

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


if __name__ == "__main__":
    main()
