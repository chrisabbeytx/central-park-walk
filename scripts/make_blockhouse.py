"""Generate Blockhouse No. 1 for Central Park Walk.

Blockhouse No. 1 (1814) is the oldest structure in Central Park,
a War of 1812 fortification on a rocky bluff in the northwest
corner of the park. Built of local schist with thick rubble walls.

Key features:
  - Rough rectangular stone blockhouse (~8m × 6m)
  - Thick rubble walls (~1m) with gun slits
  - Low profile, no roof (ruins)
  - Entrance through narrow doorway
  - Sits on exposed rock outcrop

Origin at ground center.
Exports to models/furniture/cp_blockhouse.glb
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

def make_mat(name, color, roughness=0.85, metallic=0.0):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m

schist = make_mat("Schist", (0.38, 0.36, 0.33), 0.92)  # rough dark stone
mortar = make_mat("Mortar", (0.52, 0.50, 0.46), 0.88)   # lighter mortar joints

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

W = 8.0     # length (X)
D = 6.0     # depth (Y)
H = 3.5     # wall height (remaining — originally taller)
T = 1.0     # wall thickness (fortification-grade)

hw = W / 2.0
hd = D / 2.0

# ════════════════════════════════════════════
# 1. FOUNDATION — exposed rock base
# ════════════════════════════════════════════
# Irregular rock platform (slightly larger than building)
box("rock_base", 0, 0, -0.3, hw + 1.5, hd + 1.5, 0.45, schist)
# Second irregular rock layer
box("rock_base2", 0.5, -0.3, -0.6, hw + 0.8, hd + 0.8, 0.30, schist)

# ════════════════════════════════════════════
# 2. THICK RUBBLE WALLS
# ════════════════════════════════════════════
# Front wall with narrow doorway
door_w = 0.9
left_w = (W - door_w) / 2
box("wall_front_l", -(door_w/2 + left_w/2), hd - T/2, H/2,
    left_w/2, T/2, H/2, schist)
box("wall_front_r",  (door_w/2 + left_w/2), hd - T/2, H/2,
    left_w/2, T/2, H/2, schist)
# Lintel above door
box("wall_front_top", 0, hd - T/2, 2.2 + (H - 2.2)/2,
    door_w/2, T/2, (H - 2.2)/2, schist)

# Back wall (solid)
box("wall_back", 0, -hd + T/2, H/2, hw, T/2, H/2, schist)

# Side walls
box("wall_left",  -hw + T/2, 0, H/2, T/2, hd, H/2, schist)
box("wall_right",  hw - T/2, 0, H/2, T/2, hd, H/2, schist)

# ════════════════════════════════════════════
# 3. GUN SLITS — narrow vertical openings in walls
# ════════════════════════════════════════════
slit_w = 0.10
slit_h = 0.6
slit_z = H * 0.55

# Slits on side walls (3 per side)
for side in (-1, 1):
    wx = side * (hw - T * 0.3)
    for i in range(3):
        sy = -hd + 1.5 + i * (D - 3.0) / 2
        # Slit represented as a thin darker strip
        box(f"slit_{side}_{i}", wx, sy, slit_z,
            0.12, slit_w, slit_h, mortar)

# Back wall slits
for i in range(2):
    sx = -hw + 2.5 + i * (W - 5.0)
    box(f"slit_back_{i}", sx, -hd + T * 0.3, slit_z,
        slit_w, 0.12, slit_h, mortar)

# ════════════════════════════════════════════
# 4. WALL CAP — rough stone cap (ruins, not intact)
# ════════════════════════════════════════════
# Irregular top surface — some sections higher than others
for i in range(6):
    cx = -hw + T + i * (W - 2*T) / 5
    for side_y in (-1, 1):
        cy = side_y * (hd - T/2)
        cap_h = H + (math.sin(i * 2.3 + side_y) * 0.3)
        box(f"cap_{i}_{side_y}", cx, cy, cap_h + 0.12,
            (W - 2*T) / 10 + 0.1, T/2 + 0.05, 0.15, schist)

# Side wall caps
for i in range(4):
    cy = -hd + T + i * (D - 2*T) / 3
    for side_x in (-1, 1):
        cx = side_x * (hw - T/2)
        cap_h = H + (math.sin(i * 1.7 + side_x * 3) * 0.25)
        box(f"cap_side_{i}_{side_x}", cx, cy, cap_h + 0.12,
            T/2 + 0.05, (D - 2*T) / 6 + 0.1, 0.15, schist)


# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "Blockhouse"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_blockhouse.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported Blockhouse No. 1 to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces: {len(obj.data.polygons)}")
