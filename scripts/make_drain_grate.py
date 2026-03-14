"""Generate storm drain grate for Central Park Walk.

Cast iron grate at road/path intersections for drainage.
Rectangular frame with parallel bars. Sits flush with pavement.
~0.6m × 0.3m.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

iron = bpy.data.materials.new("Iron")
iron.use_nodes = True
bsdf = iron.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.12, 0.12, 0.13, 1.0)
bsdf.inputs["Roughness"].default_value = 0.70
bsdf.inputs["Metallic"].default_value = 0.85

W = 0.60   # grate width
D = 0.30   # grate depth
H = 0.02   # grate height
BAR_W = 0.015  # bar width
N_BARS = 8  # parallel bars


def box(name, x, y, z, sx, sy, sz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y + sy, z))
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx * 2, sy * 2, sz * 2)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    return o


# ── Frame ──
# Front and back rails
box("frame_front", 0, 0, D / 2 - BAR_W / 2, W / 2, H / 2, BAR_W / 2, iron)
box("frame_back", 0, 0, -D / 2 + BAR_W / 2, W / 2, H / 2, BAR_W / 2, iron)
# Left and right rails
box("frame_left", -W / 2 + BAR_W / 2, 0, 0, BAR_W / 2, H / 2, D / 2, iron)
box("frame_right", W / 2 - BAR_W / 2, 0, 0, BAR_W / 2, H / 2, D / 2, iron)

# ── Parallel bars ──
inner_w = W - BAR_W * 2
spacing = inner_w / (N_BARS + 1)
for i in range(N_BARS):
    bx = -W / 2 + BAR_W + spacing * (i + 1)
    box(f"bar_{i}", bx, 0, 0, BAR_W / 2, H / 2, D / 2 - BAR_W, iron)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "DrainGrate"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_drain_grate.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
