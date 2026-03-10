"""Build grass clump models for Central Park Walk.

Reference: grassexample.png — bushy 3D grass clumps with wide arching blades
radiating outward from center. When tiled densely, fully carpets the ground.

Two clump types:
  1. Mowed lawn (Sheep Meadow, Great Lawn) — shorter, tighter clumps
  2. Wild meadow (North Woods, Ramble) — taller, wider, more dramatic arch

Each blade is a wide curved mesh strip (1.5-2.5cm wide, 3 segments).
Blades radiate outward from the clump center like a fountain.
Vertex colors encode green variation for the wind shader.

Exports to models/vegetation/Grass_Patch_Mowed.glb
                              Grass_Patch_Meadow.glb
"""

import bpy
import bmesh
import math
import random
import os

# ---------------------------------------------------------------------------
# Clear scene
# ---------------------------------------------------------------------------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# ---------------------------------------------------------------------------
# Output directory
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "models", "vegetation")
os.makedirs(OUT_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Grass blade builder — wide arching blade
# ---------------------------------------------------------------------------
def make_blade(bm, color_layer, uv_layer,
               bx, bz, height, width, rot, arch_strength,
               segments, base_rgb, tip_rgb):
    """Create one wide arching grass blade as a curved mesh strip.

    Blades arch outward from center — the arch_strength controls how far
    the tip extends horizontally from the base.
    """
    # Blade faces outward from clump center
    out_dx = math.cos(rot)
    out_dz = math.sin(rot)
    # Perpendicular direction for blade width
    perp_dx = -math.sin(rot)
    perp_dz = math.cos(rot)

    vert_pairs = []
    for si in range(segments + 1):
        t = si / segments
        # Height follows a parabolic arc (rises then curves over)
        seg_h = height * (t - 0.3 * t * t)
        # Horizontal extension: blade arches outward
        extend = arch_strength * t * t
        # Width tapers from base to tip
        seg_w = width * (1.0 - t * 0.75)
        hw = seg_w * 0.5

        # Center of blade at this segment
        cx = bx + out_dx * extend
        cz = bz + out_dz * extend

        # Left and right vertices (perpendicular to outward direction)
        lx = cx + perp_dx * hw
        lz = cz + perp_dz * hw
        rx = cx - perp_dx * hw
        rz = cz - perp_dz * hw

        # Colour interpolation
        r = base_rgb[0] + (tip_rgb[0] - base_rgb[0]) * t
        g = base_rgb[1] + (tip_rgb[1] - base_rgb[1]) * t
        b = base_rgb[2] + (tip_rgb[2] - base_rgb[2]) * t

        vl = bm.verts.new((lx, seg_h, lz))
        vr = bm.verts.new((rx, seg_h, rz))
        vert_pairs.append((vl, vr, (r, g, b, 1.0), t))

    # Create quad faces between segment pairs
    for si in range(segments):
        vl0, vr0, col0, t0 = vert_pairs[si]
        vl1, vr1, col1, t1 = vert_pairs[si + 1]

        try:
            face = bm.faces.new([vl0, vr0, vr1, vl1])
        except ValueError:
            continue

        for loop in face.loops:
            if loop.vert == vl0:
                loop[color_layer] = col0
                loop[uv_layer].uv = (0.0, t0)
            elif loop.vert == vr0:
                loop[color_layer] = col0
                loop[uv_layer].uv = (1.0, t0)
            elif loop.vert == vr1:
                loop[color_layer] = col1
                loop[uv_layer].uv = (1.0, t1)
            elif loop.vert == vl1:
                loop[color_layer] = col1
                loop[uv_layer].uv = (0.0, t1)


# ---------------------------------------------------------------------------
# Clump builders
# ---------------------------------------------------------------------------
def build_mowed_clump(seed=42):
    """Mowed lawn clump — shorter, tighter, bushy.

    ~18 wide blades radiating outward, 8-15cm tall, 1.5-2cm wide.
    Moderate arch. Dense coverage when tiled.
    """
    rng = random.Random(seed)

    bm = bmesh.new()
    color_layer = bm.loops.layers.color.new("Color")
    uv_layer = bm.loops.layers.uv.new("UV")

    BLADE_COUNT = 18

    for i in range(BLADE_COUNT):
        # Evenly spaced around center with jitter
        base_angle = (i / BLADE_COUNT) * 2 * math.pi
        rot = base_angle + rng.uniform(-0.3, 0.3)

        # Small offset from center for natural look
        offset_r = rng.uniform(0.0, 0.03)
        bx = math.cos(rot) * offset_r
        bz = math.sin(rot) * offset_r

        h = rng.uniform(0.08, 0.15)
        w = rng.uniform(0.015, 0.022)    # 1.5-2.2cm wide
        arch = rng.uniform(0.06, 0.12)   # moderate outward arch

        # Colors from Sheep Meadow + grass/clover reference photos
        cv = rng.uniform(-0.03, 0.03)
        base_rgb = (
            max(0.08, 0.18 + cv),
            max(0.15, 0.32 + cv * 0.7),
            max(0.02, 0.05 + cv * 0.4),
        )
        tip_rgb = (
            min(0.60, 0.45 + cv),
            min(0.70, 0.58 + cv * 0.6),
            min(0.40, 0.28 + cv * 0.3),
        )

        make_blade(bm, color_layer, uv_layer,
                   bx, bz, h, w, rot, arch,
                   segments=3, base_rgb=base_rgb, tip_rgb=tip_rgb)

    return bm


def build_meadow_clump(seed=137):
    """Wild meadow clump — taller, wider, dramatic arch.

    ~15 wide blades, 18-38cm tall, 1.8-2.8cm wide.
    Strong outward arch like ornamental grass.
    """
    rng = random.Random(seed)

    bm = bmesh.new()
    color_layer = bm.loops.layers.color.new("Color")
    uv_layer = bm.loops.layers.uv.new("UV")

    BLADE_COUNT = 15

    for i in range(BLADE_COUNT):
        base_angle = (i / BLADE_COUNT) * 2 * math.pi
        rot = base_angle + rng.uniform(-0.35, 0.35)

        offset_r = rng.uniform(0.0, 0.04)
        bx = math.cos(rot) * offset_r
        bz = math.sin(rot) * offset_r

        h = rng.uniform(0.18, 0.38)
        w = rng.uniform(0.018, 0.028)    # 1.8-2.8cm wide
        arch = rng.uniform(0.12, 0.25)   # strong outward arch

        # Colors from grass texture close-up reference photo (darker, richer)
        cv = rng.uniform(-0.05, 0.05)
        base_rgb = (
            max(0.06, 0.12 + cv),
            max(0.14, 0.26 + cv * 0.6),
            max(0.01, 0.02 + cv * 0.3),
        )
        tip_rgb = (
            min(0.50, 0.35 + cv),
            min(0.62, 0.50 + cv * 0.5),
            min(0.30, 0.18 + cv * 0.3),
        )

        make_blade(bm, color_layer, uv_layer,
                   bx, bz, h, w, rot, arch,
                   segments=4, base_rgb=base_rgb, tip_rgb=tip_rgb)

    return bm


# ---------------------------------------------------------------------------
# Material (vertex-color based for GLTF export)
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
    bsdf.inputs['Metallic'].default_value = 0.0
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])

    vcol = nodes.new('ShaderNodeVertexColor')
    vcol.location = (-200, 0)
    vcol.layer_name = "Color"
    links.new(vcol.outputs['Color'], bsdf.inputs['Base Color'])

    return mat


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------
def export_patch(bm, name, material):
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
    print(f"  Exported {name}: {vc} verts, {fc} faces -> {filepath}")

    bpy.ops.object.delete(use_global=False)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
print("=" * 60)
print("Building grass clump models (wide arching blades)")
print("=" * 60)

mat = make_grass_material("GrassBlade")

print("\n[1/2] Mowed lawn clump (18 blades, 8-15cm, 1.5-2.2cm wide)...")
bm_mowed = build_mowed_clump(seed=42)
export_patch(bm_mowed, "Grass_Patch_Mowed", mat)

print("\n[2/2] Wild meadow clump (15 blades, 18-38cm, 1.8-2.8cm wide)...")
bm_meadow = build_meadow_clump(seed=137)
export_patch(bm_meadow, "Grass_Patch_Meadow", mat)

print("\nDone.")
