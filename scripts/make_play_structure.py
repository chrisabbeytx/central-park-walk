"""Generate playground climbing structure for Central Park Walk.

Simple play structure with platform, slide, and ladder:
- Square platform at 1.5m height with railings
- Slide on one side
- Ladder on opposite side

Exports to models/furniture/cp_play_structure.glb
"""

import bpy
import math

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

objects = []

PLAT_H = 1.5     # platform height
PLAT_W = 2.0     # platform width
PLAT_D = 2.0     # platform depth
POST_R = 0.04    # support post radius
RAIL_R = 0.025   # railing radius
RAIL_H = 0.9     # railing height above platform

# --- 4 corner posts ---
for px in [-PLAT_W/2, PLAT_W/2]:
    for pz in [-PLAT_D/2, PLAT_D/2]:
        total_h = PLAT_H + RAIL_H
        bpy.ops.mesh.primitive_cylinder_add(radius=POST_R, depth=total_h, vertices=8)
        post = bpy.context.active_object
        post.name = f"Post_{px}_{pz}"
        post.location = (px, total_h/2, pz)
        bpy.ops.object.transform_apply(location=True)
        objects.append(post)

# --- Platform floor ---
bpy.ops.mesh.primitive_cube_add(size=1)
floor = bpy.context.active_object
floor.name = "PlatformFloor"
floor.scale = (PLAT_W/2, 0.03, PLAT_D/2)
floor.location = (0, PLAT_H, 0)
bpy.ops.object.transform_apply(location=True, scale=True)
objects.append(floor)

# --- Top railings (3 sides — leave one side open for slide) ---
railing_sides = [
    (0, PLAT_D/2, PLAT_W, 0),           # back
    (-PLAT_W/2, 0, PLAT_D, math.pi/2),  # left
    (PLAT_W/2, 0, PLAT_D, math.pi/2),   # right
]
for rx, rz, length, rot in railing_sides:
    bpy.ops.mesh.primitive_cylinder_add(radius=RAIL_R, depth=length, vertices=8)
    rail = bpy.context.active_object
    rail.name = f"Rail_{rx}_{rz}"
    rail.rotation_euler = (0, rot, math.pi/2)
    rail.location = (rx, PLAT_H + RAIL_H, rz)
    bpy.ops.object.transform_apply(location=True, rotation=True)
    objects.append(rail)

# --- Slide (flat angled surface from platform front edge to ground) ---
slide_length = math.sqrt(PLAT_H**2 + 2.5**2)  # 2.5m horizontal run
slide_angle = math.atan2(PLAT_H, 2.5)
bpy.ops.mesh.primitive_cube_add(size=1)
slide = bpy.context.active_object
slide.name = "Slide"
slide.scale = (0.4, 0.015, slide_length/2)
slide.location = (0, PLAT_H/2, -PLAT_D/2 - 1.25)
slide.rotation_euler = (slide_angle, 0, 0)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
objects.append(slide)

# --- Ladder (back side, simplified as 2 rails + 5 rungs) ---
for lx in [-0.3, 0.3]:
    bpy.ops.mesh.primitive_cylinder_add(radius=0.02, depth=PLAT_H + 0.2, vertices=6)
    lrail = bpy.context.active_object
    lrail.name = f"LadderRail_{lx}"
    lrail.location = (lx, PLAT_H/2, PLAT_D/2 + 0.15)
    bpy.ops.object.transform_apply(location=True)
    objects.append(lrail)

for ri in range(5):
    ry = 0.3 + (PLAT_H - 0.3) * ri / 4
    bpy.ops.mesh.primitive_cylinder_add(radius=0.015, depth=0.6, vertices=6)
    rung = bpy.context.active_object
    rung.name = f"Rung_{ri}"
    rung.rotation_euler = (0, 0, math.pi/2)
    rung.location = (0, ry, PLAT_D/2 + 0.15)
    bpy.ops.object.transform_apply(location=True, rotation=True)
    objects.append(rung)

# --- Materials ---
steel_mat = bpy.data.materials.new("PlaySteel")
steel_mat.use_nodes = True
bsdf = steel_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.15, 0.35, 0.55, 1.0)  # blue painted steel
bsdf.inputs["Metallic"].default_value = 0.6
bsdf.inputs["Roughness"].default_value = 0.5

slide_mat = bpy.data.materials.new("SlideSteel")  
slide_mat.use_nodes = True
bsdf2 = slide_mat.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.55, 0.55, 0.50, 1.0)  # stainless
bsdf2.inputs["Metallic"].default_value = 0.9
bsdf2.inputs["Roughness"].default_value = 0.25

for obj in objects:
    obj.data.materials.clear()
    if "Slide" in obj.name:
        obj.data.materials.append(slide_mat)
    elif "PlatformFloor" in obj.name:
        obj.data.materials.append(slide_mat)
    else:
        obj.data.materials.append(steel_mat)

# Join
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.join()
obj = bpy.context.active_object
obj.name = "PlayStructure"

out_path = "/home/chris/central-park-walk/models/furniture/cp_play_structure.glb"
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB')
vcount = len(obj.data.vertices)
fcount = len(obj.data.polygons)
print(f"Exported Play Structure to {out_path} ({vcount} verts, {fcount} faces)")
