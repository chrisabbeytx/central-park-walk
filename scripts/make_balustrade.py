"""Generate balustrade section for Central Park Walk.

Bethesda Terrace and other formal staircases have ornamental stone
balustrades — turned stone balusters between top and bottom rails.
Section is 2m wide with 5 balusters.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.62, 0.60, 0.56, 1.0)
bsdf.inputs["Roughness"].default_value = 0.65

SECTION_W = 2.0   # section width
RAIL_H = 0.85     # total height
BOT_RAIL_H = 0.08 # bottom rail height
TOP_RAIL_H = 0.10 # top rail height
BAL_R = 0.04      # baluster radius
N_BAL = 5         # balusters per section


def box(name, x, y, z, sx, sy, sz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y + sy, z))
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx * 2, sy * 2, sz * 2)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    return o


# ── Bottom rail ──
box("bottom_rail", 0, 0, 0, SECTION_W / 2, BOT_RAIL_H / 2, 0.06, stone)

# ── Top rail (coping, wider) ──
box("top_rail", 0, RAIL_H - TOP_RAIL_H, 0,
    SECTION_W / 2 + 0.02, TOP_RAIL_H / 2, 0.08, stone)

# ── Balusters (turned columns) ──
bal_h = RAIL_H - BOT_RAIL_H - TOP_RAIL_H
bal_spacing = SECTION_W / (N_BAL + 1)

for i in range(N_BAL):
    bx = -SECTION_W / 2 + bal_spacing * (i + 1)
    by = BOT_RAIL_H

    # Turned profile: base → belly → neck → capital
    # Base (slightly wider)
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BAL_R * 1.3, depth=bal_h * 0.15, vertices=8,
        location=(bx, by + bal_h * 0.075, 0))
    o = bpy.context.active_object
    o.name = f"bal_base_{i}"
    o.data.materials.append(stone)

    # Belly (widest part)
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=BAL_R * 1.6, segments=8, ring_count=6,
        location=(bx, by + bal_h * 0.40, 0))
    o = bpy.context.active_object
    o.name = f"bal_belly_{i}"
    o.scale = (1.0, 1.4, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(stone)

    # Shaft
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BAL_R, depth=bal_h * 0.45, vertices=8,
        location=(bx, by + bal_h * 0.65, 0))
    o = bpy.context.active_object
    o.name = f"bal_shaft_{i}"
    o.data.materials.append(stone)

    # Neck (narrower)
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BAL_R * 0.8, depth=bal_h * 0.10, vertices=8,
        location=(bx, by + bal_h * 0.90, 0))
    o = bpy.context.active_object
    o.name = f"bal_neck_{i}"
    o.data.materials.append(stone)

# ── End posts (wider square pillars) ──
POST_W = 0.10
for side in [-1, 1]:
    px = side * SECTION_W / 2
    box(f"post_{side}", px, 0, 0, POST_W / 2, RAIL_H / 2, POST_W / 2, stone)
    # Post cap
    box(f"post_cap_{side}", px, RAIL_H, 0,
        POST_W / 2 + 0.015, 0.025, POST_W / 2 + 0.015, stone)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Balustrade"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_balustrade.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
