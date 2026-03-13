"""Generate Tavern on the Green for Central Park Walk.

Tavern on the Green was originally the sheepfold (1870, Calvert Vaux),
converted to a restaurant in 1934. The current building is a sprawling
single-story structure with multiple connected pavilions, large glass
walls (crystal room), and a garden courtyard.

Key features:
  - L-shaped main building (~40m × 25m)
  - Crystal Room: glass-walled dining pavilion
  - Stone/stucco exterior walls
  - Flat and low-pitched roofs
  - Garden terrace with string lights
  - Approximate footprint: 40m × 25m

Origin at ground center.
Exports to models/furniture/cp_tavern.glb
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

stucco   = make_mat("Stucco",  (0.78, 0.74, 0.66), 0.88)
stone    = make_mat("Stone",   (0.52, 0.50, 0.46), 0.86)
glass    = make_mat("Glass",   (0.28, 0.32, 0.35), 0.12)
copper   = make_mat("Copper",  (0.30, 0.48, 0.38), 0.60, 0.15)
wood     = make_mat("Wood",    (0.40, 0.30, 0.20), 0.82)

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

# ════════════════════════════════════════════
# 1. MAIN BUILDING — L-shaped restaurant
# ════════════════════════════════════════════
MAIN_H = 4.5

# East wing (main dining)
box("east_wing", 8, 0, MAIN_H/2, 12, 6, MAIN_H/2, stucco)
# West wing
box("west_wing", -8, -4, MAIN_H/2, 8, 4, MAIN_H/2, stucco)
# Connection
box("connector", 0, -2, MAIN_H/2, 4, 5, MAIN_H/2, stucco)

# ════════════════════════════════════════════
# 2. CRYSTAL ROOM — glass-walled pavilion
# ════════════════════════════════════════════
CR_H = 5.0
cr_x = 8.0
cr_y = 8.0

# Glass walls
box("crystal_n", cr_x, cr_y + 4, CR_H/2, 6, 0.08, CR_H/2, glass)
box("crystal_s", cr_x, cr_y - 4, CR_H/2, 6, 0.08, CR_H/2, glass)
box("crystal_e", cr_x + 6, cr_y, CR_H/2, 0.08, 4, CR_H/2, glass)
# Stone piers at corners
for px in (-1, 1):
    for py in (-1, 1):
        box(f"crystal_pier_{px}_{py}",
            cr_x + px * 6, cr_y + py * 4, CR_H/2,
            0.20, 0.20, CR_H/2, stone)
# Crystal room roof
box("crystal_roof", cr_x, cr_y, CR_H + 0.15, 6.5, 4.5, 0.18, copper)

# ════════════════════════════════════════════
# 3. ROOFS — low flat/hip profiles
# ════════════════════════════════════════════
# Main east wing roof
box("roof_east", 8, 0, MAIN_H + 0.15, 12.5, 6.5, 0.20, copper)
# West wing roof
box("roof_west", -8, -4, MAIN_H + 0.15, 8.5, 4.5, 0.20, copper)
# Connector roof
box("roof_conn", 0, -2, MAIN_H + 0.15, 4.5, 5.5, 0.15, copper)

# ════════════════════════════════════════════
# 4. GARDEN TERRACE — paved area with low wall
# ════════════════════════════════════════════
box("terrace_floor", 0, 10, 0.08, 15, 5, 0.12, stone)

# Low garden wall
box("garden_wall_n", 0, 15, 0.45, 15, 0.20, 0.40, stone)
box("garden_wall_e", 15, 10, 0.45, 0.20, 5, 0.40, stone)
box("garden_wall_w", -15, 10, 0.45, 0.20, 5, 0.40, stone)

# Entrance canopy
box("canopy", -8, -8.5, 3.2, 3.0, 1.5, 0.12, copper)
# Canopy posts
for px in (-1, 1):
    box(f"canopy_post_{px}", -8 + px * 2.5, -9.5, 1.6,
        0.08, 0.08, 1.6, stone)

# Foundation
box("foundation", 0, 0, -0.10, 20.5, 10.5, 0.15, stone)


# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "TavernOnTheGreen"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_tavern.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported Tavern on the Green to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces: {len(obj.data.polygons)}")
