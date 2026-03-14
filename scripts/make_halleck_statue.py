"""Generate Fitz-Greene Halleck statue for Central Park Walk.

Literary Walk — Fitz-Greene Halleck (1877, James Wilson Alexander MacDonald).
Seated figure in chair on stone pedestal. One of the earliest statues in the park.
~2.2m figure (seated) on ~2m pedestal.
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
bsdf2.inputs["Base Color"].default_value = (0.18, 0.22, 0.14, 1.0)
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
box("plinth_base", 0, 0, 0, 0.55, 0.15, 0.55, stone)
box("pedestal_shaft", 0, 0.15, 0, 0.42, 1.50, 0.42, stone)
box("pedestal_cornice", 0, 1.65, 0, 0.48, 0.10, 0.48, stone)
box("pedestal_top", 0, 1.75, 0, 0.44, 0.08, 0.44, stone)

FIGURE_BASE = 1.83

# ── Chair (integrated with figure) ──
# Chair seat
box("chair_seat", 0, FIGURE_BASE, -0.05, 0.28, 0.05, 0.25, bronze)
# Chair back
box("chair_back", 0, FIGURE_BASE + 0.05, -0.27, 0.26, 0.60, 0.04, bronze)
# Chair legs (front)
cylinder("chair_leg_fl", 0.22, FIGURE_BASE - 0.25, 0.15, 0.03, 0.30, 6, bronze)
cylinder("chair_leg_fr", -0.22, FIGURE_BASE - 0.25, 0.15, 0.03, 0.30, 6, bronze)

# ── Seated figure ──
# Upper legs (horizontal)
cylinder("right_thigh", 0.10, FIGURE_BASE + 0.08, 0.10, 0.09, 0.35, 8, bronze)
bpy.context.active_object.rotation_euler = (1.45, 0, 0)
bpy.ops.object.transform_apply(rotation=True)
cylinder("left_thigh", -0.10, FIGURE_BASE + 0.08, 0.10, 0.09, 0.35, 8, bronze)
bpy.context.active_object.rotation_euler = (1.45, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

# Torso (upright)
cylinder("torso", 0, FIGURE_BASE + 0.10, -0.05, 0.18, 0.60, 10, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.12, segments=12, ring_count=8,
    location=(0, FIGURE_BASE + 0.85, -0.05))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# Right arm (resting on knee)
cylinder("right_arm", 0.16, FIGURE_BASE + 0.42, 0.10, 0.05, 0.40, 6, bronze)
bpy.context.active_object.rotation_euler = (0.4, 0, -0.2)
bpy.ops.object.transform_apply(rotation=True)

# Left arm (resting on armrest)
cylinder("left_arm", -0.16, FIGURE_BASE + 0.42, 0.0, 0.05, 0.38, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.3)
bpy.ops.object.transform_apply(rotation=True)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Halleck"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_halleck.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
