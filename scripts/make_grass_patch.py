"""Build grass tile models for Central Park Walk — 10 area-specific types.

Each tile is a circular area (~0.5-0.9m radius) densely packed with 3D
grass blades distributed throughout. When tiled at stride 2-3, adjacent
tiles overlap to carpet the ground. NOT clumps — blades grow across the
entire tile area like real turf.

Types based on real Central Park vegetation data + Wikimedia reference photos:

  0. sheep_meadow    — Bright Kentucky bluegrass, 5-10cm, very dense
  1. great_lawn      — Rich green turf, 6-11cm, dense
  2. north_meadow    — Open meadow, 8-14cm, moderate wild character
  3. formal_garden   — Manicured lawn, 4-8cm, very uniform
  4. sports_turf     — Short dense field grass, 3-6cm
  5. north_woods     — Sparse shade understory, 3-8cm, very dark
  6. ramble          — Moderate woodland floor, 4-10cm, dark green
  7. waterside       — Near water, taller/darker, 8-16cm
  8. wild_meadow     — Unmowed nature reserve, 18-35cm, golden tips
  9. open_lawn       — Default maintained grass, 6-12cm, moderate green

Blade design: 2-segment curved strips (6 verts per blade) distributed
randomly across the tile radius. Each blade has its own random rotation
and slight arch. Vertex colors provide albedo (no texture).

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
# Grass blade — self-contained at a position with random direction
# ---------------------------------------------------------------------------
def make_blade(bm, color_layer, uv_layer,
               bx, bz, height, width, rot, arch,
               segments, base_rgb, tip_rgb):
    """Create one grass blade as a curved strip at position (bx, bz).

    Unlike the old clump approach, blades don't radiate from center.
    Each blade has its own position and random direction.
    """
    dx = math.cos(rot)
    dz = math.sin(rot)
    px = -math.sin(rot)
    pz = math.cos(rot)

    vert_pairs = []
    for si in range(segments + 1):
        t = si / segments
        seg_h = height * (t - 0.25 * t * t)
        extend = arch * t * t
        seg_w = width * (1.0 - t * 0.65)
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
# Distributed grass tile builder
# ---------------------------------------------------------------------------
def build_grass_tile(cfg, seed):
    """Build a circular grass tile with blades distributed throughout.

    Blades are randomly placed within the tile radius, each with its
    own random rotation and arch direction. This creates uniform ground
    cover, not a single clump.
    """
    rng = random.Random(seed)
    bm = bmesh.new()
    color_layer = bm.loops.layers.color.new("Color")
    uv_layer = bm.loops.layers.uv.new("UV")

    radius = cfg["radius"]
    blade_count = cfg["blade_count"]
    h_lo, h_hi = cfg["height_range"]
    w_lo, w_hi = cfg["width_range"]
    a_lo, a_hi = cfg["arch_range"]
    segments = cfg.get("segments", 2)
    base_rgb = cfg["base_rgb"]
    tip_rgb = cfg["tip_rgb"]
    color_var = cfg.get("color_var", 0.04)

    for _ in range(blade_count):
        # Random position within tile radius (uniform disk sampling)
        r = radius * math.sqrt(rng.random())
        theta = rng.random() * 2 * math.pi
        bx = r * math.cos(theta)
        bz = r * math.sin(theta)

        # Random blade direction (NOT radiating from center)
        rot = rng.random() * 2 * math.pi

        h = rng.uniform(h_lo, h_hi)
        w = rng.uniform(w_lo, w_hi)
        arch = rng.uniform(a_lo, a_hi)

        # Color variation per blade
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

    return bm


# ---------------------------------------------------------------------------
# 10 grass types — colors from Wikimedia CP reference photos
# ---------------------------------------------------------------------------
# Color references:
#   Sheep Meadow: bright bluegrass (PIL analysis: avg 0.42,0.46,0.30)
#   North Woods: dark canopy floor
#   Grass texture close-up: blade gradients (dark base → bright tip)
#   Grass + clover: varied lawn (avg 0.46,0.60,0.28)
#   Great Lawn: maintained rich turf
#   Water edges: deeper green, moisture influence

GRASS_TYPES = [
    # 0: Sheep Meadow — iconic bright Kentucky bluegrass
    #    PIL analysis: avg (0.42, 0.46, 0.30), bright (0.64, 0.68, 0.58)
    {
        "name": "Grass_Tile_SheepMeadow",
        "blade_count": 550,
        "radius": 1.0,
        "height_range": (0.06, 0.12),
        "width_range": (0.045, 0.075),
        "arch_range": (0.03, 0.08),
        "segments": 2,
        "base_rgb": (0.22, 0.42, 0.08),
        "tip_rgb": (0.48, 0.68, 0.30),
        "color_var": 0.04,
        "seed": 42,
    },
    # 1: Great Lawn — rich green maintained turf
    {
        "name": "Grass_Tile_GreatLawn",
        "blade_count": 500,
        "radius": 1.0,
        "height_range": (0.06, 0.12),
        "width_range": (0.042, 0.070),
        "arch_range": (0.03, 0.09),
        "segments": 2,
        "base_rgb": (0.20, 0.40, 0.07),
        "tip_rgb": (0.42, 0.62, 0.25),
        "color_var": 0.05,
        "seed": 73,
    },
    # 2: North Meadow — open meadow, slightly wilder
    {
        "name": "Grass_Tile_NorthMeadow",
        "blade_count": 420,
        "radius": 0.95,
        "height_range": (0.08, 0.16),
        "width_range": (0.045, 0.075),
        "arch_range": (0.04, 0.12),
        "segments": 2,
        "base_rgb": (0.20, 0.38, 0.07),
        "tip_rgb": (0.45, 0.60, 0.26),
        "color_var": 0.06,
        "seed": 109,
    },
    # 3: Formal garden — Conservatory Garden, Shakespeare Garden
    {
        "name": "Grass_Tile_FormalGarden",
        "blade_count": 480,
        "radius": 0.95,
        "height_range": (0.04, 0.08),
        "width_range": (0.040, 0.065),
        "arch_range": (0.02, 0.05),
        "segments": 2,
        "base_rgb": (0.22, 0.40, 0.10),
        "tip_rgb": (0.40, 0.58, 0.24),
        "color_var": 0.03,
        "seed": 151,
    },
    # 4: Sports field — tennis, basketball, baseball turf
    {
        "name": "Grass_Tile_SportsTurf",
        "blade_count": 600,
        "radius": 1.0,
        "height_range": (0.03, 0.07),
        "width_range": (0.038, 0.060),
        "arch_range": (0.01, 0.04),
        "segments": 2,
        "base_rgb": (0.25, 0.45, 0.10),
        "tip_rgb": (0.45, 0.65, 0.28),
        "color_var": 0.02,
        "seed": 197,
    },
    # 5: North Woods understory — sparse but present
    {
        "name": "Grass_Tile_NorthWoods",
        "blade_count": 150,
        "radius": 0.65,
        "height_range": (0.03, 0.10),
        "width_range": (0.035, 0.060),
        "arch_range": (0.02, 0.06),
        "segments": 2,
        "base_rgb": (0.10, 0.25, 0.05),
        "tip_rgb": (0.25, 0.42, 0.15),
        "color_var": 0.05,
        "seed": 233,
    },
    # 6: Ramble / Dene — moderate woodland floor
    {
        "name": "Grass_Tile_Ramble",
        "blade_count": 250,
        "radius": 0.75,
        "height_range": (0.04, 0.12),
        "width_range": (0.038, 0.065),
        "arch_range": (0.02, 0.07),
        "segments": 2,
        "base_rgb": (0.12, 0.28, 0.06),
        "tip_rgb": (0.30, 0.48, 0.18),
        "color_var": 0.05,
        "seed": 277,
    },
    # 7: Waterside — near lakes/ponds, taller moisture-loving, richer green
    {
        "name": "Grass_Tile_Waterside",
        "blade_count": 350,
        "radius": 0.90,
        "height_range": (0.08, 0.18),
        "width_range": (0.045, 0.075),
        "arch_range": (0.04, 0.12),
        "segments": 2,
        "base_rgb": (0.14, 0.34, 0.06),
        "tip_rgb": (0.35, 0.55, 0.20),
        "color_var": 0.05,
        "seed": 313,
    },
    # 8: Wild meadow — nature reserve, tall unmowed, golden tips (BotW-style)
    {
        "name": "Grass_Tile_WildMeadow",
        "blade_count": 280,
        "radius": 0.90,
        "height_range": (0.20, 0.40),
        "width_range": (0.040, 0.065),
        "arch_range": (0.06, 0.20),
        "segments": 3,
        "base_rgb": (0.14, 0.32, 0.05),
        "tip_rgb": (0.45, 0.48, 0.20),
        "color_var": 0.06,
        "seed": 359,
    },
    # 9: Open lawn — default maintained grass for unzoned areas
    {
        "name": "Grass_Tile_OpenLawn",
        "blade_count": 480,
        "radius": 1.0,
        "height_range": (0.06, 0.12),
        "width_range": (0.042, 0.070),
        "arch_range": (0.03, 0.09),
        "segments": 2,
        "base_rgb": (0.20, 0.40, 0.07),
        "tip_rgb": (0.44, 0.62, 0.26),
        "color_var": 0.05,
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
    print(f"  {name}: {vc} verts, {fc} faces")
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
print("Building 10 grass tile models (area-specific, distributed)")
print("=" * 60)

mat = make_grass_material("GrassBlade")

for i, cfg in enumerate(GRASS_TYPES):
    name = cfg["name"]
    seed = cfg["seed"]
    blades = cfg["blade_count"]
    print(f"\n[{i+1}/{len(GRASS_TYPES)}] {name} ({blades} blades, r={cfg['radius']}m)...")

    bm = build_grass_tile(cfg, seed)
    export_tile(bm, name, mat)

print(f"\nDone. {len(GRASS_TYPES)} grass tile models exported.")
