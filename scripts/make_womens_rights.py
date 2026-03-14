"""Generate Women's Rights Pioneers Monument for Central Park Walk.

The Mall at 71st St — Women's Rights Pioneers Monument (2020, Meredith Bergmann).
Three seated/standing bronze figures: Sojourner Truth, Susan B. Anthony,
Elizabeth Cady Stanton around a table/writing desk. Low pedestal. ~2m total.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.58, 0.56, 0.52, 1.0)
bsdf.inputs["Roughness"].default_value = 0.68

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.20, 0.24, 0.16, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.42
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


# ── Low stone base ──
cylinder("base", 0, 0, 0, 1.00, 0.12, 16, stone)

PLAT = 0.12

# ── Central table/desk ──
box("table_top", 0, PLAT + 0.40, 0, 0.25, 0.03, 0.20, bronze)
# Table legs
for tx, tz in [(0.20, 0.15), (0.20, -0.15), (-0.20, 0.15), (-0.20, -0.15)]:
    cylinder(f"table_leg_{tx}_{tz}", tx, PLAT, tz, 0.015, 0.40, 4, bronze)

# Papers on table
box("papers", 0, PLAT + 0.43, 0, 0.12, 0.01, 0.10, bronze)

# ── Figure 1: Sojourner Truth (standing, to the left) ──
F1X, F1Z = -0.45, 0
cylinder("truth_legs", F1X, PLAT, F1Z, 0.06, 0.55, 8, bronze)
# Long dress
bpy.ops.mesh.primitive_cone_add(
    radius1=0.14, radius2=0.08,
    depth=0.40, vertices=8,
    location=(F1X, PLAT + 0.45, F1Z))
o = bpy.context.active_object
o.name = "truth_dress"
o.data.materials.append(bronze)
cylinder("truth_torso", F1X, PLAT + 0.60, F1Z, 0.07, 0.30, 8, bronze)
# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.055, segments=8, ring_count=6,
    location=(F1X, PLAT + 0.98, F1Z))
o = bpy.context.active_object
o.name = "truth_head"
o.data.materials.append(bronze)
# Headwrap
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.05, segments=6, ring_count=4,
    location=(F1X, PLAT + 1.02, F1Z - 0.01))
o = bpy.context.active_object
o.name = "truth_headwrap"
o.data.materials.append(bronze)
# Arms
cylinder("truth_right_arm", F1X + 0.08, PLAT + 0.72, F1Z, 0.02, 0.22, 6, bronze)
cylinder("truth_left_arm", F1X - 0.08, PLAT + 0.72, F1Z, 0.02, 0.22, 6, bronze)

# ── Figure 2: Susan B. Anthony (seated, center-right) ──
F2X, F2Z = 0.20, 0.30
# Chair
box("anthony_chair", F2X, PLAT, F2Z, 0.15, 0.25, 0.15, bronze)
# Seated body
cylinder("anthony_torso", F2X, PLAT + 0.30, F2Z, 0.06, 0.28, 8, bronze)
# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.05, segments=8, ring_count=6,
    location=(F2X, PLAT + 0.65, F2Z))
o = bpy.context.active_object
o.name = "anthony_head"
o.data.materials.append(bronze)
# Hair bun
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.035, segments=6, ring_count=4,
    location=(F2X, PLAT + 0.69, F2Z - 0.03))
o = bpy.context.active_object
o.name = "anthony_bun"
o.data.materials.append(bronze)
# Arms (writing)
cylinder("anthony_right_arm", F2X + 0.06, PLAT + 0.45, F2Z - 0.06, 0.018, 0.18, 6, bronze)
bpy.context.active_object.rotation_euler = (0.4, 0, 0.3)
bpy.ops.object.transform_apply(rotation=True)

# ── Figure 3: Elizabeth Cady Stanton (seated, center-left) ──
F3X, F3Z = 0.20, -0.30
# Chair
box("stanton_chair", F3X, PLAT, F3Z, 0.15, 0.25, 0.15, bronze)
# Seated body
cylinder("stanton_torso", F3X, PLAT + 0.30, F3Z, 0.06, 0.28, 8, bronze)
# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.05, segments=8, ring_count=6,
    location=(F3X, PLAT + 0.65, F3Z))
o = bpy.context.active_object
o.name = "stanton_head"
o.data.materials.append(bronze)
# Hair
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.04, segments=6, ring_count=4,
    location=(F3X, PLAT + 0.69, F3Z - 0.02))
o = bpy.context.active_object
o.name = "stanton_hair"
o.data.materials.append(bronze)
# Arms
cylinder("stanton_right_arm", F3X + 0.06, PLAT + 0.45, F3Z + 0.04, 0.018, 0.18, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "WomensRightsPioneers"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_womens_rights.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
