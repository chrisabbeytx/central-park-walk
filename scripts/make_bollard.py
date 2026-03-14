"""Generate park entrance bollard for Central Park Walk.

Short cast-iron bollards at vehicle-restricted park entrances.
Classic NYC Parks design: tapered cylinder with rounded cap.
~0.85m tall, 0.15m diameter.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

iron = bpy.data.materials.new("Iron")
iron.use_nodes = True
bsdf = iron.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.08, 0.08, 0.09, 1.0)
bsdf.inputs["Roughness"].default_value = 0.60
bsdf.inputs["Metallic"].default_value = 0.85


# ── Base flange ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.12, depth=0.04, vertices=12,
    location=(0, 0.02, 0))
o = bpy.context.active_object
o.name = "base"
o.data.materials.append(iron)

# ── Lower taper ──
bpy.ops.mesh.primitive_cone_add(
    radius1=0.10, radius2=0.075,
    depth=0.30, vertices=12,
    location=(0, 0.19, 0))
o = bpy.context.active_object
o.name = "lower_taper"
o.data.materials.append(iron)

# ── Main shaft ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.075, depth=0.40, vertices=12,
    location=(0, 0.54, 0))
o = bpy.context.active_object
o.name = "shaft"
o.data.materials.append(iron)

# ── Rounded cap ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.085, segments=12, ring_count=6,
    location=(0, 0.76, 0))
o = bpy.context.active_object
o.name = "cap"
o.scale = (1.0, 0.6, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(iron)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Bollard"

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_bollard.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
