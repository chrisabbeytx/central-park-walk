"""Generate Alexander von Humboldt bust/statue for Central Park Walk.

East side, just south of 77th St — Alexander von Humboldt (1869, Gustav Blaeser).
Bust on tall pedestal, one of the earliest sculptures in the park.
~1.5m bust on ~2.5m pedestal.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.58, 0.55, 0.50, 1.0)
bsdf.inputs["Roughness"].default_value = 0.72

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.22, 0.26, 0.18, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.44
bsdf2.inputs["Metallic"].default_value = 0.85


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


# ── Pedestal ──
box("plinth", 0, 0, 0, 0.50, 0.15, 0.50, stone)
box("shaft", 0, 0.15, 0, 0.38, 1.90, 0.38, stone)
box("cornice", 0, 2.05, 0, 0.44, 0.10, 0.44, stone)
box("top", 0, 2.15, 0, 0.40, 0.08, 0.40, stone)

# ── Bust (truncated at chest) ──
BUST_BASE = 2.23
# Chest/shoulders
cylinder("chest", 0, BUST_BASE, 0, 0.18, 0.30, 12, bronze)
bpy.context.active_object.scale = (1.2, 1.0, 0.8)
bpy.ops.object.transform_apply(scale=True)

# Neck
cylinder("neck", 0, BUST_BASE + 0.28, 0, 0.07, 0.10, 8, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.13, segments=12, ring_count=8,
    location=(0, BUST_BASE + 0.52, 0))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Humboldt"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_humboldt.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
