"""Generate José de San Martín equestrian statue for Central Park Walk.

Avenue of the Americas at 59th St — José de San Martín (1951, Louis J. Hidalgo).
Bronze equestrian: San Martín in military uniform on walking horse,
atop tall granite pedestal. Total ~7m.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

granite = bpy.data.materials.new("Granite")
granite.use_nodes = True
bsdf = granite.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.52, 0.50, 0.46, 1.0)
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
box("base_step", 0, 0, 0, 1.20, 0.22, 1.20, granite)
box("base_2", 0, 0.22, 0, 1.00, 0.18, 1.00, granite)
box("ped_shaft", 0, 0.40, 0, 0.80, 2.40, 0.80, granite)
box("ped_cap", 0, 2.80, 0, 0.90, 0.12, 0.90, granite)
box("ped_top", 0, 2.92, 0, 0.85, 0.08, 0.85, granite)

# ── Horse (walking pose — calm, one foreleg raised) ──
FIG = 3.00
# Barrel
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.26, segments=12, ring_count=8,
    location=(0, FIG + 0.52, 0))
o = bpy.context.active_object
o.name = "horse_barrel"
o.scale = (1.8, 1.0, 0.85)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Chest
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.20, segments=10, ring_count=6,
    location=(0.30, FIG + 0.60, 0))
o = bpy.context.active_object
o.name = "horse_chest"
o.data.materials.append(bronze)

# Haunches
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.18, segments=10, ring_count=6,
    location=(-0.30, FIG + 0.50, 0))
o = bpy.context.active_object
o.name = "horse_haunch"
o.data.materials.append(bronze)

# Neck
cylinder("horse_neck", 0.32, FIG + 0.68, 0, 0.09, 0.32, 8, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.25)
bpy.ops.object.transform_apply(rotation=True)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.09, segments=8, ring_count=6,
    location=(0.42, FIG + 1.00, 0))
o = bpy.context.active_object
o.name = "horse_head"
o.scale = (1.5, 1.0, 0.9)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Muzzle
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.04, segments=6, ring_count=4,
    location=(0.54, FIG + 0.96, 0))
o = bpy.context.active_object
o.name = "horse_muzzle"
o.data.materials.append(bronze)

# Ears
for side in [-0.03, 0.03]:
    bpy.ops.mesh.primitive_cone_add(
        radius1=0.018, radius2=0, depth=0.045, vertices=4,
        location=(0.44, FIG + 1.10, side))
    o = bpy.context.active_object
    o.name = f"ear_{side}"
    o.data.materials.append(bronze)

# Legs (3 on ground, 1 raised)
# Rear legs
for side in [-0.11, 0.11]:
    cylinder(f"rear_leg_{side}", -0.28, FIG, side, 0.035, 0.52, 6, bronze)

# Left front (on ground)
cylinder("front_leg_l", 0.22, FIG, -0.09, 0.032, 0.52, 6, bronze)

# Right front (raised — walking)
cylinder("front_leg_r", 0.22, FIG + 0.15, 0.09, 0.032, 0.40, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.4)
bpy.ops.object.transform_apply(rotation=True)

# Tail
cylinder("tail", -0.48, FIG + 0.30, 0, 0.025, 0.28, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.5)
bpy.ops.object.transform_apply(rotation=True)

# ── Rider (San Martín — upright, military bearing) ──
cylinder("rider_torso", 0.02, FIG + 0.72, 0, 0.08, 0.38, 8, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.065, segments=8, ring_count=6,
    location=(0.02, FIG + 1.18, 0))
o = bpy.context.active_object
o.name = "rider_head"
o.data.materials.append(bronze)

# Bicorn hat
box("hat", 0.02, FIG + 1.24, 0, 0.08, 0.03, 0.05, bronze)

# Arms
cylinder("right_arm", 0.12, FIG + 0.88, 0.04, 0.025, 0.30, 6, bronze)
cylinder("left_arm", -0.10, FIG + 0.88, -0.04, 0.025, 0.28, 6, bronze)

# Legs
for side in [-0.12, 0.12]:
    cylinder(f"rider_leg_{side}", 0, FIG + 0.52, side, 0.028, 0.25, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "JoseDeSanMartin"

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_san_martin.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
