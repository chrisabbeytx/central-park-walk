"""Generate decorative stone urn for Central Park Walk.

Ornamental stone urns at Bethesda Terrace, Conservatory Garden,
and other formal locations. Classical vase shape with handles.
~0.9m tall on 0.3m base.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.62, 0.60, 0.56, 1.0)
bsdf.inputs["Roughness"].default_value = 0.68


# ── Base pedestal ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.20, depth=0.15, vertices=12,
    location=(0, 0.075, 0))
o = bpy.context.active_object
o.name = "base"
o.data.materials.append(stone)

# ── Base molding ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.22, depth=0.04, vertices=12,
    location=(0, 0.17, 0))
o = bpy.context.active_object
o.name = "molding"
o.data.materials.append(stone)

# ── Lower body (tapered) ──
bpy.ops.mesh.primitive_cone_add(
    radius1=0.12, radius2=0.22,
    depth=0.30, vertices=16,
    location=(0, 0.34, 0))
o = bpy.context.active_object
o.name = "lower_body"
o.data.materials.append(stone)

# ── Belly (widest part) ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.25, segments=16, ring_count=10,
    location=(0, 0.55, 0))
o = bpy.context.active_object
o.name = "belly"
o.scale = (1.0, 0.7, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(stone)

# ── Neck ──
bpy.ops.mesh.primitive_cone_add(
    radius1=0.22, radius2=0.16,
    depth=0.15, vertices=16,
    location=(0, 0.72, 0))
o = bpy.context.active_object
o.name = "neck"
o.data.materials.append(stone)

# ── Rim (flared lip) ──
bpy.ops.mesh.primitive_cone_add(
    radius1=0.16, radius2=0.24,
    depth=0.08, vertices=16,
    location=(0, 0.84, 0))
o = bpy.context.active_object
o.name = "rim"
o.data.materials.append(stone)

# ── Handles (two scroll handles) ──
for side in [-1, 1]:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.08, minor_radius=0.02,
        major_segments=12, minor_segments=6,
        location=(side * 0.26, 0.58, 0))
    o = bpy.context.active_object
    o.name = f"handle_{side}"
    o.rotation_euler = (0, math.pi / 2, 0)
    bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(stone)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "StoneUrn"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_stone_urn.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
