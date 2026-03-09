"""Generate Trefoil Arch model for Central Park walk.

Key parameters:
  SPAN        = 4.0m    (clear opening width)
  RISE        = 3.2m    (arch crown above path)
  DEPTH       = 6.0m    (passage length through the arch)
  WALL_H      = 5.5m    (total wall height including parapet)
  WALL_T      = 0.8m    (wall thickness)
  PARAPET_H   = 0.9m    (railing above road deck)

The trefoil shape: three overlapping circles forming a clover-leaf arch,
characteristic of several Central Park arches designed by Calvert Vaux.

Orientation (Blender Z-up):
  Passage runs along Y axis. Origin at path level center of arch.

Materials: Brownstone (walls), Sandstone (arch trim + parapet), StairStone (road deck)
Exports to models/furniture/cp_trefoil_arch.glb
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

brownstone = make_mat("Brownstone", (0.45, 0.35, 0.26), 0.82)
sandstone  = make_mat("Sandstone",  (0.70, 0.63, 0.50), 0.78)
road_mat   = make_mat("RoadDeck",   (0.50, 0.48, 0.44), 0.85)
floor_mat  = make_mat("PathFloor",  (0.58, 0.54, 0.46), 0.82)

# ── Constants ──
SPAN    = 4.5       # clear opening width
RISE    = 3.8       # arch crown height above path floor
DEPTH   = 6.0       # passage length (Y direction)
WALL_H  = 4.8       # total wall height (path floor to road surface)
WALL_T  = 0.8       # wall thickness on each side
ROAD_T  = 0.5       # road deck thickness above arch
PARAPET_H = 0.9     # parapet/railing above road
PARAPET_T = 0.3     # parapet thickness

# Trefoil geometry: three overlapping arcs
# Center lobe radius ~ 0.55 * SPAN/2, side lobes smaller
CENTER_R = SPAN * 0.42   # center lobe radius
SIDE_R   = SPAN * 0.30   # side lobe radius
SPRING_H = RISE * 0.45   # height where side lobes spring from

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx, hy, hz)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o


def arc_pts(cx, cz, r, a0, a1, n):
    """Arc from angle a0 to a1 (radians, counterclockwise)."""
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n),
             cz + r * math.sin(a0 + (a1 - a0) * i / n))
            for i in range(n + 1)]


def trefoil_profile():
    """Trefoil arch profile — three circular lobes with cusps between them.
    Returns (x, z) points traced from right base counterclockwise to left base."""
    hs = SPAN / 2.0

    # Lobe geometry — three circles of equal radius
    r = hs * 0.55          # lobe radius (1.1m for 4m span)
    side_h = r * 0.85      # side lobe center height
    sep = hs * 0.55        # horizontal offset of side lobe centers
    top_h = RISE - r       # top lobe center height

    # Right lobe: center at (sep, side_h), arc from ~-30° to ~120°
    # Bottom of right lobe touches the right wall base
    r_a0 = math.atan2(0 - side_h, hs - sep)  # angle to right base
    r_a1 = math.pi * 0.65                      # angle to right cusp
    right_pts = arc_pts(sep, side_h, r, r_a0, r_a1, 10)

    # Top lobe: center at (0, top_h), arc from right cusp to left cusp
    # The cusps are roughly at ±45° below horizontal on the top circle
    t_a0 = math.pi * 0.15    # right cusp angle on top circle
    t_a1 = math.pi * 0.85    # left cusp angle on top circle
    top_pts = arc_pts(0, top_h, r, t_a0, t_a1, 14)

    # Left lobe: center at (-sep, side_h), arc from left cusp to left base
    l_a0 = math.pi * 0.35    # left cusp angle
    l_a1 = math.pi - r_a0    # mirror of right base angle
    left_pts = arc_pts(-sep, side_h, r, l_a0, l_a1, 10)

    # Combine: right base → right lobe → top lobe → left lobe → left base
    pts = [(hs, 0.0)]
    pts += right_pts
    pts += top_pts
    pts += left_pts
    pts += [(-hs, 0.0)]

    # Clamp Z >= 0
    pts = [(x, max(0.0, z)) for x, z in pts]
    return pts


def build_arch_wall(y_pos, face_dir, profile_pts):
    """Build one face of the arch (the visible wall with trefoil cutout).
    face_dir: 1 for +Y face normal, -1 for -Y face normal."""
    half_span = SPAN / 2.0
    outer_hw = half_span + WALL_T  # half width including walls

    # The wall face is a rectangle with the trefoil arch cut out.
    # Build as a mesh: outer rectangle minus arch profile.
    verts = []
    faces = []

    n_prof = len(profile_pts)

    # Vertices: arch profile points (inner opening) + outer rectangle corners
    for px, pz in profile_pts:
        verts.append((px, y_pos, pz))

    # Outer rectangle: bottom-left, bottom-right, top-right, top-left
    rect_start = n_prof
    verts.append((-outer_hw, y_pos, 0.0))           # BL
    verts.append((outer_hw, y_pos, 0.0))             # BR
    verts.append((outer_hw, y_pos, WALL_H))          # TR
    verts.append((-outer_hw, y_pos, WALL_H))         # TL

    # Fill the wall area between arch profile and rectangle using triangle fan approach.
    # Left wall section: from rect BL up to rect TL, across to arch left side
    # This is complex — use a simpler approach: build as separate quads/tris

    # Approach: create the wall as several rectangular sections
    # 1. Left pier: rect from -outer_hw to -half_span, full height
    # 2. Right pier: rect from half_span to outer_hw, full height
    # 3. Above arch: rect from -half_span to half_span, from arch crown to WALL_H
    # 4. Arch surround: triangulated fill between arch profile and the rectangles above

    # For simplicity, build solid quads for the rectangular regions
    # and a mesh strip above the arch profile

    mesh = bpy.data.meshes.new(f"arch_face_{face_dir}")
    mverts = []
    mfaces = []

    # Left pier
    bl = (-outer_hw, y_pos, 0.0)
    br = (-half_span, y_pos, 0.0)
    tr = (-half_span, y_pos, WALL_H)
    tl = (-outer_hw, y_pos, WALL_H)
    base = len(mverts)
    mverts.extend([bl, br, tr, tl])
    if face_dir > 0:
        mfaces.append((base, base+1, base+2, base+3))
    else:
        mfaces.append((base, base+3, base+2, base+1))

    # Right pier
    bl = (half_span, y_pos, 0.0)
    br = (outer_hw, y_pos, 0.0)
    tr = (outer_hw, y_pos, WALL_H)
    tl = (half_span, y_pos, WALL_H)
    base = len(mverts)
    mverts.extend([bl, br, tr, tl])
    if face_dir > 0:
        mfaces.append((base, base+1, base+2, base+3))
    else:
        mfaces.append((base, base+3, base+2, base+1))

    # Spandrel above arch: from arch profile up to WALL_H
    # Create a strip: for each arch profile point, add a vertex at WALL_H above
    arch_base_idx = len(mverts)
    for px, pz in profile_pts:
        mverts.append((px, y_pos, pz))       # arch profile point
        mverts.append((px, y_pos, WALL_H))   # top edge point

    for i in range(n_prof - 1):
        a = arch_base_idx + i * 2      # current arch
        b = arch_base_idx + i * 2 + 1  # current top
        c = arch_base_idx + (i+1) * 2 + 1  # next top
        d = arch_base_idx + (i+1) * 2      # next arch
        if face_dir > 0:
            mfaces.append((a, d, c, b))
        else:
            mfaces.append((a, b, c, d))

    mesh.from_pydata(mverts, [], mfaces)
    mesh.update()
    obj = bpy.data.objects.new(f"arch_face_{face_dir}", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(brownstone)
    all_parts.append(obj)


# ── Build the arch ──
profile = trefoil_profile()

# 1. Arch face walls (front and back)
half_depth = DEPTH / 2.0
build_arch_wall(-half_depth, -1, profile)
build_arch_wall(half_depth, 1, profile)

# 2. Side walls (solid blocks connecting front to back)
outer_hw = SPAN / 2.0 + WALL_T
for side in (-1, 1):
    wx = side * (SPAN / 2.0 + WALL_T / 2.0)
    box(f"side_wall_{side}", wx, 0, WALL_H / 2.0,
        WALL_T / 2.0, half_depth, WALL_H / 2.0, brownstone)

# 3. Ceiling / vault inside the passage
# Create an extruded trefoil vault along Y
vault_t = 0.3  # vault shell thickness
vmesh = bpy.data.meshes.new("vault_mesh")
vverts = []
vfaces = []
n_prof = len(profile)

for j in range(2):
    y = -half_depth if j == 0 else half_depth
    for px, pz in profile:
        vverts.append((px, y, pz))                    # inner surface
        vverts.append((px, y, pz + vault_t))          # outer surface (above)

stride = n_prof * 2
for i in range(n_prof - 1):
    for j in range(1):
        # Inner face (visible from below)
        a = j * stride + i * 2
        b = j * stride + (i + 1) * 2
        c = (j + 1) * stride + (i + 1) * 2
        d = (j + 1) * stride + i * 2
        vfaces.append((a, d, c, b))

vmesh.from_pydata(vverts, [], vfaces)
vmesh.update()
vault_obj = bpy.data.objects.new("vault", vmesh)
bpy.context.collection.objects.link(vault_obj)
vault_obj.data.materials.append(sandstone)
all_parts.append(vault_obj)

# 4. Road deck on top
road_z = WALL_H
box("road_deck", 0, 0, road_z + ROAD_T / 2.0,
    outer_hw + 1.0, half_depth + 1.5, ROAD_T / 2.0, road_mat)

# 5. Parapets on top of road
for side in (-1, 1):
    px = side * (outer_hw + 0.5)
    box(f"parapet_{side}", px, 0, road_z + ROAD_T + PARAPET_H / 2.0,
        PARAPET_T / 2.0, half_depth + 1.5, PARAPET_H / 2.0, sandstone)
    # Parapet cap
    box(f"parapet_cap_{side}", px, 0, road_z + ROAD_T + PARAPET_H + 0.04,
        PARAPET_T / 2.0 + 0.04, half_depth + 1.5, 0.04, sandstone)

# 6. Floor slab
box("floor", 0, 0, -0.1,
    SPAN / 2.0 + 0.5, half_depth + 0.5, 0.1, floor_mat)

# 7. Keystone at arch crown + impost blocks at spring line
for face in (-1, 1):
    fy = face * (half_depth + 0.02)
    # Keystone
    box(f"keystone_{face}", 0, fy, RISE - 0.15,
        0.25, 0.08, 0.35, sandstone)
    # Impost blocks where arch meets wall
    for side in (-1, 1):
        box(f"impost_{face}_{side}", side * SPAN / 2.0, fy, RISE * 0.3,
            0.20, 0.08, 0.20, sandstone)

# 9. Wing walls (short retaining walls extending out from the arch)
wing_len = 3.0
wing_h = 2.0
for side in (-1, 1):
    for face in (-1, 1):
        wy = face * (half_depth + wing_len / 2.0)
        wx = side * outer_hw
        # Taper: full height near arch, lower further away
        box(f"wing_{side}_{face}", wx, wy, wing_h / 2.0,
            WALL_T / 2.0, wing_len / 2.0, wing_h / 2.0, brownstone)


# ── Finalize ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

arch = bpy.context.active_object
arch.name = "TrefoilArch"
# Origin at path floor center (0, 0, 0 in Blender)
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

# Export
out_path = "/home/chris/central-park-walk/models/furniture/cp_trefoil_arch.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported Trefoil Arch to {out_path}")
print(f"  Parts: {len(all_parts)}, Verts: {len(arch.data.vertices)}, Faces: {len(arch.data.polygons)}")
