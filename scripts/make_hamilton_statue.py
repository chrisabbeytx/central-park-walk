"""Generate Alexander Hamilton statue for Central Park Walk.

East side near the Met — Alexander Hamilton (1880, Carl Conrads).
Standing figure in Revolutionary War-era coat, on tall granite pedestal.
~2.8m figure on ~3m pedestal.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.58, 0.55, 0.50, 1.0)
bsdf.inputs["Roughness"].default_value = 0.72

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.22, 0.25, 0.18, 1.0)
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
box("plinth_base", 0, 0, 0, 0.60, 0.20, 0.60, stone)
box("pedestal_shaft", 0, 0.20, 0, 0.45, 2.30, 0.45, stone)
box("pedestal_cornice", 0, 2.50, 0, 0.52, 0.12, 0.52, stone)
box("pedestal_top", 0, 2.62, 0, 0.48, 0.08, 0.48, stone)

FIGURE_BASE = 2.70

# ── Figure — Hamilton standing upright, statesmanlike pose ──
# Legs (in knee breeches)
cylinder("right_leg", 0.08, FIGURE_BASE, 0, 0.08, 0.85, 8, bronze)
cylinder("left_leg", -0.08, FIGURE_BASE, 0, 0.08, 0.85, 8, bronze)

# Long coat (wider cylinder)
cylinder("coat", 0, FIGURE_BASE + 0.40, 0, 0.22, 0.80, 12, bronze)

# Torso
cylinder("torso", 0, FIGURE_BASE + 1.05, 0, 0.18, 0.55, 10, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.13, segments=12, ring_count=8,
    location=(0, FIGURE_BASE + 1.78, 0))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# Right arm (at side)
cylinder("right_arm", 0.17, FIGURE_BASE + 1.22, 0, 0.055, 0.50, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, -0.12)
bpy.ops.object.transform_apply(rotation=True)

# Left arm (holding document or hat)
cylinder("left_arm", -0.17, FIGURE_BASE + 1.22, 0.04, 0.055, 0.48, 6, bronze)
bpy.context.active_object.rotation_euler = (0.15, 0, 0.15)
bpy.ops.object.transform_apply(rotation=True)

# Tricorn hat brim (flat disc on head)
cylinder("hat", 0, FIGURE_BASE + 1.90, 0, 0.14, 0.04, 12, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Hamilton"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_hamilton.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
