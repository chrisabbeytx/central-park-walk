"""Generate emergency call box for Central Park Walk.

Blue-light emergency phones on steel posts throughout Central Park.
Blue cylindrical housing with light on top, on a ~2.5m steel post.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

steel = bpy.data.materials.new("Steel")
steel.use_nodes = True
bsdf = steel.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.40, 0.38, 0.35, 1.0)
bsdf.inputs["Roughness"].default_value = 0.55
bsdf.inputs["Metallic"].default_value = 0.85

blue = bpy.data.materials.new("Blue")
blue.use_nodes = True
bsdf2 = blue.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.10, 0.20, 0.65, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.40
try:
    bsdf2.inputs["Emission Color"].default_value = (0.15, 0.25, 0.80, 1.0)
    bsdf2.inputs["Emission Strength"].default_value = 0.3
except KeyError:
    bsdf2.inputs["Emission"].default_value = (0.15, 0.25, 0.80, 1.0)


def cylinder(name, x, y, z, r, h, segs, mat):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=r, depth=h, vertices=segs,
        location=(x, y + h / 2, z))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    return o


# ── Steel post ──
cylinder("post", 0, 0, 0, 0.04, 2.30, 10, steel)

# ── Phone housing (blue box) ──
bpy.ops.mesh.primitive_cube_add(
    size=1, location=(0, 2.45, 0.06))
o = bpy.context.active_object
o.name = "housing"
o.scale = (0.15, 0.25, 0.10)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(blue)

# ── Blue light dome on top ──
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.06, segments=10, ring_count=6,
    location=(0, 2.62, 0))
o = bpy.context.active_object
o.name = "light"
o.scale = (1.0, 0.6, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(blue)

# ── Base plate ──
cylinder("base", 0, 0, 0, 0.10, 0.02, 10, steel)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "CallBox"

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_call_box.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
