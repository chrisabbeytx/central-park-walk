"""Generate park info/wayfinding kiosk for Central Park Walk.

Freestanding map/information display panels at major intersections.
Two-sided panel on steel frame, ~2m tall, park green color.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

green = bpy.data.materials.new("ParkGreen")
green.use_nodes = True
bsdf = green.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.12, 0.25, 0.10, 1.0)
bsdf.inputs["Roughness"].default_value = 0.55
bsdf.inputs["Metallic"].default_value = 0.65

panel_mat = bpy.data.materials.new("MapPanel")
panel_mat.use_nodes = True
bsdf2 = panel_mat.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.85, 0.82, 0.75, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.70

steel = bpy.data.materials.new("Steel")
steel.use_nodes = True
bsdf3 = steel.node_tree.nodes["Principled BSDF"]
bsdf3.inputs["Base Color"].default_value = (0.35, 0.33, 0.30, 1.0)
bsdf3.inputs["Roughness"].default_value = 0.50
bsdf3.inputs["Metallic"].default_value = 0.85


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


# ── Base plate ──
box("base", 0, 0, 0, 0.40, 0.03, 0.20, steel)

# ── Two support posts ──
cylinder("left_post", -0.30, 0.03, 0, 0.03, 1.70, 8, green)
cylinder("right_post", 0.30, 0.03, 0, 0.03, 1.70, 8, green)

# ── Top bar connecting posts ──
box("top_bar", 0, 1.73, 0, 0.32, 0.025, 0.025, green)

# ── Map panel (large, slightly tilted) ──
box("map_panel", 0, 0.70, 0, 0.38, 0.50, 0.015, panel_mat)

# ── Header bar (dark green with "CENTRAL PARK" text area) ──
box("header", 0, 1.55, 0, 0.38, 0.08, 0.018, green)

# ── "You Are Here" marker dot ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.015, segments=8, ring_count=6,
    location=(0, 0.90, 0.018))
o = bpy.context.active_object
o.name = "marker_dot"
# Red dot
red = bpy.data.materials.new("Red")
red.use_nodes = True
bsdf4 = red.node_tree.nodes["Principled BSDF"]
bsdf4.inputs["Base Color"].default_value = (0.80, 0.10, 0.10, 1.0)
o.data.materials.append(red)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "InfoKiosk"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_info_kiosk.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
