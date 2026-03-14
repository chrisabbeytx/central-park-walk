"""Generate Romeo and Juliet statue for Central Park Walk.

Delacorte Theater area — Romeo and Juliet (1977, Milton Hebald).
Bronze pair on low circular base. Romeo kneeling/reaching up,
Juliet on balcony ledge looking down. ~2.5m total.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.55, 0.52, 0.48, 1.0)
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


# ── Circular stone base ──
cylinder("base", 0, 0, 0, 0.60, 0.15, 16, stone)

# ── Low pedestal/balcony structure ──
box("balcony_base", 0, 0.15, -0.15, 0.35, 0.80, 0.25, stone)

# ── Romeo (standing/reaching up, in front) ──
ROMEO_X = 0
ROMEO_Z = 0.20
ROMEO_Y = 0.15

# Legs
cylinder("romeo_right_leg", ROMEO_X + 0.04, ROMEO_Y, ROMEO_Z, 0.03, 0.55, 6, bronze)
cylinder("romeo_left_leg", ROMEO_X - 0.04, ROMEO_Y, ROMEO_Z, 0.03, 0.50, 6, bronze)

# Torso
cylinder("romeo_torso", ROMEO_X, ROMEO_Y + 0.50, ROMEO_Z, 0.07, 0.35, 8, bronze)

# Shoulders
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.09, segments=8, ring_count=6,
    location=(ROMEO_X, ROMEO_Y + 0.83, ROMEO_Z))
o = bpy.context.active_object
o.name = "romeo_shoulders"
o.scale = (1.2, 0.5, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Neck
cylinder("romeo_neck", ROMEO_X, ROMEO_Y + 0.85, ROMEO_Z, 0.025, 0.06, 6, bronze)

# Head (looking up)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.055, segments=8, ring_count=6,
    location=(ROMEO_X, ROMEO_Y + 0.96, ROMEO_Z))
o = bpy.context.active_object
o.name = "romeo_head"
o.data.materials.append(bronze)

# Right arm (reaching up toward Juliet)
cylinder("romeo_right_arm", ROMEO_X + 0.08, ROMEO_Y + 0.78, ROMEO_Z - 0.05, 0.02, 0.30, 6, bronze)
bpy.context.active_object.rotation_euler = (0.3, 0, -0.5)
bpy.ops.object.transform_apply(rotation=True)

# Left arm
cylinder("romeo_left_arm", ROMEO_X - 0.08, ROMEO_Y + 0.72, ROMEO_Z, 0.02, 0.25, 6, bronze)

# ── Juliet (on balcony ledge, leaning forward/down) ──
JULIET_X = 0
JULIET_Z = -0.15
JULIET_Y = 0.95

# Legs (behind balcony wall)
cylinder("juliet_right_leg", JULIET_X + 0.03, JULIET_Y, JULIET_Z - 0.05, 0.025, 0.40, 6, bronze)
cylinder("juliet_left_leg", JULIET_X - 0.03, JULIET_Y, JULIET_Z - 0.05, 0.025, 0.38, 6, bronze)

# Torso (leaning forward)
cylinder("juliet_torso", JULIET_X, JULIET_Y + 0.38, JULIET_Z, 0.06, 0.30, 8, bronze)
bpy.context.active_object.rotation_euler = (0.3, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

# Shoulders
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.08, segments=8, ring_count=6,
    location=(JULIET_X, JULIET_Y + 0.68, JULIET_Z + 0.06))
o = bpy.context.active_object
o.name = "juliet_shoulders"
o.scale = (1.1, 0.5, 0.9)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Neck
cylinder("juliet_neck", JULIET_X, JULIET_Y + 0.70, JULIET_Z + 0.06, 0.02, 0.05, 6, bronze)

# Head (looking down)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.05, segments=8, ring_count=6,
    location=(JULIET_X, JULIET_Y + 0.80, JULIET_Z + 0.08))
o = bpy.context.active_object
o.name = "juliet_head"
o.data.materials.append(bronze)

# Hair
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.045, segments=6, ring_count=4,
    location=(JULIET_X, JULIET_Y + 0.83, JULIET_Z + 0.04))
o = bpy.context.active_object
o.name = "juliet_hair"
o.data.materials.append(bronze)

# Arms (reaching down toward Romeo)
cylinder("juliet_right_arm", JULIET_X + 0.06, JULIET_Y + 0.58, JULIET_Z + 0.08, 0.018, 0.22, 6, bronze)
bpy.context.active_object.rotation_euler = (0.4, 0, 0.3)
bpy.ops.object.transform_apply(rotation=True)

cylinder("juliet_left_arm", JULIET_X - 0.06, JULIET_Y + 0.58, JULIET_Z + 0.06, 0.018, 0.20, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "RomeoAndJuliet"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_romeo_juliet.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
