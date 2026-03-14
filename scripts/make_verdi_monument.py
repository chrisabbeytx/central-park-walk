"""Generate Giuseppe Verdi Monument for Central Park Walk.

Verdi Square, Broadway at 72nd St — Giuseppe Verdi Monument (1906, Pasquale Civiletti).
Standing Verdi figure atop tall pedestal surrounded by 4 seated opera characters
(Aida, Otello, Falstaff, Leonora) at the base. Total ~7m.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

granite = bpy.data.materials.new("Granite")
granite.use_nodes = True
bsdf = granite.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.72, 0.68, 0.62, 1.0)  # white marble
bsdf.inputs["Roughness"].default_value = 0.55

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf2 = bronze.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.20, 0.24, 0.16, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.42
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


# ── Base platform (large circular) ──
cylinder("base_platform", 0, 0, 0, 2.00, 0.25, 16, granite)

# ── Central pedestal ──
box("ped_lower", 0, 0.25, 0, 0.80, 0.30, 0.80, granite)
box("ped_shaft", 0, 0.55, 0, 0.60, 3.50, 0.60, granite)
box("ped_cap", 0, 4.05, 0, 0.68, 0.12, 0.68, granite)
box("ped_top", 0, 4.17, 0, 0.64, 0.08, 0.64, granite)

# ── 4 seated opera characters at base ──
for i in range(4):
    angle = i * (math.pi / 2) + math.pi / 4
    cx = math.cos(angle) * 1.20
    cz = math.sin(angle) * 1.20
    # Seat
    box(f"seat_{i}", cx, 0.25, cz, 0.20, 0.22, 0.18, granite)
    # Seated figure body
    cylinder(f"char_body_{i}", cx, 0.47, cz, 0.08, 0.30, 6, bronze)
    # Head
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.05, segments=6, ring_count=4,
        location=(cx, 0.84, cz))
    o = bpy.context.active_object
    o.name = f"char_head_{i}"
    o.data.materials.append(bronze)

# ── Standing Verdi figure ──
FIG = 4.25
cylinder("legs", 0, FIG, 0, 0.09, 0.60, 8, bronze)

# Long coat
bpy.ops.mesh.primitive_cone_add(
    radius1=0.16, radius2=0.10,
    depth=0.45, vertices=10,
    location=(0, FIG + 0.52, 0))
o = bpy.context.active_object
o.name = "coat"
o.data.materials.append(bronze)

# Torso
cylinder("torso", 0, FIG + 0.70, 0, 0.10, 0.38, 8, bronze)

# Shoulders
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.13, segments=8, ring_count=6,
    location=(0, FIG + 1.06, 0))
o = bpy.context.active_object
o.name = "shoulders"
o.scale = (1.2, 0.5, 1.0)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Neck
cylinder("neck", 0, FIG + 1.08, 0, 0.04, 0.07, 6, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.08, segments=8, ring_count=6,
    location=(0, FIG + 1.22, 0))
o = bpy.context.active_object
o.name = "head"
o.data.materials.append(bronze)

# Top hat
cylinder("hat_brim", 0, FIG + 1.28, 0, 0.09, 0.012, 10, bronze)
cylinder("hat_crown", 0, FIG + 1.30, 0, 0.065, 0.10, 8, bronze)

# Arms
cylinder("right_arm", 0.13, FIG + 0.85, 0, 0.025, 0.30, 6, bronze)
cylinder("left_arm", -0.13, FIG + 0.85, 0, 0.025, 0.30, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "GiuseppeVerdi"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_verdi.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
