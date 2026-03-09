"""Generate Bethesda Terrace model for Central Park walk.

Key parameters:
  TERRACE_WIDTH  = 50.0m   (east-west span)
  ARCADE_WIDTH   = 10.0m   (barrel vault passage)
  ARCADE_LENGTH  = 14.0m   (north-south under road)
  ARCADE_HEIGHT  = 4.2m    (vault crown from arcade floor)
  LEVEL_DROP     = 4.8m    (upper to lower terrace)
  STAIR_WIDTH    = 6.0m    (each flanking staircase)
  BALUSTRADE_H   = 0.9m

Orientation (Blender Z-up):
  +Y = south (from The Mall, upper approach)
  -Y = north (toward fountain / lake, stairs descend this way)

Materials: Sandstone, Brownstone trim, Minton vault tile, Stair stone
Exports to models/furniture/cp_bethesda_terrace.glb
"""

import bpy
import bmesh
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
def make_mat(name, color, roughness=0.80, metallic=0.0):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m

sandstone  = make_mat("Sandstone",  (0.72, 0.65, 0.52), 0.85)
brownstone = make_mat("Brownstone", (0.42, 0.32, 0.24), 0.80)
vault_tile = make_mat("VaultTile",  (0.82, 0.72, 0.55), 0.55)
stair_mat  = make_mat("StairStone", (0.60, 0.56, 0.48), 0.82)

