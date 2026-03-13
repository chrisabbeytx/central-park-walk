"""Generate Swedish Cottage Marionette Theatre for Central Park Walk.

The Swedish Cottage is a traditional Swedish timber schoolhouse, originally
built for the 1876 Centennial Exposition in Philadelphia. Moved to Central
Park in 1877. Now houses the Marionette Theatre.

Key features:
  - Scandinavian log cabin construction (stained dark brown timber)
  - Steep gable roof with decorative bargeboard
  - Cross-gable entry porch
  - Stone foundation
  - White-painted window trim
  - Approximate footprint: 12m × 8m, ridge at ~8m

Origin at ground center.
Exports to models/furniture/cp_swedish_cottage.glb
"""

import bpy
import math
import os
from mathutils import Vector

# ── Clear scene ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# ── Materials ──
def make_mat(name, color, roughness=0.85, metallic=0.0):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m

timber    = make_mat("Timber",    (0.28, 0.18, 0.12), 0.88)   # dark stained wood
roof_mat  = make_mat("RoofTile",  (0.22, 0.16, 0.14), 0.82)   # dark brown shingles
stone     = make_mat("Stone",     (0.50, 0.48, 0.44), 0.87)   # foundation stone
trim_mat  = make_mat("WoodTrim",  (0.80, 0.76, 0.68), 0.75)   # white-painted trim

# ── Dimensions ──
W = 12.0     # length (X)
D = 8.0      # depth (Y)
H = 4.5      # wall height to eave
RIDGE_H = 3.5 # ridge above eave
WALL_T = 0.30
PORCH_W = 4.0
PORCH_D = 2.5
PORCH_H = 3.0

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o


hw = W / 2.0
hd = D / 2.0

# ════════════════════════════════════════════
# 1. FOUNDATION
# ════════════════════════════════════════════
box("foundation", 0, 0, 0.15, hw + 0.15, hd + 0.15, 0.30, stone)

# ════════════════════════════════════════════
# 2. LOG WALLS
# ════════════════════════════════════════════
# Simulate log courses with horizontal planks (visible texture)
n_courses = 12
course_h = H / n_courses
for i in range(n_courses):
    z = 0.30 + i * course_h + course_h / 2
    inset = 0.02 if i % 2 == 0 else 0.0  # subtle log course offset
    # Front and back walls
    box(f"log_f_{i}", 0,  hd - WALL_T/2 - inset, z, hw, WALL_T/2, course_h/2, timber)
    box(f"log_b_{i}", 0, -hd + WALL_T/2 + inset, z, hw, WALL_T/2, course_h/2, timber)
    # Side walls
    box(f"log_l_{i}", -hw + WALL_T/2 + inset, 0, z, WALL_T/2, hd, course_h/2, timber)
    box(f"log_r_{i}",  hw - WALL_T/2 - inset, 0, z, WALL_T/2, hd, course_h/2, timber)

# Corner notch details (overlapping log ends)
for cx_s in (-1, 1):
    for cy_s in (-1, 1):
        for i in range(0, n_courses, 2):
            z = 0.30 + i * course_h + course_h / 2
            # Protruding log end on alternating corners
            box(f"notch_{cx_s}_{cy_s}_{i}",
                cx_s * (hw + 0.08), cy_s * (hd - WALL_T * 0.3), z,
                0.12, WALL_T * 0.4, course_h/2, timber)

# ════════════════════════════════════════════
# 3. GABLE ROOF — steep Scandinavian pitch
# ════════════════════════════════════════════
eave_z = 0.30 + H
overhang = 0.6

rv = [
    (-hw - overhang, -hd - overhang, eave_z),      # 0
    ( hw + overhang, -hd - overhang, eave_z),      # 1
    ( hw + overhang,  hd + overhang, eave_z),      # 2
    (-hw - overhang,  hd + overhang, eave_z),      # 3
    (-hw - overhang, 0, eave_z + RIDGE_H),          # 4 ridge left
    ( hw + overhang, 0, eave_z + RIDGE_H),          # 5 ridge right
]
rf = [
    (0, 1, 5, 4),  # front slope
    (2, 3, 4, 5),  # back slope
    (3, 0, 4),     # left gable
    (1, 2, 5),     # right gable
    (0, 3, 2, 1),  # soffit
]
rmesh = bpy.data.meshes.new("roof_mesh")
rmesh.from_pydata(rv, [], rf)
rmesh.update()
robj = bpy.data.objects.new("Roof", rmesh)
bpy.context.collection.objects.link(robj)
robj.data.materials.append(roof_mat)
all_parts.append(robj)

# Gable wall fill (timber triangles above eave)
for side in (-1, 1):
    gv = [
        (-hw + WALL_T, side * (hd - WALL_T), eave_z),
        ( hw - WALL_T, side * (hd - WALL_T), eave_z),
        (0,            side * (hd - WALL_T), eave_z + RIDGE_H - 0.15),
    ]
    gf = [(0, 1, 2)] if side < 0 else [(0, 2, 1)]
    gm = bpy.data.meshes.new(f"gable_{side}")
    gm.from_pydata(gv, [], gf)
    gm.update()
    go = bpy.data.objects.new(f"Gable_{side}", gm)
    bpy.context.collection.objects.link(go)
    go.data.materials.append(timber)
    all_parts.append(go)

