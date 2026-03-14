"""Generate Shakespeare statue for Central Park Walk.

Literary Walk — William Shakespeare (1872, John Quincy Adams Ward).
Standing figure in Elizabethan costume on tall stone pedestal.
Height ~3m figure on ~2.5m pedestal = 5.5m total.
"""

import bpy
import math
import os

# ── Cleanup ──
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
bsdf2.inputs["Base Color"].default_value = (0.18, 0.22, 0.15, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.45
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
# Base plinth (wider)
box("plinth_base", 0, 0, 0, 0.55, 0.15, 0.55, stone)
# Main pedestal shaft
box("pedestal_shaft", 0, 0.15, 0, 0.42, 1.80, 0.42, stone)
# Cornice (slightly wider than shaft)
box("pedestal_cornice", 0, 1.95, 0, 0.48, 0.12, 0.48, stone)
# Top platform
box("pedestal_top", 0, 2.07, 0, 0.44, 0.08, 0.44, stone)

# ── Figure — simplified standing pose ──
# Shakespeare stands in Elizabethan dress, left hand on hip, right holding scroll

FIGURE_BASE = 2.15

# Legs/lower body (long coat/doublet)
cylinder("lower_body", 0, FIGURE_BASE, 0, 0.22, 1.10, 12, bronze)

# Torso
cylinder("torso", 0, FIGURE_BASE + 1.10, 0, 0.20, 0.55, 10, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.14, segments=12, ring_count=8,
    location=(0, FIGURE_BASE + 1.85, 0))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# Arms — simplified as cylinders
# Right arm (extended with scroll)
cylinder("right_arm", 0.18, FIGURE_BASE + 1.30, 0.05, 0.06, 0.50, 6, bronze)
bpy.context.active_object.rotation_euler = (0.2, 0, -0.4)
bpy.ops.object.transform_apply(rotation=True)

# Left arm (bent, hand on hip)
cylinder("left_arm", -0.18, FIGURE_BASE + 1.30, 0.0, 0.06, 0.45, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.6)
bpy.ops.object.transform_apply(rotation=True)

# Collar ruff (Elizabethan)
bpy.ops.mesh.primitive_torus_add(
    major_radius=0.16, minor_radius=0.04,
    major_segments=16, minor_segments=6,
    location=(0, FIGURE_BASE + 1.68, 0))
ruff = bpy.context.active_object
ruff.name = "ruff"
ruff.data.materials.append(bronze)

# Cape draping (simplified as a flattened cylinder behind)
cylinder("cape", 0, FIGURE_BASE + 0.80, -0.12, 0.24, 1.20, 8, bronze)
bpy.context.active_object.scale = (1.0, 1.0, 0.3)
bpy.ops.object.transform_apply(scale=True)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Shakespeare"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_shakespeare.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
