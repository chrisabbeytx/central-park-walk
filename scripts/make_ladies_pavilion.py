"""Generate the Ladies' Pavilion for Central Park Walk.

The Ladies' Pavilion (1871, Jacob Wrey Mould) is an ornate Victorian
cast-iron open gazebo originally sited at the 72nd Street trolley stop,
relocated in 1912 to the shore of the Lake at Hernshead.

Key features:
  - Octagonal open pavilion, ~5m diameter
  - 8 ornate cast-iron columns (~3.5m tall) at octagon vertices
  - Decorative pagoda-style iron roof with upswept eaves (~2m rise)
  - Ornate iron railing between columns (~0.9m high)
  - Raised stone platform base (~0.3m)
  - Iron finial spike on roof peak
  - Delicate, lacy cast-iron character throughout

Origin at ground center.
Exports to models/furniture/cp_ladies_pavilion.glb
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

iron      = make_mat("Iron",     (0.18, 0.18, 0.17), roughness=0.55, metallic=0.5)
stone     = make_mat("Stone",    (0.55, 0.52, 0.48), roughness=0.85)
roof_iron = make_mat("RoofIron", (0.22, 0.22, 0.20), roughness=0.50, metallic=0.4)

# ── Helpers ───────────────────────────────────────────────────────────────────
all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    """Place a box centred at (cx, cy, cz) with half-extents (hx, hy, hz)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

def cyl(name, cx, cy, cz, radius, depth, verts, mat, rot_euler=(0, 0, 0)):
    """Place a cylinder centred at (cx, cy, cz)."""
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, vertices=verts,
        location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    if rot_euler != (0, 0, 0):
        o.rotation_euler = rot_euler
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

def cone_mesh(name, verts_xy, apex_xyz, mat):
    """Build a conical polygon mesh from a list of base (x,y,z) and apex."""
    N = len(verts_xy)
    faces = []
    for i in range(N):
        faces.append((i, (i + 1) % N, N))
    faces.append(list(range(N)))          # base cap
    m = bpy.data.meshes.new(name + "_mesh")
    m.from_pydata(verts_xy + [apex_xyz], [], faces)
    m.update()
    o = bpy.data.objects.new(name, m)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

# ── Dimensions ────────────────────────────────────────────────────────────────
N          = 8          # octagonal
R          = 2.50       # column circle radius (to column centre)
BASE_H     = 0.30       # stone platform height
COL_H      = 3.50       # column shaft height above base top
COL_R      = 0.055      # column shaft radius
COL_VERTS  = 12
PLINTH_W   = 0.14       # column base plinth half-width (square)
PLINTH_H   = 0.18       # plinth height
CAP_W      = 0.13       # capital slab half-width
CAP_H      = 0.12       # capital slab height
RAIL_H     = 0.90       # railing height above base top
PICKET_R   = 0.018      # railing picket radius
PICKET_V   = 6
TOP_RAIL_R = 0.028      # handrail radius
BOT_RAIL_R = 0.022      # bottom rail radius

# Eave ring: slightly flared outward from column circle
EAVE_R     = R + 0.65   # eave overhang radius
EAVE_Z     = BASE_H + COL_H + CAP_H  # Z of eave (top of capital)

# Pagoda roof: two-level conical form for upswept silhouette
# Lower skirt: shallow cone from eave ring up to transition ring
SKIRT_R    = R + 0.10   # inner transition ring radius (slightly inside eave)
SKIRT_Z    = EAVE_Z + 0.55   # rise of skirt transition
# Upper main cone: from transition ring up to apex
APEX_Z     = EAVE_Z + 2.00   # total roof rise from eave
APEX_XYZ   = (0.0, 0.0, APEX_Z)

# Compute 8 column positions
col_pos = [(math.cos(2 * math.pi * i / N) * R,
            math.sin(2 * math.pi * i / N) * R) for i in range(N)]

# ════════════════════════════════════════════
# 1. STONE OCTAGONAL BASE PLATFORM
# ════════════════════════════════════════════
# Octagonal slab: approximate with an 8-sided cylinder slightly larger than R
bpy.ops.mesh.primitive_cylinder_add(
    radius=R + 0.50, depth=BASE_H, vertices=N,
    location=(0, 0, BASE_H / 2))
