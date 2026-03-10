"""Generate Gapstow Bridge model for Central Park Walk.

Gapstow Bridge — stone arch spanning the north end of The Pond at the
southeast corner of Central Park. Current structure designed by Howard &
Caudwell (1896), replacing Vaux's original 1874 wooden bridge.

Key dimensions:
  SPAN        = 13.4m  (44 ft at base)
  RISE        = 3.66m  (12 ft arch height)
  SIDEWALLS   = 23.2m  (76 ft total walkway length)
  Rise-to-span ratio: ~1:3.7 (segmental arch)

Material: Unadorned Manhattan schist — rough-cut blocks in irregular courses.
No railings — low solid stone parapets (~0.9m).
Inspired by Ponte di San Francesco in San Remo, Italy.

Orientation (Blender Z-up):
  Bridge runs along Y axis. Origin at deck center, Z=0 at deck surface.

Exports to models/furniture/cp_gapstow_bridge.glb
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

# Manhattan schist: dark gray-green with mica
schist = make_mat("Schist", (0.30, 0.30, 0.28), roughness=0.88)
# Lighter schist for arch face
schist_face = make_mat("SchistFace", (0.35, 0.34, 0.31), roughness=0.85)
# Deck surface: worn stone
deck_mat = make_mat("StoneDeck", (0.42, 0.40, 0.37), roughness=0.82)
# Parapet cap
cap_mat = make_mat("ParapetCap", (0.38, 0.36, 0.34), roughness=0.80)

# ── Dimensions ──
SPAN = 13.4          # arch span at springing (m)
HALF_SPAN = SPAN / 2.0
RISE = 3.66           # arch rise (m)
TOTAL_L = 23.2        # total walkway length (m)
HALF_L = TOTAL_L / 2.0
DECK_W = 6.0          # deck width (wider than walkway for stonework)
HALF_W = DECK_W / 2.0
WALL_T = 0.60         # wall/parapet thickness
PARAPET_H = 0.90      # parapet above deck
ARCH_T = 0.50         # arch barrel thickness
ABUT_DEPTH = 3.0      # abutment pier depth
DECK_T = 0.20         # deck surface thickness

# The deck follows the arch profile — it's a humpback bridge
# (walkway curves up and over, not flat)
DECK_RISE = 1.8       # how much the deck humps above the abutments

all_parts = []


def segmental_arc(half_span, rise, n_pts):
    """Generate points for a segmental arch.
    Returns [(x, z)] from -half_span to +half_span."""
    R = (rise * rise + half_span * half_span) / (2.0 * rise)
    cz = rise - R
    pts = []
    for i in range(n_pts + 1):
        t = i / n_pts
        x = -half_span + t * (2 * half_span)
        dx = x
        inner = R * R - dx * dx
        if inner < 0:
            inner = 0
        z = cz + math.sqrt(inner)
        pts.append((x, z))
    return pts


def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o


# ── 1. Arch barrel vault ──
# The inner surface of the arch (visible from underneath)
arc_pts = segmental_arc(HALF_SPAN, RISE, 32)

mesh = bpy.data.meshes.new("arch_barrel")
verts = []
faces = []
n_arc = len(arc_pts)

# Create barrel vault: inner and outer surfaces across the bridge width
for px, pz in arc_pts:
    z = pz - RISE  # shift so deck crown is at Z=0
    # Inner surface (4 verts per arc point: left/right × inner/outer)
    verts.append((px, -HALF_W, z))
    verts.append((px,  HALF_W, z))
    verts.append((px, -HALF_W, z - ARCH_T))
    verts.append((px,  HALF_W, z - ARCH_T))

for i in range(n_arc - 1):
    b = i * 4
    nb = (i + 1) * 4
    # Inner surface (visible from below — looking up at arch)
    faces.append((b, b + 1, nb + 1, nb))
    # Outer surface (hidden, but needed for proper mesh)
    faces.append((b + 2, nb + 2, nb + 3, b + 3))
    # Side faces (left and right edges of barrel)
    faces.append((b, nb, nb + 2, b + 2))
    faces.append((b + 1, b + 3, nb + 3, nb + 1))

mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new("arch_barrel", mesh)
bpy.context.collection.objects.link(obj)
obj.data.materials.append(schist_face)
all_parts.append(obj)

# ── 2. Arch face walls (visible stone face on each side) ──
# The spandrel walls — fill between arch curve and deck profile
for side in (-1, 1):
    sy = side * HALF_W
    mesh = bpy.data.meshes.new(f"spandrel_face_{side}")
    verts = []
    faces = []

    # For each point along the arch, create vertices at arch level and deck level
    for i, (px, pz) in enumerate(arc_pts):
        z_arch = pz - RISE
        # Deck follows a gentler hump profile
        t = (px + HALF_SPAN) / SPAN  # 0 to 1 along bridge
        z_deck = DECK_RISE * math.sin(t * math.pi)  # sinusoidal hump
        verts.append((px, sy, z_arch))
        verts.append((px, sy, z_deck))

    for i in range(n_arc - 1):
        b = i * 2
        nb = (i + 1) * 2
        if side > 0:
            faces.append((b, nb, nb + 1, b + 1))
        else:
            faces.append((b, b + 1, nb + 1, nb))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(f"spandrel_face_{side}", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(schist)
    all_parts.append(obj)

# ── 3. Deck surface (follows hump profile) ──
n_deck = 24
mesh = bpy.data.meshes.new("deck_surface")
verts = []
faces = []

for i in range(n_deck + 1):
    t = i / n_deck
    x = -HALF_L + t * TOTAL_L
    z = DECK_RISE * math.sin(t * math.pi)  # hump profile

    verts.append((x, -HALF_W, z))
    verts.append((x,  HALF_W, z))
    verts.append((x, -HALF_W, z - DECK_T))
    verts.append((x,  HALF_W, z - DECK_T))

for i in range(n_deck):
    b = i * 4
    nb = (i + 1) * 4
    # Top surface
    faces.append((b, b + 1, nb + 1, nb))
    # Bottom surface
    faces.append((b + 2, nb + 2, nb + 3, b + 3))

mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new("deck_surface", mesh)
bpy.context.collection.objects.link(obj)
obj.data.materials.append(deck_mat)
all_parts.append(obj)

# ── 4. Parapets (solid stone walls along bridge edges) ──
# Follow the deck hump profile
for side in (-1, 1):
    py = side * (HALF_W - WALL_T / 2)
    mesh = bpy.data.meshes.new(f"parapet_{side}")
    verts = []
    faces = []

    for i in range(n_deck + 1):
        t = i / n_deck
        x = -HALF_L + t * TOTAL_L
        z_base = DECK_RISE * math.sin(t * math.pi)

        # Inner face and outer face of parapet
        inner_y = py - side * WALL_T / 2
        outer_y = py + side * WALL_T / 2
        verts.append((x, inner_y, z_base))
        verts.append((x, inner_y, z_base + PARAPET_H))
        verts.append((x, outer_y, z_base))
        verts.append((x, outer_y, z_base + PARAPET_H))

    for i in range(n_deck):
        b = i * 4
        nb = (i + 1) * 4
        # Inner face
        if side > 0:
            faces.append((b, b + 1, nb + 1, nb))
        else:
            faces.append((b, nb, nb + 1, b + 1))
        # Outer face
        if side > 0:
            faces.append((b + 2, nb + 2, nb + 3, b + 3))
        else:
            faces.append((b + 2, b + 3, nb + 3, nb + 2))
        # Top face
        faces.append((b + 1, b + 3, nb + 3, nb + 1))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(f"parapet_{side}", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(schist)
    all_parts.append(obj)

# ── 5. Parapet caps (slightly protruding stone coping) ──
for side in (-1, 1):
    py = side * (HALF_W - WALL_T / 2)
    mesh = bpy.data.meshes.new(f"cap_{side}")
    verts = []
    faces = []
    cap_overhang = 0.05

    for i in range(n_deck + 1):
        t = i / n_deck
        x = -HALF_L + t * TOTAL_L
        z = DECK_RISE * math.sin(t * math.pi) + PARAPET_H

        inner_y = py - side * (WALL_T / 2 + cap_overhang)
        outer_y = py + side * (WALL_T / 2 + cap_overhang)
        verts.append((x, inner_y, z))
        verts.append((x, outer_y, z))
        verts.append((x, inner_y, z + 0.08))
        verts.append((x, outer_y, z + 0.08))

    for i in range(n_deck):
        b = i * 4
        nb = (i + 1) * 4
        # Top face
        faces.append((b + 2, b + 3, nb + 3, nb + 2))
        # Outer side
        faces.append((b + 1, nb + 1, nb + 3, b + 3))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(f"cap_{side}", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(cap_mat)
    all_parts.append(obj)

# ── 6. Abutments (stone piers at each end) ──
for end in (-1, 1):
    ax = end * (HALF_L + ABUT_DEPTH / 2 - 0.3)
    # Abutments taper into the ground
    box(f"abutment_{end}", ax, 0, -1.5,
        ABUT_DEPTH / 2, HALF_W + 0.3, 1.5, schist)

# ── 7. Fill walls between abutments and arch ──
# The approach walls connecting the walkway to the arch
for end in (-1, 1):
    for side in (-1, 1):
        # Wall from abutment to arch springing point
        wx = end * (HALF_SPAN + (HALF_L - HALF_SPAN) / 2)
        wy = side * (HALF_W - WALL_T / 2)
        wl = HALF_L - HALF_SPAN
        wh = 1.5
        box(f"approach_wall_{end}_{side}",
            wx, wy, -wh / 2,
            wl / 2, WALL_T / 2, wh / 2, schist)


# ── Finalize ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

bridge = bpy.context.active_object
bridge.name = "GapstowBridge"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

# Export
out_path = "/home/chris/central-park-walk/models/furniture/cp_gapstow_bridge.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported Gapstow Bridge to {out_path}")
print(f"  Verts: {len(bridge.data.vertices)}, Faces: {len(bridge.data.polygons)}")
