"""Generate Daniel Webster statue for Central Park Walk.

West Drive near 72nd St — Daniel Webster (1876, Thomas Ball).
Standing bronze figure of the statesman in formal coat, holding scroll,
on granite pedestal. Total ~5.5m.
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
box("ped_shaft", 0, 0.33, 0, 0.55, 2.60, 0.55, granite)
box("ped_cornice", 0, 2.93, 0, 0.62, 0.10, 0.62, granite)
box("ped_top", 0, 3.03, 0, 0.58, 0.08, 0.58, granite)

# ── Standing figure ──
FIG = 3.11
# Legs
cylinder("right_leg", 0.05, FIG, 0.03, 0.04, 0.65, 8, bronze)
cylinder("left_leg", -0.05, FIG, -0.03, 0.04, 0.60, 8, bronze)

# Long coat (flared)
bpy.ops.mesh.primitive_cone_add(
    radius1=0.18, radius2=0.12,
    depth=0.50, vertices=10,
    location=(0, FIG + 0.60, 0))
o = bpy.context.active_object
o.name = "coat_skirt"
o.data.materials.append(bronze)

# Torso
cylinder("torso", 0, FIG + 0.80, 0, 0.11, 0.40, 8, bronze)

# Shoulders
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.14, segments=8, ring_count=6,
    location=(0, FIG + 1.18, 0))
o = bpy.context.active_object
o.name = "shoulders"
o.scale = (1.2, 0.5, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Neck
cylinder("neck", 0, FIG + 1.20, 0, 0.04, 0.08, 6, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.08, segments=8, ring_count=6,
    location=(0, FIG + 1.36, 0))
o = bpy.context.active_object
o.name = "head"
o.data.materials.append(bronze)

# Right arm (at side)
cylinder("right_arm", 0.14, FIG + 0.90, 0, 0.03, 0.35, 6, bronze)

# Left arm (holding scroll)
cylinder("left_arm", -0.14, FIG + 0.95, 0.05, 0.03, 0.30, 6, bronze)
bpy.context.active_object.rotation_euler = (0.3, 0, 0.3)
bpy.ops.object.transform_apply(rotation=True)

# Scroll in left hand
cylinder("scroll", -0.18, FIG + 0.80, 0.08, 0.015, 0.18, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "DanielWebster"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_daniel_webster.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
