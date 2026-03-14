"""Generate 7th Regiment Memorial for Central Park Walk.

West Drive at 67th St — 7th Regiment Memorial (1874, John Quincy Adams Ward).
Single standing soldier (infantryman) atop a tall granite column.
Total height ~15m (9m column + 3m figure).
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


# ── Base (stepped granite) ──
box("base_3", 0, 0, 0, 1.50, 0.25, 1.50, granite)
box("base_2", 0, 0.25, 0, 1.30, 0.25, 1.30, granite)
box("base_1", 0, 0.50, 0, 1.10, 0.30, 1.10, granite)

# ── Pedestal (decorated shaft) ──
box("ped_lower", 0, 0.80, 0, 0.90, 0.40, 0.90, granite)
box("ped_shaft", 0, 1.20, 0, 0.75, 6.50, 0.75, granite)
box("ped_capital", 0, 7.70, 0, 0.85, 0.30, 0.85, granite)

# ── Top platform ──
box("platform", 0, 8.00, 0, 0.80, 0.15, 0.80, granite)

# ── Bronze soldier figure ──
FIG_BASE = 8.15
# Legs
cylinder("legs", 0, FIG_BASE, 0, 0.12, 0.80, 10, bronze)
# Coat
cylinder("coat", 0, FIG_BASE + 0.80, 0, 0.16, 0.70, 10, bronze)
# Torso
cylinder("torso", 0, FIG_BASE + 1.40, 0, 0.14, 0.45, 10, bronze)
# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.11, segments=10, ring_count=8,
    location=(0, FIG_BASE + 2.02, 0))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# Kepi cap
cylinder("kepi", 0, FIG_BASE + 2.10, 0, 0.10, 0.05, 8, bronze)

# Right arm (holding musket)
cylinder("right_arm", 0.14, FIG_BASE + 1.50, 0.05, 0.04, 0.45, 6, bronze)
bpy.context.active_object.rotation_euler = (-0.2, 0, -0.1)
bpy.ops.object.transform_apply(rotation=True)

# Musket
cylinder("musket", 0.16, FIG_BASE + 0.60, 0.08, 0.015, 1.40, 6, bronze)
bpy.context.active_object.rotation_euler = (-0.1, 0, 0.05)
bpy.ops.object.transform_apply(rotation=True)

# Left arm
cylinder("left_arm", -0.14, FIG_BASE + 1.50, 0, 0.04, 0.42, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Regiment7th"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_7th_regiment.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
