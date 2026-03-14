"""Generate Christopher Columbus statue for Central Park (Columbus Circle).

Columbus Circle — Christopher Columbus (1892, Gaetano Russo).
Standing figure atop a tall Corinthian column, ~23m total height.
The column has a ship's prow relief at the base.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

marble = bpy.data.materials.new("Marble")
marble.use_nodes = True
bsdf = marble.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.78, 0.76, 0.72, 1.0)
bsdf.inputs["Roughness"].default_value = 0.55

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.20, 0.24, 0.16, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.42
bsdf2.inputs["Metallic"].default_value = 0.85

granite = bpy.data.materials.new("Granite")
granite.use_nodes = True
bsdf3 = granite.node_tree.nodes["Principled BSDF"]
bsdf3.inputs["Base Color"].default_value = (0.48, 0.45, 0.42, 1.0)
bsdf3.inputs["Roughness"].default_value = 0.70


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


# ── Base platform (stepped granite) ──
box("base_3", 0, 0, 0, 2.0, 0.30, 2.0, granite)
box("base_2", 0, 0.30, 0, 1.7, 0.30, 1.7, granite)
box("base_1", 0, 0.60, 0, 1.4, 0.30, 1.4, granite)

# ── Pedestal (marble, with prow relief) ──
box("ped_base", 0, 0.90, 0, 1.10, 0.50, 1.10, marble)
# Ship's prow projecting from front
box("prow", 0, 0.90, 1.20, 0.15, 0.60, 0.40, marble)

# ── Column (Corinthian style — simplified) ──
COL_BASE = 1.40
# Column base molding
cylinder("col_base", 0, COL_BASE, 0, 0.65, 0.40, 16, marble)
# Column shaft (tapers slightly)
cylinder("col_shaft", 0, COL_BASE + 0.40, 0, 0.55, 14.0, 20, marble)
# Column capital (wider)
cylinder("col_capital", 0, COL_BASE + 14.40, 0, 0.70, 0.50, 16, marble)

# ── Top platform ──
PLAT_Y = COL_BASE + 14.90
box("top_plat", 0, PLAT_Y, 0, 0.75, 0.15, 0.75, marble)

# ── Figure (standing Columbus at top) ──
FIG_BASE = PLAT_Y + 0.15
# Legs
cylinder("legs", 0, FIG_BASE, 0, 0.15, 0.90, 10, bronze)
# Coat/torso
cylinder("torso", 0, FIG_BASE + 0.90, 0, 0.18, 0.70, 10, bronze)
# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.12, segments=12, ring_count=8,
    location=(0, FIG_BASE + 1.78, 0))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)
# Arms
cylinder("right_arm", 0.15, FIG_BASE + 1.20, 0, 0.05, 0.45, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, -0.15)
bpy.ops.object.transform_apply(rotation=True)
cylinder("left_arm", -0.15, FIG_BASE + 1.20, 0.05, 0.05, 0.45, 6, bronze)

# ── Globe in left hand ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.10, segments=10, ring_count=8,
    location=(-0.15, FIG_BASE + 0.95, 0.05))
globe = bpy.context.active_object
globe.name = "globe"
globe.data.materials.append(bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Columbus"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_columbus.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
