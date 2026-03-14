"""Generate The Pilgrim statue for Central Park Walk.

East 72nd St near Fifth Ave — The Pilgrim (1885, John Quincy Adams Ward).
Standing bronze Puritan figure in wide-brimmed hat, long coat, holding Bible,
on granite pedestal with bas-relief. Total ~4.5m.
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


# ── Pedestal ──
box("base_step", 0, 0, 0, 0.75, 0.18, 0.75, granite)
box("base_2", 0, 0.18, 0, 0.65, 0.12, 0.65, granite)
box("ped_shaft", 0, 0.30, 0, 0.50, 2.00, 0.50, granite)
box("ped_cornice", 0, 2.30, 0, 0.56, 0.10, 0.56, granite)
box("ped_top", 0, 2.40, 0, 0.52, 0.08, 0.52, granite)

# ── Standing figure ──
FIG = 2.48
# Legs
cylinder("right_leg", 0.05, FIG, 0.03, 0.04, 0.58, 8, bronze)
cylinder("left_leg", -0.04, FIG, -0.02, 0.04, 0.55, 8, bronze)

# Long Puritan coat
bpy.ops.mesh.primitive_cone_add(
    radius1=0.20, radius2=0.10,
    depth=0.55, vertices=10,
    location=(0, FIG + 0.55, 0))
o = bpy.context.active_object
o.name = "coat"
o.data.materials.append(bronze)

# Torso
cylinder("torso", 0, FIG + 0.75, 0, 0.10, 0.38, 8, bronze)

# Shoulders with cape
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.14, segments=8, ring_count=6,
    location=(0, FIG + 1.10, 0))
o = bpy.context.active_object
o.name = "shoulders"
o.scale = (1.3, 0.5, 1.1)
bpy.ops.object.transform_apply(scale=True)
o.data.materials.append(bronze)

# Neck
cylinder("neck", 0, FIG + 1.12, 0, 0.035, 0.07, 6, bronze)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.07, segments=8, ring_count=6,
    location=(0, FIG + 1.26, 0))
o = bpy.context.active_object
o.name = "head"
o.data.materials.append(bronze)

# Wide-brimmed Puritan hat
cylinder("hat_brim", 0, FIG + 1.32, 0, 0.14, 0.015, 12, bronze)
cylinder("hat_crown", 0, FIG + 1.34, 0, 0.07, 0.08, 8, bronze)

# Left arm (holding Bible close to body)
cylinder("left_arm", -0.12, FIG + 0.88, 0, 0.025, 0.30, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.3)
bpy.ops.object.transform_apply(rotation=True)

# Bible
box("bible", -0.14, FIG + 0.75, 0.05, 0.04, 0.06, 0.03, bronze)

# Right arm (walking stick/staff)
cylinder("right_arm", 0.12, FIG + 0.90, 0, 0.025, 0.32, 6, bronze)

# Walking staff
cylinder("staff", 0.16, FIG, 0.05, 0.012, 1.15, 4, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "ThePilgrim"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_pilgrim.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
