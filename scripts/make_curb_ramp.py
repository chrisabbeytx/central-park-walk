"""Generate ADA curb ramp for Central Park Walk.

Truncated dome detectable warning panel at curb ramps.
Yellow/red tactile paving at intersection crossings.
~1.2m × 0.9m, flush transition from path to road level.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Yellow detectable warning surface
yellow = bpy.data.materials.new("Warning")
yellow.use_nodes = True
bsdf = yellow.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.75, 0.65, 0.15, 1.0)
bsdf.inputs["Roughness"].default_value = 0.80

concrete = bpy.data.materials.new("Concrete")
concrete.use_nodes = True
bsdf2 = concrete.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.65, 0.63, 0.60, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.85

W = 1.20   # width
D = 0.90   # depth
H = 0.02   # slight raised surface

# ── Base pad (concrete transition) ──
bpy.ops.mesh.primitive_cube_add(
    size=1, location=(0, H / 2, 0))
o = bpy.context.active_object
o.name = "base"
o.scale = (W + 0.10, H / 2, D + 0.10)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(concrete)

# ── Warning panel (yellow) ──
bpy.ops.mesh.primitive_cube_add(
    size=1, location=(0, H + 0.005, 0))
o = bpy.context.active_object
o.name = "panel"
o.scale = (W, 0.005, D)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(yellow)

# ── Truncated dome array (simplified as small cylinders) ──
DOME_R = 0.015
DOME_H = 0.008
DOME_SPACING = 0.06
nx = int(W / DOME_SPACING) - 1
nz = int(D / DOME_SPACING) - 1
for ix in range(nx):
    for iz in range(nz):
        dx = -W / 2 + DOME_SPACING * (ix + 1)
        dz = -D / 2 + DOME_SPACING * (iz + 1)
        bpy.ops.mesh.primitive_cylinder_add(
            radius=DOME_R, depth=DOME_H, vertices=6,
            location=(dx, H + 0.01 + DOME_H / 2, dz))
        o = bpy.context.active_object
        o.name = f"dome_{ix}_{iz}"
        o.data.materials.append(yellow)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "CurbRamp"

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_curb_ramp.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
