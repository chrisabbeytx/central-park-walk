"""Generate Joan of Arc equestrian statue for Central Park Walk.

Riverside Drive at 93rd St (near park) — Joan of Arc (1915, Anna Hyatt Huntington).
Bronze equestrian: Joan in armor, holding sword aloft, on prancing horse.
Tall granite pedestal with stone base. Total ~8m.
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
box("base_step", 0, 0, 0, 1.30, 0.25, 1.30, granite)
box("base_2", 0, 0.25, 0, 1.10, 0.22, 1.10, granite)
box("ped_shaft", 0, 0.47, 0, 0.85, 3.20, 0.85, granite)
box("ped_cap", 0, 3.67, 0, 0.95, 0.15, 0.95, granite)
box("ped_top", 0, 3.82, 0, 0.90, 0.10, 0.90, granite)

# ── Horse (prancing, one leg raised) ──
FIG = 3.92
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.26, segments=12, ring_count=8,
    location=(0, FIG + 0.52, 0))
o = bpy.context.active_object
o.name = "horse_barrel"
o.scale = (1.7, 1.0, 0.85)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.20, segments=10, ring_count=6,
    location=(0.28, FIG + 0.62, 0))
o = bpy.context.active_object
o.name = "horse_chest"
o.data.materials.append(bronze)

cylinder("horse_neck", 0.32, FIG + 0.72, 0, 0.09, 0.35, 8, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.3)
bpy.ops.object.transform_apply(rotation=True)

bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.09, segments=8, ring_count=6,
    location=(0.42, FIG + 1.08, 0))
o = bpy.context.active_object
o.name = "horse_head"
o.scale = (1.5, 1.0, 0.9)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.04, segments=6, ring_count=4,
    location=(0.54, FIG + 1.04, 0))
o = bpy.context.active_object
o.name = "horse_muzzle"
o.data.materials.append(bronze)

for side in [-0.035, 0.035]:
    bpy.ops.mesh.primitive_cone_add(
        radius1=0.018, radius2=0, depth=0.05, vertices=4,
        location=(0.44, FIG + 1.18, side))
    o = bpy.context.active_object
    o.name = f"ear_{side}"
    o.data.materials.append(bronze)

# Rear legs
for side in [-0.11, 0.11]:
    cylinder(f"rear_leg_{side}", -0.28, FIG, side, 0.035, 0.52, 6, bronze)

# Front legs (one raised)
cylinder("front_leg_l", 0.22, FIG, -0.09, 0.032, 0.52, 6, bronze)
cylinder("front_leg_r", 0.22, FIG + 0.12, 0.09, 0.032, 0.42, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.35)
bpy.ops.object.transform_apply(rotation=True)

# Tail
cylinder("tail", -0.48, FIG + 0.32, 0, 0.025, 0.30, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.6)
bpy.ops.object.transform_apply(rotation=True)

# ── Joan (armored, holding sword aloft) ──
cylinder("rider_torso", 0.02, FIG + 0.72, 0, 0.08, 0.38, 8, bronze)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.065, segments=8, ring_count=6,
    location=(0.02, FIG + 1.18, 0))
o = bpy.context.active_object
o.name = "rider_head"
o.data.materials.append(bronze)

# Helmet
cylinder("helmet", 0.02, FIG + 1.22, 0, 0.06, 0.04, 8, bronze)

# Right arm (holding sword high)
cylinder("right_arm", 0.10, FIG + 1.00, 0.05, 0.025, 0.35, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, -0.4)
bpy.ops.object.transform_apply(rotation=True)

# Sword (held aloft)
cylinder("sword", 0.12, FIG + 1.30, 0.05, 0.01, 0.55, 4, bronze)

# Sword crossguard
box("guard", 0.12, FIG + 1.28, 0.05, 0.035, 0.012, 0.012, bronze)

# Left arm (holding reins)
cylinder("left_arm", -0.10, FIG + 0.90, -0.03, 0.025, 0.30, 6, bronze)

# Legs
for side in [-0.12, 0.12]:
    cylinder(f"rider_leg_{side}", 0, FIG + 0.52, side, 0.028, 0.25, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "JoanOfArc"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_joan_of_arc.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
