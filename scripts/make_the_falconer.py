"""Generate The Falconer statue for Central Park Walk.

West side near 72nd St — The Falconer (1875, George Blackall Simonds).
Bronze figure of a medieval falconer with bird on raised left arm,
standing on rocky base atop granite pedestal. ~4m total.
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
box("base_step", 0, 0, 0, 0.70, 0.15, 0.70, granite)
box("ped_shaft", 0, 0.15, 0, 0.55, 1.40, 0.55, granite)
box("ped_cap", 0, 1.55, 0, 0.60, 0.10, 0.60, granite)

# ── Rocky base on pedestal ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.30, segments=8, ring_count=6,
    location=(0, 1.80, 0))
o = bpy.context.active_object
o.name = "rock_base"
o.scale = (1.3, 0.5, 1.1)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(granite)

# ── Standing figure ──
FIG = 1.95
# Legs
cylinder("right_leg", 0.05, FIG, 0.04, 0.04, 0.60, 8, bronze)
cylinder("left_leg", -0.05, FIG, -0.04, 0.04, 0.55, 8, bronze)

# Torso (tunic)
cylinder("torso", 0, FIG + 0.55, 0, 0.10, 0.45, 8, bronze)

# Shoulders
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.12, segments=8, ring_count=6,
    location=(0, FIG + 0.98, 0))
o = bpy.context.active_object
o.name = "shoulders"
o.scale = (1.2, 0.5, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Neck
cylinder("neck", 0, FIG + 1.00, 0, 0.035, 0.08, 6, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.07, segments=8, ring_count=6,
    location=(0, FIG + 1.16, 0))
o = bpy.context.active_object
o.name = "head"
o.data.materials.append(bronze)

# Cap/hat
cylinder("cap", 0, FIG + 1.22, 0, 0.07, 0.04, 8, bronze)

# Left arm (raised, holding falcon)
cylinder("left_arm", -0.12, FIG + 0.90, 0, 0.025, 0.40, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, -0.5)
bpy.ops.object.transform_apply(rotation=True)

# Right arm (down at side)
cylinder("right_arm", 0.12, FIG + 0.75, 0, 0.025, 0.35, 6, bronze)

# ── Falcon on left arm ──
BIRD_Y = FIG + 1.35
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.04, segments=6, ring_count=4,
    location=(-0.22, BIRD_Y, 0))
o = bpy.context.active_object
o.name = "falcon_body"
o.scale = (1.3, 1.0, 0.8)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Falcon head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.02, segments=6, ring_count=4,
    location=(-0.22, BIRD_Y + 0.06, 0))
o = bpy.context.active_object
o.name = "falcon_head"
o.data.materials.append(bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "TheFalconer"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_falconer.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
