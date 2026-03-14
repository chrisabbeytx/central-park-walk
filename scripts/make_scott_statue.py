"""Generate Sir Walter Scott statue for Central Park Walk.

Literary Walk — Sir Walter Scott (1872, Sir John Steell).
Seated figure with dog at feet, on tall stone pedestal.
~2.4m figure on ~2.5m pedestal.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.55, 0.52, 0.46, 1.0)
bsdf.inputs["Roughness"].default_value = 0.75

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.19, 0.23, 0.15, 1.0)
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
box("plinth_base", 0, 0, 0, 0.58, 0.18, 0.58, stone)
box("pedestal_shaft", 0, 0.18, 0, 0.44, 1.90, 0.44, stone)
box("pedestal_cornice", 0, 2.08, 0, 0.50, 0.12, 0.50, stone)
box("pedestal_top", 0, 2.20, 0, 0.46, 0.08, 0.46, stone)

FIGURE_BASE = 2.28

# ── Chair ──
box("chair_seat", 0, FIGURE_BASE, -0.05, 0.30, 0.05, 0.28, bronze)
box("chair_back", 0, FIGURE_BASE + 0.05, -0.30, 0.28, 0.65, 0.04, bronze)

# ── Seated figure ──
# Legs
cylinder("right_thigh", 0.10, FIGURE_BASE + 0.08, 0.12, 0.09, 0.38, 8, bronze)
bpy.context.active_object.rotation_euler = (1.45, 0, 0)
bpy.ops.object.transform_apply(rotation=True)
cylinder("left_thigh", -0.10, FIGURE_BASE + 0.08, 0.12, 0.09, 0.38, 8, bronze)
bpy.context.active_object.rotation_euler = (1.45, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

# Lower legs
cylinder("right_shin", 0.10, FIGURE_BASE - 0.25, 0.25, 0.07, 0.40, 8, bronze)
cylinder("left_shin", -0.10, FIGURE_BASE - 0.25, 0.25, 0.07, 0.40, 8, bronze)

# Torso
cylinder("torso", 0, FIGURE_BASE + 0.10, -0.05, 0.19, 0.60, 10, bronze)

# Head (turned slightly)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.13, segments=12, ring_count=8,
    location=(0.02, FIGURE_BASE + 0.85, -0.05))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# Arms
cylinder("right_arm", 0.17, FIGURE_BASE + 0.45, 0.05, 0.055, 0.42, 6, bronze)
bpy.context.active_object.rotation_euler = (0.3, 0, -0.2)
bpy.ops.object.transform_apply(rotation=True)
cylinder("left_arm", -0.17, FIGURE_BASE + 0.45, 0.0, 0.055, 0.40, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.25)
bpy.ops.object.transform_apply(rotation=True)

# ── Greyhound dog at feet ──
DOG_BASE = FIGURE_BASE - 0.30
cylinder("dog_body", 0.25, DOG_BASE, 0.20, 0.06, 0.30, 8, bronze)
bpy.context.active_object.rotation_euler = (1.3, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.05, segments=8, ring_count=6,
    location=(0.25, DOG_BASE + 0.15, 0.05))
dog_head = bpy.context.active_object
dog_head.name = "dog_head"
dog_head.data.materials.append(bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Scott"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_scott.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
