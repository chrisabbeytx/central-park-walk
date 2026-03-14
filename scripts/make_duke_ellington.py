"""Generate Duke Ellington Memorial for Central Park Walk.

Fifth Ave at 110th St (Duke Ellington Circle) — Duke Ellington (1997, Robert Graham).
Standing figure of Duke Ellington with piano, elevated on three columns
representing the three Graces (muses). Total ~7.6m (columns 3m + figure 2m + piano platform).
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


# ── Base platform (circular) ──
cylinder("base", 0, 0, 0, 1.60, 0.25, 16, granite)

# ── Three support columns (Graces) ──
for i in range(3):
    angle = i * (2 * math.pi / 3)
    cx = math.cos(angle) * 0.80
    cz = math.sin(angle) * 0.80
    cylinder(f"column_{i}", cx, 0.25, cz, 0.15, 3.00, 10, bronze)
    # Column figure (Grace/muse - simplified as cylinder with sphere head)
    cylinder(f"grace_body_{i}", cx, 0.40, cz, 0.10, 1.20, 8, bronze)
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.07, segments=8, ring_count=6,
        location=(cx, 1.72, cz))
    o = bpy.context.active_object
    o.name = f"grace_head_{i}"
    o.data.materials.append(bronze)

# ── Upper platform ──
cylinder("upper_platform", 0, 3.25, 0, 1.20, 0.15, 16, granite)

# ── Piano ──
PLAT = 3.40
box("piano_body", -0.30, PLAT, 0, 0.60, 0.35, 0.45, bronze)
# Piano lid (raised)
box("piano_lid", -0.30, PLAT + 0.35, 0, 0.58, 0.02, 0.44, bronze)
# Piano legs
for pos in [(-0.75, -0.35), (-0.75, 0.35), (0.10, 0)]:
    cylinder(f"piano_leg_{pos}", pos[0], PLAT, pos[1], 0.03, 0.02, 6, bronze)

# ── Duke Ellington figure (standing next to piano) ──
FIG = PLAT
# Legs
cylinder("legs", 0.40, FIG, 0, 0.08, 0.70, 8, bronze)
# Torso (suit)
cylinder("torso", 0.40, FIG + 0.65, 0, 0.10, 0.45, 8, bronze)
# Head
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=0.08, segments=8, ring_count=6,
    location=(0.40, FIG + 1.22, 0))
o = bpy.context.active_object
o.name = "head"
o.data.materials.append(bronze)

# Right arm (extended toward piano)
cylinder("right_arm", 0.30, FIG + 0.90, -0.05, 0.03, 0.35, 6, bronze)
bpy.context.active_object.rotation_euler = (0, 0, 0.5)
bpy.ops.object.transform_apply(rotation=True)

# Left arm
cylinder("left_arm", 0.50, FIG + 0.90, 0, 0.03, 0.30, 6, bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "DukeEllington"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_duke_ellington.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
