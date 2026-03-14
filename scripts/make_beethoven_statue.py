"""Generate Ludwig van Beethoven statue for Central Park Walk.

The Mall near Concert Ground — Ludwig van Beethoven (1884, Henry Baerer).
Bronze bust of Beethoven on tall granite pedestal.
Total ~4.5m (3m pedestal + 1.5m bust).
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

granite = bpy.data.materials.new("Granite")
granite.use_nodes = True
bsdf = granite.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.50, 0.48, 0.44, 1.0)
bsdf.inputs["Roughness"].default_value = 0.72

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.22, 0.26, 0.18, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.44
bsdf2.inputs["Metallic"].default_value = 0.85


def box(name, x, y, z, sx, sy, sz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y + sy, z))
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx * 2, sy * 2, sz * 2)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    return o


def cylinder(name, x, y, z, r, h, segs, mat):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=r, depth=h, vertices=segs,
        location=(x, y + h / 2, z))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


# ── Pedestal ──
box("base_step", 0, 0, 0, 0.65, 0.18, 0.65, granite)
box("base_2", 0, 0.18, 0, 0.55, 0.12, 0.55, granite)
box("ped_shaft", 0, 0.30, 0, 0.42, 2.20, 0.42, granite)
box("ped_cornice", 0, 2.50, 0, 0.48, 0.10, 0.48, granite)
box("ped_top", 0, 2.60, 0, 0.44, 0.08, 0.44, granite)

# ── Bust ──
BUST_BASE = 2.68
# Chest/shoulders
cylinder("chest", 0, BUST_BASE, 0, 0.20, 0.35, 12, bronze)
bpy.context.active_object.scale = (1.2, 1.0, 0.85)
bpy.ops.object.transform_apply(scale=True)

# Neck
cylinder("neck", 0, BUST_BASE + 0.32, 0, 0.07, 0.10, 8, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.14, segments=12, ring_count=8,
    location=(0, BUST_BASE + 0.55, 0))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# Beethoven's wild hair (larger sphere behind head)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.16, segments=10, ring_count=6,
    location=(0, BUST_BASE + 0.58, -0.02))
o = bpy.context.active_object
o.name = "hair"
o.scale = (1.1, 1.0, 1.1)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Side hair puffs
for side in [-0.12, 0.12]:
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.06, segments=6, ring_count=4,
        location=(side, BUST_BASE + 0.52, -0.02))
    o = bpy.context.active_object
    o.name = f"side_hair_{side}"
    o.data.materials.append(bronze)

# Brow ridge (stern expression)
box("brow", 0, BUST_BASE + 0.52, 0.10, 0.10, 0.02, 0.03, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Beethoven"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_beethoven.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
