"""Generate playground swing set for Central Park Walk.

Simple A-frame swing set with 2 swings:
- Two A-frame end supports (galvanized steel pipe)
- Top crossbar
- 2 swing seats on chains (simplified)

Exports to models/furniture/cp_swing_set.glb
"""

import bpy
import math

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

objects = []

FRAME_H = 2.5    # 8ft tall
FRAME_W = 3.0    # total width
LEG_SPREAD = 1.8 # A-frame base spread
PIPE_R = 0.03    # steel pipe radius
SEAT_W = 0.4     # swing seat width
CHAIN_R = 0.008

# --- A-frame legs (4 legs total, 2 per end) ---
for end_x in [-FRAME_W/2, FRAME_W/2]:
    for spread in [-LEG_SPREAD/2, LEG_SPREAD/2]:
        # Leg from ground to top
        length = math.sqrt(FRAME_H**2 + (LEG_SPREAD/2)**2)
        angle = math.atan2(spread, FRAME_H)
        
        bpy.ops.mesh.primitive_cylinder_add(radius=PIPE_R, depth=length, vertices=8)
        leg = bpy.context.active_object
        leg.name = f"Leg_{end_x}_{spread}"
        leg.location = (end_x, FRAME_H/2, spread/2)
        leg.rotation_euler = (angle, 0, 0)
        bpy.ops.object.transform_apply(location=True, rotation=True)
        objects.append(leg)

# --- Top crossbar ---
bpy.ops.mesh.primitive_cylinder_add(radius=PIPE_R, depth=FRAME_W, vertices=8)
bar = bpy.context.active_object
bar.name = "Crossbar"
bar.rotation_euler = (0, 0, math.pi/2)
bar.location = (0, FRAME_H, 0)
bpy.ops.object.transform_apply(location=True, rotation=True)
objects.append(bar)

# --- Swing seats (2) ---
for sx in [-0.6, 0.6]:
    # Seat (flat rectangle)
    bpy.ops.mesh.primitive_cube_add(size=1)
    seat = bpy.context.active_object
    seat.name = f"Seat_{sx}"
    seat.scale = (SEAT_W/2, 0.01, 0.15)
    seat.location = (sx, 0.45, 0)
    bpy.ops.object.transform_apply(location=True, scale=True)
    objects.append(seat)
    
    # Chains (2 per seat — simplified as thin cylinders)
    for cz in [-0.12, 0.12]:
        chain_h = FRAME_H - 0.45
        bpy.ops.mesh.primitive_cylinder_add(radius=CHAIN_R, depth=chain_h, vertices=4)
        chain = bpy.context.active_object
        chain.name = f"Chain_{sx}_{cz}"
        chain.location = (sx, 0.45 + chain_h/2, cz)
        bpy.ops.object.transform_apply(location=True)
        objects.append(chain)

# --- Material: galvanized steel ---
mat = bpy.data.materials.new("GalvanizedSteel")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.45, 0.45, 0.42, 1.0)
bsdf.inputs["Metallic"].default_value = 0.8
bsdf.inputs["Roughness"].default_value = 0.55

# Seat material — dark rubber
seat_mat = bpy.data.materials.new("RubberSeat")
seat_mat.use_nodes = True
bsdf2 = seat_mat.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.08, 0.08, 0.08, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.9

for obj in objects:
    obj.data.materials.clear()
    if "Seat" in obj.name:
        obj.data.materials.append(seat_mat)
    else:
        obj.data.materials.append(mat)

# Join
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.join()
obj = bpy.context.active_object
obj.name = "SwingSet"

out_path = "/home/chris/central-park-walk/models/furniture/cp_swing_set.glb"
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB')
vcount = len(obj.data.vertices)
fcount = len(obj.data.polygons)
print(f"Exported Swing Set to {out_path} ({vcount} verts, {fcount} faces)")
