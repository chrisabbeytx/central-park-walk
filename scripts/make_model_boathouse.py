"""Generate Kerbs Model Boathouse for Central Park Walk.

The Kerbs Model Boathouse (1954) is a small classical-style pavilion
on the west shore of Conservatory Water where model boats are rented
and sailed.  White-painted wood construction on a stone base with a
low copper hip roof and a full-width service counter facing the pond.

Key features:
  - Rectangular building ~8m × 5m
  - Classical style, white/cream painted wood
  - Low hip roof with copper/green patina
  - Full-width service window/counter on east (pond-facing) front
  - Decorative cornice band under eave
  - ~3.5m wall height
  - Raised stone base (~0.4m)
  - Shuttered window bays on north and south sides
  - Solid back (west) wall

Coordinate convention:
  +X = south,  -X = north,  +Y = east (pond side),  -Y = west (back)
  Z up.  Origin at ground center.

Exports to models/furniture/cp_model_boathouse.glb
"""

import bpy
import math
import os

# ── Clear scene ──────────────────────────────────────────────────────────────
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# ── Materials ─────────────────────────────────────────────────────────────────
def make_mat(name, color, roughness=0.85, metallic=0.0):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m

cream      = make_mat("Cream",      (0.85, 0.82, 0.75), roughness=0.75)
stone      = make_mat("Stone",      (0.55, 0.52, 0.48), roughness=0.85)
copper_roof= make_mat("CopperRoof", (0.35, 0.50, 0.42), roughness=0.65, metallic=0.3)
trim       = make_mat("Trim",       (0.40, 0.38, 0.35), roughness=0.78)

