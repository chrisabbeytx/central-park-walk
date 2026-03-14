"""Generate Group of Bears sculpture for Central Park Walk.

Pat Hoffman Friedman Playground area — Group of Bears (1990, Paul Manship).
Three bronze bears: standing mother bear with two cubs, naturalistic grouping.
Total ~1.5m tall. On low stone base.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.55, 0.52, 0.48, 1.0)
bsdf.inputs["Roughness"].default_value = 0.72

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.22, 0.26, 0.18, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.44
bsdf2.inputs["Metallic"].default_value = 0.82


def cylinder(name, x, y, z, r, h, segs, mat):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=r, depth=h, vertices=segs,
        location=(x, y + h / 2, z))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


# ── Low stone base ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.55, depth=0.12, vertices=12,
    location=(0, 0.06, 0))
o = bpy.context.active_object
o.name = "base"
o.scale = (1.3, 1.0, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(stone)

# ── Mother bear (standing upright) ──
BASE = 0.12
# Body
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.16, segments=10, ring_count=8,
    location=(0, BASE + 0.40, 0))
o = bpy.context.active_object
o.name = "mama_body"
o.scale = (0.9, 1.2, 0.85)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Upper torso/shoulders
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.14, segments=8, ring_count=6,
    location=(0, BASE + 0.65, 0))
o = bpy.context.active_object
o.name = "mama_shoulders"
o.scale = (0.9, 1.0, 0.9)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.09, segments=8, ring_count=6,
    location=(0, BASE + 0.82, 0.02))
o = bpy.context.active_object
o.name = "mama_head"
o.data.materials.append(bronze)

# Snout
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.04, segments=6, ring_count=4,
    location=(0, BASE + 0.80, 0.10))
o = bpy.context.active_object
o.name = "mama_snout"
o.scale = (0.8, 0.7, 1.2)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Ears
for side in [-0.06, 0.06]:
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.025, segments=6, ring_count=4,
        location=(side, BASE + 0.90, 0))
    o = bpy.context.active_object
    o.name = f"mama_ear_{side}"
    o.data.materials.append(bronze)

# Legs
for side in [-0.06, 0.06]:
    cylinder(f"mama_leg_{side}", side, BASE, 0, 0.04, 0.25, 6, bronze)

# Arms (at sides)
for side in [-0.12, 0.12]:
    cylinder(f"mama_arm_{side}", side, BASE + 0.45, 0.03, 0.03, 0.25, 6, bronze)

# ── Cub 1 (sitting, to the right) ──
CUB1_X = 0.28
CUB1_Z = 0.10
# Body
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.08, segments=8, ring_count=6,
    location=(CUB1_X, BASE + 0.16, CUB1_Z))
o = bpy.context.active_object
o.name = "cub1_body"
o.scale = (0.9, 1.0, 0.85)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.05, segments=6, ring_count=4,
    location=(CUB1_X, BASE + 0.28, CUB1_Z + 0.02))
o = bpy.context.active_object
o.name = "cub1_head"
o.data.materials.append(bronze)

# Ears
for side in [-0.03, 0.03]:
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.015, segments=4, ring_count=3,
        location=(CUB1_X + side, BASE + 0.33, CUB1_Z))
    o = bpy.context.active_object
    o.name = f"cub1_ear_{side}"
    o.data.materials.append(bronze)

# ── Cub 2 (on all fours, to the left) ──
CUB2_X = -0.25
CUB2_Z = -0.08
# Body (horizontal)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.07, segments=8, ring_count=6,
    location=(CUB2_X, BASE + 0.12, CUB2_Z))
o = bpy.context.active_object
o.name = "cub2_body"
o.scale = (1.3, 0.8, 0.8)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.045, segments=6, ring_count=4,
    location=(CUB2_X + 0.10, BASE + 0.14, CUB2_Z))
o = bpy.context.active_object
o.name = "cub2_head"
o.data.materials.append(bronze)

# Legs
for dx, dz in [(0.06, 0.03), (0.06, -0.03), (-0.06, 0.03), (-0.06, -0.03)]:
    cylinder(f"cub2_leg_{dx}_{dz}", CUB2_X + dx, BASE, CUB2_Z + dz, 0.015, 0.10, 4, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "GroupOfBears"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_group_of_bears.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