base_slab = bpy.context.active_object
base_slab.name = "BaseSlab"
base_slab.data.materials.append(stone)
all_parts.append(base_slab)

# Low step ring around the base perimeter
bpy.ops.mesh.primitive_cylinder_add(
    radius=R + 0.80, depth=0.12, vertices=N,
    location=(0, 0, 0.06))
step = bpy.context.active_object
step.name = "BaseStep"
step.data.materials.append(stone)
all_parts.append(step)

# ════════════════════════════════════════════
# 2. IRON COLUMNS — 8 columns at octagon vertices
#    Each column: square plinth + cylinder shaft + flat capital + side brackets
# ════════════════════════════════════════════
col_base_z = BASE_H   # bottom of column assembly

for i, (px, py) in enumerate(col_pos):
    a = 2 * math.pi * i / N

    # Square plinth at column base
    box(f"col_plinth_{i}", px, py, col_base_z + PLINTH_H / 2,
        PLINTH_W, PLINTH_W, PLINTH_H / 2, iron)

    # Column shaft cylinder
    shaft_bot = col_base_z + PLINTH_H
    shaft_cz  = shaft_bot + COL_H / 2
    cyl(f"col_shaft_{i}", px, py, shaft_cz,
        COL_R, COL_H, COL_VERTS, iron)

    # Capital slab on top of shaft
    cap_bot = col_base_z + PLINTH_H + COL_H
    box(f"col_cap_{i}", px, py, cap_bot + CAP_H / 2,
        CAP_W, CAP_W, CAP_H / 2, iron)

    # Decorative collar ring just below capital (represents scroll volute)
    collar_z = cap_bot - 0.08
    cyl(f"col_collar_{i}", px, py, collar_z,
        COL_R + 0.035, 0.06, COL_VERTS, iron)

    # Decorative base ring just above plinth (represents base moulding)
    base_ring_z = shaft_bot + 0.06
    cyl(f"col_base_ring_{i}", px, py, base_ring_z,
        COL_R + 0.030, 0.05, COL_VERTS, iron)

    # Bracket arms: two thin flat arms projecting tangentially from column top
    # These represent the ornate ironwork brackets that support the eave ring
    arm_len = 0.45
    # Tangent direction (perpendicular to radial direction)
    tx = -math.sin(a)
    ty =  math.cos(a)
    bracket_z = cap_bot + CAP_H + 0.05
    bracket_h = 0.06
    for side in (-1, 1):
        arm_cx = px + tx * side * arm_len / 2
        arm_cy = py + ty * side * arm_len / 2
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(arm_cx, arm_cy, bracket_z))
        arm_obj = bpy.context.active_object
        arm_obj.name = f"bracket_{i}_{side}"
        arm_obj.scale = (arm_len / 2 * abs(tx) + bracket_h / 2 * abs(ty),
                         arm_len / 2 * abs(ty) + bracket_h / 2 * abs(tx),
                         0.030)
        arm_obj.rotation_euler = (0, 0, a)
        arm_obj.data.materials.append(iron)
        all_parts.append(arm_obj)

# ════════════════════════════════════════════
# 3. RAILING — ornate iron railing between each column pair
#    Top rail + bottom rail + vertical pickets (5 per bay)
# ════════════════════════════════════════════
RAIL_R = R - 0.04   # railing sits just inside the column circle

