"""Generate NYC Parks wire mesh trash can for Central Park Walk.

The distinctive green wire-frame waste baskets used throughout NYC parks.
Cylindrical wire cage on a central post with peaked lid.
~0.9m tall, 0.45m diameter.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

green = bpy.data.materials.new("ParkGreen")
green.use_nodes = True
bsdf = green.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.15, 0.28, 0.12, 1.0)
bsdf.inputs["Roughness"].default_value = 0.60
bsdf.inputs["Metallic"].default_value = 0.70

steel = bpy.data.materials.new("Steel")
steel.use_nodes = True
bsdf2 = steel.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.35, 0.33, 0.30, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.55
bsdf2.inputs["Metallic"].default_value = 0.85

CAN_R = 0.225    # radius
CAN_H = 0.75     # can height
POST_H = 0.90    # total height including post
POST_R = 0.025   # central post radius


def cylinder(name, x, y, z, r, h, segs, mat):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=r, depth=h, vertices=segs,
        location=(x, y + h / 2, z))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


# ── Central post ──
cylinder("post", 0, 0, 0, POST_R, POST_H, 8, steel)

# ── Base plate ──
cylinder("base_plate", 0, 0, 0, CAN_R * 0.6, 0.015, 12, green)

# ── Wire cage (simplified as semi-transparent cylinder) ──
# Bottom ring
bpy.ops.mesh.primitive_torus_add(
    major_radius=CAN_R, minor_radius=0.008,
    major_segments=20, minor_segments=4,
    location=(0, 0.10, 0))
o = bpy.context.active_object
o.name = "bottom_ring"
o.data.materials.append(green)

# Middle ring
bpy.ops.mesh.primitive_torus_add(
    major_radius=CAN_R, minor_radius=0.008,
    major_segments=20, minor_segments=4,
    location=(0, 0.40, 0))
o = bpy.context.active_object
o.name = "mid_ring"
o.data.materials.append(green)

# Top ring
bpy.ops.mesh.primitive_torus_add(
    major_radius=CAN_R, minor_radius=0.008,
    major_segments=20, minor_segments=4,
    location=(0, CAN_H, 0))
o = bpy.context.active_object
o.name = "top_ring"
o.data.materials.append(green)

# Vertical wire bars (12 around the circumference)
for i in range(12):
    angle = math.pi * 2 * i / 12
    bx = math.cos(angle) * CAN_R
    bz = math.sin(angle) * CAN_R
    cylinder(f"bar_{i}", bx, 0.10, bz, 0.005, CAN_H - 0.10, 4, green)

# ── Peaked lid ──
bpy.ops.mesh.primitive_cone_add(
    radius1=CAN_R + 0.02, radius2=0.03,
    depth=0.12, vertices=12,
    location=(0, CAN_H + 0.06, 0))
lid = bpy.context.active_object
lid.name = "lid"
lid.data.materials.append(green)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "WireTrashCan"

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_wire_trash_can.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
