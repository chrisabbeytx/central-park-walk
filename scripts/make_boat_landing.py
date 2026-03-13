"""Generate a Central Park boat landing/dock for Central Park Walk.

Central Park has several small wooden boat landings extending over the lake:
Wagner Cove, Hernshead Landing, and the Western Shore landing. These are
simple rustic docks — rectangular wooden platforms on pile supports used
for rowboat rental access and contemplative lakeside seating.

Key features:
  - Rectangular wooden deck platform ~8m × 3m
  - Low profile — deck surface ~0.5m above water level
  - Wood plank deck (series of parallel planks with gaps)
  - 6 square support posts below deck (3 per long side)
  - Corner bollard posts (short stub cylinders for tying boats)
  - X-cross bracing between pile pairs below deck
  - Wood pilings extend ~1.5m below deck (into lake bed)

Origin at ground center, deck surface at y=0.5 so the dock floats at
water level when placed at terrain_y.

Exports to models/furniture/cp_boat_landing.glb
"""

import bpy
import math
import os

# ─── Clear scene ───────────────────────────────────────────────────────────────
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# ─── Materials ──────────────────────────────────────────────────────────────────
def make_mat(name, color, roughness=0.85, metallic=0.0):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m

wood   = make_mat("Wood",   (0.42, 0.35, 0.25), roughness=0.85)
piling = make_mat("Piling", (0.35, 0.28, 0.20), roughness=0.90)

all_parts = []