# Ridge board
box("ridge", 0, 0, eave_z + RIDGE_H + 0.04, hw + overhang, 0.04, 0.06, timber)


# ════════════════════════════════════════════
# 4. DECORATIVE BARGEBOARD — scalloped trim along gable edges
# ════════════════════════════════════════════
# Simplified as trim strips along the roof edge
for side in (-1, 1):
    gy = side * (hd + overhang * 0.7)
    # Left slope trim
    box(f"barge_l_{side}", -hw/2 - overhang * 0.3, gy,
        eave_z + RIDGE_H * 0.5 - 0.3,
        hw/2 * 0.7, 0.03, 0.08, trim_mat)
    # Right slope trim
    box(f"barge_r_{side}",  hw/2 + overhang * 0.3, gy,
        eave_z + RIDGE_H * 0.5 - 0.3,
        hw/2 * 0.7, 0.03, 0.08, trim_mat)


# ════════════════════════════════════════════
# 5. ENTRY PORCH — cross-gable front porch
# ════════════════════════════════════════════
porch_y = hd + PORCH_D / 2
porch_eave = 0.30 + PORCH_H
porch_ridge_h = 1.8

# Porch posts
for px in (-PORCH_W/2 + 0.15, PORCH_W/2 - 0.15):
    box(f"porch_post_{px}", px, hd + PORCH_D - 0.15, porch_eave/2,
        0.10, 0.10, porch_eave/2, timber)

# Porch floor
box("porch_floor", 0, porch_y, 0.25, PORCH_W/2, PORCH_D/2, 0.10, stone)

# Porch roof
pv = [
    (-PORCH_W/2 - 0.3, hd - 0.1,          porch_eave),
    ( PORCH_W/2 + 0.3, hd - 0.1,          porch_eave),
    ( PORCH_W/2 + 0.3, hd + PORCH_D + 0.3, porch_eave),
    (-PORCH_W/2 - 0.3, hd + PORCH_D + 0.3, porch_eave),
    (0, hd - 0.1,          porch_eave + porch_ridge_h),
    (0, hd + PORCH_D + 0.3, porch_eave + porch_ridge_h),
]
pf = [
    (3, 2, 5, 4),  # left slope (east)
    (0, 1, 5, 4),  # right slope (west) — need to fix winding
    (0, 3, 4),     # front gable
    (2, 1, 5),     # back gable
    (0, 1, 2, 3),  # soffit
]
pm = bpy.data.meshes.new("porch_roof_mesh")
pm.from_pydata(pv, [], pf)
pm.update()
po = bpy.data.objects.new("PorchRoof", pm)
bpy.context.collection.objects.link(po)
po.data.materials.append(roof_mat)
all_parts.append(po)

# ════════════════════════════════════════════
# 6. WINDOW TRIM — white-painted frames
# ════════════════════════════════════════════
win_w = 0.8
win_h = 1.2
win_z = 0.30 + H * 0.45  # window center height

# Windows on each side wall
for side_y in (-1, 1):
    wy = side_y * hd
    for wx in (-hw * 0.5, 0, hw * 0.5):
        # Frame (4 strips)
        box(f"win_t_{side_y}_{wx}", wx, wy, win_z + win_h/2 + 0.04, win_w/2 + 0.04, 0.04, 0.05, trim_mat)
        box(f"win_b_{side_y}_{wx}", wx, wy, win_z - win_h/2 - 0.04, win_w/2 + 0.04, 0.04, 0.05, trim_mat)
        box(f"win_l_{side_y}_{wx}", wx - win_w/2 - 0.04, wy, win_z, 0.04, 0.04, win_h/2, trim_mat)
        box(f"win_r_{side_y}_{wx}", wx + win_w/2 + 0.04, wy, win_z, 0.04, 0.04, win_h/2, trim_mat)

# Windows on side walls (east/west)
for side_x in (-1, 1):
    wx = side_x * hw
    for wy in (-hd * 0.35, hd * 0.35):
        box(f"win_t_s_{side_x}_{wy}", wx, wy, win_z + win_h/2 + 0.04, 0.04, win_w/2 + 0.04, 0.05, trim_mat)
        box(f"win_b_s_{side_x}_{wy}", wx, wy, win_z - win_h/2 - 0.04, 0.04, win_w/2 + 0.04, 0.05, trim_mat)


# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

cottage = bpy.context.active_object
cottage.name = "SwedishCottage"

bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_swedish_cottage.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported Swedish Cottage to {out_path}")
print(f"  Vertices: {len(cottage.data.vertices)}")
print(f"  Faces: {len(cottage.data.polygons)}")