# ── Constants ──
TERRACE_W   = 50.0
ARCADE_W    = 8.0       # interior width (vault_r = 4.0 < ARCADE_H)
ARCADE_L    = 14.0
ARCADE_H    = 4.5       # vault crown above arcade floor
VAULT_T     = 0.45     # vault shell thickness
WALL_T      = 0.7      # side walls
ROAD_SLAB_T = 0.8      # road slab above vault
STAIR_W     = 6.0
STEP_RISE   = 0.17
STEP_RUN    = 0.30
BALUSTRADE_H    = 0.90
BAL_POST_W      = 0.20
BAL_POST_D      = 0.16
BAL_RAIL_H      = 0.10
BAL_RAIL_D      = 0.12
BAL_SPACING     = 1.8
BALUSTER_W      = 0.07
PIER_W          = 0.55

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    """Axis-aligned box at center (cx,cy,cz) with half-extents (hx,hy,hz)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx, hy, hz)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o


# ── Derived geometry ──
# Arcade floor at Z=0. Upper terrace above, lower terrace = arcade floor level.
arcade_floor_z = 0.0
vault_r = ARCADE_W / 2.0                          # vault semicircle radius
spring_z = arcade_floor_z + (ARCADE_H - vault_r)  # where arch springs from walls
vault_crown_z = arcade_floor_z + ARCADE_H
upper_z = vault_crown_z + VAULT_T + ROAD_SLAB_T   # upper terrace floor
lower_z = arcade_floor_z                           # lower terrace = arcade floor

LEVEL_DROP = upper_z - lower_z
n_steps = round(LEVEL_DROP / STEP_RISE)
STEP_RISE = LEVEL_DROP / n_steps  # exact fit
stair_run = n_steps * STEP_RUN

# X extents
half_arc = ARCADE_W / 2.0
stair_inner_x = half_arc + WALL_T        # inner edge of stair
stair_outer_x = stair_inner_x + STAIR_W  # outer edge of stair

# Y extents — stairs descend toward -Y (north/fountain side)
stair_top_y = -ARCADE_L / 2.0            # top of stairs = north face of arcade
stair_bot_y = stair_top_y - stair_run    # bottom of stairs

print(f"Terrace: upper_z={upper_z:.2f} lower_z={lower_z:.2f} drop={LEVEL_DROP:.2f} "
      f"steps={n_steps} stair_run={stair_run:.2f}")


# ════════════════════════════════════════════
# 1. ARCADE — walls, floor, vault, piers
# ════════════════════════════════════════════

# East and west walls of arcade passage
for side in (-1, 1):
    wx = side * (half_arc + WALL_T / 2.0)
    wall_h = upper_z - arcade_floor_z
    box(f"arcade_wall_{side}", wx, 0, arcade_floor_z + wall_h / 2.0,
        WALL_T / 2.0, ARCADE_L / 2.0, wall_h / 2.0, sandstone)

# Arcade floor slab
box("arcade_floor", 0, 0, arcade_floor_z - 0.15,
    half_arc + WALL_T, ARCADE_L / 2.0, 0.15, stair_mat)

# Barrel vault (half-cylinder shell)
vault_segs = 20
mesh = bpy.data.meshes.new("vault_mesh")
verts = []
faces = []
hl = ARCADE_L / 2.0

for j in range(2):
    y = -hl if j == 0 else hl
    for i in range(vault_segs + 1):
        a = math.pi * i / vault_segs
        cos_a, sin_a = math.cos(a), math.sin(a)
        # Inner vertex
        verts.append((cos_a * vault_r, y, sin_a * vault_r + spring_z))
        # Outer vertex
        verts.append((cos_a * (vault_r + VAULT_T), y, sin_a * (vault_r + VAULT_T) + spring_z))

stride = (vault_segs + 1) * 2
for i in range(vault_segs):
    # Inner face (visible from below — winding for -Y normal towards interior)
    a = i * 2
    b = i * 2 + 2
    c = stride + i * 2 + 2
    d = stride + i * 2
    faces.append((a, d, c, b))   # inner surface faces inward
    # Outer face
    a2 = a + 1
    b2 = b + 1
    c2 = c + 1
    d2 = d + 1
    faces.append((a2, b2, c2, d2))  # outer surface faces outward

# End caps (front and back arches)
for j in range(2):
    base = j * stride
    for i in range(vault_segs):
        a = base + i * 2
        b = base + i * 2 + 1
        c = base + i * 2 + 3
        d = base + i * 2 + 2
        if j == 0:
            faces.append((a, b, c, d))  # front face
        else:
            faces.append((a, d, c, b))  # back face

mesh.from_pydata(verts, [], faces)
mesh.update()
vault_obj = bpy.data.objects.new("arcade_vault", mesh)
bpy.context.collection.objects.link(vault_obj)
vault_obj.data.materials.append(vault_tile)
all_parts.append(vault_obj)

# Road slab above vault
slab_bot = vault_crown_z + VAULT_T
slab_top = upper_z
box("road_slab", 0, 0, (slab_bot + slab_top) / 2.0,
    half_arc + WALL_T, ARCADE_L / 2.0, (slab_top - slab_bot) / 2.0, sandstone)

# Piers at arcade entrances (decorative pilasters)
pier_h = spring_z - arcade_floor_z
for face in (-1, 1):
    py = face * hl
    for side in (-1, 1):
        px = side * (half_arc - 0.05)
        box(f"pier_{face}_{side}", px, py, arcade_floor_z + pier_h / 2.0,
            PIER_W / 2.0, 0.25, pier_h / 2.0, brownstone)
        # Pier capital
        box(f"pier_cap_{face}_{side}", px, py, arcade_floor_z + pier_h + 0.08,
            PIER_W / 2.0 + 0.06, 0.30, 0.08, brownstone)

# Cornice / impost band at springing line
for face in (-1, 1):
    py = face * (hl + 0.01)
    box(f"impost_{face}", 0, py, spring_z + 0.06,
        half_arc + WALL_T + 0.12, 0.12, 0.06, brownstone)


# ════════════════════════════════════════════
# 2. UPPER TERRACE PLATFORM
# ════════════════════════════════════════════
plat_h = 0.35  # slab thickness

# Full-width upper platform (includes road surface over arcade)
box("upper_platform", 0, 0, upper_z - plat_h / 2.0,
    TERRACE_W / 2.0, ARCADE_L / 2.0, plat_h / 2.0, sandstone)

# Extended wings projecting forward (+Y, south toward Mall)
wing_depth = 3.0
box("upper_wing_s", 0, ARCADE_L / 2.0 + wing_depth / 2.0, upper_z - plat_h / 2.0,
    TERRACE_W / 2.0, wing_depth / 2.0, plat_h / 2.0, sandstone)


# ════════════════════════════════════════════
# 3. GRAND STAIRCASES (east and west)
# ════════════════════════════════════════════

# Each staircase is a solid stepped mass.
# Build as bmesh: a cross-section extruded along X.
for side in (-1, 1):
    inner_x = side * stair_inner_x if side > 0 else -stair_outer_x
    outer_x = side * stair_outer_x if side > 0 else -stair_inner_x
    # Ensure inner < outer in X
    x_lo = min(inner_x, outer_x)
    x_hi = max(inner_x, outer_x)
    width = x_hi - x_lo
    cx = (x_lo + x_hi) / 2.0

    # Build staircase profile (YZ cross-section) — stepped outline
    # Start at top-front: (stair_top_y, upper_z)
    # Step down to (stair_bot_y, lower_z)
    # Then close underneath
    profile_verts = []
    for si in range(n_steps):
        sy = stair_top_y - si * STEP_RUN
        sz = upper_z - si * STEP_RISE
        profile_verts.append((sy, sz))               # tread front edge
        profile_verts.append((sy - STEP_RUN, sz))     # tread back edge
        profile_verts.append((sy - STEP_RUN, sz - STEP_RISE))  # riser bottom

    # Bottom of stairs
    profile_verts.append((stair_bot_y, lower_z))
    # Close the bottom — go back under to start
    profile_verts.append((stair_bot_y, lower_z - 0.5))
    profile_verts.append((stair_top_y, lower_z - 0.5))
    # Back up to start
    profile_verts.append((stair_top_y, upper_z))

    # Create mesh by extruding profile along X
    n_pv = len(profile_verts)
    mverts = []
    mfaces = []

    for xi, xv in enumerate([x_lo, x_hi]):
        for pv in profile_verts:
            mverts.append((xv, pv[0], pv[1]))

    # Side faces (left and right)
    for xi in range(2):
        base = xi * n_pv
        face = list(range(base, base + n_pv))
        if xi == 1:
            face.reverse()
        mfaces.append(face)

    # Connecting faces between the two profiles
    for i in range(n_pv):
        i_next = (i + 1) % n_pv
        a = i
        b = i_next
        c = n_pv + i_next
        d = n_pv + i
        mfaces.append((a, b, c, d))

    smesh = bpy.data.meshes.new(f"stair_mesh_{side}")
    smesh.from_pydata(mverts, [], mfaces)
    smesh.update()
    sobj = bpy.data.objects.new(f"staircase_{side}", smesh)
    bpy.context.collection.objects.link(sobj)
    sobj.data.materials.append(stair_mat)
    all_parts.append(sobj)


# ════════════════════════════════════════════
# 4. RETAINING / CHEEK WALLS alongside stairs
# ════════════════════════════════════════════
for side in (-1, 1):
    # Outer cheek wall (full height, runs along the staircase)
    ow_x = side * (stair_outer_x + WALL_T / 2.0)
    ow_h = LEVEL_DROP + 0.5
    ow_cy = (stair_top_y + stair_bot_y) / 2.0
    ow_hl = abs(stair_top_y - stair_bot_y) / 2.0
    box(f"cheek_outer_{side}", ow_x, ow_cy, lower_z + ow_h / 2.0,
        WALL_T / 2.0, ow_hl, ow_h / 2.0, sandstone)

    # Inner cheek wall (between stair and arcade mouth)
    iw_x = side * (stair_inner_x - WALL_T / 2.0)
    box(f"cheek_inner_{side}", iw_x, ow_cy, lower_z + ow_h / 2.0,
        WALL_T / 2.0, ow_hl, ow_h / 2.0, sandstone)

# Back wall connecting inner cheek walls (behind arcade exit, north face)
back_wall_y = stair_bot_y - 0.5
box("back_wall", 0, back_wall_y, lower_z + LEVEL_DROP / 2.0,
    stair_outer_x + WALL_T, 0.35, LEVEL_DROP / 2.0, sandstone)


# ════════════════════════════════════════════
# 5. LOWER TERRACE PLATFORM
# ════════════════════════════════════════════
landing_depth = 4.0
landing_cy = stair_bot_y - landing_depth / 2.0
box("lower_platform", 0, landing_cy, lower_z - 0.15,
    stair_outer_x + WALL_T + 2.0, landing_depth / 2.0, 0.15, stair_mat)


# ════════════════════════════════════════════
# 6. BALUSTRADES
# ════════════════════════════════════════════

def add_balustrade_run(x_start, x_end, y_pos, z_base, prefix, along='X'):
    """Stone balustrade with posts, rail, and balusters along X axis."""
    length = abs(x_end - x_start)
    if length < 0.5:
        return
    n_posts = max(2, round(length / BAL_SPACING) + 1)
    spacing = length / (n_posts - 1)
    dx = 1 if x_end > x_start else -1

    for i in range(n_posts):
        px = x_start + i * spacing * dx
        # Post
        box(f"{prefix}_p{i}", px, y_pos, z_base + BALUSTRADE_H / 2.0,
            BAL_POST_W / 2.0, BAL_POST_D / 2.0, BALUSTRADE_H / 2.0, brownstone)
        # Cap
        box(f"{prefix}_c{i}", px, y_pos, z_base + BALUSTRADE_H + 0.03,
            BAL_POST_W / 2.0 + 0.03, BAL_POST_D / 2.0 + 0.03, 0.04, brownstone)

    # Top rail
    mid_x = (x_start + x_end) / 2.0
    box(f"{prefix}_tr", mid_x, y_pos, z_base + BALUSTRADE_H - BAL_RAIL_H / 2.0,
        length / 2.0, BAL_RAIL_D / 2.0, BAL_RAIL_H / 2.0, sandstone)
    # Bottom rail
    box(f"{prefix}_br", mid_x, y_pos, z_base + 0.12,
        length / 2.0, BAL_RAIL_D / 2.0 - 0.01, 0.04, sandstone)

    # Balusters
    for i in range(n_posts - 1):
        seg_s = x_start + i * spacing * dx + BAL_POST_W / 2.0 * dx + 0.03 * dx
        seg_e = x_start + (i + 1) * spacing * dx - BAL_POST_W / 2.0 * dx - 0.03 * dx
        seg_len = abs(seg_e - seg_s)
        n_b = max(1, round(seg_len / (BALUSTER_W + 0.10)))
        for bi in range(n_b):
            bx = seg_s + (bi + 0.5) * (seg_e - seg_s) / n_b
            bh = BALUSTRADE_H - BAL_RAIL_H - 0.20
            box(f"{prefix}_b{i}_{bi}", bx, y_pos,
                z_base + 0.16 + bh / 2.0,
                BALUSTER_W / 2.0, BALUSTER_W / 2.0, bh / 2.0, sandstone)


def add_balustrade_y(y_start, y_end, x_pos, z_base, prefix):
    """Balustrade running along Y axis."""
    length = abs(y_end - y_start)
    if length < 0.5:
        return
    n_posts = max(2, round(length / BAL_SPACING) + 1)
    spacing = length / (n_posts - 1)
    dy = 1 if y_end > y_start else -1

    for i in range(n_posts):
        py = y_start + i * spacing * dy
        box(f"{prefix}_p{i}", x_pos, py, z_base + BALUSTRADE_H / 2.0,
            BAL_POST_D / 2.0, BAL_POST_W / 2.0, BALUSTRADE_H / 2.0, brownstone)
        box(f"{prefix}_c{i}", x_pos, py, z_base + BALUSTRADE_H + 0.03,
            BAL_POST_D / 2.0 + 0.03, BAL_POST_W / 2.0 + 0.03, 0.04, brownstone)

    mid_y = (y_start + y_end) / 2.0
    box(f"{prefix}_tr", x_pos, mid_y, z_base + BALUSTRADE_H - BAL_RAIL_H / 2.0,
        BAL_RAIL_D / 2.0, length / 2.0, BAL_RAIL_H / 2.0, sandstone)
    box(f"{prefix}_br", x_pos, mid_y, z_base + 0.12,
        BAL_RAIL_D / 2.0 - 0.01, length / 2.0, 0.04, sandstone)

    for i in range(n_posts - 1):
        seg_s = y_start + i * spacing * dy + BAL_POST_W / 2.0 * dy + 0.03 * dy
        seg_e = y_start + (i + 1) * spacing * dy - BAL_POST_W / 2.0 * dy - 0.03 * dy
        n_b = max(1, round(abs(seg_e - seg_s) / (BALUSTER_W + 0.10)))
        for bi in range(n_b):
            by = seg_s + (bi + 0.5) * (seg_e - seg_s) / n_b
            bh = BALUSTRADE_H - BAL_RAIL_H - 0.20
            box(f"{prefix}_b{i}_{bi}", x_pos, by,
                z_base + 0.16 + bh / 2.0,
                BALUSTER_W / 2.0, BALUSTER_W / 2.0, bh / 2.0, sandstone)


# South edge (upper terrace, looking back toward Mall)
south_y = ARCADE_L / 2.0 + wing_depth
add_balustrade_run(-TERRACE_W / 2.0, TERRACE_W / 2.0, south_y, upper_z, "bal_s")

# North edge — west wing (upper terrace, overlooking stairs)
add_balustrade_run(-TERRACE_W / 2.0, -stair_outer_x - WALL_T,
                   stair_top_y, upper_z, "bal_nw")
# North edge — east wing
add_balustrade_run(stair_outer_x + WALL_T, TERRACE_W / 2.0,
                   stair_top_y, upper_z, "bal_ne")

# East and west terrace edges (upper, connecting south to north)
for side in (-1, 1):
    ex = side * TERRACE_W / 2.0
    label = "e" if side > 0 else "w"
    add_balustrade_y(stair_top_y, south_y, ex, upper_z, f"bal_{label}_edge")

# Stair cheek wall cap balustrades (run along Y on top of cheek walls)
for side in (-1, 1):
    ow_x = side * (stair_outer_x + WALL_T / 2.0)
    add_balustrade_y(stair_bot_y, stair_top_y, ow_x, upper_z - 0.5, f"bal_chk_{side}")


# ════════════════════════════════════════════
# 7. NEWEL POSTS at stair tops
# ════════════════════════════════════════════
newel_size = 0.30
newel_h = BALUSTRADE_H + 0.3
for side in (-1, 1):
    for edge in (-1, 1):  # inner and outer edge of each staircase
        if edge == -1:
            nx = side * stair_inner_x
        else:
            nx = side * (stair_outer_x + WALL_T)
        ny = stair_top_y
        box(f"newel_{side}_{edge}", nx, ny, upper_z + newel_h / 2.0,
            newel_size / 2.0, newel_size / 2.0, newel_h / 2.0, brownstone)
        # Urn / finial on top (simplified as a sphere-ish cylinder)
        add_cy_name = f"newel_urn_{side}_{edge}"
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=0.18, segments=10, ring_count=6,
            location=(nx, ny, upper_z + newel_h + 0.18))
        urn = bpy.context.active_object
        urn.name = add_cy_name
        urn.data.materials.append(brownstone)
        all_parts.append(urn)


# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

terrace = bpy.context.active_object
terrace.name = "BethesdaTerrace"
# Set origin at arcade floor center (0, 0, 0 in Blender = arcade_floor_z = 0).
# This means in Godot, position.y = terrain_y puts the lower terrace at ground level.
# The 3D cursor is already at world origin, so ORIGIN_CURSOR does it.
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

# Export
out_path = "/home/chris/central-park-walk/models/furniture/cp_bethesda_terrace.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported Bethesda Terrace to {out_path}")
print(f"  Parts joined: {len(all_parts)}")
print(f"  Vertices: {len(terrace.data.vertices)}")
print(f"  Faces: {len(terrace.data.polygons)}")