# ─── Primitives ─────────────────────────────────────────────────────────────────
def box(name, cx, cy, cz, hx, hy, hz, mat):
    """Add a box centred at (cx,cy,cz) with half-extents (hx,hy,hz)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

def cyl(name, cx, cy, cz, radius, height, verts=12, mat=None):
    """Add a Z-axis cylinder centred at (cx,cy,cz)."""
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=height, vertices=verts,
        location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    if mat:
        o.data.materials.append(mat)
    all_parts.append(o)
    return o

# ─── Dimensions ──────────────────────────────────────────────────────────────────
DOCK_L   = 8.0   # dock length along X
DOCK_W   = 3.0   # dock width along Y
DECK_Y   = 0.5   # deck surface elevation above origin (= water level)

PLANK_T  = 0.05  # plank thickness
PLANK_W  = 0.18  # plank width
PLANK_GAP = 0.025 # gap between planks
STRINGER_W = 0.12  # width of longitudinal stringers (beams)
STRINGER_T = 0.14  # depth of stringers

POST_W   = 0.18  # square post cross section half-width
POST_H   = DECK_Y + 1.5   # post extends from -1.5 (lake bed) to deck underside

BRACE_T  = 0.06  # cross-brace thickness
BRACE_W  = 0.08  # cross-brace width

BOLLARD_R = 0.08  # corner bollard radius
BOLLARD_H = 0.40  # bollard height above deck

# ─── 1. DECK PLANKS ─────────────────────────────────────────────────────────────
# Planks run along X (length), spaced along Y (width).
# Total plank span = DOCK_W, centred at Y=0.
# Number of planks to fill DOCK_W:
n_planks = int(DOCK_W / (PLANK_W + PLANK_GAP))
total_span = n_planks * (PLANK_W + PLANK_GAP) - PLANK_GAP
plank_y0 = -total_span / 2.0

deck_surf_y = DECK_Y   # top of planks
plank_cy_y  = deck_surf_y - PLANK_T / 2.0

for i in range(n_planks):
    py = plank_y0 + i * (PLANK_W + PLANK_GAP) + PLANK_W / 2.0
    box(f"plank_{i:02d}", 0.0, py, plank_cy_y,
        DOCK_L / 2.0, PLANK_W / 2.0, PLANK_T / 2.0, wood)

# ─── 2. LONGITUDINAL STRINGERS (pair of beams under deck) ───────────────────────
# Two stringers run the full length, set in ~0.7m from each side.
stringer_top_y  = deck_surf_y - PLANK_T
stringer_cy_y   = stringer_top_y - STRINGER_T / 2.0
stringer_y_offsets = [-DOCK_W / 2.0 + 0.70, DOCK_W / 2.0 - 0.70]

for i, sy in enumerate(stringer_y_offsets):
    box(f"stringer_{i}", 0.0, sy, stringer_cy_y,
        DOCK_L / 2.0, STRINGER_W / 2.0, STRINGER_T / 2.0, wood)

# ─── 3. CROSS BEAMS (3 transverse beams tying stringers together) ───────────────
# At X = -DOCK_L/2, 0, +DOCK_L/2  (ends + middle)
crossbeam_top_y = stringer_top_y
crossbeam_cy_y  = crossbeam_top_y - STRINGER_T / 2.0 - 0.02   # just below stringers
crossbeam_xs    = [-DOCK_L / 2.0 + 0.15, 0.0, DOCK_L / 2.0 - 0.15]

for i, cx in enumerate(crossbeam_xs):
    box(f"crossbeam_{i}", cx, 0.0, crossbeam_cy_y,
        STRINGER_W / 2.0, DOCK_W / 2.0 + 0.05, STRINGER_T / 2.0, wood)

# ─── 4. SUPPORT POSTS / PILINGS ─────────────────────────────────────────────────
# 6 posts total: 2 rows of 3 along X, at Y = ±(DOCK_W/2 - 0.35).
# X positions: quarter, half, three-quarter of dock length.
post_y_offsets = [-(DOCK_W / 2.0 - 0.35), (DOCK_W / 2.0 - 0.35)]
post_x_offsets = [
    -DOCK_L / 2.0 + 0.6,   # near land end
    0.0,                    # middle
    DOCK_L / 2.0 - 0.6,    # far (water) end
]
# Posts run from lake bed (y = -(POST_H - DECK_Y)) up to deck underside
post_bot_y = -(POST_H - DECK_Y)   # below water surface
post_top_y = stringer_cy_y - STRINGER_T / 2.0  # flush with stringer bottom
post_half_h = (post_top_y - post_bot_y) / 2.0
post_cy_y   = post_bot_y + post_half_h

for row, py in enumerate(post_y_offsets):
    for col, px in enumerate(post_x_offsets):
        box(f"post_r{row}_c{col}", px, py, post_cy_y,
            POST_W / 2.0, POST_W / 2.0, post_half_h, piling)

# ─── 5. DIAGONAL CROSS BRACING (X-braces between post pairs along each side) ────
# Between adjacent post pairs on each side, add two diagonal braces forming an X.
# Braces are thin rectangular boxes rotated to connect post tops and bottoms.
brace_top_y   = stringer_cy_y - STRINGER_T / 2.0 - 0.05   # near post top
brace_bot_y   = post_bot_y + 0.2                           # near post bottom
brace_half_h  = (brace_top_y - brace_bot_y) / 2.0
brace_cy_y    = brace_bot_y + brace_half_h

for row, py in enumerate(post_y_offsets):
    for col in range(len(post_x_offsets) - 1):
        x_left  = post_x_offsets[col]
        x_right = post_x_offsets[col + 1]
        span    = x_right - x_left
        diag_angle = math.atan2(brace_top_y - brace_bot_y, span)

        for sign in (-1, 1):
            # Each diagonal: from (x_left, brace_bot) to (x_right, brace_top)
            # or mirrored. Approximate as a rotated thin box.
            cx_brace = (x_left + x_right) / 2.0
            length   = math.sqrt(span**2 + (brace_top_y - brace_bot_y)**2)

            bpy.ops.mesh.primitive_cube_add(
                size=1.0, location=(cx_brace, py, brace_cy_y))
            o = bpy.context.active_object
            o.name = f"brace_r{row}_c{col}_s{sign}"
            o.scale = (length / 2.0, BRACE_W / 2.0, BRACE_T / 2.0)
            o.rotation_euler = (0.0, sign * diag_angle, 0.0)
            o.data.materials.append(piling)
            all_parts.append(o)

# ─── 6. CORNER BOLLARDS (short tie-off posts at deck corners) ───────────────────
# 4 bollards, one at each deck corner, sitting on top of the deck.
bollard_bot_y = deck_surf_y
bollard_cy_y  = bollard_bot_y + BOLLARD_H / 2.0
corner_xs = [-DOCK_L / 2.0 + 0.25,  DOCK_L / 2.0 - 0.25]
corner_ys = [-DOCK_W / 2.0 + 0.25,  DOCK_W / 2.0 - 0.25]

for i, bx in enumerate(corner_xs):
    for j, by in enumerate(corner_ys):
        cyl(f"bollard_{i}_{j}", bx, by, bollard_cy_y,
            BOLLARD_R, BOLLARD_H, verts=8, mat=wood)
        # Small cap disc on top
        cyl(f"bollard_cap_{i}_{j}", bx, by, bollard_bot_y + BOLLARD_H,
            BOLLARD_R * 1.3, 0.04, verts=8, mat=wood)

# ─── 7. DECK EDGE FASCIA (trim boards on the two long sides) ────────────────────
# Thin vertical boards along the long (X) edges, giving a finished edge look.
fascia_t = 0.04   # fascia thickness
fascia_h = PLANK_T + STRINGER_T * 0.6
fascia_cy_y = deck_surf_y - fascia_h / 2.0

for sign in (-1, 1):
    fy = sign * (DOCK_W / 2.0 + fascia_t / 2.0)
    box(f"fascia_{sign}", 0.0, fy, fascia_cy_y,
        DOCK_L / 2.0, fascia_t / 2.0, fascia_h / 2.0, wood)

# ─── FINALIZE ───────────────────────────────────────────────────────────────────
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "BoatLanding"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_boat_landing.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported Boat Landing to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces:    {len(obj.data.polygons)}")
print(f"  Deck surface at Y={DECK_Y}m above origin")
print(f"  Dock footprint: {DOCK_L}m x {DOCK_W}m")
