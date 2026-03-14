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
import struct
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
LIDAR_DEM   = "lidar_data/central_park_dem_8k.tif"  # Bare earth DEM — clean ground level, no tree/structure peaks
LIDAR_DSM   = "lidar_data/central_park_dsm_enhanced_8k.tif"  # DSM with tree canopy masked — reveals rock outcrops, retaining walls, steps
GRID_W      = 8192         # heightmap output resolution (~0.6 m/cell)
GRID_H      = 8192
ATLAS_RES   = 8192         # world atlas / boundary / landuse grid — matches heightmap (0.61 m/cell)
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
def _load_lidar_raster(path, label="LiDAR raster"):
    """Load a LiDAR GeoTIFF → 2D float64 numpy array at GRID_W×GRID_H.

    Handles GDAL loading, US Survey Feet → metres conversion, nodata fill,
    resampling, and light smoothing. Returns None if unavailable.
    """
    if not os.path.exists(path):
        print(f"  {label}: file not found ({path})", file=sys.stderr)
        return None
    try:
        from osgeo import gdal
        import numpy as np
    except ImportError:
        print(f"  GDAL/numpy not available – skipping {label}", file=sys.stderr)
        return None

    ds = gdal.Open(path)
    if ds is None:
        return None
    band = ds.GetRasterBand(1)
    nodata = band.GetNoDataValue()
    data = band.ReadAsArray()
    rows, cols = data.shape
    print(f"  {label}: {cols}×{rows} pixels, nodata={nodata}")

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

    ds = None
    return elev_m


