"""Generate fitness/exercise station for Central Park Walk.

Central Park has fitness stations along the running paths —
metal pull-up bars and exercise equipment posts.
Standard design: two vertical steel posts with horizontal bars.
~2.4m tall, 1.8m wide.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

steel = bpy.data.materials.new("Steel")
steel.use_nodes = True
bsdf = steel.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.35, 0.32, 0.28, 1.0)
bsdf.inputs["Roughness"].default_value = 0.55
bsdf.inputs["Metallic"].default_value = 0.90


def cylinder(name, x, y, z, r, h, segs, mat, rx=0, ry=0, rz=0):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=r, depth=h, vertices=segs,
        location=(x, y + h / 2, z))
    o = bpy.context.active_object
    o.name = name
    if rx != 0 or ry != 0 or rz != 0:
        o.rotation_euler = (rx, ry, rz)
        bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(mat)
    return o


POST_R = 0.04    # 40mm steel pipe
BAR_R = 0.025    # 25mm bar
WIDTH = 1.80     # between posts
HEIGHT = 2.40    # post height
DEPTH = 0.015    # ground plate

# ── Ground plates ──
for side in [-1, 1]:
    bpy.ops.mesh.primitive_cube_add(
        size=1, location=(side * WIDTH / 2, DEPTH, 0))
    o = bpy.context.active_object
    o.name = f"plate_{side}"
    o.scale = (0.20, DEPTH, 0.20)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(steel)

# ── Vertical posts ──
cylinder("left_post", -WIDTH / 2, 0, 0, POST_R, HEIGHT, 12, steel)
cylinder("right_post", WIDTH / 2, 0, 0, POST_R, HEIGHT, 12, steel)

# ── Horizontal bars (pull-up bars) ──
# Top bar
cylinder("top_bar", 0, HEIGHT - 0.05, 0, BAR_R, WIDTH, 10, steel,
         rx=0, ry=0, rz=math.pi / 2)

# Middle bar (chin-up height)
cylinder("mid_bar", 0, HEIGHT * 0.75, 0, BAR_R, WIDTH, 10, steel,
         rx=0, ry=0, rz=math.pi / 2)

# Lower bar (dip height)
cylinder("low_bar", 0, HEIGHT * 0.50, 0, BAR_R, WIDTH, 10, steel,
         rx=0, ry=0, rz=math.pi / 2)

# ── Diagonal braces ──
brace_len = math.sqrt(HEIGHT**2 * 0.25**2 + 0.4**2)
for side in [-1, 1]:
    cylinder(f"brace_{side}", side * WIDTH / 2, HEIGHT * 0.4, 0,
             0.015, HEIGHT * 0.55, 6, steel,
             rx=0, ry=0, rz=side * 0.15)

# ── Exercise instruction plate (flat rectangle on one post) ──
bpy.ops.mesh.primitive_cube_add(
    size=1, location=(-WIDTH / 2 - 0.05, HEIGHT * 0.55, 0))
plate = bpy.context.active_object
plate.name = "info_plate"
plate.scale = (0.005, 0.30, 0.20)
bpy.ops.object.transform_apply(scale=True)
plate.data.materials.append(steel)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "FitnessStation"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_fitness_station.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
