"""Generate Indian Hunter statue for Central Park Walk.

Literary Walk / Mall — The Indian Hunter (1869, John Quincy Adams Ward).
Crouching Native American figure with dog, on a low naturalistic rock base.
~2.0m figure on ~0.6m base. One of Central Park's most famous sculptures.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.45, 0.42, 0.38, 1.0)
bsdf.inputs["Roughness"].default_value = 0.80

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.15, 0.20, 0.12, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.40
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


# ── Naturalistic rock base ──
# Irregular rocky mound (use icosphere for organic shape)
bpy.ops.mesh.primitive_ico_sphere_add(
    radius=0.55, subdivisions=2,
    location=(0, 0.25, 0))
base = bpy.context.active_object
base.name = "rock_base"
base.scale = (1.2, 0.45, 1.0)
bpy.ops.object.transform_apply(scale=True)
base.data.materials.append(stone)

FIGURE_BASE = 0.50

# ── Figure — crouching hunter in forward lean ──
# Lower body (crouching)
cylinder("lower_body", 0, FIGURE_BASE, 0.05, 0.16, 0.60, 10, bronze)
bpy.context.active_object.rotation_euler = (0.3, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

# Torso (leaning forward)
cylinder("torso", 0, FIGURE_BASE + 0.55, -0.08, 0.15, 0.50, 10, bronze)
bpy.context.active_object.rotation_euler = (-0.3, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.12, segments=12, ring_count=8,
    location=(0, FIGURE_BASE + 1.15, -0.15))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# Right arm (extended forward with bow)
cylinder("right_arm", 0.14, FIGURE_BASE + 0.85, -0.18, 0.05, 0.45, 6, bronze)
bpy.context.active_object.rotation_euler = (-0.6, 0, -0.3)
bpy.ops.object.transform_apply(rotation=True)

# Left arm (pulling bowstring back)
cylinder("left_arm", -0.12, FIGURE_BASE + 0.85, -0.05, 0.05, 0.40, 6, bronze)
bpy.context.active_object.rotation_euler = (-0.2, 0, 0.4)
bpy.ops.object.transform_apply(rotation=True)

# ── Dog (small companion figure at side) ──
DOG_BASE = 0.42
# Dog body
cylinder("dog_body", 0.30, DOG_BASE, 0.15, 0.08, 0.35, 8, bronze)
bpy.context.active_object.rotation_euler = (1.2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

# Dog head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.06, segments=8, ring_count=6,
    location=(0.30, DOG_BASE + 0.20, -0.05))
dog_head = bpy.context.active_object
dog_head.name = "dog_head"
dog_head.data.materials.append(bronze)

# Dog legs (4 small cylinders)
for dx, dz in [(0.24, 0.22), (0.36, 0.22), (0.24, 0.05), (0.36, 0.05)]:
    cylinder(f"dog_leg_{dx}_{dz}", dx, DOG_BASE - 0.10, dz, 0.025, 0.20, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "IndianHunter"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_indian_hunter.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
