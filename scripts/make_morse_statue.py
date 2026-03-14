"""Generate Samuel F. B. Morse statue for Central Park Walk.

The Mall near 72nd St — Samuel F. B. Morse (1871, Byron M. Pickett).
Seated bronze figure of Morse holding telegraph device,
on granite pedestal. Total ~4.5m.
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


# ── Pedestal ──
box("base_step", 0, 0, 0, 0.80, 0.18, 0.80, granite)
box("base_2", 0, 0.18, 0, 0.70, 0.15, 0.70, granite)
box("ped_shaft", 0, 0.33, 0, 0.58, 1.80, 0.58, granite)
box("ped_cornice", 0, 2.13, 0, 0.65, 0.10, 0.65, granite)
box("ped_top", 0, 2.23, 0, 0.60, 0.08, 0.60, granite)

# ── Chair/seat ──
SEAT = 2.31
box("seat", 0, SEAT, 0, 0.30, 0.25, 0.30, bronze)
box("chair_back", -0.10, SEAT + 0.25, 0, 0.05, 0.45, 0.28, bronze)

# ── Seated figure ──
# Thighs (horizontal)
cylinder("thighs", 0.05, SEAT + 0.22, 0, 0.09, 0.28, 8, bronze)
bpy.context.active_object.rotation_euler = (0, 0, math.pi / 2)
bpy.ops.object.transform_apply(rotation=True)

# Lower legs (hanging down from seat)
for side in [-0.07, 0.07]:
    cylinder(f"leg_{side}", 0.15, SEAT - 0.10, side, 0.04, 0.35, 6, bronze)

# Feet
for side in [-0.07, 0.07]:
    box(f"foot_{side}", 0.18, SEAT - 0.10 - 0.35, side, 0.05, 0.03, 0.04, bronze)

# Torso
cylinder("torso", 0, SEAT + 0.40, 0, 0.10, 0.40, 8, bronze)

# Shoulders
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.13, segments=8, ring_count=6,
    location=(0, SEAT + 0.78, 0))
o = bpy.context.active_object
o.name = "shoulders"
o.scale = (1.1, 0.5, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Neck
cylinder("neck", 0, SEAT + 0.80, 0, 0.04, 0.08, 6, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.08, segments=8, ring_count=6,
    location=(0, SEAT + 0.96, 0))
o = bpy.context.active_object
o.name = "head"
o.data.materials.append(bronze)

# Right arm (holding telegraph device on lap)
cylinder("right_arm", 0.12, SEAT + 0.55, -0.05, 0.03, 0.30, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.6)
bpy.ops.object.transform_apply(rotation=True)

# Left arm (resting on armrest)
cylinder("left_arm", -0.12, SEAT + 0.55, 0, 0.03, 0.30, 6, bronze)

# Telegraph device on lap
box("telegraph", 0.12, SEAT + 0.30, 0, 0.06, 0.04, 0.04, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "SamuelMorse"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_morse.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
