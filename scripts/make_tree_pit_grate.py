"""Generate tree pit grate for Central Park Walk.

Cast iron grates around tree bases along paved paths.
Circular opening for tree trunk, with radiating bars.
~1.2m square with 0.3m center opening.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

iron = bpy.data.materials.new("Iron")
iron.use_nodes = True
bsdf = iron.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.10, 0.10, 0.11, 1.0)
bsdf.inputs["Roughness"].default_value = 0.65
bsdf.inputs["Metallic"].default_value = 0.85

SIZE = 1.20      # overall square size
CENTER_R = 0.15  # center opening radius
H = 0.015        # grate height
BAR_W = 0.012    # bar width
N_RADIAL = 8     # radial bars
N_RINGS = 3      # concentric rings


def box(name, x, y, z, sx, sy, sz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y + sy, z))
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx * 2, sy * 2, sz * 2)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    return o


# ── Outer frame ──
hw = SIZE / 2
# Four edges
box("frame_n", 0, 0, hw - BAR_W, hw, H / 2, BAR_W, iron)
box("frame_s", 0, 0, -hw + BAR_W, hw, H / 2, BAR_W, iron)
box("frame_e", hw - BAR_W, 0, 0, BAR_W, H / 2, hw, iron)
box("frame_w", -hw + BAR_W, 0, 0, BAR_W, H / 2, hw, iron)

# ── Radial bars (from center outward) ──
for i in range(N_RADIAL):
    angle = math.pi * 2 * i / N_RADIAL
    dx = math.cos(angle)
    dz = math.sin(angle)
    bar_len = hw - CENTER_R - BAR_W * 2
    cx = dx * (CENTER_R + bar_len / 2)
    cz = dz * (CENTER_R + bar_len / 2)

    bpy.ops.mesh.primitive_cube_add(
        size=1, location=(cx, H / 2, cz))
    o = bpy.context.active_object
    o.name = f"radial_{i}"
    o.scale = (BAR_W, H, bar_len)
    o.rotation_euler = (0, -angle, 0)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    o.data.materials.append(iron)

# ── Concentric ring segments ──
for ring in range(N_RINGS):
    r = CENTER_R + (hw - CENTER_R) * (ring + 1) / (N_RINGS + 1)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=r, minor_radius=BAR_W / 2,
        major_segments=20, minor_segments=4,
        location=(0, H / 2, 0))
    o = bpy.context.active_object
    o.name = f"ring_{ring}"
    o.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(iron)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "TreePitGrate"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_tree_pit_grate.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
