"""Build grass tile models for Central Park Walk — 10 area-specific types.

AAA-quality approach: narrow blades (8-15mm) at high density (800-1200
per tile) create a dense fringe that reads as real grass. Mowed lawns
use 1-segment straight spikes (nearly vertical). Unmowed types use 2-3
segments with dramatic arch for flowing tall grass.

Types match Central Park Conservancy ABCD lawn classification:

  0. sheep_meadow    — A Lawn, KBG/ryegrass, 6-8cm, very dense, uniform
  1. great_lawn      — A Lawn, KBG/ryegrass, 6-8cm, dense, uniform
  2. north_meadow    — A Lawn, heavy-use soccer, 6-8cm, dense
  3. formal_garden   — A Lawn, manicured, 4-5.5cm, very dense, pristine
  4. sports_turf     — A Lawn, athletic fields, 3-4cm, densest, crew-cut
  5. north_woods     — D Lawn, shade fescue, 3-10cm sparse, varied
  6. ramble          — D Lawn, woodland floor, 4-12cm, moderate
  7. waterside       — C Lawn, moisture-loving, 6-14cm, reedy, curved
  8. wild_meadow     — Unmowed, 15-35cm, dramatic arch, golden tips
  9. open_lawn       — B/C Lawn, maintained, 6-8cm, moderate

Blade design:
  Mowed (types 0-4, 9): 1-segment straight spike (4 verts). Nearly
    vertical, narrow (8-12mm), barely any arch. Dense fringe of thin
    spikes creates convincing cut-grass look.
  Woodland (5-6): 2-segment curve, moderate width (10-16mm), varied.
  Waterside (7): 2-segment, wider (12-18mm), tall, reedy curves.
  Wild meadow (8): 3-segment dramatic arch, flowing (12-18mm), golden.

Wildflowers: subtle tiny quads — clover, dandelion, violet, chickweed.
  A Lawns ~1%, B/C ~3%, D ~5%, wild ~10%.

Exports to models/vegetation/Grass_Tile_*.glb
"""