for i in range(N):
    a1 = 2 * math.pi * i / N
    a2 = 2 * math.pi * ((i + 1) % N) / N
    am = (a1 + a2) / 2   # mid angle of the bay

    x1, y1 = col_pos[i]
    x2, y2 = col_pos[(i + 1) % N]

    # Bay midpoint on the railing ring
    mx = math.cos(am) * RAIL_R
    my = math.sin(am) * RAIL_R

    # Segment length between the two column centres
    seg_len = math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
    bay_ang  = math.atan2(y2 - y1, x2 - x1)

    # Subtract column diameter from each end so rail meets column face
    inner_len = max(seg_len - 2 * (COL_R + 0.02), 0.05)

    # Top handrail (horizontal cylinder along bay midpoint)
    top_rail_z = col_base_z + RAIL_H
    bpy.ops.mesh.primitive_cylinder_add(
        radius=TOP_RAIL_R, depth=inner_len, vertices=8,
        location=(mx, my, top_rail_z))
    tr = bpy.context.active_object
    tr.name = f"top_rail_{i}"
    tr.rotation_euler = (math.pi / 2, 0, bay_ang)
    tr.data.materials.append(iron)
    all_parts.append(tr)

    # Bottom rail at ~0.12m above base
    bot_rail_z = col_base_z + 0.12
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BOT_RAIL_R, depth=inner_len, vertices=8,
        location=(mx, my, bot_rail_z))
    br = bpy.context.active_object
    br.name = f"bot_rail_{i}"
    br.rotation_euler = (math.pi / 2, 0, bay_ang)
    br.data.materials.append(iron)
    all_parts.append(br)

    # Mid rail at ~0.50m above base
    mid_rail_z = col_base_z + 0.50
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BOT_RAIL_R, depth=inner_len, vertices=8,
        location=(mx, my, mid_rail_z))
    mr = bpy.context.active_object
    mr.name = f"mid_rail_{i}"
    mr.rotation_euler = (math.pi / 2, 0, bay_ang)
    mr.data.materials.append(iron)
    all_parts.append(mr)

    # Vertical pickets: 5 per bay, evenly spaced
    N_PICKETS = 5
    for p in range(N_PICKETS):
        t = (p + 1) / (N_PICKETS + 1)
        px_p = x1 + (x2 - x1) * t
        py_p = y1 + (y2 - y1) * t
        # Nudge inward by a tiny amount (rail thickness)
        px_p = px_p * (RAIL_R / R) if R != 0 else px_p
        py_p = py_p * (RAIL_R / R) if R != 0 else py_p
        picket_h = RAIL_H - 0.12
        picket_cz = col_base_z + 0.12 + picket_h / 2
        cyl(f"picket_{i}_{p}", px_p, py_p, picket_cz,
            PICKET_R, picket_h, PICKET_V, iron)

        # Decorative spear tip on each picket (tiny cone stand-in: thin box spike)
        tip_z = col_base_z + RAIL_H + 0.04
        box(f"picket_tip_{i}_{p}", px_p, py_p, tip_z,
            0.020, 0.020, 0.045, iron)

# ════════════════════════════════════════════
# 4. EAVE RING — horizontal octagonal band connecting all column tops
#    Acts as the structural tie-beam and eave fascia of the roof
# ════════════════════════════════════════════
eave_ring_z  = EAVE_Z + 0.06   # slightly above capital tops
eave_ring_th = 0.10             # ring thickness (depth inward)
eave_ring_h  = 0.15             # ring vertical height

for i in range(N):
    a1 = 2 * math.pi * i / N
    a2 = 2 * math.pi * ((i + 1) % N) / N
    am = (a1 + a2) / 2

    x1 = math.cos(a1) * EAVE_R
    y1 = math.sin(a1) * EAVE_R
    x2 = math.cos(a2) * EAVE_R
    y2 = math.sin(a2) * EAVE_R
    mx = (x1 + x2) / 2
    my = (y1 + y2) / 2

    seg_len = math.sqrt((x2 - x1)**2 + (y2 - y1)**2)
    bay_ang  = math.atan2(y2 - y1, x2 - x1)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(mx, my, eave_ring_z))
    er = bpy.context.active_object
    er.name = f"eave_ring_{i}"
    er.scale = (seg_len / 2, eave_ring_th / 2, eave_ring_h / 2)
    er.rotation_euler = (0, 0, bay_ang)
    er.data.materials.append(roof_iron)
    all_parts.append(er)

# ════════════════════════════════════════════
# 5. PAGODA ROOF — two-tier conical with upswept eave flare
#
# Tier 1: lower skirt — wide shallow cone from eave ring (EAVE_R) up to
#         a transition circle at SKIRT_R / SKIRT_Z.  The eave radius is
#         LARGER than the skirt radius, giving the outward flare / upturn.
#
# Tier 2: upper cone — from SKIRT_R / SKIRT_Z up to APEX.
# ════════════════════════════════════════════

