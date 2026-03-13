"""Generate The Dairy visitor center for Central Park Walk.

The Dairy is a Victorian Gothic cottage designed by Calvert Vaux in 1870.
Originally dispensed fresh milk to children. Now serves as the park's
main visitor center and gift shop.

Key features:
  - Polychrome stone and timber construction
  - Steep Gothic gable roof with decorative ridge cresting
  - Open loggia/veranda along south face (Gothic arches)
  - Pointed arch windows
  - Ornamental timber brackets under eaves
  - Approximate footprint: 16m × 9m, ridge at ~10m

Origin at ground center.
Exports to models/furniture/cp_dairy.glb
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

stone_light = make_mat("StoneLt", (0.72, 0.68, 0.58), 0.85)  # warm sandstone
stone_dark  = make_mat("StoneDk", (0.42, 0.38, 0.32), 0.88)  # dark schist bands
timber      = make_mat("Timber",  (0.35, 0.25, 0.18), 0.82)  # dark stained wood
slate       = make_mat("Slate",   (0.28, 0.26, 0.24), 0.78)  # dark slate roof
trim_mat    = make_mat("Trim",    (0.65, 0.60, 0.52), 0.80)  # carved stone trim

# ── Dimensions ──
W = 16.0     # length (X)
D = 9.0      # depth (Y)
H = 5.5      # wall height to eave
RIDGE_H = 4.5 # ridge above eave (steep Gothic pitch)
WALL_T = 0.40
LOGGIA_D = 3.0  # depth of the open veranda
LOGGIA_N = 6    # number of Gothic arch bays
PIER_W = 0.45

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
box("foundation", 0, 0, 0.15, hw + 0.20, hd + LOGGIA_D/2 + 0.20, 0.30, stone_dark)

# ════════════════════════════════════════════
# 2. MAIN WALLS — polychrome stone (alternating bands)
# ════════════════════════════════════════════
n_bands = 8
band_h = H / n_bands
for i in range(n_bands):
    z = 0.30 + i * band_h + band_h / 2
    mat = stone_light if i % 2 == 0 else stone_dark
    # Back wall (north)
    box(f"wall_n_{i}", 0, -hd + WALL_T/2, z, hw, WALL_T/2, band_h/2, mat)
    # Side walls
    box(f"wall_e_{i}", -hw + WALL_T/2, 0, z, WALL_T/2, hd, band_h/2, mat)
    box(f"wall_w_{i}",  hw - WALL_T/2, 0, z, WALL_T/2, hd, band_h/2, mat)

# Front wall (south) — above loggia line
# Lower portion has pier openings; upper is solid
upper_h = H - 4.0  # solid wall above loggia arches
box("wall_s_upper", 0, hd - WALL_T/2, 4.0 + 0.30 + upper_h/2, hw, WALL_T/2, upper_h/2, stone_light)


# ════════════════════════════════════════════
# 3. LOGGIA — open Gothic arched veranda on south face
# ════════════════════════════════════════════
loggia_y = hd + LOGGIA_D / 2
arch_h = 3.8  # height of Gothic arch opening

# Loggia floor
box("loggia_floor", 0, loggia_y, 0.25, hw + 0.3, LOGGIA_D/2 + 0.3, 0.10, stone_dark)

# Loggia piers
total_bay_w = W
bay_w = total_bay_w / LOGGIA_N
for i in range(LOGGIA_N + 1):
    px = -hw + i * bay_w
    box(f"loggia_pier_{i}", px, hd + LOGGIA_D, arch_h/2 + 0.30,
        PIER_W/2, 0.25, arch_h/2, stone_light)
    # Pier capital (Gothic detail)
    box(f"pier_cap_{i}", px, hd + LOGGIA_D, arch_h + 0.30 + 0.08,
        PIER_W/2 + 0.06, 0.28, 0.10, trim_mat)

# Gothic arch keystones (pointed arch tops)
for i in range(LOGGIA_N):
    ax = -hw + (i + 0.5) * bay_w
    # Pointed arch represented by a narrow diamond-ish block
    box(f"arch_point_{i}", ax, hd + LOGGIA_D, arch_h + 0.30 + 0.35,
        bay_w * 0.25, 0.26, 0.30, trim_mat)

# Loggia back wall (front of main building within loggia)
for i in range(n_bands):
    z = 0.30 + i * band_h + band_h / 2
    if z > 4.3:
        break
    mat = stone_light if i % 2 == 0 else stone_dark
    box(f"loggia_back_{i}", 0, hd - WALL_T/2, z, hw, WALL_T/2, band_h/2, mat)

# Loggia roof (flat slab under main eave)
box("loggia_roof", 0, loggia_y, arch_h + 0.30 + 0.65,
    hw + 0.3, LOGGIA_D/2 + 0.3, 0.15, stone_dark)


# ════════════════════════════════════════════
# 4. MAIN ROOF — steep Gothic gable
# ════════════════════════════════════════════
eave_z = 0.30 + H
overhang = 0.5

rv = [
    (-hw - overhang, -hd - overhang,          eave_z),
    ( hw + overhang, -hd - overhang,          eave_z),
    ( hw + overhang,  hd + LOGGIA_D + overhang, eave_z),
    (-hw - overhang,  hd + LOGGIA_D + overhang, eave_z),
    (-hw - overhang, (LOGGIA_D)/2, eave_z + RIDGE_H),
    ( hw + overhang, (LOGGIA_D)/2, eave_z + RIDGE_H),
]
rf = [
    (0, 1, 5, 4),
    (2, 3, 4, 5),
    (3, 0, 4),
    (1, 2, 5),
    (0, 3, 2, 1),
]
rm = bpy.data.meshes.new("roof_mesh")
rm.from_pydata(rv, [], rf)
rm.update()
ro = bpy.data.objects.new("MainRoof", rm)
bpy.context.collection.objects.link(ro)
ro.data.materials.append(slate)
all_parts.append(ro)

# Gable fill (timber + stone)
for side in (-1, 1):
    gy = -hd if side < 0 else hd + LOGGIA_D
    gv = [
        (-hw + WALL_T, gy, eave_z),
        ( hw - WALL_T, gy, eave_z),
        (0,            gy, eave_z + RIDGE_H - 0.2),
    ]
    gf = [(0, 1, 2)] if side < 0 else [(0, 2, 1)]
    gm = bpy.data.meshes.new(f"gable_{side}")
    gm.from_pydata(gv, [], gf)
    gm.update()
    go = bpy.data.objects.new(f"Gable_{side}", gm)
    bpy.context.collection.objects.link(go)
    go.data.materials.append(timber)
    all_parts.append(go)


# ════════════════════════════════════════════
# 5. RIDGE CRESTING — decorative iron cresting along ridge
# ════════════════════════════════════════════
iron_mat = make_mat("Iron", (0.12, 0.11, 0.10), 0.60, 0.3)
n_crests = 10
crest_spacing = W / n_crests
for i in range(n_crests):
    cx = -hw + (i + 0.5) * crest_spacing
    box(f"crest_{i}", cx, (LOGGIA_D)/2, eave_z + RIDGE_H + 0.20,
        0.02, 0.02, 0.22, iron_mat)
    # Finial cross-piece
    box(f"crest_h_{i}", cx, (LOGGIA_D)/2, eave_z + RIDGE_H + 0.35,
        0.08, 0.02, 0.02, iron_mat)


# ════════════════════════════════════════════
# 6. GOTHIC WINDOW DETAILS — pointed arch windows on side walls
# ════════════════════════════════════════════
win_w = 0.7
win_h = 1.6
win_z = 0.30 + H * 0.42

for side_x in (-1, 1):
    wx = side_x * hw
    for wy_off in (-hd * 0.55, -hd * 0.15, hd * 0.25, hd * 0.65):
        # Window surround
        box(f"win_surr_{side_x}_{wy_off}", wx, wy_off, win_z,
            0.06, win_w/2 + 0.06, win_h/2 + 0.06, trim_mat)
        # Pointed arch top
        box(f"win_point_{side_x}_{wy_off}", wx, wy_off, win_z + win_h/2 + 0.15,
            0.06, win_w * 0.35, 0.18, trim_mat)

# Back wall windows
for wx_off in (-hw * 0.55, -hw * 0.15, hw * 0.15, hw * 0.55):
    wy = -hd
    box(f"win_n_{wx_off}", wx_off, wy, win_z,
        win_w/2 + 0.06, 0.06, win_h/2 + 0.06, trim_mat)
    box(f"win_n_pt_{wx_off}", wx_off, wy, win_z + win_h/2 + 0.15,
        win_w * 0.35, 0.06, 0.18, trim_mat)


# ════════════════════════════════════════════
# 7. TIMBER BRACKETS — decorative eave supports
# ════════════════════════════════════════════
n_brackets = 8
bracket_spacing = W / n_brackets
for i in range(n_brackets):
    bx = -hw + (i + 0.5) * bracket_spacing
    for side in (-1, 1):
        by = side * hd if side < 0 else hd + LOGGIA_D
        box(f"bracket_{side}_{i}", bx, by, eave_z - 0.15,
            0.06, 0.25, 0.30, timber)


# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

dairy = bpy.context.active_object
dairy.name = "TheDairy"

bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_dairy.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported The Dairy to {out_path}")
print(f"  Vertices: {len(dairy.data.vertices)}")
print(f"  Faces: {len(dairy.data.polygons)}")