import bpy
import bmesh
import math
import random
import os

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "models", "vegetation")
os.makedirs(OUT_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Grass blade — narrow strip at a position with random direction
# ---------------------------------------------------------------------------
def make_blade(bm, color_layer, uv_layer,
               bx, bz, height, width, rot, arch,
               segments, base_rgb, tip_rgb):
    """Create one grass blade as a narrow strip at position (bx, bz).

    For segments=1: a single straight quad (4 verts, 1 face) — mowed grass.
    For segments=2+: curved multi-segment strip — unmowed/wild grass.
    """
    dx = math.cos(rot)
    dz = math.sin(rot)
    px = -math.sin(rot)
    pz = math.cos(rot)

    vert_pairs = []
    for si in range(segments + 1):
        t = si / segments
        # Height curve: slight deceleration at top for natural taper
        seg_h = height * (t - 0.15 * t * t)
        # Arch: quadratic extension in facing direction
        extend = arch * t * t
        # Width tapers toward tip (grass blade narrows)
        seg_w = width * (1.0 - t * 0.7)
        hw = seg_w * 0.5

        cx = bx + dx * extend
        cz = bz + dz * extend

        r = base_rgb[0] + (tip_rgb[0] - base_rgb[0]) * t
        g = base_rgb[1] + (tip_rgb[1] - base_rgb[1]) * t
        b = base_rgb[2] + (tip_rgb[2] - base_rgb[2]) * t

        vl = bm.verts.new((cx + px * hw, seg_h, cz + pz * hw))
        vr = bm.verts.new((cx - px * hw, seg_h, cz - pz * hw))
        vert_pairs.append((vl, vr, (r, g, b, 1.0), t))

    for si in range(segments):
        vl0, vr0, c0, t0 = vert_pairs[si]
        vl1, vr1, c1, t1 = vert_pairs[si + 1]
        try:
            face = bm.faces.new([vl0, vr0, vr1, vl1])
        except ValueError:
            continue
        for loop in face.loops:
            if loop.vert == vl0:
                loop[color_layer] = c0
                loop[uv_layer].uv = (0.0, t0)
            elif loop.vert == vr0:
                loop[color_layer] = c0
                loop[uv_layer].uv = (1.0, t0)
            elif loop.vert == vr1:
                loop[color_layer] = c1
                loop[uv_layer].uv = (1.0, t1)
            elif loop.vert == vl1:
                loop[color_layer] = c1
                loop[uv_layer].uv = (0.0, t1)


# ---------------------------------------------------------------------------
# Small wildflower / clover element
# ---------------------------------------------------------------------------
def make_flower(bm, color_layer, uv_layer, fx, fz, height, size, rgb):
    """Create a small flower as a horizontal quad at the given height."""
    hs = size * 0.5
    y = height
    v0 = bm.verts.new((fx - hs, y, fz - hs))
    v1 = bm.verts.new((fx + hs, y, fz - hs))
    v2 = bm.verts.new((fx + hs, y, fz + hs))
    v3 = bm.verts.new((fx - hs, y, fz + hs))
    try:
        face = bm.faces.new([v0, v1, v2, v3])
    except ValueError:
        return
    col = (rgb[0], rgb[1], rgb[2], 1.0)
    for loop in face.loops:
        loop[color_layer] = col
        loop[uv_layer].uv = (0.5, 0.5)


def make_clover_leaf(bm, color_layer, uv_layer, cx, cz, height, size):
    """Create a 3-leaf clover cluster as 3 tiny tilted quads."""
    leaf_rgb = (0.15, 0.38, 0.08)
    for i in range(3):
        angle = i * 2.094 + 0.3  # 120° apart
        lx = cx + math.cos(angle) * size * 0.6
        lz = cz + math.sin(angle) * size * 0.6
        hs = size * 0.35
        y = height
        v0 = bm.verts.new((lx - hs, y,        lz - hs))
        v1 = bm.verts.new((lx + hs, y,        lz - hs))
        v2 = bm.verts.new((lx + hs, y + 0.003, lz + hs))
        v3 = bm.verts.new((lx - hs, y + 0.003, lz + hs))
        try:
            face = bm.faces.new([v0, v1, v2, v3])
        except ValueError:
            continue
        col = (leaf_rgb[0], leaf_rgb[1], leaf_rgb[2], 1.0)
        for loop in face.loops:
            loop[color_layer] = col
            loop[uv_layer].uv = (0.5, 0.5)


# Flower types — subtle, small, nestled in grass
FLOWER_PALETTE = [
    # (rgb, size_mult, name)
    ((0.70, 0.70, 0.62), 0.5, "white_clover_bloom"),
    ((0.72, 0.65, 0.12), 0.6, "dandelion"),
    ((0.40, 0.25, 0.55), 0.5, "violet"),
    ((0.65, 0.65, 0.58), 0.35, "chickweed"),
    ((0.60, 0.42, 0.52), 0.4, "henbit"),
]


# ---------------------------------------------------------------------------
# Distributed grass tile builder
# ---------------------------------------------------------------------------
def build_grass_tile(cfg, seed):
    """Build a circular grass tile with narrow blades distributed throughout."""
    rng = random.Random(seed)
    bm = bmesh.new()
    color_layer = bm.loops.layers.color.new("Color")
    uv_layer = bm.loops.layers.uv.new("UV")

    radius = cfg["radius"]
    blade_count = cfg["blade_count"]
    h_lo, h_hi = cfg["height_range"]
    w_lo, w_hi = cfg["width_range"]
    a_lo, a_hi = cfg["arch_range"]
    segments = cfg.get("segments", 1)
    base_rgb = cfg["base_rgb"]
    tip_rgb = cfg["tip_rgb"]
    color_var = cfg.get("color_var", 0.04)
    flower_pct = cfg.get("flower_pct", 0.0)
    clover_pct = cfg.get("clover_pct", 0.0)

    for _ in range(blade_count):
        r = radius * math.sqrt(rng.random())
        theta = rng.random() * 2 * math.pi
        bx = r * math.cos(theta)
        bz = r * math.sin(theta)

        rot = rng.random() * 2 * math.pi

        h = rng.uniform(h_lo, h_hi)
        w = rng.uniform(w_lo, w_hi)
        arch = rng.uniform(a_lo, a_hi)

        cv = rng.uniform(-color_var, color_var)
        b_rgb = (
            max(0.01, base_rgb[0] + cv * 0.8),
            max(0.01, base_rgb[1] + cv * 0.6),
            max(0.01, base_rgb[2] + cv * 0.4),
        )
        t_rgb = (
            min(0.95, tip_rgb[0] + cv * 0.6),
            min(0.95, tip_rgb[1] + cv * 0.5),
            min(0.95, tip_rgb[2] + cv * 0.3),
        )

        make_blade(bm, color_layer, uv_layer,
                   bx, bz, h, w, rot, arch,
                   segments, b_rgb, t_rgb)

    # Wildflowers
    n_flowers = int(blade_count * flower_pct)
    for _ in range(n_flowers):
        r = radius * math.sqrt(rng.random())
        theta = rng.random() * 2 * math.pi
        fx = r * math.cos(theta)
        fz = r * math.sin(theta)
        fh = rng.uniform(h_lo * 0.8, h_hi * 1.1)
        ftype = rng.choice(FLOWER_PALETTE)
        fsize = rng.uniform(0.006, 0.012) * ftype[1]
        make_flower(bm, color_layer, uv_layer, fx, fz, fh, fsize, ftype[0])

    # Clover patches
    n_clover = int(blade_count * clover_pct)
    for _ in range(n_clover):
        r = radius * math.sqrt(rng.random())
        theta = rng.random() * 2 * math.pi
        cx = r * math.cos(theta)
        cz = r * math.sin(theta)
        ch = rng.uniform(h_lo * 0.5, h_lo * 0.9)
        csize = rng.uniform(0.008, 0.015)
        make_clover_leaf(bm, color_layer, uv_layer, cx, cz, ch, csize)
        if rng.random() < 0.2:
            make_flower(bm, color_layer, uv_layer, cx, cz,
                        ch + 0.006, rng.uniform(0.004, 0.008),
                        (0.65, 0.65, 0.58))

    return bm


# ---------------------------------------------------------------------------
# 10 grass types — CPC Conservancy ABCD lawn data + Wikimedia colors
# ---------------------------------------------------------------------------
GRASS_TYPES = [
    # 0: Sheep Meadow — A Lawn, 80% KBG / 20% ryegrass, mowed 2x/week
    #    Tight height range = uniform mowed look. 1-segment straight spikes.
    {
        "name": "Grass_Tile_SheepMeadow",
        "blade_count": 1000,
        "radius": 1.0,
        "height_range": (0.06, 0.08),
        "width_range": (0.008, 0.014),
        "arch_range": (0.005, 0.015),
        "segments": 1,
        "base_rgb": (0.22, 0.42, 0.08),
        "tip_rgb": (0.48, 0.68, 0.30),
        "color_var": 0.04,
        "flower_pct": 0.01,
        "clover_pct": 0.01,
        "seed": 42,
    },
    # 1: Great Lawn — A Lawn, KBG/ryegrass, mowed 2x/week
    {
        "name": "Grass_Tile_GreatLawn",
        "blade_count": 900,
        "radius": 1.0,
        "height_range": (0.06, 0.08),
        "width_range": (0.008, 0.013),
        "arch_range": (0.005, 0.015),
        "segments": 1,
        "base_rgb": (0.20, 0.40, 0.07),
        "tip_rgb": (0.42, 0.62, 0.25),
        "color_var": 0.05,
        "flower_pct": 0.01,
        "clover_pct": 0.01,
        "seed": 73,
    },
    # 2: North Meadow — A Lawn, heavy-use soccer, seeded 2x/week
    {
        "name": "Grass_Tile_NorthMeadow",
        "blade_count": 850,
        "radius": 0.95,
        "height_range": (0.06, 0.08),
        "width_range": (0.009, 0.015),
        "arch_range": (0.005, 0.018),
        "segments": 1,
        "base_rgb": (0.20, 0.38, 0.07),
        "tip_rgb": (0.45, 0.60, 0.26),
        "color_var": 0.06,
        "flower_pct": 0.02,
        "clover_pct": 0.02,
        "seed": 109,
    },
    # 3: Formal garden — A Lawn, Conservatory Garden, pristine
    {
        "name": "Grass_Tile_FormalGarden",
        "blade_count": 1100,
        "radius": 0.95,
        "height_range": (0.04, 0.055),
        "width_range": (0.007, 0.012),
        "arch_range": (0.003, 0.010),
        "segments": 1,
        "base_rgb": (0.22, 0.40, 0.10),
        "tip_rgb": (0.40, 0.58, 0.24),
        "color_var": 0.03,
        "flower_pct": 0.005,
        "clover_pct": 0.005,
        "seed": 151,
    },
    # 4: Sports field — A Lawn, athletic crew-cut, densest
    {
        "name": "Grass_Tile_SportsTurf",
        "blade_count": 1200,
        "radius": 1.0,
        "height_range": (0.025, 0.04),
        "width_range": (0.007, 0.011),
        "arch_range": (0.002, 0.008),
        "segments": 1,
        "base_rgb": (0.25, 0.45, 0.10),
        "tip_rgb": (0.45, 0.65, 0.28),
        "color_var": 0.02,
        "flower_pct": 0.005,
        "clover_pct": 0.005,
        "seed": 197,
    },
    # 5: North Woods understory — D Lawn, shade fescue, sparse + varied
    {
        "name": "Grass_Tile_NorthWoods",
        "blade_count": 300,
        "radius": 0.70,
        "height_range": (0.03, 0.10),
        "width_range": (0.010, 0.018),
        "arch_range": (0.010, 0.040),
        "segments": 2,
        "base_rgb": (0.10, 0.25, 0.05),
        "tip_rgb": (0.25, 0.42, 0.15),
        "color_var": 0.05,
        "flower_pct": 0.06,
        "clover_pct": 0.02,
        "seed": 233,
    },
    # 6: Ramble / Dene — D Lawn, woodland floor, moderate density
    {
        "name": "Grass_Tile_Ramble",
        "blade_count": 450,
        "radius": 0.80,
        "height_range": (0.04, 0.12),
        "width_range": (0.010, 0.018),
        "arch_range": (0.010, 0.045),
        "segments": 2,
        "base_rgb": (0.12, 0.28, 0.06),
        "tip_rgb": (0.30, 0.48, 0.18),
        "color_var": 0.05,
        "flower_pct": 0.05,
        "clover_pct": 0.02,
        "seed": 277,
    },
    # 7: Waterside — C Lawn, tall reedy moisture-loving, curved blades
    {
        "name": "Grass_Tile_Waterside",
        "blade_count": 600,
        "radius": 0.90,
        "height_range": (0.06, 0.14),
        "width_range": (0.012, 0.020),
        "arch_range": (0.020, 0.060),
        "segments": 2,
        "base_rgb": (0.14, 0.34, 0.06),
        "tip_rgb": (0.35, 0.55, 0.20),
        "color_var": 0.05,
        "flower_pct": 0.03,
        "clover_pct": 0.02,
        "seed": 313,
    },
    # 8: Wild meadow — unmowed nature reserve, BotW-style flowing grass
    #    3-segment dramatic arch, golden tips, abundant wildflowers
    {
        "name": "Grass_Tile_WildMeadow",
        "blade_count": 500,
        "radius": 0.95,
        "height_range": (0.15, 0.35),
        "width_range": (0.012, 0.020),
        "arch_range": (0.040, 0.140),
        "segments": 3,
        "base_rgb": (0.14, 0.32, 0.05),
        "tip_rgb": (0.45, 0.48, 0.20),
        "color_var": 0.06,
        "flower_pct": 0.10,
        "clover_pct": 0.03,
        "seed": 359,
    },
    # 9: Open lawn — B/C Lawn, default maintained grass
    {
        "name": "Grass_Tile_OpenLawn",
        "blade_count": 850,
        "radius": 1.0,
        "height_range": (0.06, 0.08),
        "width_range": (0.008, 0.014),
        "arch_range": (0.005, 0.018),
        "segments": 1,
        "base_rgb": (0.20, 0.40, 0.07),
        "tip_rgb": (0.44, 0.62, 0.26),
        "color_var": 0.05,
        "flower_pct": 0.03,
        "clover_pct": 0.02,
        "seed": 401,
    },
]


# ---------------------------------------------------------------------------
# Material & export
# ---------------------------------------------------------------------------
def make_grass_material(name):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    tree = mat.node_tree
    nodes = tree.nodes
    links = tree.links
    for n in nodes:
        nodes.remove(n)
    out = nodes.new('ShaderNodeOutputMaterial')
    out.location = (400, 0)
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.location = (100, 0)
    bsdf.inputs['Roughness'].default_value = 0.85
    bsdf.inputs['Specular'].default_value = 0.06
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    vcol = nodes.new('ShaderNodeVertexColor')
    vcol.location = (-200, 0)
    vcol.layer_name = "Color"
    links.new(vcol.outputs['Color'], bsdf.inputs['Base Color'])
    return mat


def export_tile(bm, name, material):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)

    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    filepath = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=True,
        export_colors=True,
        export_normals=True,
        export_apply=True,
    )

    vc = len(mesh.vertices)
    fc = len(mesh.polygons)
    print(f"  {name}: {vc} verts, {fc} faces ({cfg['blade_count']} blades, "
          f"seg={cfg.get('segments', 1)}, w={cfg['width_range'][0]*1000:.0f}-"
          f"{cfg['width_range'][1]*1000:.0f}mm)")
    bpy.ops.object.delete(use_global=False)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)

print("=" * 60)
print("Building 10 grass tile models — AAA narrow-blade approach")
print("=" * 60)

mat = make_grass_material("GrassBlade")

for i, cfg in enumerate(GRASS_TYPES):
    name = cfg["name"]
    seed = cfg["seed"]
    blades = cfg["blade_count"]
    segs = cfg.get("segments", 1)
    wlo, whi = cfg["width_range"]
    print(f"\n[{i+1}/{len(GRASS_TYPES)}] {name} ({blades} blades, "
          f"seg={segs}, w={wlo*1000:.0f}-{whi*1000:.0f}mm)...")

    bm = build_grass_tile(cfg, seed)
    export_tile(bm, name, mat)

print(f"\nDone. {len(GRASS_TYPES)} grass tile models exported.")