def build_height_grid_lidar() -> tuple[list, float, float] | tuple[None, float, float]:
    """
    Read the bare earth LiDAR DEM (8K) and return:
        (flat_grid, min_elev, origin_height)
    Elevation values are in metres (converted from US Survey Feet).
    Returns (None, 0, 0) if file missing or GDAL unavailable.
    """
    elev_m = _load_lidar_raster(LIDAR_DEM, "LiDAR DEM (bare earth)")
    if elev_m is None:
        return None, 0.0, 0.0

    W, H = GRID_W, GRID_H
    grid = elev_m.flatten().tolist()
    min_elev = min(grid)
    origin_height = grid[(H // 2) * W + W // 2] - min_elev

    print(f"  Final: min={min_elev:.2f} m  max={max(grid):.2f} m  "
          f"origin_above_min={origin_height:.2f} m")
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
# Binary park data (CPW1 format)
# ---------------------------------------------------------------------------
def _write_string_table(f, strings):
    """Write uint16 count, then count x (uint16 len, utf8 bytes)."""
    f.write(struct.pack('<H', len(strings)))
    for s in strings:
        encoded = s.encode('utf-8')
        f.write(struct.pack('<H', len(encoded)))
        f.write(encoded)


def _build_string_index(values):
    """Return (table: list[str], indices: list[int]) for a list of string values."""
    table = []
    lookup = {}
    indices = []
    for v in values:
        s = str(v) if v else ""
        if s not in lookup:
            lookup[s] = len(table)
            table.append(s)
        indices.append(lookup[s])
    return table, indices


def write_park_data_bin(filename, data_dict):
    """Write a binary version of park_data.json in CPW1 format.

    Designed for fast bulk reading via Godot FileAccess (little-endian).
    See format spec in project docs.
    """
    import io

    # -- Helpers to build section bytes in memory -------------------------
    def _pack_floats(vals):
        return struct.pack(f'<{len(vals)}f', *vals)

    def _pack_uint16s(vals):
        return struct.pack(f'<{len(vals)}H', *vals)

    def _pack_uint32s(vals):
        return struct.pack(f'<{len(vals)}I', *vals)

    sections = []  # list of (tag_bytes, data_bytes)

    # == META section =====================================================
    # Contains scalar metadata + all small/complex sections as JSON
    meta = {}
    for key in ("ref_lat", "ref_lon", "metres_per_deg_lat",
                "metres_per_deg_lon", "heightmap"):
        if key in data_dict:
            meta[key] = data_dict[key]
    for key in ("water", "streams", "statues", "landuse",
                "bridge_outlines", "tunnel_outlines", "rocks", "shrubbery",
                "amenities", "playgrounds", "facilities", "foliage_zones",
                "viewpoints", "attractions"):
        if key in data_dict:
            meta[key] = data_dict[key]

    meta_json = json.dumps(meta, separators=(",", ":")).encode('utf-8')
    meta_buf = struct.pack('<I', len(meta_json)) + meta_json
    sections.append((b"META", meta_buf))

    # == BNDY section =====================================================
    boundary = data_dict.get("boundary", [])
    bndy_buf = io.BytesIO()
    bndy_buf.write(struct.pack('<I', len(boundary)))
    for pt in boundary:
        bndy_buf.write(struct.pack('<2f', float(pt[0]), float(pt[1])))
    sections.append((b"BNDY", bndy_buf.getvalue()))

    # == TREE section (columnar) ==========================================
    trees = data_dict.get("trees", [])
    tree_buf = io.BytesIO()
    count = len(trees)
    tree_buf.write(struct.pack('<I', count))

    if count:
        species_vals = [t.get("species", "") for t in trees]
        sp_table, sp_idx = _build_string_index(species_vals)

        # species string table
        stab = io.BytesIO()
        _write_string_table(stab, sp_table)
        tree_buf.write(stab.getvalue())

        # positions: float32[count*3] (x,y,z interleaved)
        pos_floats = []
        for t in trees:
            p = t["pos"]
            pos_floats.extend([float(p[0]), float(p[1]), float(p[2])])
        tree_buf.write(_pack_floats(pos_floats))

        # species_idx: uint16[count]
        tree_buf.write(_pack_uint16s(sp_idx))

        # dbh: uint16[count]
        tree_buf.write(_pack_uint16s([int(t.get("dbh", 0)) for t in trees]))

        # lidar_h: float32[count]
        tree_buf.write(_pack_floats([float(t.get("lidar_h", 0)) for t in trees]))

        # crown_a: float32[count]
        tree_buf.write(_pack_floats([float(t.get("crown_a", 0)) for t in trees]))

    sections.append((b"TREE", tree_buf.getvalue()))

    # == BLDG section (columnar) ==========================================
    buildings = data_dict.get("buildings", [])
    bldg_buf = io.BytesIO()
    bcount = len(buildings)
    bldg_buf.write(struct.pack('<I', bcount))

    if bcount:
        # Gather all polygon points
        all_pts = []
        offsets = []
        pt_counts = []
        for b in buildings:
            offsets.append(len(all_pts))
            pts = b.get("points", [])
            pt_counts.append(len(pts))
            for pt in pts:
                all_pts.append((float(pt[0]), float(pt[1])))

        total_pts = len(all_pts)
        bldg_buf.write(struct.pack('<I', total_pts))

        # all_points: float32[total_pts*2]
        flat_pts = []
        for px, pz in all_pts:
            flat_pts.extend([px, pz])
        bldg_buf.write(_pack_floats(flat_pts))

        # offsets: uint32[count]
        bldg_buf.write(_pack_uint32s(offsets))

        # pt_counts: uint16[count]
        bldg_buf.write(_pack_uint16s(pt_counts))

        # heights: float32[count]
        bldg_buf.write(_pack_floats([float(b.get("height", 0)) for b in buildings]))

        # bases: float32[count]
        bldg_buf.write(_pack_floats([float(b.get("base", 0)) for b in buildings]))

        # ground_elevs: float32[count]
        bldg_buf.write(_pack_floats([float(b.get("ground_elev", 0)) for b in buildings]))

        # years: uint16[count]
        bldg_buf.write(_pack_uint16s([int(b.get("year_built", 0)) for b in buildings]))

        # floors: uint16[count]
        bldg_buf.write(_pack_uint16s([int(b.get("num_floors", 0)) for b in buildings]))

        # bin string table + indices
        bin_table, bin_idx = _build_string_index([b.get("bin", "") for b in buildings])
        stab = io.BytesIO()
        _write_string_table(stab, bin_table)
        bldg_buf.write(stab.getvalue())
        bldg_buf.write(_pack_uint16s(bin_idx))

        # name string table + indices
        name_table, name_idx = _build_string_index([b.get("name", "") for b in buildings])
        stab = io.BytesIO()
        _write_string_table(stab, name_table)
        bldg_buf.write(stab.getvalue())
        bldg_buf.write(_pack_uint16s(name_idx))

    sections.append((b"BLDG", bldg_buf.getvalue()))

    # == PATH section (columnar) ==========================================
    paths = data_dict.get("paths", [])
    path_buf = io.BytesIO()
    pcount = len(paths)
    path_buf.write(struct.pack('<I', pcount))

    if pcount:
        # String tables for highway, surface, name
        hw_table, hw_idx = _build_string_index([p.get("highway", "") for p in paths])
        surf_table, surf_idx = _build_string_index([p.get("surface", "") for p in paths])
        name_table, name_idx = _build_string_index([p.get("name", "") for p in paths])

        stab = io.BytesIO()
        _write_string_table(stab, hw_table)
        path_buf.write(stab.getvalue())

        stab = io.BytesIO()
        _write_string_table(stab, surf_table)
        path_buf.write(stab.getvalue())

        stab = io.BytesIO()
        _write_string_table(stab, name_table)
        path_buf.write(stab.getvalue())

        # Gather all path points (x,y,z)
        all_pts = []
        offsets = []
        pt_counts = []
        for p in paths:
            offsets.append(len(all_pts))
            pts = p.get("points", [])
            pt_counts.append(len(pts))
            for pt in pts:
                all_pts.append((float(pt[0]), float(pt[1]), float(pt[2])))

        total_pts = len(all_pts)
        path_buf.write(struct.pack('<I', total_pts))

        # all_points: float32[total_pts*3]
        flat_pts = []
        for px, py, pz in all_pts:
            flat_pts.extend([px, py, pz])
        path_buf.write(_pack_floats(flat_pts))

        # offsets: uint32[count]
        path_buf.write(_pack_uint32s(offsets))

        # pt_counts: uint16[count]
        path_buf.write(_pack_uint16s(pt_counts))

        # hw_idx, surf_idx, name_idx: uint16[count]
        path_buf.write(_pack_uint16s(hw_idx))
        path_buf.write(_pack_uint16s(surf_idx))
        path_buf.write(_pack_uint16s(name_idx))

    sections.append((b"PATH", path_buf.getvalue()))

    # == BARR section (columnar) ==========================================
    barriers = data_dict.get("barriers", [])
    barr_buf = io.BytesIO()
    bacount = len(barriers)
    barr_buf.write(struct.pack('<I', bacount))

    if bacount:
        type_table, type_idx = _build_string_index([b.get("type", "") for b in barriers])
        mat_table, mat_idx = _build_string_index([b.get("material", "") for b in barriers])

        stab = io.BytesIO()
        _write_string_table(stab, type_table)
        barr_buf.write(stab.getvalue())

        stab = io.BytesIO()
        _write_string_table(stab, mat_table)
        barr_buf.write(stab.getvalue())

        # Gather all barrier points (x,y,z)
        all_pts = []
        offsets = []
        pt_counts = []
        for b in barriers:
            offsets.append(len(all_pts))
            pts = b.get("points", [])
            pt_counts.append(len(pts))
            for pt in pts:
                all_pts.append((float(pt[0]), float(pt[1]), float(pt[2])))

        total_pts = len(all_pts)
        barr_buf.write(struct.pack('<I', total_pts))

        # all_points: float32[total_pts*3]
        flat_pts = []
        for px, py, pz in all_pts:
            flat_pts.extend([px, py, pz])
        barr_buf.write(_pack_floats(flat_pts))

        # offsets: uint32[count]
        barr_buf.write(_pack_uint32s(offsets))

        # pt_counts: uint16[count]
        barr_buf.write(_pack_uint16s(pt_counts))

        # type_idx: uint16[count]
        barr_buf.write(_pack_uint16s(type_idx))

        # heights: float32[count]
        barr_buf.write(_pack_floats([float(b.get("height", 0)) for b in barriers]))

        # mat_idx: uint16[count]
        barr_buf.write(_pack_uint16s(mat_idx))

    sections.append((b"BARR", barr_buf.getvalue()))

    # == BNCH section (flat float array) ==================================
    benches = data_dict.get("benches", [])
    bnch_buf = io.BytesIO()
    bnch_buf.write(struct.pack('<I', len(benches)))
    if benches:
        flat = []
        for b in benches:
            flat.extend([float(b[0]), float(b[1]), float(b[2]), float(b[3])])
        bnch_buf.write(_pack_floats(flat))
    sections.append((b"BNCH", bnch_buf.getvalue()))

    # == LAMP section (flat float array) ==================================
    lampposts = data_dict.get("lampposts", [])
    lamp_buf = io.BytesIO()
    lamp_buf.write(struct.pack('<I', len(lampposts)))
    if lampposts:
        flat = []
        for lp in lampposts:
            flat.extend([float(lp[0]), float(lp[1]), float(lp[2])])
        lamp_buf.write(_pack_floats(flat))
    sections.append((b"LAMP", lamp_buf.getvalue()))

    # == TRSH section (flat float array) ==================================
    trash_cans = data_dict.get("trash_cans", [])
    trsh_buf = io.BytesIO()
    trsh_buf.write(struct.pack('<I', len(trash_cans)))
    if trash_cans:
        flat = []
        for tc in trash_cans:
            flat.extend([float(tc[0]), float(tc[1]), float(tc[2])])
        trsh_buf.write(_pack_floats(flat))
    sections.append((b"TRSH", trsh_buf.getvalue()))

    # == FLAG section (flat float array) ==================================
    flagpoles = data_dict.get("flagpoles", [])
    flag_buf = io.BytesIO()
    flag_buf.write(struct.pack('<I', len(flagpoles)))
    if flagpoles:
        flat = []
        for fp in flagpoles:
            flat.extend([float(fp[0]), float(fp[1]), float(fp[2])])
        flag_buf.write(_pack_floats(flat))
    sections.append((b"FLAG", flag_buf.getvalue()))

    # -- Assemble the file ------------------------------------------------
    section_count = len(sections)
    # Header: magic(4) + version(4) + section_count(4) = 12
    # Directory: section_count * (tag(4) + offset(4) + size(4)) = section_count * 12
    header_size = 12 + section_count * 12

    # Calculate offsets
    offset = header_size
    directory = []
    for tag, data in sections:
        directory.append((tag, offset, len(data)))
        offset += len(data)

    with open(filename, "wb") as f:
        # File header
        f.write(b"CPW1")
        f.write(struct.pack('<I', 1))            # version
        f.write(struct.pack('<I', section_count))

        # Section directory
        for tag, sec_offset, sec_size in directory:
            f.write(tag)
            f.write(struct.pack('<II', sec_offset, sec_size))

        # Section data
        for _tag, data in sections:
            f.write(data)

    return os.path.getsize(filename)


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

        # Pre-bake 4K GPU texture (RG8 16-bit encoded heights)
        # Matches park_loader.gd _build_hm_gpu_texture() encoding exactly
        import numpy as np
        hm_arr = np.array(flat_grid, dtype=np.float32).reshape(GRID_H, GRID_W)
        hm_min_h = float(hm_arr.min())
        hm_max_h = float(hm_arr.max())
        hm_range = max(hm_max_h - hm_min_h, 0.01)
        TEX_RES = ATLAS_RES
        # Nearest-neighbor downsample matching GDScript: int(i * scale + 0.5)
        sx = (GRID_W - 1) / (TEX_RES - 1)
        sz = (GRID_H - 1) / (TEX_RES - 1)
        xi_src = np.clip(np.round(np.arange(TEX_RES) * sx).astype(int), 0, GRID_W - 1)
        zi_src = np.clip(np.round(np.arange(TEX_RES) * sz).astype(int), 0, GRID_H - 1)
        arr4k = hm_arr[np.ix_(zi_src, xi_src)]
        norm = np.clip((arr4k - hm_min_h) / hm_range, 0.0, 1.0)
        h16 = (norm * 65535.0).astype(np.uint16)
        rg8 = np.empty((TEX_RES, TEX_RES, 2), dtype=np.uint8)
        rg8[:, :, 0] = (h16 >> 8).astype(np.uint8)    # R = high byte
        rg8[:, :, 1] = (h16 & 0xFF).astype(np.uint8)  # G = low byte
        with open("heightmap_gpu.bin", "wb") as fh:
            fh.write(struct.pack("<II", TEX_RES, TEX_RES))
            fh.write(struct.pack("<ff", hm_min_h, hm_max_h))
            fh.write(rg8.tobytes())
        gpu_kb = os.path.getsize("heightmap_gpu.bin") / 1024
        print(f"  Saved → heightmap_gpu.bin ({TEX_RES}×{TEX_RES} RG8, {gpu_kb:.0f} KB)")

        # Terrain mesh prebake deferred — needs boundary_pts loaded below
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
    # Prefer authoritative boundary from Nominatim GeoJSON (correct 3.35 km² polygon)
    # over the OSM bicycle-route relation which only covers ~1.96 km².
    boundary_pts: list = []
    BOUNDARY_FILE = os.path.join(os.path.dirname(__file__),
                                 "lidar_data", "central_park_boundary_osm.json")
    if os.path.exists(BOUNDARY_FILE):
        with open(BOUNDARY_FILE) as bf:
            ring = json.load(bf)  # [[lon, lat], ...] GeoJSON order
        for lon_lat in ring:
            x, z = project(lon_lat[1], lon_lat[0])
            boundary_pts.append([round(x, 2), round(z, 2)])
        if boundary_pts and boundary_pts[0] == boundary_pts[-1]:
            boundary_pts.pop()
        print(f"  Boundary: {len(boundary_pts)} points from {BOUNDARY_FILE}")
    else:
        # Fallback: assemble from OSM relation (may be incomplete)
        cp_rel = None
        for rel in relations:
            tags = rel.get("tags", {})
            if tags.get("name") == "Central Park" and tags.get("type") == "multipolygon":
                cp_rel = rel
                break
        if cp_rel is None:
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

    # Filter water bodies to park boundary (Overpass bbox catches rivers extending
    # far outside — e.g. Harlem River at Z=-10471, West Channel at Z=+4029)
    if boundary_pts:
        bx_w = [float(p[0]) for p in boundary_pts]
        bz_w = [float(p[1]) for p in boundary_pts]
        bnd_w = len(boundary_pts)

        def _centroid_in_boundary(pts_2d):
            cx = sum(p[0] for p in pts_2d) / len(pts_2d)
            cz = sum(p[1] for p in pts_2d) / len(pts_2d)
            inside = False
            j = bnd_w - 1
            for i in range(bnd_w):
                zi, zj = bz_w[i], bz_w[j]
                if (zi > cz) != (zj > cz):
                    if cx < bx_w[i] + (cz - zi) / (zj - zi) * (bx_w[j] - bx_w[i]):
                        inside = not inside
                j = i
            return inside

        before = len(water_out)
        water_out = [w for w in water_out if _centroid_in_boundary(w["points"])]
        removed = before - len(water_out)
        if removed:
            print(f"  Water: removed {removed} bodies outside park boundary")

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
        # Floor count from OSM or estimated from height
        levels_str = tags.get("building:levels", "")
        if levels_str:
            try:
                bld["num_floors"] = int(float(levels_str))
            except ValueError:
                pass
        if "num_floors" not in bld:
            bld["num_floors"] = max(1, round(bld["height"] / 3.5))
        # Start date for age patina
        sd = tags.get("start_date", "")
        if sd:
            try:
                bld["year_built"] = int(sd[:4])
            except ValueError:
                pass
        buildings_out.append(bld)
        osm_count += 1
    print(f"  OSM buildings: {osm_count} (in-park structures)")
    print(f"  Total buildings (pre-filter): {len(buildings_out)}")

    # Filter buildings by distance to park boundary polygon (80m max).
    # Buildings beyond the first ring don't inform the park simulation.
    MAX_BUILDING_DIST = 350.0  # metres from park boundary — captures first 1-2 rows of buildings
    if len(boundary_pts) >= 3:
        # Precompute boundary arrays + AABB for fast rejection
        bx_arr = [float(p[0]) for p in boundary_pts]
        bz_arr = [float(p[1]) for p in boundary_pts]
        bnd_n = len(boundary_pts)
        aabb_xmin = min(bx_arr) - MAX_BUILDING_DIST
        aabb_xmax = max(bx_arr) + MAX_BUILDING_DIST
        aabb_zmin = min(bz_arr) - MAX_BUILDING_DIST
        aabb_zmax = max(bz_arr) + MAX_BUILDING_DIST
        thresh_sq = MAX_BUILDING_DIST * MAX_BUILDING_DIST

        def _near_or_in_boundary(px, pz):
            """Check if point is inside boundary or within MAX_BUILDING_DIST of it."""
            # AABB reject
            if px < aabb_xmin or px > aabb_xmax or pz < aabb_zmin or pz > aabb_zmax:
                return False
            # Point-in-polygon (ray casting)
            inside = False
            j = bnd_n - 1
            for i in range(bnd_n):
                zi, zj = bz_arr[i], bz_arr[j]
                if (zi > pz) != (zj > pz):
                    if px < bx_arr[i] + (pz - zi) / (zj - zi) * (bx_arr[j] - bx_arr[i]):
                        inside = not inside
                j = i
            if inside:
                return True
            # Distance to nearest boundary segment
            for i in range(bnd_n):
                ni = (i + 1) % bnd_n
                abx, abz = bx_arr[ni] - bx_arr[i], bz_arr[ni] - bz_arr[i]
                len_sq = abx * abx + abz * abz
                if len_sq < 0.001:
                    dsq = (px - bx_arr[i]) ** 2 + (pz - bz_arr[i]) ** 2
                else:
                    t = max(0.0, min(1.0, ((px - bx_arr[i]) * abx + (pz - bz_arr[i]) * abz) / len_sq))
                    cx, cz = bx_arr[i] + t * abx, bz_arr[i] + t * abz
                    dsq = (px - cx) ** 2 + (pz - cz) ** 2
                if dsq <= thresh_sq:
                    return True
            return False

        filtered = []
        for bld in buildings_out:
            pts = bld["points"]
            cx = sum(float(p[0]) for p in pts) / len(pts)
            cz = sum(float(p[1]) for p in pts) / len(pts)
            if _near_or_in_boundary(cx, cz):
                filtered.append(bld)
        print(f"  Filtered to {len(filtered)} buildings (within {MAX_BUILDING_DIST}m of boundary, "
              f"{len(buildings_out) - len(filtered)} removed)")
        buildings_out = filtered

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
    flagpoles_out = []

    # -------------------------------------------------------------------
    # Trees — NYC census (authoritative) + OSM individual nodes + woodland fill
    #
    # Strategy:
    #   1. Load NYC census trees (real positions, species, DBH)
    #   2. Add OSM individual tree nodes (dedup against census)
    #   3. Fill OSM natural=wood polygons with scattered trees
    #      (census only covers street trees, not park interior)
    # -------------------------------------------------------------------

    SPECIES_MAP = {
        # 12 visual archetypes — each gets distinct crown shape, leaf/bark color, fall colors
        # Deciduous — broad-leaved
        "quercus":     "oak",           # 7% pin oak + 3% red/swamp/willow oak
        "acer":        "maple",         # 2% — red maple, sugar maple, Norway maple
        "ulmus":       "elm",           # 4.4% American elm — iconic vase shape
        "betula":      "birch",         # 0.1% — white bark
        "gleditsia":   "honeylocust",   # 17% — airy compound leaves, open canopy
        "pyrus":       "callery_pear",  # 10% — dense ovoid crown, white spring bloom
        "ginkgo":      "ginkgo",        # 9% — columnar, fan leaves, golden fall
        "platanus":    "london_plane",  # 8% — tall broad crown, mottled bark
        "tilia":       "linden",        # 7% — dense symmetrical, heart-shaped leaves
        "prunus":      "cherry",        # 2.4% — small ornamental, spring blossoms
        "zelkova":     "zelkova",       # 3.7% — upright vase, elm family
        "styphnolobium": "deciduous",   # 5.7% Japanese pagoda — broad, spreading
        "robinia":     "honeylocust",   # black locust — similar airy compound leaves
        "celtis":      "deciduous",     # hackberry
        "fraxinus":    "deciduous",     # ash
        "liquidambar": "maple",         # sweetgum — star-shaped leaves, maple-like
        "cornus":      "cherry",        # dogwood — small ornamental, like cherry
        "magnolia":    "magnolia",      # saucer magnolia — spreading, spring bloom
        "cercis":      "cherry",        # redbud — small ornamental
        "malus":       "cherry",        # crabapple — small ornamental, spring blooms
        "salix":       "willow",        # weeping willow — cascading branches
        "fagus":       "deciduous",     # beech
        "carpinus":    "deciduous",     # hornbeam
        "sophora":     "deciduous",     # Japanese pagoda tree (old genus name)
        "catalpa":     "deciduous",     # catalpa — large leaves
        "gymnocladus": "honeylocust",   # Kentucky coffeetree — similar compound leaves
        "crataegus":   "cherry",        # hawthorn — small ornamental
        # Conifers
        "picea":       "conifer",
        "pinus":       "conifer",
        "abies":       "conifer",
        "tsuga":       "conifer",
        "juniperus":   "conifer",
        "thuja":       "conifer",
        "cedrus":      "conifer",
        "taxus":       "conifer",
        "metasequoia": "conifer",       # dawn redwood
        "cryptomeria": "conifer",       # Japanese cedar
    }

    DEDUP_DIST = 3.0  # metres — avoid exact overlaps between census and OSM
    CELL = 10.0
    tree_hash: dict = {}

    # --- Step 1: NYC census trees (authoritative positions & species) ---
    # Pre-filter to boundary + 20m buffer (census includes surrounding street trees)
    def _pip(px, pz, poly):
        """Point-in-polygon (ray casting)."""
        n = len(poly)
        inside = False
        j = n - 1
        for i in range(n):
            xi, zi = float(poly[i][0]), float(poly[i][1])
            xj, zj = float(poly[j][0]), float(poly[j][1])
            if ((zi > pz) != (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi):
                inside = not inside
            j = i
        return inside

    def _near_boundary(px, pz, poly, dist):
        """Check if point is within dist metres of any boundary segment."""
        thresh_sq = dist * dist
        n = len(poly)
        for i in range(n):
            ax, az = float(poly[i][0]), float(poly[i][1])
            bx, bz = float(poly[(i+1) % n][0]), float(poly[(i+1) % n][1])
            dx, dz = bx - ax, bz - az
            l2 = dx * dx + dz * dz
            if l2 < 0.001:
                dsq = (px - ax) ** 2 + (pz - az) ** 2
            else:
                t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / l2))
                cx, cz = ax + t * dx, az + t * dz
                dsq = (px - cx) ** 2 + (pz - cz) ** 2
            if dsq < thresh_sq:
                return True
        return False

    NYC_TREES = "lidar_data/central_park_trees.json"
    nyc_count = 0
    nyc_filtered = 0
    if os.path.exists(NYC_TREES):
        with open(NYC_TREES) as fh:
            nyc_trees = json.load(fh)
        for t in nyc_trees:
            x, z = project(t["lat"], t["lon"])
            # Skip trees outside park boundary (with 20m buffer for edge trees)
            if not _pip(x, z, boundary_pts) and not _near_boundary(x, z, boundary_pts, 20.0):
                nyc_filtered += 1
                continue
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
        print(f"  Trees: {nyc_count} from NYC census ({nyc_filtered} filtered outside boundary)")

    # --- Step 2: OSM individual tree nodes ---
    osm_added = 0
    for e in elements:
        if e["type"] != "node" or "lat" not in e:
            continue
        tags = e.get("tags", {})
        if tags.get("natural") != "tree":
            continue
        x, z = project(e["lat"], e["lon"])
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

    # --- Step 3: Enrich with LiDAR heights from 6 Million Trees ---
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

    # --- Step 4: Fill OSM natural=wood polygons with scattered trees ---
    # NYC census covers street trees only. Park interior woodland needs procedural fill.
    #
    # Ecological model based on Central Park Conservancy published data,
    # NYC Parks natural areas assessment, and documented forest ecology of
    # the park's named woodland zones. Species weighted by documented
    # dominance in each zone. DBH follows inverse-J distribution typical
    # of uneven-aged urban forest (many saplings, fewer mature trees).
    # Density varies by zone character: dense successional forest vs
    # open managed woodland vs ornamental groves.
    import random as _rng
    _rng.seed(42)
    MIN_TREE_SPACING = 3.5  # minimum spacing in metres

    # Common name → archetype mapping
    ZONE_SPECIES_MAP = {
        "american elm": "elm", "pin oak": "oak", "red oak": "oak",
        "scarlet oak": "oak", "sawtooth oak": "oak", "white oak": "oak",
        "black cherry": "cherry", "yoshino cherry": "cherry",
        "kwanzan cherry": "cherry", "cornelian cherry": "cherry",
        "red maple": "maple", "sugar maple": "maple", "norway maple": "maple",
        "sweetgum": "deciduous", "tupelo": "deciduous", "black tupelo": "deciduous",
        "sassafras": "deciduous", "hickory": "deciduous", "shagbark hickory": "deciduous",
        "pignut hickory": "deciduous", "black locust": "honeylocust",
        "honeylocust": "honeylocust", "black walnut": "deciduous",
        "crabapple": "callery_pear", "star magnolia": "magnolia",
        "stewartia": "deciduous", "bald cypress": "conifer",
        "eastern redcedar": "conifer", "white pine": "conifer",
        "austrian pine": "conifer", "eastern hemlock": "conifer",
        "flowering dogwood": "cherry", "gray birch": "birch",
        "river birch": "birch", "paper birch": "birch",
        "ginkgo": "ginkgo", "london plane": "london_plane",
        "linden": "linden", "littleleaf linden": "linden",
        "american linden": "linden", "zelkova": "deciduous",
        "kentucky coffeetree": "deciduous", "catalpa": "deciduous",
        "horsechestnut": "deciduous", "beech": "deciduous",
        "hackberry": "elm",  # Celtis — vase-shaped, similar habit to elm
        "birch": "birch",
        "weeping willow": "willow", "willow": "willow",
        "star magnolia": "magnolia", "saucer magnolia": "magnolia",
        "magnolia": "magnolia",
    }

    # --- Ecological zone model ---
    # Each zone: z_range, weighted species list (species, weight), density
    # multiplier (1.0 = 150 trees/ha), and DBH parameters.
    #
    # Weights reflect documented species dominance from Conservancy reports
    # and the 2013 Natural Areas Conservancy assessment. Zones overlap where
    # ecological transitions occur naturally.
    #
    # Zone types:
    #   "successional" — dense regrowth forest (North Woods, Hallett)
    #   "managed"      — curated woodland with clearings (Ramble, Dene)
    #   "grove"        — open canopy, widely spaced (Mall elms, Cherry Hill)
    #   "mixed"        — transitional, varied structure

    BASE_DENSITY = 0.015  # trees/m² = 150/ha baseline

    _foliage_zones = [
        # NORTH WOODS (110th–102nd): Central Park's most natural woodland.
        # Dense successional oak-hickory forest with native understory.
        # The Loch ravine adds moisture-loving species. Highest density in park.
        {
            "z_range": [-1800, -1125],
            "type": "successional",
            "density_mult": 1.3,  # dense canopy, 195 trees/ha
            "species": [
                ("red oak", 0.22), ("pin oak", 0.12), ("scarlet oak", 0.08),
                ("red maple", 0.10), ("sugar maple", 0.06),
                ("black cherry", 0.10), ("sweetgum", 0.08),
                ("hickory", 0.06), ("tupelo", 0.05),
                ("american elm", 0.04), ("flowering dogwood", 0.04),
                ("eastern redcedar", 0.03), ("birch", 0.02),
            ],
            "dbh_range": [5, 45],  # mature forest — some large oaks
            "dbh_shape": 1.8,      # inverse-J: many small, some large
        },
        # RAVINE / THE LOCH (within North Woods): Wet ravine microhabitat.
        # Moisture-loving species near stream. Overlaps North Woods z-range.
        {
            "z_range": [-1650, -1350],
            "type": "successional",
            "density_mult": 1.1,
            "species": [
                ("tupelo", 0.18), ("red maple", 0.16),
                ("sweetgum", 0.14), ("bald cypress", 0.08),
                ("hickory", 0.09), ("black cherry", 0.08),
                ("flowering dogwood", 0.07), ("american elm", 0.05),
                ("sassafras", 0.05), ("star magnolia", 0.03),
                ("willow", 0.07),  # weeping willows along The Loch
            ],
            "dbh_range": [5, 35],
            "dbh_shape": 2.0,
        },
        # THE RAMBLE (79th–73rd): Intentionally "wild" 36-acre woodland.
        # Diverse species, managed but naturalistic. Major birding habitat.
        # More open understory than North Woods.
        {
            "z_range": [-750, -375],
            "type": "managed",
            "density_mult": 1.0,  # 150 trees/ha
            "species": [
                ("red oak", 0.15), ("pin oak", 0.10),
                ("black cherry", 0.12), ("red maple", 0.08),
                ("sweetgum", 0.08), ("tupelo", 0.07),
                ("flowering dogwood", 0.08), ("sassafras", 0.06),
                ("hickory", 0.06), ("american elm", 0.05),
                ("crabapple", 0.04), ("eastern redcedar", 0.03),
                ("gray birch", 0.04), ("honeylocust", 0.04),
            ],
            "dbh_range": [5, 40],
            "dbh_shape": 2.0,
        },
        # THE DENE (67th–65th, east side): Sheltered slope woodland.
        {
            "z_range": [-375, -150],
            "type": "managed",
            "density_mult": 0.9,
            "species": [
                ("red oak", 0.18), ("sugar maple", 0.15),
                ("american elm", 0.12), ("hickory", 0.10),
                ("sweetgum", 0.08), ("flowering dogwood", 0.10),
                ("black cherry", 0.08), ("tupelo", 0.05),
                ("red maple", 0.07), ("linden", 0.07),
            ],
            "dbh_range": [8, 38],
            "dbh_shape": 1.8,
        },
        # HALLETT NATURE SANCTUARY (62nd, south): Fenced 4-acre preserve.
        # Oldest successional growth in park. Very dense.
        {
            "z_range": [75, 375],
            "type": "successional",
            "density_mult": 1.4,  # densest zone, 210 trees/ha
            "species": [
                ("black cherry", 0.20), ("red oak", 0.15),
                ("hackberry", 0.10), ("norway maple", 0.12),
                ("black locust", 0.08), ("sweetgum", 0.08),
                ("red maple", 0.07), ("sassafras", 0.05),
                ("flowering dogwood", 0.06), ("tupelo", 0.05),
                ("american elm", 0.04),
            ],
            "dbh_range": [5, 50],  # some very old trees
            "dbh_shape": 1.6,
        },
        # RESERVOIR WOODLAND (86th–96th): Mixed plantings around reservoir.
        {
            "z_range": [-1125, -750],
            "type": "mixed",
            "density_mult": 0.85,
            "species": [
                ("pin oak", 0.15), ("red oak", 0.12),
                ("black cherry", 0.10), ("red maple", 0.10),
                ("sweetgum", 0.08), ("hickory", 0.08),
                ("london plane", 0.07), ("american elm", 0.06),
                ("tupelo", 0.06), ("honeylocust", 0.05),
                ("sassafras", 0.04), ("linden", 0.05),
                ("eastern redcedar", 0.04),
            ],
            "dbh_range": [8, 35],
            "dbh_shape": 2.0,
        },
        # LITERARY WALK / MALL (72nd–66th, center): Formal elm allée.
        # Wide spacing, large mature elms. Not really "woodland" but
        # any wood polygon here should match the elm character.
        {
            "z_range": [-150, 75],
            "type": "grove",
            "density_mult": 0.5,  # open canopy, 75 trees/ha
            "species": [
                ("american elm", 0.70), ("london plane", 0.10),
                ("linden", 0.10), ("honeylocust", 0.10),
            ],
            "dbh_range": [20, 60],  # large mature trees
            "dbh_shape": 1.0,       # flatter distribution — mostly large
        },
        # CHERRY HILL / BETHESDA (72nd–70th): Ornamental plantings.
        {
            "z_range": [-450, -150],
            "type": "grove",
            "density_mult": 0.6,
            "species": [
                ("yoshino cherry", 0.25), ("kwanzan cherry", 0.20),
                ("crabapple", 0.10), ("cornelian cherry", 0.08),
                ("flowering dogwood", 0.10), ("american elm", 0.08),
                ("london plane", 0.07), ("red maple", 0.06),
                ("linden", 0.06),
            ],
            "dbh_range": [8, 25],  # smaller ornamental trees
            "dbh_shape": 2.5,
        },
        # GREAT LAWN / TURTLE POND surroundings (80th–85th):
        {
            "z_range": [-975, -750],
            "type": "mixed",
            "density_mult": 0.7,
            "species": [
                ("london plane", 0.15), ("pin oak", 0.15),
                ("american elm", 0.12), ("red oak", 0.10),
                ("honeylocust", 0.10), ("linden", 0.08),
                ("red maple", 0.08), ("black cherry", 0.06),
                ("sweetgum", 0.06), ("ginkgo", 0.05),
                ("hickory", 0.05),
            ],
            "dbh_range": [10, 40],
            "dbh_shape": 1.8,
        },
        # SOUTH END (59th–62nd): Heavily managed, mixed ornamental + shade.
        {
            "z_range": [375, 750],
            "type": "mixed",
            "density_mult": 0.7,
            "species": [
                ("london plane", 0.18), ("pin oak", 0.12),
                ("american elm", 0.10), ("honeylocust", 0.10),
                ("linden", 0.10), ("red maple", 0.08),
                ("ginkgo", 0.08), ("black cherry", 0.06),
                ("sweetgum", 0.06), ("red oak", 0.06),
                ("norway maple", 0.06),
            ],
            "dbh_range": [10, 35],
            "dbh_shape": 2.0,
        },
        # CONSERVATORY GARDEN area (105th–106th, east):
        {
            "z_range": [-1500, -1350],
            "type": "grove",
            "density_mult": 0.6,
            "species": [
                ("crabapple", 0.25), ("yoshino cherry", 0.15),
                ("star magnolia", 0.10), ("stewartia", 0.08),
                ("flowering dogwood", 0.12), ("american elm", 0.10),
                ("linden", 0.10), ("red maple", 0.10),
            ],
            "dbh_range": [8, 25],
            "dbh_shape": 2.5,
        },
        # HARLEM MEER surroundings (106th–110th):
        {
            "z_range": [-1800, -1500],
            "type": "mixed",
            "density_mult": 0.9,
            "species": [
                ("red oak", 0.15), ("pin oak", 0.12),
                ("sweetgum", 0.10), ("red maple", 0.10),
                ("black cherry", 0.10), ("tupelo", 0.08),
                ("gray birch", 0.06), ("ginkgo", 0.05),
                ("hickory", 0.06), ("sawtooth oak", 0.05),
                ("american elm", 0.05), ("sassafras", 0.04),
                ("eastern redcedar", 0.04),
            ],
            "dbh_range": [5, 40],
            "dbh_shape": 1.8,
        },
    ]

    def _pick_zone(tz: float):
        """Find best-matching foliage zone for a Z coordinate.
        If multiple zones overlap, pick the one whose center is closest."""
        best = None
        best_dist = float('inf')
        for zone in _foliage_zones:
            zr = zone["z_range"]
            if zr[0] <= tz <= zr[1]:
                center = (zr[0] + zr[1]) / 2.0
                dist = abs(tz - center)
                if dist < best_dist:
                    best_dist = dist
                    best = zone
        return best

    # Fallback species pool with weights (generic Central Park mix)
    _FALLBACK_POOL = [
        ("red oak", 0.15), ("pin oak", 0.10), ("red maple", 0.10),
        ("american elm", 0.08), ("black cherry", 0.08), ("sweetgum", 0.07),
        ("honeylocust", 0.07), ("london plane", 0.07), ("hickory", 0.05),
        ("linden", 0.05), ("tupelo", 0.04), ("ginkgo", 0.04),
        ("flowering dogwood", 0.04), ("sassafras", 0.03), ("birch", 0.03),
    ]

    def _weighted_species(pool) -> str:
        """Weighted random choice from a species pool."""
        r = _rng.random()
        cumulative = 0.0
        for sp_name, weight in pool:
            cumulative += weight
            if r <= cumulative:
                return ZONE_SPECIES_MAP.get(sp_name.lower(), "deciduous")
        # Fallback if weights don't sum to 1.0
        sp_name = pool[-1][0]
        return ZONE_SPECIES_MAP.get(sp_name.lower(), "deciduous")

    def _zone_species(tz: float) -> str:
        """Pick a species appropriate for the foliage zone at this z coordinate."""
        zone = _pick_zone(tz)
        if zone:
            return _weighted_species(zone["species"])
        return _weighted_species(_FALLBACK_POOL)

    def _zone_dbh(tz: float) -> int:
        """Generate ecologically realistic DBH for a woodland tree.
        Uses inverse-J distribution: many small trees, fewer large ones.
        Shape parameter controls the curve — lower = more large trees."""
        zone = _pick_zone(tz)
        if zone:
            lo, hi = zone["dbh_range"]
            shape = zone["dbh_shape"]
        else:
            lo, hi = 5, 35
            shape = 2.0
        # Inverse-J via exponential: u^(1/shape) biases toward 0 (small trees)
        u = _rng.random()
        t = u ** shape  # shape>1 skews toward 0 = small DBH
        return max(lo, min(hi, int(lo + t * (hi - lo))))

    def _zone_density(tz: float) -> float:
        """Get density multiplier for the foliage zone at this Z."""
        zone = _pick_zone(tz)
        if zone:
            return BASE_DENSITY * zone["density_mult"]
        return BASE_DENSITY

    # _point_in_poly reuses _pip defined in Step 1 above
    _point_in_poly = _pip

    # Collect woodland polygons from OSM ways
    woodland_polys = []
    for e in elements:
        if e["type"] != "way":
            continue
        tags = e.get("tags", {})
        if tags.get("natural") != "wood":
            continue
        nids = e.get("nodes", [])
        if len(nids) < 3:
            continue
        poly = []
        for nid in nids:
            if nid in nodes_ll:
                x, z = project(*nodes_ll[nid])
                poly.append((x, z))
        if len(poly) >= 3:
            woodland_polys.append(poly)

    wood_added = 0
    wood_total_area = 0.0
    zone_stats = {}  # track species per zone for reporting
    for poly in woodland_polys:
        # Bounding box
        xs = [p[0] for p in poly]
        zs = [p[1] for p in poly]
        x_min, x_max = min(xs), max(xs)
        z_min, z_max = min(zs), max(zs)
        # Approximate area via shoelace
        area = 0.0
        n = len(poly)
        for i in range(n):
            j = (i + 1) % n
            area += poly[i][0] * poly[j][1]
            area -= poly[j][0] * poly[i][1]
        area = abs(area) / 2.0
        wood_total_area += area
        # Zone-specific density — use polygon centroid Z for zone lookup
        centroid_z = sum(zs) / len(zs)
        density = _zone_density(centroid_z)
        n_trees = int(area * density)
        placed = []
        attempts = 0
        max_attempts = n_trees * 20
        while len(placed) < n_trees and attempts < max_attempts:
            attempts += 1
            tx = _rng.uniform(x_min, x_max)
            tz = _rng.uniform(z_min, z_max)
            if not _point_in_poly(tx, tz, poly):
                continue
            # Check minimum spacing against already-placed and census trees
            too_close = False
            for (px, pz) in placed:
                if abs(tx - px) < MIN_TREE_SPACING and abs(tz - pz) < MIN_TREE_SPACING:
                    too_close = True
                    break
            if too_close:
                continue
            # Also check against census trees
            tck = (int(tx // CELL), int(tz // CELL))
            for dx in range(-1, 2):
                if too_close:
                    break
                for dz in range(-1, 2):
                    for (cx, cz) in tree_hash.get((tck[0] + dx, tck[1] + dz), []):
                        if abs(tx - cx) < MIN_TREE_SPACING and abs(tz - cz) < MIN_TREE_SPACING:
                            too_close = True
                            break
                    if too_close:
                        break
            if too_close:
                continue
            placed.append((tx, tz))
            th = round(terrain(tx, tz), 2)
            species = _zone_species(tz)
            dbh = _zone_dbh(tz)
            trees_out.append({"pos": [round(tx, 2), th, round(tz, 2)],
                              "species": species, "dbh": dbh})
            if tck not in tree_hash:
                tree_hash[tck] = []
            tree_hash[tck].append((tx, tz))
            wood_added += 1
            # Track zone stats
            zone = _pick_zone(tz)
            zname = zone["type"] if zone else "fallback"
            if zname not in zone_stats:
                zone_stats[zname] = {}
            zone_stats[zname][species] = zone_stats[zname].get(species, 0) + 1
    print(f"  Trees: +{wood_added} scattered in {len(woodland_polys)} woodland polygons "
          f"({wood_total_area/1e4:.1f} ha)")
    for ztype, sp_counts in sorted(zone_stats.items()):
        total = sum(sp_counts.values())
        top3 = sorted(sp_counts.items(), key=lambda x: -x[1])[:3]
        top3_str = ", ".join(f"{s}={c}" for s, c in top3)
        print(f"    {ztype}: {total} trees ({top3_str})")
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
            continue

        # Flagpoles
        if tags.get("man_made") == "flagpole":
            flagpoles_out.append([x, h, z])

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
    # Shrubbery areas — natural=shrubbery (decorative plantings)
    # -------------------------------------------------------------------
    shrubbery_out = []
    for wid, tags in ways_tags.items():
        if tags.get("natural") != "shrubbery":
            continue
        nids = ways_nodes.get(wid, [])
        if len(nids) < 3:
            continue
        pts = _extract_polygon(nids)
        if len(pts) >= 3:
            shrubbery_out.append({"name": tags.get("name", ""), "points": pts})
    if shrubbery_out:
        print(f"  Shrubbery areas: {len(shrubbery_out)}")

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
    # Viewpoints, attractions, and historic features from OSM tourism/historic
    # -------------------------------------------------------------------
    viewpoints_out = []
    attractions_out = []
    for e in elements:
        if e["type"] != "node" or "lat" not in e:
            continue
        tags = e.get("tags", {})
        if not tags:
            continue
        x, z = project(e["lat"], e["lon"])
        h = round(terrain(x, z), 2)
        tourism = tags.get("tourism", "")
        if tourism == "viewpoint":
            viewpoints_out.append({
                "name": tags.get("name", ""),
                "position": [x, h, z],
            })
        elif tourism == "attraction":
            attractions_out.append({
                "name": tags.get("name", ""),
                "position": [x, h, z],
                "subtype": tags.get("attraction", ""),
            })
        elif tourism == "museum":
            attractions_out.append({
                "name": tags.get("name", ""),
                "position": [x, h, z],
                "subtype": "museum",
            })
    # Way attractions (Cleopatra's Needle, Carousel, etc.)
    for wid, tags in ways_tags.items():
        tourism = tags.get("tourism", "")
        if tourism in ("attraction", "museum"):
            nids = ways_nodes.get(wid, [])
            pts_2d = [project(*nodes_ll[nid]) for nid in nids if nid in nodes_ll]
            if pts_2d:
                cx = sum(p[0] for p in pts_2d) / len(pts_2d)
                cz = sum(p[1] for p in pts_2d) / len(pts_2d)
                attractions_out.append({
                    "name": tags.get("name", ""),
                    "position": [cx, round(terrain(cx, cz), 2), cz],
                    "subtype": "museum" if tourism == "museum" else tags.get("attraction", ""),
                })
    # Historic features: forts, cannons (from nodes and ways)
    for e in elements:
        if e["type"] != "node" or "lat" not in e:
            continue
        tags = e.get("tags", {})
        hist = tags.get("historic", "")
        if hist in ("fort", "cannon", "castle", "citywalls"):
            x, z = project(e["lat"], e["lon"])
            h = round(terrain(x, z), 2)
            attractions_out.append({
                "name": tags.get("name", ""),
                "position": [x, h, z],
                "subtype": hist,
            })
    for wid, tags in ways_tags.items():
        hist = tags.get("historic", "")
        if hist in ("fort", "cannon", "castle"):
            nids = ways_nodes.get(wid, [])
            pts_2d = [project(*nodes_ll[nid]) for nid in nids if nid in nodes_ll]
            if pts_2d:
                cx = sum(p[0] for p in pts_2d) / len(pts_2d)
                cz = sum(p[1] for p in pts_2d) / len(pts_2d)
                attractions_out.append({
                    "name": tags.get("name", ""),
                    "position": [cx, round(terrain(cx, cz), 2), cz],
                    "subtype": hist,
                })
    if viewpoints_out:
        print(f"  Viewpoints: {len(viewpoints_out)}")
    if attractions_out:
        print(f"  Attractions: {len(attractions_out)}")

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
            entry = {
                "name": tags.get("name", ""),
                "type": zone_type,
                "points": pts,
            }
            sport = tags.get("sport", "")
            if sport:
                entry["sport"] = sport
            landuse_out.append(entry)
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
            entry = {
                "name": tags.get("name", ""),
                "type": zone_type,
                "points": pts,
            }
            sport = tags.get("sport", "")
            if sport:
                entry["sport"] = sport
            landuse_out.append(entry)

    # -------------------------------------------------------------------
    # Orient benches toward nearest path (OSM rarely has direction tags)
    # -------------------------------------------------------------------
    # Build flat list of path segments for nearest-segment search
    path_segs = []  # [(x0, z0, x1, z1), ...]
    for p in paths_out:
        pts = p.get("points", [])
        for i in range(len(pts) - 1):
            # pts are [x, h, z] (3 elements)
            if len(pts[i]) >= 3 and len(pts[i+1]) >= 3:
                path_segs.append((pts[i][0], pts[i][2], pts[i+1][0], pts[i+1][2]))

    oriented = 0
    for b in benches_out:
        if len(b) < 4 or b[3] != 0.0:
            continue  # already has a direction from OSM
        bx, bz = b[0], b[2]
        best_dist_sq = float('inf')
        best_dx, best_dz = 0.0, -1.0  # default: face north
        for sx0, sz0, sx1, sz1 in path_segs:
            # Closest point on segment to bench
            abx, abz = sx1 - sx0, sz1 - sz0
            len_sq = abx * abx + abz * abz
            if len_sq < 0.01:
                continue
            t = max(0.0, min(1.0, ((bx - sx0) * abx + (bz - sz0) * abz) / len_sq))
            cx, cz = sx0 + t * abx, sz0 + t * abz
            dsq = (bx - cx) ** 2 + (bz - cz) ** 2
            if dsq < best_dist_sq:
                best_dist_sq = dsq
                best_dx = cx - bx
                best_dz = cz - bz
        # Convert direction vector to compass bearing (0=N, 90=E)
        if best_dist_sq < 400.0:  # within 20m of a path
            bearing = math.degrees(math.atan2(best_dx, -best_dz)) % 360.0
            b[3] = round(bearing, 1)
            oriented += 1
    if oriented:
        print(f"  Bench orientation: {oriented} / {len(benches_out)} oriented toward nearest path")

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
        "flagpoles":          flagpoles_out,
        "landuse":            landuse_out,
        "bridge_outlines":    bridge_outlines,
        "tunnel_outlines":    tunnel_outlines,
        "rocks":              rocks_out,
        "shrubbery":          shrubbery_out,
        "amenities":          amenities_out,

        "playgrounds":        playgrounds,
        "facilities":         facilities,
        "foliage_zones":      foliage_zones,
        "viewpoints":         viewpoints_out,
        "attractions":        attractions_out,
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
    print(f"Flagpoles:  {len(flagpoles_out):5d}")
    print(f"Landuse:    {len(landuse_out):5d}  zones")
    print(f"Bridges:    {len(bridge_outlines):5d}  outlines")
    print(f"Tunnels:    {len(tunnel_outlines):5d}  outlines")
    print(f"Rocks:      {len(rocks_out):5d}  outcrops")
    print(f"Amenities:  {len(amenities_out):5d}")
    print(f"\nSaved → park_data.json  ({size_kb:.0f} KB)")

    bin_size = write_park_data_bin("park_data.bin", out)
    bin_kb = bin_size / 1024
    print(f"Saved → park_data.bin   ({bin_kb:.0f} KB)")

    # Pre-bake path textures for fast Godot loading
    bridge_centroids = []
    for p in paths_out:
        if p.get("bridge") or int(p.get("layer", 0)) >= 1:
            pts = p["points"]
            bcx = sum(float(pt[0]) for pt in pts) / len(pts)
            bcz = sum(float(pt[2]) for pt in pts) / len(pts)
            bridge_centroids.append((bcx, bcz))
    surface_arr = prebake_world_atlas(boundary_pts, paths_out, water_out, buildings_out,
                        trees_out, benches_out, lampposts_out, trash_cans_out,
                        barriers_out, bridge_outlines, terrain, bridge_centroids)
    prebake_landuse_map(landuse_out, water_out)
    prebake_grass_instances(landuse_out)
    prebake_boundary_mask(boundary_pts)
    prebake_water_grids(water_out, terrain, boundary_pts)
    if have_terrain:
        # --- DEM/DSM hybrid terrain ---
        # Rock outcrops, retaining walls, natural stone steps are captured by DSM
        # but smoothed away by bare-earth DEM. Blend both: DEM under buildings/bridges
        # (where 3D models provide geometry), DSM everywhere else.
        if os.path.exists(LIDAR_DSM) and surface_arr is not None:
            import numpy as np
            from scipy.ndimage import binary_dilation, gaussian_filter
            print("\n--- DEM/DSM hybrid terrain ---")
            dsm_raw = _load_lidar_raster(LIDAR_DSM, "LiDAR DSM (structure-enhanced)")
            if dsm_raw is not None:
                # Normalize DSM with same min_elev as DEM so heights are compatible
                dsm_arr = (dsm_raw - min_elev).astype(np.float32)
                dsm_arr = np.maximum(dsm_arr, 0.0)
                del dsm_raw

                # Build DEM-priority mask: 1.0 where we want DEM (buildings + bridges)
                # Dilate by ~10m (16 cells at 0.61m/cell) — buffer zone around structures
                # prevents DSM rooftop heights from bleeding into nearby terrain
                struct_mask = (surface_arr == 5) | (surface_arr == 6)

                # TODO: Bethesda Terrace terrain integration (session 34)
                # The terrace is a tunnel through a hillside — open both ends,
                # road on top, earth on sides, staircases carved into slopes.
                # Needs custom terrain carve-out following the actual tunnel
                # cross-section, not a simple rectangular flatten. The terrain
                # mesh needs a void where the passage is, solid ground above,
                # hillside wrapping the sides. Complex problem — needs its own session.

                struct_count = int(struct_mask.sum())
                print(f"  Structure cells (buildings+bridges): {struct_count:,}")

                # Dilate to create buffer zone around structures
                dilated = binary_dilation(struct_mask, iterations=16)
                dilated_count = int(dilated.sum())
                print(f"  After 10m dilation: {dilated_count:,} cells")
                del struct_mask

                # Gaussian feather for smooth transition (~3m = 5 cells)
                dem_priority = gaussian_filter(dilated.astype(np.float32), sigma=5.0)
                dem_priority = np.clip(dem_priority, 0.0, 1.0)
                del dilated

                # Blend: DEM under structures, DSM elsewhere
                hybrid_arr = hm_arr * dem_priority + dsm_arr * (1.0 - dem_priority)

                # Statistics
                diff = hybrid_arr - hm_arr
                changed = np.abs(diff) > 0.1  # >10cm difference
                if changed.any():
                    print(f"  Hybrid: {changed.sum():,} cells differ >10cm from bare-earth DEM")
                    print(f"  Height delta range: {diff[changed].min():.2f}m to {diff[changed].max():.2f}m "
                          f"(mean {diff[changed].mean():.2f}m)")
                else:
                    print(f"  Hybrid: no significant height differences found")
                del diff, changed, dem_priority, dsm_arr

                # Replace heightmap array
                hm_arr = hybrid_arr.astype(np.float32)

                # Re-write heightmap.bin with hybrid values
                flat_hybrid = hm_arr.flatten()
                origin_h = float(flat_hybrid[(GRID_H // 2) * GRID_W + GRID_W // 2])
                with open("heightmap.bin", "wb") as fh:
                    fh.write(struct.pack("<II", GRID_W, GRID_H))
                    fh.write(struct.pack("<f", WORLD_SIZE))
                    fh.write(struct.pack("<f", origin_h))
                    fh.write(flat_hybrid.tobytes())
                print(f"  Re-wrote heightmap.bin (hybrid DEM/DSM)")

                # Re-write heightmap_gpu.bin
                hm_min_h = float(hm_arr.min())
                hm_max_h = float(hm_arr.max())
                hm_range = max(hm_max_h - hm_min_h, 0.01)
                TEX_RES = ATLAS_RES
                sx = (GRID_W - 1) / (TEX_RES - 1)
                sz = (GRID_H - 1) / (TEX_RES - 1)
                xi_src = np.clip(np.round(np.arange(TEX_RES) * sx).astype(int), 0, GRID_W - 1)
                zi_src = np.clip(np.round(np.arange(TEX_RES) * sz).astype(int), 0, GRID_H - 1)
                arr4k = hm_arr[np.ix_(zi_src, xi_src)]
                norm = np.clip((arr4k - hm_min_h) / hm_range, 0.0, 1.0)
                h16 = (norm * 65535.0).astype(np.uint16)
                rg8 = np.empty((TEX_RES, TEX_RES, 2), dtype=np.uint8)
                rg8[:, :, 0] = (h16 >> 8).astype(np.uint8)
                rg8[:, :, 1] = (h16 & 0xFF).astype(np.uint8)
                with open("heightmap_gpu.bin", "wb") as fh:
                    fh.write(struct.pack("<II", TEX_RES, TEX_RES))
                    fh.write(struct.pack("<ff", hm_min_h, hm_max_h))
                    fh.write(rg8.tobytes())
                print(f"  Re-wrote heightmap_gpu.bin (hybrid DEM/DSM)")
                del flat_hybrid, arr4k, norm, h16, rg8
        else:
            print("  DSM not available — using bare-earth DEM only")

        prebake_terrain_mesh(hm_arr, boundary_pts, surface_arr)


def prebake_water_grids(water_bodies, terrain_func, boundary_pts):
    """Pre-bake per-body inside/outside grids for water mesh construction.

    Eliminates ~244M Geometry2D.is_point_in_polygon() calls at runtime (~5s → <0.1s).

    Output: water_grids.bin
    Format:
      "WGRD" magic (4 bytes)
      uint32 body_count
      For each body:
        uint16 name_len + UTF-8 name bytes
        float32 bb_min_x, bb_min_z   (bounding box of expanded polygon)
        float32 water_y              (minimum terrain height along shore + WATER_Y)
        uint32  nx, nz               (grid dimensions)
        uint32  poly_count           (expanded polygon vertex count)
        float32[poly_count*2]        (expanded polygon x,z pairs for proximity baking)
        uint8[(nx+1)*(nz+1)]        (inside flags: 1=inside, 0=outside, row-major Z then X)
    """
    import numpy as np
    from PIL import Image, ImageDraw
    from scipy.ndimage import binary_dilation

    WATER_CELL = WORLD_SIZE / ATLAS_RES  # ~0.61m — match atlas resolution
    EXPAND_M = 3.0  # expand polygons so water fills under bridges
    EXPAND_PX = int(math.ceil(EXPAND_M / WATER_CELL))  # ~5 pixels at 0.61m/cell
    WATER_Y_OFFSET = 0.03  # matches park_loader.WATER_Y

    # Boundary check (same algorithm as main extraction)
    bx_w = [float(p[0]) for p in boundary_pts] if boundary_pts else []
    bz_w = [float(p[1]) for p in boundary_pts] if boundary_pts else []
    bnd_w = len(boundary_pts) if boundary_pts else 0

    def centroid_in_boundary(pts_2d):
        if bnd_w < 3:
            return True
        cx = sum(p[0] for p in pts_2d) / len(pts_2d)
        cz = sum(p[1] for p in pts_2d) / len(pts_2d)
        inside = False
        j = bnd_w - 1
        for i in range(bnd_w):
            zi, zj = bz_w[i], bz_w[j]
            if (zi > cz) != (zj > cz):
                if cx < bx_w[i] + (cz - zi) / (zj - zi) * (bx_w[j] - bx_w[i]):
                    inside = not inside
            j = i
        return inside

    bodies_out = []
    total_cells = 0

    for body in water_bodies:
        pts = body.get("points", [])
        if len(pts) < 3:
            continue
        bname = body.get("name", "")

        # Skip bodies outside boundary (same filter as GDScript)
        if not centroid_in_boundary(pts):
            continue

        # Skip oversized bodies (rivers/ocean)
        xs = [float(p[0]) for p in pts]
        zs = [float(p[1]) for p in pts]
        if (max(xs) - min(xs)) > 1000.0 or (max(zs) - min(zs)) > 1000.0:
            continue

        # Skip fountains — handled separately in GDScript
        if "fountain" in bname.lower():
            continue

        # Compute water_y = minimum terrain height along shore + offset
        water_y = min(terrain_func(float(p[0]), float(p[1])) for p in pts)
        water_y += WATER_Y_OFFSET

        # Rasterize polygon at atlas resolution, then dilate to expand 3m
        bb_min_x, bb_max_x = min(xs), max(xs)
        bb_min_z, bb_max_z = min(zs), max(zs)

        # Add padding for the dilation
        pad_m = EXPAND_M + WATER_CELL
        bb_min_x -= pad_m
        bb_min_z -= pad_m
        bb_max_x += pad_m
        bb_max_z += pad_m

        nx = int(math.ceil((bb_max_x - bb_min_x) / WATER_CELL)) + 1
        nz = int(math.ceil((bb_max_z - bb_min_z) / WATER_CELL)) + 1

        # Rasterize raw polygon onto local grid using PIL
        local_img = Image.new('L', (nx + 1, nz + 1), 0)
        draw = ImageDraw.Draw(local_img)
        poly_pixels = []
        for p in pts:
            px = (float(p[0]) - bb_min_x) / WATER_CELL
            pz = (float(p[1]) - bb_min_z) / WATER_CELL
            poly_pixels.append((px, pz))
        draw.polygon(poly_pixels, fill=1)

        # Dilate to expand ~3m (fills under bridges)
        raw_mask = np.array(local_img, dtype=np.uint8)
        struct_elem = np.ones((2 * EXPAND_PX + 1, 2 * EXPAND_PX + 1), dtype=bool)
        expanded_mask = binary_dilation(raw_mask, structure=struct_elem).astype(np.uint8)

        # Extract expanded polygon outline for proximity baking (convex hull of dilated cells)
        # Use the dilated mask boundary cells as the expanded polygon
        expanded_coords = []
        for zi in range(nz + 1):
            for xi in range(nx + 1):
                if expanded_mask[zi, xi]:
                    wx = bb_min_x + xi * WATER_CELL
                    wz = bb_min_z + zi * WATER_CELL
                    expanded_coords.append((wx, wz))

        # Subsample polygon outline: walk the edge of the dilated mask
        # For proximity baking, provide the expanded polygon boundary
        # Use a simpler approach: dilate the original polygon coordinates
        exp_poly = []
        if len(pts) >= 3:
            # Compute outward offset of each edge by EXPAND_M
            n = len(pts)
            for i in range(n):
                j = (i + 1) % n
                x0, z0 = float(pts[i][0]), float(pts[i][1])
                x1, z1 = float(pts[j][0]), float(pts[j][1])
                exp_poly.append((x0, z0))
            # For simplicity, store the raw polygon — GDScript can use
            # Geometry2D.offset_polygon for the proximity polygon if needed
            exp_poly = [(float(p[0]), float(p[1])) for p in pts]

        inside_flags = expanded_mask.flatten().tobytes()
        total_cells += (nx + 1) * (nz + 1)

        bodies_out.append({
            "name": bname,
            "bb_min_x": bb_min_x,
            "bb_min_z": bb_min_z,
            "water_y": water_y,
            "nx": nx,
            "nz": nz,
            "poly": exp_poly,
            "inside": inside_flags,
        })

    # Write binary file
    with open("water_grids.bin", "wb") as f:
        f.write(b"WGRD")
        f.write(struct.pack("<I", len(bodies_out)))
        for bd in bodies_out:
            name_bytes = bd["name"].encode("utf-8")
            f.write(struct.pack("<H", len(name_bytes)))
            f.write(name_bytes)
            f.write(struct.pack("<fff", bd["bb_min_x"], bd["bb_min_z"], bd["water_y"]))
            f.write(struct.pack("<II", bd["nx"], bd["nz"]))
            poly = bd["poly"]
            f.write(struct.pack("<I", len(poly)))
            for px, pz in poly:
                f.write(struct.pack("<ff", px, pz))
            f.write(bd["inside"])

    print(f"  Water grids: {len(bodies_out)} bodies, {total_cells} total cells → water_grids.bin ({os.path.getsize('water_grids.bin') // 1024} KB)")


def prebake_world_atlas(boundary_pts, paths, water, buildings, trees,
                        benches, lampposts, trash_cans, barriers, bridge_outlines,
                        terrain_func, bridge_centroids):
    """
    Pre-bake a unified world atlas at ATLAS_RES (8192×8192, ~0.61m/cell).

    Output: world_atlas.bin
    Format: 8-byte header (width, height as uint32) + width×height×2 bytes (RG8)
      R = surface type
      G = occupancy bitmask

    Surface types (R channel):
      0 = outside park boundary
      1 = grass (default inside park)
      2 = paved path (asphalt/concrete/stone)
      3 = unpaved path (dirt/gravel/compacted)
      4 = water
      5 = building footprint
      6 = bridge deck
      7 = rock outcrop (from landuse)

    Occupancy bitmask (G channel):
      bit 0 (1)   = tree
      bit 1 (2)   = bench
      bit 2 (4)   = lamppost
      bit 3 (8)   = trash can
      bit 4 (16)  = barrier/wall
      bit 5 (32)  = reserved
      bit 6 (64)  = reserved
      bit 7 (128) = reserved

    Replaces: splat_map.bin surface classification, boundary bitmap,
              5 runtime dictionary grids, structure mask.
    """
    import numpy as np
    import struct

    RES = ATLAS_RES  # 8192×8192 at ~0.61m/cell (matches heightmap resolution)
    HALF = WORLD_SIZE / 2.0
    CELL = WORLD_SIZE / RES  # ~1.22m

    surface = np.zeros((RES, RES), dtype=np.uint8)   # R channel
    occupancy = np.zeros((RES, RES), dtype=np.uint8)  # G channel

    def world_to_pixel(wx, wz):
        px = (wx + HALF) / WORLD_SIZE * RES
        pz = (wz + HALF) / WORLD_SIZE * RES
        return px, pz

    def world_to_cell(wx, wz):
        px, pz = world_to_pixel(wx, wz)
        return int(px), int(pz)

    from PIL import Image, ImageDraw

    # --- 1. Rasterize park boundary → surface=1 (grass) inside ---
    print("  Atlas: rasterizing boundary...")
    if len(boundary_pts) >= 3:
        bnd_img = Image.new('L', (RES, RES), 0)
        draw = ImageDraw.Draw(bnd_img)
        poly_pixels = [(world_to_pixel(float(bp[0]), float(bp[1]))) for bp in boundary_pts]
        draw.polygon(poly_pixels, fill=1)
        boundary_mask = np.array(bnd_img, dtype=np.uint8)
        surface[boundary_mask == 1] = 1  # grass
        inside_count = int(boundary_mask.sum())
        print(f"    {inside_count} cells inside park ({inside_count * CELL * CELL / 1e6:.2f} km²)")
        del bnd_img, boundary_mask

    # --- 2. Rasterize water bodies → surface=4 ---
    # All water polygons drawn onto one shared image
    print("  Atlas: rasterizing water...")
    w_img = Image.new('L', (RES, RES), 0)
    draw = ImageDraw.Draw(w_img)
    for body in water:
        pts = body.get("points", [])
        if len(pts) < 3:
            continue
        poly = [world_to_pixel(float(pt[0]), float(pt[1])) for pt in pts]
        draw.polygon(poly, fill=1)
    w_mask = np.array(w_img, dtype=np.uint8)
    water_count = int(w_mask.sum())
    surface[w_mask == 1] = 4
    print(f"    {water_count} water cells")
    del w_img, w_mask

    # --- 3. Rasterize building footprints → surface=5 ---
    # All buildings drawn onto one shared image
    print("  Atlas: rasterizing buildings...")
    b_img = Image.new('L', (RES, RES), 0)
    draw = ImageDraw.Draw(b_img)
    for bld in buildings:
        pts = bld.get("points", [])
        if len(pts) < 3:
            continue
        poly = [world_to_pixel(float(pt[0]), float(pt[1])) for pt in pts]
        draw.polygon(poly, fill=1)
    b_mask = np.array(b_img, dtype=np.uint8)
    bld_count = int(b_mask.sum())
    surface[b_mask == 1] = 5
    print(f"    {bld_count} building cells")
    del b_img, b_mask

    # --- 4. Rasterize bridge outlines → surface=6 ---
    print("  Atlas: rasterizing bridges...")
    br_img = Image.new('L', (RES, RES), 0)
    draw = ImageDraw.Draw(br_img)
    for bo in bridge_outlines:
        pts = bo.get("points", bo) if isinstance(bo, dict) else bo
        if not isinstance(pts, list) or len(pts) < 3:
            continue
        poly = [world_to_pixel(float(pt[0]), float(pt[1])) for pt in pts]
        draw.polygon(poly, fill=1)
    br_mask = np.array(br_img, dtype=np.uint8)
    bridge_count = int(br_mask.sum())
    surface[br_mask == 1] = 6
    print(f"    {bridge_count} bridge cells")
    del br_img, br_mask

    # --- 5. Rasterize paths → surface=2 (paved) or 3 (unpaved) ---
    print("  Atlas: rasterizing paths...")
    PAVED_SURFACES = {"asphalt", "concrete", "concrete:plates", "paving_stones",
                      "sett", "unhewn_cobblestone", "brick", "stone", "metal",
                      "rubber", "tartan", "wood"}
    PAVED_HW = {"pedestrian", "footway", "cycleway", "service", "secondary"}

    path_cells = 0
    for p in paths:
        hw = p.get("highway", "path")
        layer = int(p.get("layer", 0))
        is_bridge = p.get("bridge", False) or layer >= 1
        is_tunnel = p.get("tunnel", False) or layer <= -1
        if is_bridge or hw == "steps":
            continue
        if is_tunnel:
            continue

        surf = p.get("surface", "")
        if surf in PAVED_SURFACES or (not surf and hw in PAVED_HW):
            stype = 2  # paved
        else:
            stype = 3  # unpaved

        hw2 = HIGHWAY_WIDTH.get(hw, 2.5) * 0.5
        w = p.get("width", 0)
        if isinstance(w, (int, float)) and w > 0:
            hw2 = float(w) * 0.5
        elif isinstance(w, str) and w:
            try:
                wf = float(w)
                if wf > 0:
                    hw2 = wf * 0.5
            except ValueError:
                pass

        pts = p["points"]
        for i in range(len(pts) - 1):
            x0, z0 = float(pts[i][0]), float(pts[i][2])
            x1, z1 = float(pts[i+1][0]), float(pts[i+1][2])
            px0, pz0 = world_to_pixel(x0, z0)
            px1, pz1 = world_to_pixel(x1, z1)
            pr = hw2 / CELL  # half-width in pixels

            bmin_x = max(0, int(min(px0, px1) - pr - 1))
            bmax_x = min(RES - 1, int(max(px0, px1) + pr + 1))
            bmin_z = max(0, int(min(pz0, pz1) - pr - 1))
            bmax_z = min(RES - 1, int(max(pz0, pz1) + pr + 1))
            if bmax_x <= bmin_x or bmax_z <= bmin_z:
                continue

            # Vectorized distance-to-segment
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
            mask = dist_sq <= pr * pr
            region = surface[bmin_z:bmax_z+1, bmin_x:bmax_x+1]
            # Only overwrite grass/boundary cells, not water/buildings
            can_write = mask & ((region == 0) | (region == 1))
            region[can_write] = stype
            path_cells += int(can_write.sum())
    print(f"    {path_cells} path cells")

    # --- 6. Mark object occupancy (G channel bitmask) ---
    print("  Atlas: marking occupancy...")

    # Trees (bit 0)
    tree_marked = 0
    for t in trees:
        pos = t["pos"] if isinstance(t, dict) else t
        ci, cj = world_to_cell(float(pos[0]), float(pos[2]))
        if 0 <= ci < RES and 0 <= cj < RES:
            occupancy[cj, ci] |= 1
            tree_marked += 1

    # Benches (bit 1)
    bench_marked = 0
    for b in benches:
        ci, cj = world_to_cell(float(b[0]), float(b[2]))
        if 0 <= ci < RES and 0 <= cj < RES:
            occupancy[cj, ci] |= 2
            bench_marked += 1

    # Lampposts (bit 2)
    lamp_marked = 0
    for lp in lampposts:
        ci, cj = world_to_cell(float(lp[0]), float(lp[2]))
        if 0 <= ci < RES and 0 <= cj < RES:
            occupancy[cj, ci] |= 4
            lamp_marked += 1

    # Trash cans (bit 3)
    trash_marked = 0
    for tc in trash_cans:
        ci, cj = world_to_cell(float(tc[0]), float(tc[2]))
        if 0 <= ci < RES and 0 <= cj < RES:
            occupancy[cj, ci] |= 8
            trash_marked += 1

    # Barriers (bit 4) — mark cells along barrier segments
    barrier_marked = 0
    for bar in barriers:
        pts = bar.get("points", [])
        for i in range(len(pts) - 1):
            x0, z0 = float(pts[i][0]), float(pts[i][1])
            x1, z1 = float(pts[i+1][0]), float(pts[i+1][1])
            seg_len = math.hypot(x1 - x0, z1 - z0)
            steps = max(1, int(seg_len / (CELL * 0.5)))
            for s in range(steps + 1):
                t = s / steps
                wx = x0 + (x1 - x0) * t
                wz = z0 + (z1 - z0) * t
                ci, cj = world_to_cell(wx, wz)
                if 0 <= ci < RES and 0 <= cj < RES:
                    occupancy[cj, ci] |= 16
                    barrier_marked += 1

    print(f"    trees={tree_marked} benches={bench_marked} lamps={lamp_marked} "
          f"trash={trash_marked} barriers={barrier_marked}")

    # --- 7. Save ---
    atlas_data = np.zeros((RES, RES, 2), dtype=np.uint8)
    atlas_data[:, :, 0] = surface
    atlas_data[:, :, 1] = occupancy
    atlas_bytes = atlas_data.tobytes()

    with open("world_atlas.bin", "wb") as f:
        f.write(struct.pack("<II", RES, RES))
        f.write(atlas_bytes)

    total_mb = len(atlas_bytes) / (1024 * 1024)
    print(f"  Atlas: {RES}×{RES} RG8 → world_atlas.bin ({total_mb:.1f} MB)")

    # Summary
    nonzero_surface = int(np.count_nonzero(surface))
    nonzero_occ = int(np.count_nonzero(occupancy))
    print(f"  Atlas: {nonzero_surface} classified cells, {nonzero_occ} occupied cells")

    return surface  # Return for vertex color baking in terrain mesh


def prebake_grass_instances(landuse_zones):
    """Pre-bake grass patch positions → grass_instances.bin.

    Data-driven density: stride varies by landuse zone to reflect real
    Central Park ground cover. Grass density is inversely proportional to
    canopy density — dense woodland has sparse ground cover.

    Three grass types based on real park vegetation:
      0 = Maintained lawn (Kentucky bluegrass) — dense, bright green
          Zones: grass(2), pitch(3), sports(7), garden(1), unzoned(0)
          Stride: 3 (~1.83m) — patches overlap at 0.85m radius
      1 = Woodland floor — sparse shade-adapted understory
          Zones: wood(10), forest(11)
          Stride: 6 (~3.66m) — sparse, canopy blocks light
      2 = Wild meadow — tall flowing grass
          Zone: nature_reserve(5)
          Stride: 4 (~2.44m) — moderate density

    Output: grass_instances.bin
    Format: uint32 count, float32[N] x, float32[N] z, uint8[N] type
    """
    import numpy as np
    import struct
    from PIL import Image

    RES = ATLAS_RES
    HALF = WORLD_SIZE / 2.0
    cell_m = WORLD_SIZE / RES

    # Zone → grass type and stride
    # 10 grass tile types matching Blender models (Grass_Tile_*.glb):
    #   0: SheepMeadow   — bright Kentucky bluegrass, 150 blades
    #   1: GreatLawn     — rich green turf, 140 blades
    #   2: NorthMeadow   — open meadow, slightly wilder, 120 blades
    #   3: FormalGarden   — manicured, 130 blades
    #   4: SportsTurf    — short dense field grass, 160 blades
    #   5: NorthWoods    — sparse shade understory, 30 blades
    #   6: Ramble        — moderate woodland floor, 50 blades
    #   7: Waterside     — near water, taller, 80 blades
    #   8: WildMeadow    — unmowed nature reserve, 60 blades
    #   9: OpenLawn      — default maintained grass, 130 blades

    SKIP_ZONES = {4, 6, 8, 9, 12}  # playground, dog_park, pool, track, water

    # Zone → (default grass_type, stride)
    ZONE_CONFIG = {
        0:  (9, 3),   # unzoned → open_lawn (refined by Z-range below)
        1:  (3, 3),   # garden → formal_garden
        2:  (0, 2),   # grass → sheep_meadow default (refined by Z-range)
        3:  (4, 2),   # pitch → sports_turf
        5:  (8, 4),   # nature_reserve → wild_meadow
        7:  (4, 2),   # sports → sports_turf
        10: (5, 6),   # wood → north_woods
        11: (5, 6),   # forest → north_woods
        13: (7, 3),   # shore → waterside
    }

    # Location-specific type overrides for zone 0 (unzoned) cells.
    # First entries have HIGHEST priority (applied last in reversed loop).
    # Based on Conservancy foliage zone data + real park geography.
    #
    # Note: Great Lawn, North Meadow etc. are zone 0 in OSM, not zone 2.
    # Zone 2 (grass) in OSM mainly covers Sheep Meadow area + north lawns.
    ZONE0_Z_OVERRIDES = [
        # --- Named open lawns (higher priority than woodland) ---
        # Great Lawn: large open turf, 80th-85th Streets
        ((-975, -750), 1, 2),     # great_lawn, stride 2
        # North Meadow: open meadow, 97th-102nd Streets
        ((-1200, -975), 2, 3),    # north_meadow, stride 3
        # --- Woodland zones (lower priority) ---
        # North Woods: dense successional canopy → very sparse floor
        ((-1800, -1125), 5, 7),   # north_woods, stride 7
        # Ravine / The Loch: wet understory
        ((-1650, -1350), 5, 7),   # north_woods variant
        # Reservoir woodland strips
        ((-1125, -750), 6, 5),    # ramble, stride 5
        # The Ramble + The Dene: managed woodland
        ((-750, -150), 6, 5),     # ramble, stride 5
        # Hallett Nature Sanctuary: densest canopy
        ((75, 375), 5, 8),        # north_woods, stride 8 (very sparse)
    ]

    print("Pre-baking grass instances (zone-aware density)...")

    # Load world atlas
    atlas_path = "world_atlas.bin"
    if not os.path.exists(atlas_path):
        print("  WARNING: world_atlas.bin not found — skipping grass prebake")
        return
    with open(atlas_path, 'rb') as f:
        aw, ah = struct.unpack('<II', f.read(8))
        atlas_raw = np.frombuffer(f.read(), dtype=np.uint8).reshape(ah, aw, 2)
    surface = atlas_raw[:, :, 0]
    occupancy = atlas_raw[:, :, 1]

    # Load landuse map
    landuse_path = "landuse_map.png"
    if not os.path.exists(landuse_path):
        print("  WARNING: landuse_map.png not found — skipping grass prebake")
        return
    landuse_img = Image.open(landuse_path).convert('L')
    landuse_arr = np.array(landuse_img, dtype=np.uint8)

    # Vectorized prebake: compute type+stride grid, then sample per stride.
    # This avoids the BASE_STRIDE sub-sampling bug where stride-3 zones
    # scanned at stride-2 base effectively become stride-6.

    # Step 1: Build per-cell type and stride grids
    type_grid = np.full((RES, RES), 255, dtype=np.uint8)  # 255 = skip
    stride_grid = np.zeros((RES, RES), dtype=np.uint8)
    grass_raw = (surface == 1) & ((occupancy & 0x1F) == 0)
    # Erode grass mask by 2 cells (~1.2m) — prevents grass tile visual bleed
    # onto adjacent paved/rock/water surfaces. Grass tiles have ~1m radius,
    # so a 1.2m buffer ensures no overlap.
    grass_mask = grass_raw.copy()
    for dr, dc in [(-2,0),(2,0),(0,-2),(0,2),(-1,-1),(-1,1),(1,-1),(1,1)]:
        shifted = np.zeros_like(grass_raw)
        sr = max(0, dr); er = RES + min(0, dr)
        sc = max(0, dc); ec = RES + min(0, dc)
        shifted[sr:er, sc:ec] = grass_raw[sr-dr:er-dr, sc-dc:ec-dc]
        grass_mask &= shifted
    eroded = int(np.sum(grass_raw)) - int(np.sum(grass_mask))
    print(f"  Grass mask: {int(np.sum(grass_raw))} raw → {int(np.sum(grass_mask))} after 2-cell erosion ({eroded} edge cells removed)")

    # Apply base zone config
    for zone_id, (gtype, stride) in ZONE_CONFIG.items():
        zmask = grass_mask & (landuse_arr == zone_id)
        type_grid[zmask] = gtype
        stride_grid[zmask] = stride

    # Skip zones
    for zone_id in SKIP_ZONES:
        zmask = landuse_arr == zone_id
        type_grid[zmask] = 255

    # Step 2: Apply Z-range overrides (later overrides have lower priority)
    gz_world = np.arange(RES, dtype=np.float32) * cell_m - HALF

    # Zone 0 overrides (apply in reverse so earlier ones take precedence)
    zone0_base = (landuse_arr == 0) & grass_mask
    for (z_lo, z_hi), gtype, stride in reversed(ZONE0_Z_OVERRIDES):
        row_mask = (gz_world >= z_lo) & (gz_world <= z_hi)
        z_mask = zone0_base & row_mask[:, None]
        type_grid[z_mask] = gtype
        stride_grid[z_mask] = stride

    # Zone 2 stays as sheep_meadow (type 0, stride 2) everywhere — it's
    # mainly Sheep Meadow area + north lawns in the actual OSM data.

    # Step 3: For each stride value, sample grid and collect instances
    xs = []
    zs = []
    types = []
    rng = np.random.RandomState(73856093)

    all_strides = sorted(set(stride_grid[type_grid < 255]))
    for stride_val in all_strides:
        if stride_val == 0:
            continue
        gz_idx = np.arange(0, RES, stride_val)
        gx_idx = np.arange(0, RES, stride_val)
        gz_g, gx_g = np.meshgrid(gz_idx, gx_idx, indexing='ij')

        valid = (stride_grid[gz_g, gx_g] == stride_val) & (type_grid[gz_g, gx_g] < 255)
        gz_sel = gz_g[valid].astype(np.float32)
        gx_sel = gx_g[valid].astype(np.float32)
        types_sel = type_grid[gz_g[valid], gx_g[valid]]

        if len(gz_sel) == 0:
            continue

        # Deterministic jitter per cell — scale with stride to break grid
        # ±40% of grid spacing in each axis fully eliminates visible rows
        n = len(gz_sel)
        seed = 73856093 * stride_val + 19349663
        jrng = np.random.RandomState(seed)
        jitter_range = 0.4 * stride_val * cell_m
        jx = jrng.uniform(-jitter_range, jitter_range, n).astype(np.float32)
        jz = jrng.uniform(-jitter_range, jitter_range, n).astype(np.float32)

        wx = gx_sel * cell_m - HALF + jx
        wz = gz_sel * cell_m - HALF + jz

        xs.extend(wx.tolist())
        zs.extend(wz.tolist())
        types.extend(types_sel.tolist())

        print(f"    stride {stride_val}: {len(gz_sel)} instances")

    count = len(xs)
    x_arr = np.array(xs, dtype=np.float32)
    z_arr = np.array(zs, dtype=np.float32)
    type_arr = np.array(types, dtype=np.uint8)

    print(f"  Grass: {count} raw instances before filtering")

    # --- Pre-filter water-adjacent instances (vectorized) ---
    # Convert world positions to atlas grid indices
    ix = np.clip(((x_arr + HALF) / WORLD_SIZE * RES).astype(np.int32), 0, RES - 1)
    iz = np.clip(((z_arr + HALF) / WORLD_SIZE * RES).astype(np.int32), 0, RES - 1)

    # Check if instance is on water (surface == 4)
    on_water = surface[iz, ix] == 4

    # Check 8 neighbors at ±1, ±2 cells (~0.6m, ~1.2m) for water proximity
    near_water = np.zeros(count, dtype=bool)
    for dx, dz in [(1,0),(-1,0),(0,1),(0,-1),(2,0),(-2,0),(0,2),(0,-2)]:
        nix = np.clip(ix + dx, 0, RES - 1)
        niz = np.clip(iz + dz, 0, RES - 1)
        near_water |= (surface[niz, nix] == 4)

    water_mask = on_water | near_water
    keep = ~water_mask
    n_water_filtered = int(np.sum(water_mask))
    print(f"    Filtered {n_water_filtered} water-adjacent instances")

    x_arr = x_arr[keep]
    z_arr = z_arr[keep]
    type_arr = type_arr[keep]
    ix = ix[keep]
    iz = iz[keep]
    count = len(x_arr)

    # --- Pre-compute path proximity (vectorized) ---
    # Surface types 2 (paved_path) and 3 (unpaved_path)
    s0 = surface[iz, ix]
    path_prox = np.zeros(count, dtype=np.float32)
    # Instances on path get full proximity
    path_prox[np.isin(s0, [2, 3])] = 1.0
    # Check 4 neighbors at ±1 cell (~0.6m)
    for dx, dz in [(1,0),(-1,0),(0,1),(0,-1)]:
        nix = np.clip(ix + dx, 0, RES - 1)
        niz = np.clip(iz + dz, 0, RES - 1)
        ns = surface[niz, nix]
        near_path = np.isin(ns, [2, 3])
        path_prox = np.maximum(path_prox, np.where(near_path, 0.8, 0.0))
    # Check 4 neighbors at ±2 cells (~1.2m)
    for dx, dz in [(2,0),(-2,0),(0,2),(0,-2)]:
        nix = np.clip(ix + dx, 0, RES - 1)
        niz = np.clip(iz + dz, 0, RES - 1)
        ns = surface[niz, nix]
        near_path = np.isin(ns, [2, 3])
        path_prox = np.maximum(path_prox, np.where(near_path, 0.4, 0.0))
    path_prox_u8 = np.clip((path_prox * 255.0).astype(np.uint8), 0, 255)
    n_near_path = int(np.sum(path_prox > 0.05))
    print(f"    {n_near_path} instances near paths (with proximity)")

    # --- Pre-compute terrain Y (vectorized) ---
    # Load heightmap.bin (written earlier in pipeline)
    hm_path = "heightmap.bin"
    if os.path.exists(hm_path):
        with open(hm_path, 'rb') as hf:
            hm_w, hm_h = struct.unpack('<II', hf.read(8))
            hm_world_size = struct.unpack('<f', hf.read(4))[0]
            hm_origin_y = struct.unpack('<f', hf.read(4))[0]
            hm_data = np.frombuffer(hf.read(), dtype=np.float32).reshape(hm_h, hm_w)

        # Bilinear sample heightmap at instance positions
        u = (x_arr + hm_world_size * 0.5) / hm_world_size
        v = (z_arr + hm_world_size * 0.5) / hm_world_size
        xi_f = u * (hm_w - 1)
        zi_f = v * (hm_h - 1)
        xi0 = np.clip(xi_f.astype(np.int32), 0, hm_w - 2)
        zi0 = np.clip(zi_f.astype(np.int32), 0, hm_h - 2)
        fx = xi_f - xi0
        fz = zi_f - zi0
        h00 = hm_data[zi0, xi0]
        h10 = hm_data[zi0, xi0 + 1]
        h01 = hm_data[zi0 + 1, xi0]
        h11 = hm_data[zi0 + 1, xi0 + 1]
        y_arr = (h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) +
                 h01 * (1 - fx) * fz + h11 * fx * fz + 0.002).astype(np.float32)
        print(f"    Pre-computed Y from heightmap ({hm_w}×{hm_h})")
    else:
        print("    WARNING: heightmap.bin not found — Y values will be 0")
        y_arr = np.full(count, 0.002, dtype=np.float32)

    # --- Write enhanced format (v2) ---
    # Magic "GRS2" + count + x + y + z + type + path_prox
    out_path = "grass_instances.bin"
    with open(out_path, 'wb') as f:
        f.write(struct.pack('<I', 0x47525332))  # magic "GRS2"
        f.write(struct.pack('<I', count))
        f.write(x_arr.tobytes())
        f.write(y_arr.tobytes())
        f.write(z_arr.tobytes())
        f.write(type_arr.tobytes())
        f.write(path_prox_u8.tobytes())

    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    names = ["SheepMeadow","GreatLawn","NorthMeadow","FormalGarden","SportsTurf",
             "NorthWoods","Ramble","Waterside","WildMeadow","OpenLawn"]
    breakdown = ", ".join(f"{names[i]}={int(np.sum(type_arr==i))}" for i in range(10) if np.sum(type_arr==i) > 0)
    print(f"  Grass: {count} instances (v2 format) → {size_mb:.1f} MB")
    print(f"    {breakdown}")


def prebake_landuse_map(landuse_zones, water_bodies):
    """Pre-bake landuse zone map at 8192×8192 resolution → landuse_map.png.

    Replaces runtime GDScript scanline rasterization (1024×1024) with a
    higher-resolution pre-baked texture.  Zone encoding matches main.gd:
      0=unzoned, 1=garden, 2=grass, 3=pitch, 4=playground, 5=nature_reserve,
      6=dog_park, 7=sports, 8=pool, 9=track, 10=wood, 11=forest, 12=water, 13=shore
    """
    import numpy as np
    from PIL import Image, ImageDraw

    ZONE_MAP = {
        "garden": 1, "grass": 2, "pitch": 3, "playground": 4,
        "nature_reserve": 5, "dog_park": 6, "sports": 7,
        "sports_centre": 7, "swimming_pool": 8, "pool": 8,
        "track": 9, "wood": 10, "forest": 11,
    }

    RES = ATLAS_RES  # 8192 — matches heightmap and world atlas
    HALF = WORLD_SIZE / 2.0

    def world_to_pixel(wx, wz):
        px = (wx + HALF) / WORLD_SIZE * RES
        pz = (wz + HALF) / WORLD_SIZE * RES
        return px, pz

    print("Pre-baking landuse map at %d×%d..." % (RES, RES))

    # Use PIL for fast polygon rasterization
    img = Image.new('L', (RES, RES), 0)
    draw = ImageDraw.Draw(img)

    # --- Rasterize landuse zones ---
    filled = 0
    for zone in landuse_zones:
        zone_type = zone.get("type", "")
        zone_id = ZONE_MAP.get(zone_type, 0)
        if zone_id == 0:
            continue
        pts = zone.get("points", [])
        if len(pts) < 3:
            continue
        poly = [world_to_pixel(float(pt[0]), float(pt[1])) for pt in pts]
        draw.polygon(poly, fill=zone_id)
        filled += 1
    print(f"  Landuse: {filled} zones rasterized")

    # --- Rasterize water bodies (zone 12) ---
    water_count = 0
    for body in water_bodies:
        pts = body.get("points", [])
        if len(pts) < 3:
            continue
        poly = [world_to_pixel(float(pt[0]), float(pt[1])) for pt in pts]
        draw.polygon(poly, fill=12)
        water_count += 1
    print(f"  Landuse: {water_count} water bodies rasterized")

    # --- Dilate water → shore zone (13) using numpy ---
    # At 8192 over 5000m, 1 pixel ≈ 0.61m. 24-pixel radius ≈ 15m shore.
    if water_count > 0:
        arr = np.array(img, dtype=np.uint8)
        water_mask = (arr == 12)
        # Create circular structuring element
        SHORE_R = 24  # pixels ≈ 15m at 8192
        y_idx, x_idx = np.ogrid[-SHORE_R:SHORE_R+1, -SHORE_R:SHORE_R+1]
        disk = (x_idx**2 + y_idx**2) <= SHORE_R**2
        # Dilate water mask
        from scipy.ndimage import binary_dilation
        dilated = binary_dilation(water_mask, structure=disk)
        # Shore = dilated AND NOT water AND NOT already a non-zero zone
        shore_mask = dilated & ~water_mask & (arr == 0)
        # Also allow shore to overwrite grass (zone 1,2) near water
        shore_mask |= dilated & ~water_mask & ((arr == 1) | (arr == 2))
        shore_count = int(shore_mask.sum())
        arr[shore_mask] = 13
        print(f"  Landuse: {shore_count} shore pixels ({SHORE_R}px ≈ 15m radius)")
        img = Image.fromarray(arr, mode='L')

    img.save("landuse_map.png")
    size_kb = os.path.getsize("landuse_map.png") / 1024
    print(f"  Landuse: saved → landuse_map.png ({RES}×{RES}, {size_kb:.0f} KB)")

    # --- Pre-bake shore distance field → shore_distance.png ---
    # Continuous distance-to-water encoded as 0-255 (0=water edge, 255=far away).
    # Saved with filter_linear so the shader gets smooth interpolation — no aliased edges.
    if water_count > 0:
        from scipy.ndimage import distance_transform_edt
        arr2 = np.array(img, dtype=np.uint8)
        water_mask2 = (arr2 == 12)
        # Distance from every non-water pixel to the nearest water pixel (in pixel units)
        dist = distance_transform_edt(~water_mask2).astype(np.float32)
        # Also compute distance INTO water from shore (for underwater depth tinting)
        dist_in = distance_transform_edt(water_mask2).astype(np.float32)
        # Encode: R = distance from water (0-30m mapped to 0-255), G = depth into water (0-30m)
        MAX_DIST_M = 30.0
        px_per_m = RES / WORLD_SIZE  # ~0.82 px/m
        max_dist_px = MAX_DIST_M * px_per_m
        r_ch = np.clip(dist / max_dist_px * 255.0, 0, 255).astype(np.uint8)
        g_ch = np.clip(dist_in / max_dist_px * 255.0, 0, 255).astype(np.uint8)
        shore_img = Image.fromarray(np.stack([r_ch, g_ch], axis=-1), mode='LA')
        shore_img.save("shore_distance.png")
        sd_kb = os.path.getsize("shore_distance.png") / 1024
        print(f"  Shore distance: saved → shore_distance.png ({RES}×{RES}, {sd_kb:.0f} KB)")


def prebake_terrain_mesh(hm_arr, boundary_pts, surface_arr=None):
    """Pre-bake terrain mesh at full 8K resolution → terrain_mesh.bin.

    Generates the terrain ArrayMesh in Python rather than GDScript.
    At 8192×8192, the mesh has 0.61m cells — enough to capture bridge decks,
    parapets, steps, retaining walls, and rock outcrop detail from LiDAR.

    Only emits triangles inside the park boundary + 200m buffer.
    Vertices are re-indexed so only used vertices are stored.

    Vertex colors encode smoothed surface blend weights (replaces the GPU
    splat map atlas — GPU hardware interpolates vertex colors across triangle
    faces, eliminating the hard 0.61m cell boundaries that caused grid artifacts):
        R = paved path/bridge blend (0-255)
        G = unpaved trail blend (0-255)
        B = rock blend (0-255)
        A = structure mask / special (0-255)

    Format v2:
        uint32 vertex_count
        uint32 index_count
        float32 world_size
        uint32  version (2 = has vertex colors)
        float32[vertex_count * 3] positions (x, y, z interleaved)
        uint8[vertex_count * 4] colors (RGBA8 interleaved)
        uint32[index_count] indices
    """
    import struct
    import numpy as np
    from PIL import Image, ImageDraw
    from scipy.ndimage import binary_dilation

    W = hm_arr.shape[1]  # 8192
    H = hm_arr.shape[0]  # 8192
    HALF = WORLD_SIZE / 2.0
    cell = WORLD_SIZE / (W - 1)
    print(f"Pre-baking terrain mesh at {W}×{H} ({cell:.2f} m/cell)...")

    # Rasterize boundary + buffer as a mask at grid resolution
    def world_to_pixel(wx, wz):
        px = (wx + HALF) / WORLD_SIZE * W
        pz = (wz + HALF) / WORLD_SIZE * H
        return px, pz

    mask_img = Image.new('L', (W, H), 0)
    draw = ImageDraw.Draw(mask_img)
    if len(boundary_pts) >= 3:
        poly = [world_to_pixel(float(bp[0]), float(bp[1])) for bp in boundary_pts]
        draw.polygon(poly, fill=255)

    inside = np.array(mask_img, dtype=np.uint8) > 0
    del mask_img

    # Dilate by ~200m buffer (streets between park and buildings)
    buf_cells = int(np.ceil(200.0 / cell))
    dilated = binary_dilation(inside, iterations=buf_cells)
    # Use dilated mask for vertex inclusion
    vertex_mask = dilated
    inside_count = int(inside.sum())
    buffer_count = int(vertex_mask.sum()) - inside_count
    print(f"  Boundary: {inside_count} cells inside + {buffer_count} buffer = {int(vertex_mask.sum())} total")
    del inside, dilated

    # Determine which cells emit triangles (any corner inside mask)
    print("  Building cell and vertex maps...")
    cell_mask = (vertex_mask[:-1, :-1] | vertex_mask[:-1, 1:] |
                 vertex_mask[1:, :-1]  | vertex_mask[1:, 1:])

    # Mark vertices needed: all 4 corners of every emitting cell
    needed = np.zeros((H, W), dtype=bool)
    cell_zi, cell_xi = np.where(cell_mask)
    needed[cell_zi,     cell_xi]     = True  # top-left
    needed[cell_zi,     cell_xi + 1] = True  # top-right
    needed[cell_zi + 1, cell_xi]     = True  # bottom-left
    needed[cell_zi + 1, cell_xi + 1] = True  # bottom-right

    n_verts = int(needed.sum())
    print(f"  Vertices: {n_verts:,} ({n_verts * 12 / 1e6:.1f} MB positions)")

    # Assign sequential indices to needed vertices
    vert_idx = np.full((H, W), -1, dtype=np.int32)
    vert_idx[needed] = np.arange(n_verts, dtype=np.int32)

    # Generate vertex positions (UVs derived at load time from position)
    print("  Generating positions...")
    zi_all, xi_all = np.where(needed)
    positions = np.empty((n_verts, 3), dtype=np.float32)
    positions[:, 0] = -HALF + xi_all.astype(np.float32) * cell  # x
    positions[:, 1] = hm_arr[zi_all, xi_all]                     # y (height)
    positions[:, 2] = -HALF + zi_all.astype(np.float32) * cell  # z

    # --- Vertex colors: smoothed surface blend weights ---
    # GPU hardware interpolation across triangle faces eliminates the hard
    # 0.61m cell boundaries that caused visible grid artifacts with the atlas.
    # Pre-blur each surface mask with Gaussian kernel for natural ~2m transitions.
    print("  Computing vertex colors (smoothed surface blends)...")
    colors = np.zeros((n_verts, 4), dtype=np.uint8)
    if surface_arr is not None:
        from scipy.ndimage import gaussian_filter
        # Ensure surface array matches heightmap resolution
        assert surface_arr.shape == (H, W), \
            f"Surface array {surface_arr.shape} != heightmap {(H, W)}"
        # Sigma in pixels: 2.5 px × 0.61 m/px ≈ 1.5m blur radius.
        # This creates ~3m wide transitions at surface boundaries —
        # natural for grass-to-path edges (real paths have worn dirt borders).
        SIGMA = 2.5
        # R channel: paved path + bridge blend
        paved_mask = ((surface_arr == 2) | (surface_arr == 6)).astype(np.float32)
        paved_smooth = gaussian_filter(paved_mask, sigma=SIGMA)
        del paved_mask
        # G channel: unpaved trail blend
        unpaved_mask = (surface_arr == 3).astype(np.float32)
        unpaved_smooth = gaussian_filter(unpaved_mask, sigma=SIGMA)
        del unpaved_mask
        # B channel: rock blend (from atlas type 7 + slope detection)
        rock_mask = (surface_arr == 7).astype(np.float32)
        # Also add slope-based rock: compute terrain slope from heightmap
        # Finite differences for slope magnitude
        dy_dz = np.zeros_like(hm_arr)
        dy_dx = np.zeros_like(hm_arr)
        dy_dz[1:-1, :] = (hm_arr[2:, :] - hm_arr[:-2, :]) / (2.0 * cell)
        dy_dx[:, 1:-1] = (hm_arr[:, 2:] - hm_arr[:, :-2]) / (2.0 * cell)
        slope = np.sqrt(dy_dx**2 + dy_dz**2)
        # Steep slopes (>30°, slope>0.577) get rock material
        slope_rock = np.clip((slope - 0.4) / 0.3, 0.0, 1.0)
        # Combine atlas rock + slope rock
        rock_combined = np.maximum(rock_mask, slope_rock).astype(np.float32)
        rock_smooth = gaussian_filter(rock_combined, sigma=SIGMA)
        del rock_mask, slope_rock, rock_combined, slope, dy_dx, dy_dz
        # A channel: building area (surface_arr == 5) — shader can skip detail
        bldg_mask = (surface_arr == 5).astype(np.float32)
        bldg_smooth = gaussian_filter(bldg_mask, sigma=1.0)  # tighter transition
        del bldg_mask
        # Sample smoothed fields at vertex positions and encode as uint8
        colors[:, 0] = np.clip(paved_smooth[zi_all, xi_all] * 255.0, 0, 255).astype(np.uint8)
        colors[:, 1] = np.clip(unpaved_smooth[zi_all, xi_all] * 255.0, 0, 255).astype(np.uint8)
        colors[:, 2] = np.clip(rock_smooth[zi_all, xi_all] * 255.0, 0, 255).astype(np.uint8)
        colors[:, 3] = np.clip(bldg_smooth[zi_all, xi_all] * 255.0, 0, 255).astype(np.uint8)
        del paved_smooth, unpaved_smooth, rock_smooth, bldg_smooth
        paved_verts = int((colors[:, 0] > 128).sum())
        unpaved_verts = int((colors[:, 1] > 128).sum())
        rock_verts = int((colors[:, 2] > 128).sum())
        print(f"  Vertex colors: {paved_verts:,} paved, {unpaved_verts:,} unpaved, "
              f"{rock_verts:,} rock (with ~1.5m Gaussian transition)")
    else:
        print("  WARNING: No surface array — vertex colors will be all-zero (grass)")

    # Generate triangle indices from cell_mask (already computed above)
    print("  Generating triangles...")
    n_cells = len(cell_zi)
    n_tris = n_cells * 2
    n_indices = n_tris * 3
    print(f"  Triangles: {n_tris:,} ({n_indices:,} indices, {n_indices * 4 / 1e6:.1f} MB)")

    # Look up vertex indices for each cell's 4 corners
    i00 = vert_idx[cell_zi,     cell_xi]      # top-left
    i10 = vert_idx[cell_zi,     cell_xi + 1]  # top-right
    i01 = vert_idx[cell_zi + 1, cell_xi]      # bottom-left
    i11 = vert_idx[cell_zi + 1, cell_xi + 1]  # bottom-right

    # Two triangles per cell: (i00, i10, i11) and (i00, i11, i01)
    indices = np.empty((n_cells, 6), dtype=np.uint32)
    indices[:, 0] = i00; indices[:, 1] = i10; indices[:, 2] = i11
    indices[:, 3] = i00; indices[:, 4] = i11; indices[:, 5] = i01
    indices = indices.ravel()

    # Verify no -1 indices (should never happen with correct needed mask)
    bad = int((indices == 0xFFFFFFFF).sum())
    if bad > 0:
        print(f"  WARNING: {bad} invalid indices — vertex mask error")

    # Write binary v2 (positions + vertex colors + indices)
    print("  Writing terrain_mesh.bin (v2 with vertex colors)...")
    with open("terrain_mesh.bin", "wb") as f:
        f.write(struct.pack("<II", n_verts, len(indices)))
        f.write(struct.pack("<f", WORLD_SIZE))
        f.write(struct.pack("<I", 2))  # version 2: has vertex colors
        f.write(positions.tobytes())
        f.write(colors.tobytes())  # RGBA8, n_verts × 4 bytes
        f.write(indices.tobytes())

    mesh_mb = os.path.getsize("terrain_mesh.bin") / 1e6
    color_mb = n_verts * 4 / 1e6
    print(f"  Saved → terrain_mesh.bin ({n_verts:,} verts, {n_tris:,} tris, "
          f"{mesh_mb:.1f} MB, vertex colors {color_mb:.1f} MB)")

    del vert_idx, needed, positions, colors, indices


def prebake_boundary_mask(boundary_pts):
    """Pre-bake park boundary mask at 8192×8192 → boundary_mask.png.

    White = inside park, black = outside.  Replaces runtime GDScript
    scanline rasterization (1024×1024) with higher-resolution pre-bake.
    """
    from PIL import Image, ImageDraw

    RES = ATLAS_RES  # 8192 — matches heightmap and world atlas
    HALF = WORLD_SIZE / 2.0

    def world_to_pixel(wx, wz):
        px = (wx + HALF) / WORLD_SIZE * RES
        pz = (wz + HALF) / WORLD_SIZE * RES
        return px, pz

    print("Pre-baking boundary mask at %d×%d..." % (RES, RES))

    if len(boundary_pts) < 3:
        print("  Boundary: not enough points, skipping")
        return

    img = Image.new('L', (RES, RES), 0)
    draw = ImageDraw.Draw(img)
    poly = [world_to_pixel(float(bp[0]), float(bp[1])) for bp in boundary_pts]
    draw.polygon(poly, fill=255)

    img.save("boundary_mask.png")
    size_kb = os.path.getsize("boundary_mask.png") / 1024
    print(f"  Boundary: saved → boundary_mask.png ({RES}×{RES}, {size_kb:.0f} KB)")


if __name__ == "__main__":
    main()