# ── Helpers ───────────────────────────────────────────────────────────────────
all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    """Add a box at centre (cx,cy,cz) with half-extents (hx,hy,hz)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

def cyl(name, cx, cy, cz, r, h, mat, segs=12):
    """Add a Z-axis cylinder with bottom at cz."""
    bpy.ops.mesh.primitive_cylinder_add(
        radius=r, depth=h, vertices=segs,
        location=(cx, cy, cz + h * 0.5))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

# ── Dimensions ────────────────────────────────────────────────────────────────
W  = 8.0    # full width  (X, north–south)
D  = 5.0    # full depth  (Y, west–east)
H  = 3.5    # wall height above base
T  = 0.22   # wall thickness
BH = 0.40   # stone base height
OH = 0.30   # roof overhang beyond walls

hw = W / 2.0   # half-width  (±X)
hd = D / 2.0   # half-depth  (±Y)

# Elevation references (Z)
Z_BASE   = 0.0          # ground
Z_FLOOR  = BH           # top of stone base = bottom of walls
Z_WALL_T = Z_FLOOR + H  # top of walls / eave line
Z_ROOF   = Z_WALL_T     # roof starts at eave

# ════════════════════════════════════════════════════════════════════
# 1. STONE BASE
# ════════════════════════════════════════════════════════════════════
box("base", 0, 0, Z_BASE + BH * 0.5,
    hw + 0.12, hd + 0.12, BH * 0.5, stone)

# Base step at pond-facing front — slightly projected landing
box("base_step", 0, hd + 0.15, Z_BASE + 0.12,
    hw + 0.15, 0.28, 0.12, stone)

# ════════════════════════════════════════════════════════════════════
# 2. WALLS  (cream painted wood)
#    Front (+Y, pond side): full-width SERVICE WINDOW opening
#                           counter sill + header remain
#    Back  (-Y, solid)
#    Sides (±X): two shuttered window bays each
# ════════════════════════════════════════════════════════════════════

# ── 2a. Back wall (solid) ────────────────────────────────────────
box("wall_back", 0, -hd + T * 0.5, Z_FLOOR + H * 0.5,
    hw, T * 0.5, H * 0.5, cream)

# ── 2b. Front wall — counter/window opening ──────────────────────
# The service opening runs almost full width: leave only narrow
# posts (0.25m) at each corner and a low counter sill (0.85m high)
# plus a narrow header above (0.45m).

CTR_SILL  = 0.85   # counter sill height above floor
CTR_HDR   = 0.45   # header band depth below eave
CTR_POST  = 0.25   # corner post half-width
OPEN_W    = hw - CTR_POST   # opening half-width each side of centre

# Left corner post
box("wall_front_post_l",
    -(hw - CTR_POST * 0.5), hd - T * 0.5,
    Z_FLOOR + H * 0.5,
    CTR_POST * 0.5, T * 0.5, H * 0.5, cream)

# Right corner post
box("wall_front_post_r",
    (hw - CTR_POST * 0.5), hd - T * 0.5,
    Z_FLOOR + H * 0.5,
    CTR_POST * 0.5, T * 0.5, H * 0.5, cream)

# Counter sill (low parapet below opening)
box("wall_front_sill",
    0, hd - T * 0.5,
    Z_FLOOR + CTR_SILL * 0.5,
    OPEN_W, T * 0.5, CTR_SILL * 0.5, cream)

# Header band above opening
HDR_Z = Z_FLOOR + H - CTR_HDR
box("wall_front_header",
    0, hd - T * 0.5,
    HDR_Z + CTR_HDR * 0.5,
    OPEN_W, T * 0.5, CTR_HDR * 0.5, cream)

# ── 2c. Side walls with shuttered windows ────────────────────────
# Each side has two window bays.
# Window opening: 0.9m wide × 1.4m tall, sill at 0.9m above floor.
WIN_W   = 0.90
WIN_H   = 1.40
WIN_SILL= 0.90   # height of sill above floor
WIN_Z_C = Z_FLOOR + WIN_SILL + WIN_H * 0.5   # window centre Z

# Positions of two window centres along Y (west–east axis)
WIN_Y_OFFSETS = [-hd + 1.8, hd - 1.8]

for side in (-1, 1):     # -1 = north (–X), +1 = south (+X)
    sx = side * (hw - T * 0.5)
    # Solid lower strip (below sill)
    box(f"side_{side}_lower",
        side * (hw - T * 0.5), 0,
        Z_FLOOR + WIN_SILL * 0.5,
        T * 0.5, hd, WIN_SILL * 0.5, cream)
    # Solid upper strip (above window tops → eave)
    above_h = H - (WIN_SILL + WIN_H)
    box(f"side_{side}_upper",
        side * (hw - T * 0.5), 0,
        Z_FLOOR + WIN_SILL + WIN_H + above_h * 0.5,
        T * 0.5, hd, above_h * 0.5, cream)
    # Fill between the two windows (pier)
    PIER_Y = 0.0   # centre of the building depth
    box(f"side_{side}_pier",
        side * (hw - T * 0.5), PIER_Y,
        WIN_Z_C,
        T * 0.5, 0.3, WIN_H * 0.5, cream)
    # Fill at far front end (between window and front wall)
    fill_front_h_c = WIN_Z_C
    box(f"side_{side}_fill_front",
        side * (hw - T * 0.5), hd - (hd - WIN_Y_OFFSETS[1]) * 0.5,
        WIN_Z_C,
        T * 0.5, (hd - WIN_Y_OFFSETS[1]) * 0.5, WIN_H * 0.5, cream)
    # Fill at far back end
    box(f"side_{side}_fill_back",
        side * (hw - T * 0.5), -hd + (WIN_Y_OFFSETS[0] + hd) * 0.5,
        WIN_Z_C,
        T * 0.5, (WIN_Y_OFFSETS[0] + hd) * 0.5, WIN_H * 0.5, cream)

# ── 2d. Shutter panels (two per window bay) ──────────────────────
# Shutters sit flush on wall exterior, folded back either side of
# each window opening.  Represented as thin flat boxes.
SHT_T  = 0.04   # shutter thickness
SHT_W  = WIN_W * 0.48   # each shutter leaf width

for side in (-1, 1):
    sx_out = side * hw   # outer face of side wall
    for wy in WIN_Y_OFFSETS:
        for leaf in (-1, 1):   # left / right leaf
            # Shutter Y centre = window edge + half-shutter width
            shy = wy + leaf * (WIN_W * 0.5 + SHT_W * 0.5)
            box(f"shutter_{side}_{wy:.1f}_{leaf}",
                sx_out, shy,
                WIN_Z_C,
                SHT_T * 0.5, SHT_W * 0.5, WIN_H * 0.5, trim)

# ════════════════════════════════════════════════════════════════════
# 3. CORNICE BAND  (runs full perimeter at eave level)
# ════════════════════════════════════════════════════════════════════
CRN_H  = 0.18   # cornice height
CRN_P  = 0.12   # cornice projection beyond wall face

CRN_Z  = Z_WALL_T - CRN_H * 0.5

# Front
box("cornice_front", 0, hd + CRN_P * 0.5, CRN_Z,
    hw + CRN_P, (T + CRN_P) * 0.5, CRN_H * 0.5, trim)
# Back
box("cornice_back", 0, -hd - CRN_P * 0.5, CRN_Z,
    hw + CRN_P, (T + CRN_P) * 0.5, CRN_H * 0.5, trim)
# Sides
box("cornice_side_s", (hw + CRN_P * 0.5), 0, CRN_Z,
    (T + CRN_P) * 0.5, hd, CRN_H * 0.5, trim)
box("cornice_side_n", -(hw + CRN_P * 0.5), 0, CRN_Z,
    (T + CRN_P) * 0.5, hd, CRN_H * 0.5, trim)

# ════════════════════════════════════════════════════════════════════
# 4. HIP ROOF  (copper-green patina)
#
# A hip roof has four trapezoidal / triangular slope panels meeting
# at a short central ridge.  Built as a mesh from pydata.
# Ridge runs W–E (Y axis), offset toward front (pond side).
# ════════════════════════════════════════════════════════════════════
EAV_OH  = OH        # eave overhang (beyond cornice)
ROOF_RISE = 1.30    # vertical rise from eave to ridge
RIDGE_LEN = D * 0.55 * 0.5   # half-length of the ridge

# Eave corners (bottom of roof at eave line, with overhang)
eav_z = Z_ROOF
eav_xp =  hw + EAV_OH   # south eave X
eav_xn = -hw - EAV_OH   # north eave X
eav_yp =  hd + EAV_OH   # east (front) eave Y
eav_yn = -hd - EAV_OH   # west (back)  eave Y

# Ridge sits slightly toward the pond face (Y+) because it's a
# shallow hip — keep centred in X.
ridge_yp =  RIDGE_LEN
ridge_yn = -RIDGE_LEN
ridge_z  = eav_z + ROOF_RISE

# Vertex list:
# 0–3: eave corners  (sw, se, ne, nw) → (-x+y, +x+y, +x-y, -x-y)
# 4–5: ridge ends    (east, west)
rv = [
    (-eav_xp,  eav_yp, eav_z),   # 0 south-east eave  (note: X=south)
    ( eav_xp,  eav_yp, eav_z),   # 1 north-east eave
    ( eav_xp,  eav_yn, eav_z),   # 2 north-west eave
    (-eav_xp,  eav_yn, eav_z),   # 3 south-west eave
    (0,        ridge_yp, ridge_z),# 4 ridge east end
    (0,        ridge_yn, ridge_z),# 5 ridge west end
]

# Faces (outward normals):
#   front slope  (east/pond face) : 0,1,4       ← triangle
#   back slope   (west face)      : 2,3,5       ← triangle
#   south slope  (south face)     : 3,0,4,5     ← trapezoid
#   north slope  (north face)     : 1,2,5,4     ← trapezoid
#   soffit       (flat underside) : 0,3,2,1
rf = [
    (0, 1, 4),       # front (east) triangle
    (2, 3, 5),       # back  (west) triangle
    (3, 0, 4, 5),    # south slope
    (1, 2, 5, 4),    # north slope
    (0, 3, 2, 1),    # soffit
]

rmesh = bpy.data.meshes.new("hip_roof")
rmesh.from_pydata(rv, [], rf)
rmesh.update()
robj = bpy.data.objects.new("HipRoof", rmesh)
bpy.context.collection.objects.link(robj)
robj.data.materials.append(copper_roof)
all_parts.append(robj)

# ════════════════════════════════════════════════════════════════════
# 5. COUNTER / SERVICE SHELF  (interior side of front window)
# ════════════════════════════════════════════════════════════════════
# Shallow counter slab visible through the opening
box("counter_slab",
    0, hd - 0.35,
    Z_FLOOR + CTR_SILL + 0.06,
    hw - CTR_POST - 0.05, 0.30, 0.06, stone)

# Counter front fascia (visible from outside)
box("counter_fascia",
    0, hd - 0.05,
    Z_FLOOR + CTR_SILL * 0.5,
    hw - CTR_POST - 0.05, 0.04, CTR_SILL * 0.5, trim)

# ════════════════════════════════════════════════════════════════════
# 6. WINDOW TRIM — simple surround on side windows
# ════════════════════════════════════════════════════════════════════
WIN_SURR = 0.06   # surround half-thickness

for side in (-1, 1):
    sx_out = side * hw
    for wy in WIN_Y_OFFSETS:
        # Top / bottom rail
        for zoff in (WIN_Z_C + WIN_H * 0.5 + WIN_SURR,
                     WIN_Z_C - WIN_H * 0.5 - WIN_SURR):
            box(f"wt_rail_{side}_{wy:.1f}_{zoff:.2f}",
                sx_out, wy,
                zoff,
                WIN_SURR * 0.5, WIN_W * 0.5 + WIN_SURR, WIN_SURR * 0.5, trim)
        # Left / right stile
        for yoff in (wy - WIN_W * 0.5 - WIN_SURR,
                     wy + WIN_W * 0.5 + WIN_SURR):
            box(f"wt_stile_{side}_{wy:.1f}_{yoff:.2f}",
                sx_out, yoff,
                WIN_Z_C,
                WIN_SURR * 0.5, WIN_SURR * 0.5, WIN_H * 0.5 + WIN_SURR, trim)

# ════════════════════════════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "ModelBoathouse"

bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_model_boathouse.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported Kerbs Model Boathouse to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces:    {len(obj.data.polygons)}")
