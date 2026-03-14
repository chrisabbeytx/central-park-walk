"""Generate Giuseppe Mazzini bust for Central Park Walk.

West Drive near 67th St — Giuseppe Mazzini (1878, Giovanni Turini).
Bronze bust of Italian patriot on tall granite pedestal.
Total ~4m (2.5m pedestal + 1.5m bust).
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

granite = bpy.data.materials.new("Granite")
granite.use_nodes = True
bsdf = granite.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.50, 0.48, 0.44, 1.0)
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
box("base_step", 0, 0, 0, 0.55, 0.15, 0.55, granite)
box("ped_shaft", 0, 0.15, 0, 0.40, 2.00, 0.40, granite)
box("ped_cornice", 0, 2.15, 0, 0.46, 0.10, 0.46, granite)
box("ped_top", 0, 2.25, 0, 0.42, 0.08, 0.42, granite)

# ── Bust ──
BUST_BASE = 2.33
# Chest
cylinder("chest", 0, BUST_BASE, 0, 0.18, 0.30, 12, bronze)
bpy.context.active_object.scale = (1.2, 1.0, 0.8)
bpy.ops.object.transform_apply(scale=True)

# Neck
cylinder("neck", 0, BUST_BASE + 0.28, 0, 0.06, 0.10, 8, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.12, segments=12, ring_count=8,
    location=(0, BUST_BASE + 0.50, 0))
head = bpy.context.active_object
head.name = "head"
head.data.materials.append(bronze)

# Hair (receding)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.10, segments=8, ring_count=6,
    location=(0, BUST_BASE + 0.55, -0.03))
o = bpy.context.active_object
o.name = "hair"
o.data.materials.append(bronze)

# Beard
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.06, segments=6, ring_count=4,
    location=(0, BUST_BASE + 0.42, 0.08))
o = bpy.context.active_object
o.name = "beard"
o.scale = (0.8, 1.0, 0.6)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "GiuseppeMazzini"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_mazzini.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
