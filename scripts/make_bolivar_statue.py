"""Generate Simón Bolívar equestrian statue for Central Park Walk.

Avenue of the Americas entrance at 59th St — Simón Bolívar (1921, Sally James Farnham).
Bronze equestrian: Bolívar on rearing horse atop granite pedestal.
Total height ~6m (3m pedestal + 3m horse/rider).
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
box("base_step", 0, 0, 0, 1.20, 0.20, 1.20, granite)
box("base_2", 0, 0.20, 0, 1.00, 0.20, 1.00, granite)
box("ped_shaft", 0, 0.40, 0, 0.80, 2.00, 0.80, granite)
box("ped_cap", 0, 2.40, 0, 0.90, 0.15, 0.90, granite)
box("ped_top", 0, 2.55, 0, 0.85, 0.10, 0.85, granite)

# ── Horse body ──
FIG = 2.65
# Barrel/torso
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.28, segments=12, ring_count=8,
    location=(0, FIG + 0.60, 0))
o = bpy.context.active_object
o.name = "horse_barrel"
o.scale = (1.8, 1.0, 0.9)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Horse chest
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.22, segments=10, ring_count=6,
    location=(0.30, FIG + 0.75, 0))
o = bpy.context.active_object
o.name = "horse_chest"
o.data.materials.append(bronze)

# Horse neck (angled up - rearing)
cylinder("horse_neck", 0.32, FIG + 0.90, 0, 0.10, 0.40, 8, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.5)
bpy.ops.object.transform_apply(rotation=True)

# Horse head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.10, segments=8, ring_count=6,
    location=(0.45, FIG + 1.30, 0))
o = bpy.context.active_object
o.name = "horse_head"
o.scale = (1.6, 1.0, 0.9)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Horse muzzle
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.05, segments=6, ring_count=4,
    location=(0.58, FIG + 1.26, 0))
o = bpy.context.active_object
o.name = "horse_muzzle"
o.scale = (1.5, 0.8, 0.8)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Rear legs (on ground, supporting)
for side in [-0.12, 0.12]:
    cylinder(f"rear_leg_{side}", -0.30, FIG, side, 0.04, 0.60, 6, bronze)

# Front legs (rearing up)
for side in [-0.10, 0.10]:
    cylinder(f"front_leg_{side}", 0.20, FIG + 0.55, side, 0.035, 0.50, 6, bronze)
    bpy.context.active_object.rotation_euler = (0, 0, 0.6)
    bpy.ops.object.transform_apply(rotation=True)

# Tail
cylinder("tail", -0.50, FIG + 0.40, 0, 0.03, 0.35, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.8)
bpy.ops.object.transform_apply(rotation=True)

# ── Rider (Bolívar) ──
# Torso
cylinder("rider_torso", 0.05, FIG + 0.85, 0, 0.08, 0.35, 8, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.07, segments=8, ring_count=6,
    location=(0.05, FIG + 1.30, 0))
o = bpy.context.active_object
o.name = "rider_head"
o.data.materials.append(bronze)

# Hat (bicorn)
box("hat", 0.05, FIG + 1.36, 0, 0.10, 0.03, 0.06, bronze)

# Arms
for side in [-0.10, 0.10]:
    cylinder(f"rider_arm_{side}", 0.05 + side * 0.5, FIG + 1.05, side, 0.025, 0.30, 6, bronze)

# Rider legs (along horse)
for side in [-0.14, 0.14]:
    cylinder(f"rider_leg_{side}", 0, FIG + 0.60, side, 0.03, 0.30, 6, bronze)

# ── Ears (horse) ──
for side in [-0.04, 0.04]:
    bpy.ops.mesh.primitive_cone_add(
        radius1=0.02, radius2=0, depth=0.06, vertices=4,
        location=(0.48, FIG + 1.40, side))
    o = bpy.context.active_object
    o.name = f"ear_{side}"
    o.data.materials.append(bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "SimonBolivar"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_bolivar.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