# Lower eave ring vertices (outer flare, at eave Z)
eave_verts = [(math.cos(2 * math.pi * i / N) * EAVE_R,
               math.sin(2 * math.pi * i / N) * EAVE_R,
               EAVE_Z) for i in range(N)]

# Transition ring vertices (inner, above eave)
skirt_verts = [(math.cos(2 * math.pi * i / N) * SKIRT_R,
                math.sin(2 * math.pi * i / N) * SKIRT_R,
                SKIRT_Z) for i in range(N)]

# Build the lower skirt as N quadrilateral panels + base cap
# Skirt faces: each panel connects eave[i] — eave[i+1] — skirt[i+1] — skirt[i]
skirt_v = eave_verts + skirt_verts   # indices 0-7 = eave, 8-15 = skirt
skirt_f = []
for i in range(N):
    # Outward-facing panel (eave bottom → skirt top)
    skirt_f.append((i, (i + 1) % N, N + (i + 1) % N, N + i))
# Base cap (eave ring, facing down)
skirt_f.append(list(range(N - 1, -1, -1)))
# Top cap (skirt ring, facing up — will be covered by upper cone)
skirt_f.append(list(range(N, 2 * N)))

skirt_m = bpy.data.meshes.new("skirt_mesh")
skirt_m.from_pydata(skirt_v, [], skirt_f)
skirt_m.update()
skirt_o = bpy.data.objects.new("RoofSkirt", skirt_m)
bpy.context.collection.objects.link(skirt_o)
skirt_o.data.materials.append(roof_iron)
all_parts.append(skirt_o)

# Upper cone: from skirt ring up to apex
cone_mesh("RoofCone", skirt_verts, APEX_XYZ, roof_iron)

# Decorative eave tip pendants — small iron drop at each eave vertex
# (the characteristic pointed drops seen on Victorian iron gazebos)
for i, (ex, ey, ez) in enumerate(eave_verts):
    # Thin pendant cylinder hanging below eave
    cyl(f"eave_pendant_{i}", ex, ey, ez - 0.10,
        0.022, 0.20, 6, iron)
    # Small ball at pendant tip
    cyl(f"eave_ball_{i}", ex, ey, ez - 0.22,
        0.038, 0.05, 8, iron)

# Decorative ridge finlets at eave-to-skirt transitions (one per bay)
for i in range(N):
    a1 = 2 * math.pi * i / N
    a2 = 2 * math.pi * ((i + 1) % N) / N
    am = (a1 + a2) / 2
    # Small upturned curl: tiny box at mid-eave edge, just above eave ring
    fx = math.cos(am) * (EAVE_R - 0.10)
    fy = math.sin(am) * (EAVE_R - 0.10)
    box(f"eave_curl_{i}", fx, fy, EAVE_Z + 0.14,
        0.06, 0.06, 0.06, roof_iron)

# ════════════════════════════════════════════
# 6. FINIAL — iron spike at roof apex
# ════════════════════════════════════════════
finial_base_z = APEX_Z

# Base ball of finial
cyl("finial_ball", 0, 0, finial_base_z + 0.09,
    0.065, 0.18, 12, iron)

# Tapered spike above ball: approximate taper with stacked cylinders
spike_segments = [(0.048, 0.20), (0.030, 0.18), (0.016, 0.16), (0.008, 0.12)]
sz = finial_base_z + 0.18
for k, (sr, sh) in enumerate(spike_segments):
    cyl(f"finial_spike_{k}", 0, 0, sz + sh / 2,
        sr, sh, 8, iron)
    sz += sh

# Small decorative collar ring at base of finial
cyl("finial_collar", 0, 0, finial_base_z + 0.06,
    0.095, 0.05, 12, iron)

# ════════════════════════════════════════════
# 7. CENTRAL FLOOR — stone octagonal deck inside pavilion
# ════════════════════════════════════════════
# Interior floor slab flush with top of base platform
bpy.ops.mesh.primitive_cylinder_add(
    radius=R - 0.12, depth=0.08, vertices=N,
    location=(0, 0, BASE_H - 0.04))
floor = bpy.context.active_object
floor.name = "FloorDeck"
floor.data.materials.append(stone)
all_parts.append(floor)

# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "LadiesPavilion"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_ladies_pavilion.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported Ladies' Pavilion to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces:    {len(obj.data.polygons)}")
