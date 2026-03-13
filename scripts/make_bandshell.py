"""Generate Naumburg Bandshell for Central Park Walk.

The Naumburg Bandshell (1923, Elkan Naumburg) is a Neoclassical open-air
concert stage on the east side of the Mall, near 72nd Street. Used for
free public concerts since its dedication.

Key features:
  - Raised stone stage platform (~14m × 8m, ~1m high)
  - 3 full-width stone steps leading up to stage
  - 8 Tuscan columns across the front
  - Entablature/cornice band above columns
  - Semicircular acoustic shell (quarter-sphere reflector, ~12m wide × ~10m tall)
  - Decorative stone balustrade atop the shell

Layout (Blender Z-up, Y-forward):
  +Y = toward audience (south / Mall side)
  -Y = back of shell (north)
  Origin at ground center-front of stage

Exports to models/furniture/cp_bandshell.glb
"""

import bpy
import math
import os

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

limestone    = make_mat("Limestone",   (0.68, 0.64, 0.58), 0.82)
column_stone = make_mat("ColumnStone", (0.72, 0.68, 0.62), 0.78)

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    """Axis-aligned box at center (cx,cy,cz) with half-extents (hx,hy,hz)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

def cylinder(name, cx, cy, cz, radius, height, mat, segments=16):
    """Upright cylinder, bottom at cz."""
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=height, vertices=segments,
        location=(cx, cy, cz + height / 2.0))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat)
    all_parts.append(o)
    return o


# ════════════════════════════════════════════════════════════
# DIMENSIONS
# ════════════════════════════════════════════════════════════
STAGE_W    = 14.0    # stage width (X)
STAGE_D    = 8.0     # stage depth (Y, from front edge to back wall)
STAGE_H    = 1.00    # stage platform height above ground
STEP_RISE  = 0.333   # each of 3 steps = STAGE_H / 3
STEP_RUN   = 0.35    # tread depth

N_COLS     = 8       # Tuscan columns across front
COL_R      = 0.28    # column radius at shaft
COL_H      = 5.8     # shaft height (entablature base)
COL_BASE_R = 0.34    # base/plinth radius
COL_BASE_H = 0.22    # plinth height
COL_CAP_R  = 0.36    # capital width
COL_CAP_H  = 0.28    # capital slab height

ENTAB_H    = 0.65    # entablature band height
ENTAB_T    = 0.55    # entablature depth (Y)

SHELL_R    = 6.0     # half-width of acoustic shell (X radius)
SHELL_H    = 10.0    # shell apex height from stage floor
SHELL_T    = 0.40    # shell wall thickness
SHELL_SEGS = 20      # arc subdivisions

BAL_H      = 0.75    # balustrade height atop shell
BAL_POST_W = 0.14    # baluster width
BAL_RAIL_H = 0.12    # handrail height
BAL_SPACE  = 0.55    # baluster spacing

# Derived
STAGE_FRONT_Y  = 0.0             # front edge of stage (audience side)
STAGE_BACK_Y   = -(STAGE_D)      # back wall of stage
STEP_TOT_RUN   = 3 * STEP_RUN    # total stair run depth
STAIR_FRONT_Y  = STAGE_FRONT_Y + STEP_TOT_RUN  # front edge of bottom step

# Column positions (evenly spaced across stage width)
col_spacing = STAGE_W / (N_COLS - 1)
col_xs = [-STAGE_W / 2.0 + i * col_spacing for i in range(N_COLS)]
COL_FRONT_Y = STAGE_FRONT_Y - COL_R - 0.05  # columns sit just inside front edge

# Shell back center (shell arc center = stage back wall at stage floor level)
SHELL_CY = STAGE_BACK_Y          # center Y of the arc (at back wall)
SHELL_Z0 = STAGE_H               # shell base = stage floor height

# ════════════════════════════════════════════════════════════
# 1. STEPS — 3 full-width stone steps (descend toward audience)
# ════════════════════════════════════════════════════════════
step_w = STAGE_W + 0.40   # steps slightly wider than stage
for i in range(3):
    # Step i: i=0 is bottom (ground level), i=2 is top (meets stage floor)
    step_bot_z = i * STEP_RISE
    step_top_z = (i + 1) * STEP_RISE
    step_front_y = STAIR_FRONT_Y - i * STEP_RUN
    step_back_y  = step_front_y - STEP_RUN
    step_cz = step_bot_z + STEP_RISE / 2.0
    step_cy = (step_front_y + step_back_y) / 2.0
    box(f"step_{i}", 0, step_cy, step_cz,
        step_w / 2.0, STEP_RUN / 2.0, STEP_RISE / 2.0, limestone)

# ════════════════════════════════════════════════════════════
# 2. STAGE PLATFORM
# ════════════════════════════════════════════════════════════
stage_cy = (STAGE_FRONT_Y + STAGE_BACK_Y) / 2.0
box("stage_platform", 0, stage_cy, STAGE_H / 2.0,
    STAGE_W / 2.0, STAGE_D / 2.0, STAGE_H / 2.0, limestone)

# Side returns of stage (slightly thicker reveal at front corners)
for side in (-1, 1):
    box(f"stage_side_{side}", side * (STAGE_W / 2.0 + 0.12),
        stage_cy - 0.5, STAGE_H / 2.0,
        0.12, STAGE_D / 2.0 - 0.5, STAGE_H / 2.0, limestone)

# ════════════════════════════════════════════════════════════
# 3. COLUMNS — 8 Tuscan columns across stage front
# ════════════════════════════════════════════════════════════
for i, cx in enumerate(col_xs):
    # Base/plinth
    cylinder(f"col_base_{i}", cx, COL_FRONT_Y, STAGE_H,
             COL_BASE_R, COL_BASE_H, column_stone, 16)
    # Shaft
    cylinder(f"col_shaft_{i}", cx, COL_FRONT_Y, STAGE_H + COL_BASE_H,
             COL_R, COL_H, column_stone, 16)
    # Capital (wider flat slab)
    cylinder(f"col_cap_{i}", cx, COL_FRONT_Y, STAGE_H + COL_BASE_H + COL_H,
             COL_CAP_R, COL_CAP_H, column_stone, 16)

# ════════════════════════════════════════════════════════════
# 4. ENTABLATURE — continuous beam above columns
# ════════════════════════════════════════════════════════════
entab_z = STAGE_H + COL_BASE_H + COL_H + COL_CAP_H
# Main horizontal beam (full width, deep)
box("entablature", 0, COL_FRONT_Y - ENTAB_T / 2.0,
    entab_z + ENTAB_H / 2.0,
    STAGE_W / 2.0 + 0.25, ENTAB_T / 2.0, ENTAB_H / 2.0, limestone)
# Cornice overhang (slightly projecting cap on top)
box("cornice", 0, COL_FRONT_Y - ENTAB_T / 2.0,
    entab_z + ENTAB_H + 0.10,
    STAGE_W / 2.0 + 0.40, ENTAB_T / 2.0 + 0.12, 0.12, limestone)

# Side entablature returns (wrap to shell wall)
for side in (-1, 1):
    ret_cx = side * (STAGE_W / 2.0 + 0.12)
    ret_len = abs(STAGE_BACK_Y - COL_FRONT_Y) / 2.0
    ret_cy  = (STAGE_BACK_Y + COL_FRONT_Y) / 2.0
    box(f"entab_return_{side}", ret_cx, ret_cy,
        entab_z + ENTAB_H / 2.0,
        0.30, ret_len, ENTAB_H / 2.0, limestone)

# ════════════════════════════════════════════════════════════
# 5. ACOUSTIC SHELL — semicircular quarter-sphere arc
#    Arc sweeps 180° in XZ plane (semicircle) along Y depth.
#    The shell faces forward (+Y), open to audience.
#    Built as a ring of vertical arc-segment panels arranged in a
#    half-circle plan — each panel is a thin box rotated to follow
#    the arc, giving a faceted shell approximation without bmesh.
# ════════════════════════════════════════════════════════════

# The shell is a quarter-sphere cross-section:
#   - In plan (XY): semicircle of radius SHELL_R, open toward +Y
#   - In section (ZY): quarter-circle arc rising from SHELL_Z0 to SHELL_H
#
# Build with pydata: generate a shell mesh from parametric arc.
# theta = azimuth (plan, 0=right +X, pi=left -X), 0..pi
# phi   = elevation (section, 0=floor, pi/2=apex)

THETA_SEGS = 18   # plan subdivisions (half-circle plan)
PHI_SEGS   = 12   # elevation subdivisions (quarter-circle section)

shell_verts = []
shell_faces = []

def shell_pt(theta, phi):
    """Point on the outer surface of the shell.

    Quarter-sphere surface of revolution:
      theta in [0, pi]   — plan azimuth (0=+X, pi=-X)
      phi   in [0, pi/2] — elevation (0=floor, pi/2=apex)
      r(phi) = SHELL_R * cos(phi)  (horizontal radius narrows toward apex)
      X = r * cos(theta)
      Y = SHELL_CY - r * sin(theta)  (concave face opens toward +Y audience)
      Z = SHELL_Z0 + SHELL_H * sin(phi)
    """
    r = SHELL_R * math.cos(phi)
    x = r * math.cos(theta)
    y = SHELL_CY - SHELL_R * math.cos(phi) * math.sin(theta)
    z = SHELL_Z0 + SHELL_H * math.sin(phi)
    return (x, y, z)

def shell_pt_inner(theta, phi):
    r = (SHELL_R - SHELL_T) * math.cos(phi)
    x = r * math.cos(theta)
    y = SHELL_CY - (SHELL_R - SHELL_T) * math.cos(phi) * math.sin(theta)
    z = SHELL_Z0 + SHELL_H * math.sin(phi)
    return (x, y, z)

# Build vertex grid: outer surface
# Indices: [phi_i * (THETA_SEGS+1) + theta_i]  for outer
# Offset by (PHI_SEGS+1)*(THETA_SEGS+1) for inner

n_phi   = PHI_SEGS + 1
n_theta = THETA_SEGS + 1
outer_off = 0
inner_off = n_phi * n_theta

for pi_i in range(n_phi):
    phi = (math.pi / 2.0) * pi_i / PHI_SEGS
    for ti in range(n_theta):
        theta = math.pi * ti / THETA_SEGS
        shell_verts.append(shell_pt(theta, phi))

for pi_i in range(n_phi):
    phi = (math.pi / 2.0) * pi_i / PHI_SEGS
    for ti in range(n_theta):
        theta = math.pi * ti / THETA_SEGS
        shell_verts.append(shell_pt_inner(theta, phi))

# Outer surface faces
for pi_i in range(PHI_SEGS):
    for ti in range(THETA_SEGS):
        a = outer_off + pi_i * n_theta + ti
        b = outer_off + pi_i * n_theta + ti + 1
        c = outer_off + (pi_i + 1) * n_theta + ti + 1
        d = outer_off + (pi_i + 1) * n_theta + ti
        shell_faces.append((a, b, c, d))  # outer face (normals outward)

# Inner surface faces (reverse winding)
for pi_i in range(PHI_SEGS):
    for ti in range(THETA_SEGS):
        a = inner_off + pi_i * n_theta + ti
        b = inner_off + pi_i * n_theta + ti + 1
        c = inner_off + (pi_i + 1) * n_theta + ti + 1
        d = inner_off + (pi_i + 1) * n_theta + ti
        shell_faces.append((a, d, c, b))  # inner face (normals inward)

# Bottom edge cap (phi=0: connect outer row 0 to inner row 0)
for ti in range(THETA_SEGS):
    a = outer_off + ti
    b = outer_off + ti + 1
    c = inner_off + ti + 1
    d = inner_off + ti
    shell_faces.append((a, d, c, b))

# Top edge cap (phi=pi/2: apex row)
apex_phi = PHI_SEGS
for ti in range(THETA_SEGS):
    a = outer_off + apex_phi * n_theta + ti
    b = outer_off + apex_phi * n_theta + ti + 1
    c = inner_off + apex_phi * n_theta + ti + 1
    d = inner_off + apex_phi * n_theta + ti
    shell_faces.append((a, b, c, d))

# Side edge caps at theta=0 (+X side) and theta=pi (-X side)
for pi_i in range(PHI_SEGS):
    # theta=0 side
    a = outer_off + pi_i * n_theta + 0
    b = outer_off + (pi_i + 1) * n_theta + 0
    c = inner_off + (pi_i + 1) * n_theta + 0
    d = inner_off + pi_i * n_theta + 0
    shell_faces.append((a, b, c, d))
    # theta=pi side (last column)
    a = outer_off + pi_i * n_theta + THETA_SEGS
    b = outer_off + (pi_i + 1) * n_theta + THETA_SEGS
    c = inner_off + (pi_i + 1) * n_theta + THETA_SEGS
    d = inner_off + pi_i * n_theta + THETA_SEGS
    shell_faces.append((a, d, c, b))

shell_mesh = bpy.data.meshes.new("shell_mesh")
shell_mesh.from_pydata(shell_verts, [], shell_faces)
shell_mesh.update()
shell_obj = bpy.data.objects.new("AcousticShell", shell_mesh)
bpy.context.collection.objects.link(shell_obj)
shell_obj.data.materials.append(limestone)
all_parts.append(shell_obj)

# ════════════════════════════════════════════════════════════
# 6. BACK WALL — solid masonry wall behind shell bottom opening
#    Fills the gap between stage floor and shell base at Y=SHELL_CY
# ════════════════════════════════════════════════════════════
# The shell's bottom edge sits at Z=SHELL_Z0 (=stage floor level)
# The stage platform back face is at Y=STAGE_BACK_Y = SHELL_CY
# Fill solid wall from stage floor up to entablature height
back_wall_h = entab_z + ENTAB_H
box("back_wall", 0, STAGE_BACK_Y - SHELL_T / 2.0,
    back_wall_h / 2.0,
    STAGE_W / 2.0, SHELL_T / 2.0, back_wall_h / 2.0, limestone)

# Side wing walls (flanking the shell, from back wall to column line)
wing_len = abs(STAGE_BACK_Y - COL_FRONT_Y)
for side in (-1, 1):
    wing_cx = side * (STAGE_W / 2.0 + 0.30)
    wing_cy = (STAGE_BACK_Y + COL_FRONT_Y) / 2.0
    wing_h  = entab_z + ENTAB_H
    box(f"wing_wall_{side}", wing_cx, wing_cy,
        wing_h / 2.0,
        0.30, wing_len / 2.0, wing_h / 2.0, limestone)

# ════════════════════════════════════════════════════════════
# 7. BALUSTRADE atop the shell
#    Runs along the top edge of the shell at its crest.
#    The shell apex is at Z = SHELL_Z0 + SHELL_H, Y = SHELL_CY.
#    In plan the apex is a single point (the top of the quarter-sphere),
#    but the top edge of the shell at phi near pi/2 (near apex) is small.
#    More visually useful: place balustrade along the front rim of the
#    shell (phi=0 row, the visible silhouette from the audience).
#    The front rim of the shell (phi=0) spans X=-SHELL_R..+SHELL_R at
#    Y=SHELL_CY (back), Z=SHELL_Z0. That's the floor — not visible.
#    Place balustrade at the top outer edge: run a row of balusters
#    along the top cornice of the back wall (Y=STAGE_BACK_Y, Z=entab_z+ENTAB_H).
# ════════════════════════════════════════════════════════════
bal_z = entab_z + ENTAB_H   # balustrade sits on top of entablature/shell rim
bal_y = STAGE_BACK_Y - SHELL_T / 2.0

# Continuous handrail
box("bal_rail_top", 0, bal_y,
    bal_z + BAL_H - BAL_RAIL_H / 2.0,
    STAGE_W / 2.0 + 0.30, 0.10, BAL_RAIL_H / 2.0, limestone)
# Bottom rail
box("bal_rail_bot", 0, bal_y,
    bal_z + 0.08,
    STAGE_W / 2.0 + 0.30, 0.09, 0.06, limestone)

# Balusters
n_bals = int((STAGE_W + 0.60) / BAL_SPACE)
bal_total_w = STAGE_W + 0.60
for i in range(n_bals):
    bx = -bal_total_w / 2.0 + (i + 0.5) * BAL_SPACE
    box(f"bal_{i}", bx, bal_y,
        bal_z + 0.14 + (BAL_H - BAL_RAIL_H - 0.14) / 2.0,
        BAL_POST_W / 2.0, 0.07, (BAL_H - BAL_RAIL_H - 0.14) / 2.0, column_stone)

# Corner newel posts
for side in (-1, 1):
    nx = side * (bal_total_w / 2.0)
    cylinder(f"newel_{side}", nx, bal_y, bal_z,
             0.12, BAL_H + 0.12, limestone, 12)

# ════════════════════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "NaumburgBandshell"

bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_bandshell.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported Naumburg Bandshell to {out_path}")
print(f"  Parts: {len(all_parts)}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces: {len(obj.data.polygons)}")
