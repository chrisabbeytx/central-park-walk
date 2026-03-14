"""Generate Still Hunt (cougar/panther) for Central Park Walk.

East Drive near 76th St — Still Hunt (1883, Edward Kemeys).
Bronze cougar crouching on natural rock ledge, ready to pounce.
~1.2m long, ~0.6m tall at shoulder. Very low-profile, naturalistic.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf = bronze.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.18, 0.22, 0.14, 1.0)
bsdf.inputs["Roughness"].default_value = 0.45
bsdf.inputs["Metallic"].default_value = 0.85

rock = bpy.data.materials.new("Rock")
rock.use_nodes = True
bsdf2 = rock.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.42, 0.40, 0.36, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.82


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


# ── Rock base (natural outcrop shape) ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.50, segments=10, ring_count=6,
    location=(0, 0.22, 0))
o = bpy.context.active_object
o.name = "rock_base"
o.scale = (1.4, 0.5, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(rock)

# ── Cougar body (elongated ellipsoid) ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.16, segments=10, ring_count=8,
    location=(0, 0.52, 0))
o = bpy.context.active_object
o.name = "body"
o.scale = (2.8, 1.0, 1.2)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# ── Haunches (rear, slightly raised - crouching) ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.14, segments=8, ring_count=6,
    location=(-0.30, 0.50, 0))
o = bpy.context.active_object
o.name = "haunches"
o.scale = (1.2, 1.1, 1.3)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# ── Head ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.10, segments=8, ring_count=6,
    location=(0.38, 0.54, 0))
o = bpy.context.active_object
o.name = "head"
o.scale = (1.3, 0.9, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# ── Snout ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.05, segments=6, ring_count=4,
    location=(0.50, 0.51, 0))
o = bpy.context.active_object
o.name = "snout"
o.scale = (1.5, 0.8, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# ── Tail (long, curves down) ──
cylinder("tail", -0.45, 0.46, 0, 0.025, 0.40, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 1.2)
bpy.ops.object.transform_apply(rotation=True)

# ── Front legs ──
for side in [-0.08, 0.08]:
    cylinder(f"fleg_{side}", 0.25, 0.30, side, 0.025, 0.22, 6, bronze)

# ── Rear legs ──
for side in [-0.10, 0.10]:
    cylinder(f"rleg_{side}", -0.28, 0.30, side, 0.03, 0.22, 6, bronze)

# ── Ears ──
for side in [-0.04, 0.04]:
    bpy.ops.mesh.primitive_cone_add(
        radius1=0.025, radius2=0, depth=0.04, vertices=4,
        location=(0.40, 0.64, side))
    o = bpy.context.active_object
    o.name = f"ear_{side}"
    o.data.materials.append(bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "StillHunt"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_still_hunt.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
