"""Generate José Martí equestrian statue for Central Park Walk.

Avenue of the Americas at 59th St — José Martí (1965, Anna Hyatt Huntington).
Bronze equestrian: Martí on rearing horse, mortally wounded, falling backward.
Dramatic pose — horse rearing, rider slumping with arm outstretched.
Total height ~6m (granite pedestal + horse/rider).
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
box("base_step", 0, 0, 0, 1.10, 0.20, 1.10, granite)
box("base_2", 0, 0.20, 0, 0.95, 0.18, 0.95, granite)
box("ped_shaft", 0, 0.38, 0, 0.75, 2.00, 0.75, granite)
box("ped_cap", 0, 2.38, 0, 0.85, 0.12, 0.85, granite)
box("ped_top", 0, 2.50, 0, 0.80, 0.08, 0.80, granite)

# ── Horse (rearing) ──
FIG = 2.58
# Barrel
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.26, segments=12, ring_count=8,
    location=(0, FIG + 0.55, 0))
o = bpy.context.active_object
o.name = "horse_barrel"
o.scale = (1.7, 1.0, 0.85)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Chest
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.20, segments=10, ring_count=6,
    location=(0.28, FIG + 0.70, 0))
o = bpy.context.active_object
o.name = "horse_chest"
o.data.materials.append(bronze)

# Neck (angled up)
cylinder("horse_neck", 0.30, FIG + 0.85, 0, 0.09, 0.38, 8, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.45)
bpy.ops.object.transform_apply(rotation=True)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.09, segments=8, ring_count=6,
    location=(0.42, FIG + 1.25, 0))
o = bpy.context.active_object
o.name = "horse_head"
o.scale = (1.5, 1.0, 0.9)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Muzzle
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.045, segments=6, ring_count=4,
    location=(0.54, FIG + 1.20, 0))
o = bpy.context.active_object
o.name = "horse_muzzle"
o.scale = (1.4, 0.8, 0.8)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Ears
for side in [-0.035, 0.035]:
    bpy.ops.mesh.primitive_cone_add(
        radius1=0.02, radius2=0, depth=0.05, vertices=4,
        location=(0.45, FIG + 1.35, side))
    o = bpy.context.active_object
    o.name = f"ear_{side}"
    o.data.materials.append(bronze)

# Rear legs (on ground)
for side in [-0.11, 0.11]:
    cylinder(f"rear_leg_{side}", -0.28, FIG, side, 0.038, 0.55, 6, bronze)

# Front legs (rearing up)
for side in [-0.09, 0.09]:
    cylinder(f"front_leg_{side}", 0.18, FIG + 0.50, side, 0.032, 0.48, 6, bronze)
    bpy.context.active_object.rotation_euler = (0, 0, 0.55)
    bpy.ops.object.transform_apply(rotation=True)

# Tail
cylinder("tail", -0.48, FIG + 0.35, 0, 0.025, 0.30, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.7)
bpy.ops.object.transform_apply(rotation=True)

# ── Rider (Martí — leaning back, mortally wounded) ──
# Torso (leaning backward)
cylinder("rider_torso", -0.02, FIG + 0.80, 0, 0.08, 0.35, 8, bronze)
bpy.context.active_object.rotation_euler = (0, 0, -0.3)
bpy.ops.object.transform_apply(rotation=True)

# Head (tilted back)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.065, segments=8, ring_count=6,
    location=(-0.08, FIG + 1.20, 0))
o = bpy.context.active_object
o.name = "rider_head"
o.data.materials.append(bronze)

# Right arm (outstretched dramatically)
cylinder("right_arm", 0.05, FIG + 1.00, 0.08, 0.025, 0.35, 6, bronze)
bpy.context.active_object.rotation_euler = (0.3, 0, 0.8)
bpy.ops.object.transform_apply(rotation=True)

# Left arm (down)
cylinder("left_arm", -0.08, FIG + 0.90, -0.05, 0.025, 0.28, 6, bronze)

# Rider legs (along horse flanks)
for side in [-0.13, 0.13]:
    cylinder(f"rider_leg_{side}", 0, FIG + 0.55, side, 0.028, 0.28, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "JoseMarti"

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_jose_marti.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
