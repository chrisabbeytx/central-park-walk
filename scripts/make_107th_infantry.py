"""Generate 107th Infantry Memorial for Central Park Walk.

Fifth Avenue and 67th St — 107th Infantry Memorial (1927, Karl Illava).
Seven bronze soldiers advancing through battle over rocky terrain.
One of the most dramatic war memorials in any American park.
~3.5m high on a natural stone base ~1.5m.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

stone = bpy.data.materials.new("Stone")
stone.use_nodes = True
bsdf = stone.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.45, 0.42, 0.38, 1.0)
bsdf.inputs["Roughness"].default_value = 0.80

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.18, 0.22, 0.14, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.40
bsdf2.inputs["Metallic"].default_value = 0.85


def box(name, x, y, z, sx, sy, sz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y + sy, z))
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx * 2, sy * 2, sz * 2)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)


def cylinder(name, x, y, z, r, h, segs, mat):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=r, depth=h, vertices=segs,
        location=(x, y + h / 2, z))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)


# ── Rocky base (natural Manhattan schist) ──
bpy.ops.mesh.primitive_ico_sphere_add(
    radius=1.5, subdivisions=2,
    location=(0, 0.6, 0))
base = bpy.context.active_object
base.name = "rock_base"
base.scale = (1.8, 0.45, 1.0)
bpy.ops.object.transform_apply(scale=True)
base.data.materials.append(stone)

# ── Seven advancing soldiers (simplified as figure silhouettes) ──
# Staggered across the rocky base, advancing forward
positions = [
    (-1.2, 1.0, -0.3, 0.2),   # leftmost, slightly crouched
    (-0.7, 1.1, -0.1, -0.1),  # second
    (-0.2, 1.2, 0.0, 0.0),    # center-left
    (0.2, 1.3, 0.1, 0.15),    # center (tallest, leader)
    (0.7, 1.1, 0.0, -0.2),    # center-right
    (1.0, 1.0, -0.2, 0.1),    # second-right
    (1.3, 0.9, -0.3, -0.15),  # rightmost, lower
]

for i, (fx, fy, fz, lean) in enumerate(positions):
    # Each soldier: legs + torso + head + arms + rifle
    h_var = 0.85 + (i % 3) * 0.08  # slight height variation

    # Legs
    cylinder(f"legs_{i}", fx, fy, fz, 0.10, 0.70 * h_var, 8, bronze)
    bpy.context.active_object.rotation_euler = (lean * 0.5, 0, lean)
    bpy.ops.object.transform_apply(rotation=True)

    # Torso
    cylinder(f"torso_{i}", fx, fy + 0.65 * h_var, fz - lean * 0.1,
             0.12, 0.50 * h_var, 8, bronze)
    bpy.context.active_object.rotation_euler = (lean, 0, lean * 0.3)
    bpy.ops.object.transform_apply(rotation=True)

    # Head (with helmet)
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.09, segments=8, ring_count=6,
        location=(fx, fy + 1.25 * h_var, fz - lean * 0.15))
    head = bpy.context.active_object
    head.name = f"head_{i}"
    head.data.materials.append(bronze)

    # Helmet brim
    cylinder(f"helmet_{i}", fx, fy + 1.30 * h_var, fz - lean * 0.15,
             0.10, 0.03, 8, bronze)

    # Rifle (thin cylinder, angled)
    cylinder(f"rifle_{i}", fx + 0.08, fy + 0.70 * h_var, fz + 0.12,
             0.015, 0.80, 6, bronze)
    bpy.context.active_object.rotation_euler = (-0.5 + lean, 0.1, 0)
    bpy.ops.object.transform_apply(rotation=True)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "Infantry107"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_107th_infantry.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
