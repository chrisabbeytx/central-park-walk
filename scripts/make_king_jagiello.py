"""Generate King Jagiello Monument for Central Park Walk.

Turtle Pond, near Belvedere Castle — King Jagiello (1939, Stanisław Kazimierz Ostrowski).
Standing armored figure holding two crossed swords aloft (victory at Grunwald 1410).
Total height ~5.5m on granite pedestal.
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
bsdf.inputs["Roughness"].default_value = 0.75

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.18, 0.22, 0.14, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.40
bsdf2.inputs["Metallic"].default_value = 0.88


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
box("base_step", 0, 0, 0, 0.90, 0.20, 0.90, granite)
box("base_2", 0, 0.20, 0, 0.80, 0.15, 0.80, granite)
box("ped_shaft", 0, 0.35, 0, 0.65, 2.20, 0.65, granite)
box("ped_cap", 0, 2.55, 0, 0.72, 0.12, 0.72, granite)
box("ped_top", 0, 2.67, 0, 0.68, 0.08, 0.68, granite)

# ── Standing figure ──
FIG = 2.75
# Legs
cylinder("legs", 0, FIG, 0, 0.10, 0.70, 10, bronze)
# Armored skirt
cylinder("skirt", 0, FIG + 0.60, 0, 0.14, 0.25, 10, bronze)
# Torso (armored)
cylinder("torso", 0, FIG + 0.80, 0, 0.13, 0.50, 10, bronze)
# Shoulders (wider)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.16, segments=10, ring_count=6,
    location=(0, FIG + 1.25, 0))
o = bpy.context.active_object
o.name = "shoulders"
o.scale = (1.3, 0.6, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Neck
cylinder("neck", 0, FIG + 1.30, 0, 0.05, 0.08, 8, bronze)

# Head (helmeted)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.09, segments=8, ring_count=6,
    location=(0, FIG + 1.48, 0))
o = bpy.context.active_object
o.name = "head"
o.data.materials.append(bronze)

# Crown/helmet
cylinder("helmet", 0, FIG + 1.54, 0, 0.10, 0.06, 8, bronze)

# ── Two crossed swords (held aloft in X shape) ──
# Right sword
cylinder("sword_r", 0.12, FIG + 1.50, 0, 0.012, 0.90, 4, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.35)
bpy.ops.object.transform_apply(rotation=True)

# Left sword
cylinder("sword_l", -0.12, FIG + 1.50, 0, 0.012, 0.90, 4, bronze)
bpy.context.active_object.rotation_euler = (0, 0, -0.35)
bpy.ops.object.transform_apply(rotation=True)

# Sword crossguards
for side in [0.12, -0.12]:
    box(f"guard_{side}", side, FIG + 1.45, 0, 0.04, 0.015, 0.015, bronze)

# Arms (raised, holding swords)
cylinder("right_arm", 0.14, FIG + 1.20, 0.05, 0.03, 0.35, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.3)
bpy.ops.object.transform_apply(rotation=True)

cylinder("left_arm", -0.14, FIG + 1.20, 0.05, 0.03, 0.35, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, -0.3)
bpy.ops.object.transform_apply(rotation=True)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "KingJagiello"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_king_jagiello.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
