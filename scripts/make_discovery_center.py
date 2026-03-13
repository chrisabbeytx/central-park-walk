"""Generate Dana Discovery Center for Central Park Walk.

The Charles A. Dana Discovery Center (1993) sits on the north shore
of the Harlem Meer. A Victorian-inspired modern building that serves
as the park's northernmost visitor center.

Key features:
  - Symmetrical brick and stone facade
  - Central entrance with gabled portico
  - Large windows facing the Meer
  - Cupola/lantern on the roof ridge
  - Approximate footprint: 20m × 12m

Origin at ground center.
Exports to models/furniture/cp_discovery_center.glb
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

brick    = make_mat("Brick",    (0.55, 0.30, 0.22), 0.88)
stone    = make_mat("Stone",    (0.68, 0.64, 0.56), 0.85)
slate    = make_mat("Slate",    (0.30, 0.28, 0.26), 0.78)
glass    = make_mat("Glass",    (0.28, 0.32, 0.36), 0.12)
trim_mat = make_mat("Trim",     (0.72, 0.68, 0.60), 0.80)
copper   = make_mat("Copper",   (0.32, 0.50, 0.40), 0.60, 0.15)

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

# Dimensions
W = 20.0
D = 12.0
H = 5.0
RIDGE_H = 3.0
WALL_T = 0.35
PORTICO_W = 6.0
PORTICO_D = 3.0
PORTICO_H = 5.5

hw = W / 2.0
hd = D / 2.0

# ════════════════════════════════════════════
# 1. FOUNDATION
# ════════════════════════════════════════════
box("foundation", 0, 0, 0.18, hw + 0.2, hd + 0.2, 0.25, stone)

# ════════════════════════════════════════════
# 2. MAIN WALLS — brick with stone trim
# ════════════════════════════════════════════
# Back wall
box("wall_back", 0, -hd + WALL_T/2, H/2 + 0.30, hw, WALL_T/2, H/2, brick)
# Side walls
box("wall_east", -hw + WALL_T/2, 0, H/2 + 0.30, WALL_T/2, hd, H/2, brick)
box("wall_west",  hw - WALL_T/2, 0, H/2 + 0.30, WALL_T/2, hd, H/2, brick)
# Front wall (with window openings suggested by trim)
box("wall_front", 0, hd - WALL_T/2, H/2 + 0.30, hw, WALL_T/2, H/2, brick)

# Stone band course at mid-height
box("band_n", 0, -hd, H * 0.55 + 0.30, hw + 0.05, 0.06, 0.12, stone)
box("band_s", 0,  hd, H * 0.55 + 0.30, hw + 0.05, 0.06, 0.12, stone)
for sx in (-1, 1):
    box(f"band_{sx}", sx * hw, 0, H * 0.55 + 0.30, 0.06, hd, 0.12, stone)

# Stone quoins at corners
for cx_s in (-1, 1):
    for cy_s in (-1, 1):
        for qi in range(5):
            qz = 0.50 + qi * 0.90
            if qz > H:
                break
            box(f"quoin_{cx_s}_{cy_s}_{qi}",
                cx_s * hw, cy_s * hd, qz + 0.30,
                0.18, 0.18, 0.30, stone)

# ════════════════════════════════════════════
# 3. WINDOW TRIM — large windows on south (Meer-facing) wall
# ════════════════════════════════════════════
win_w = 1.4
win_h = 2.0
win_z = 0.30 + H * 0.35

# South-facing windows (5 bays)
for i in range(5):
    wx = -hw + 2.0 + i * (W - 4.0) / 4
    box(f"win_s_{i}", wx, hd, win_z, win_w/2 + 0.06, 0.06, win_h/2 + 0.06, trim_mat)
    # Glass
    box(f"glass_s_{i}", wx, hd - 0.02, win_z, win_w/2, 0.04, win_h/2, glass)

# Side windows (3 per side)
for sx in (-1, 1):
    for i in range(3):
        wy = -hd + 2.0 + i * (D - 4.0) / 2
        box(f"win_e_{sx}_{i}", sx * hw, wy, win_z,
            0.06, win_w/2 + 0.06, win_h/2 + 0.06, trim_mat)

# ════════════════════════════════════════════
# 4. GABLED PORTICO — central entrance on south face
# ════════════════════════════════════════════
portico_y = hd + PORTICO_D / 2

# Portico columns (4 columns)
for px in (-PORTICO_W/2 + 0.3, -PORTICO_W/6, PORTICO_W/6, PORTICO_W/2 - 0.3):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.18, depth=PORTICO_H, vertices=12,
        location=(px, hd + PORTICO_D, 0.30 + PORTICO_H / 2))
    col = bpy.context.active_object
    col.name = f"column_{px}"
    col.data.materials.append(stone)
    all_parts.append(col)

# Portico pediment (triangular gable)
ped_base = 0.30 + PORTICO_H
pv = [
    (-PORTICO_W/2 - 0.3, hd + PORTICO_D, ped_base),
    ( PORTICO_W/2 + 0.3, hd + PORTICO_D, ped_base),
    (0,                   hd + PORTICO_D, ped_base + 1.5),
]
pf = [(0, 1, 2)]
pm = bpy.data.meshes.new("pediment")
pm.from_pydata(pv, [], pf)
pm.update()
po = bpy.data.objects.new("Pediment", pm)
bpy.context.collection.objects.link(po)
po.data.materials.append(stone)
all_parts.append(po)

# Portico entablature (horizontal beam)
box("entablature", 0, hd + PORTICO_D, ped_base - 0.10,
    PORTICO_W/2 + 0.3, 0.25, 0.15, stone)

# Portico floor
box("portico_floor", 0, portico_y, 0.25, PORTICO_W/2 + 0.3, PORTICO_D/2 + 0.3, 0.10, stone)

# ════════════════════════════════════════════
# 5. MAIN ROOF — gable with cupola
# ════════════════════════════════════════════
eave_z = H + 0.30
overhang = 0.4

rv = [
    (-hw - overhang, -hd - overhang, eave_z),
    ( hw + overhang, -hd - overhang, eave_z),
    ( hw + overhang,  hd + overhang, eave_z),
    (-hw - overhang,  hd + overhang, eave_z),
    (-hw - overhang, 0, eave_z + RIDGE_H),
    ( hw + overhang, 0, eave_z + RIDGE_H),
]
rf = [
    (0, 1, 5, 4), (2, 3, 4, 5),
    (3, 0, 4), (1, 2, 5),
    (0, 3, 2, 1),
]
rm = bpy.data.meshes.new("roof_mesh")
rm.from_pydata(rv, [], rf)
rm.update()
ro = bpy.data.objects.new("MainRoof", rm)
bpy.context.collection.objects.link(ro)
ro.data.materials.append(slate)
all_parts.append(ro)

# Cupola (small lantern on ridge)
cupola_z = eave_z + RIDGE_H
bpy.ops.mesh.primitive_cylinder_add(
    radius=1.0, depth=1.5, vertices=8,
    location=(0, 0, cupola_z + 0.75))
cup = bpy.context.active_object
cup.name = "cupola_base"
cup.data.materials.append(stone)
all_parts.append(cup)

# Cupola roof (small cone)
cv = []
for i in range(8):
    a = 2 * math.pi * i / 8
    cv.append((math.cos(a) * 1.2, math.sin(a) * 1.2, cupola_z + 1.5))
cv.append((0, 0, cupola_z + 3.0))
cf = []
for i in range(8):
    cf.append((i, (i+1) % 8, 8))
cf.append(list(range(8)))
cm = bpy.data.meshes.new("cupola_roof")
cm.from_pydata(cv, [], cf)
cm.update()
co = bpy.data.objects.new("CupolaRoof", cm)
bpy.context.collection.objects.link(co)
co.data.materials.append(copper)
all_parts.append(co)


# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "DanaDiscoveryCenter"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_discovery_center.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported Dana Discovery Center to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces: {len(obj.data.polygons)}")
