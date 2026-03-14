"""Generate bicycle rack for Central Park Walk.

NYC Parks standard inverted-U bike rack (aka "staple" rack).
Single galvanized steel tube bent into an inverted U shape.
~0.85m tall, 0.70m wide.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

steel = bpy.data.materials.new("Steel")
steel.use_nodes = True
bsdf = steel.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.45, 0.44, 0.42, 1.0)
bsdf.inputs["Roughness"].default_value = 0.50
bsdf.inputs["Metallic"].default_value = 0.90

TUBE_R = 0.025   # 25mm tube radius
HEIGHT = 0.85     # height of the U
WIDTH = 0.70      # width between legs
SEGS = 12         # segments for the curved top

# ── Left leg ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=TUBE_R, depth=HEIGHT - TUBE_R * 2, vertices=10,
    location=(-WIDTH / 2, (HEIGHT - TUBE_R * 2) / 2, 0))
o = bpy.context.active_object
o.name = "left_leg"
o.data.materials.append(steel)

# ── Right leg ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=TUBE_R, depth=HEIGHT - TUBE_R * 2, vertices=10,
    location=(WIDTH / 2, (HEIGHT - TUBE_R * 2) / 2, 0))
o = bpy.context.active_object
o.name = "right_leg"
o.data.materials.append(steel)

# ── Curved top (half-circle using torus segment) ──
bpy.ops.mesh.primitive_torus_add(
    major_radius=WIDTH / 2, minor_radius=TUBE_R,
    major_segments=SEGS, minor_segments=6,
    location=(0, HEIGHT - TUBE_R, 0))
o = bpy.context.active_object
o.name = "top_curve"
# Delete bottom half
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='DESELECT')
bpy.ops.object.mode_set(mode='OBJECT')
# Instead of editing, just scale down the torus to approximate
o.scale = (1.0, 0.5, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(steel)

# ── Ground anchors (small flanges) ──
for side in [-1, 1]:
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.05, depth=0.01, vertices=8,
        location=(side * WIDTH / 2, 0.005, 0))
    o = bpy.context.active_object
    o.name = f"anchor_{side}"
    o.data.materials.append(steel)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "BikeRack"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_bike_rack.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
