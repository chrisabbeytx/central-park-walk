"""Generate Bow Bridge model for Central Park Walk.

Bow Bridge — the park's most famous bridge, designed by Calvert Vaux and
Jacob Wrey Mould (1859–1862). Cast iron hingeless deck arch spanning
The Lake from Cherry Hill to the Ramble.

Key dimensions (from LOC HABS/HAER, HistoricBridges.org):
  SPAN        = 26.6m  (87 ft 4 in — longest arch span in CP)
  DECK_W      = 4.78m  (15 ft 8 in)
  RISE        = 2.90m  (9 ft 6 in above water)
  BALUSTRADE  = 43.0m  (142 ft total railing length)

Arch profile: very flat segmental curve (rise-to-span ~1:9).
"Resembles the bow of an archer or violinist."

Materials: Cast iron (dark gray), stone abutments.
Railing: Gothic cinquefoil + interlaced spiral circles.
Eight 3.5-ft planting urns along the balustrade.

Orientation (Blender Z-up):
  Bridge runs along Y axis (north-south in park).
  Origin at deck center, Z=0 at deck surface level.

Exports to models/furniture/cp_bow_bridge.glb
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

# Cast iron: dark gray with slight metallic sheen
cast_iron = make_mat("CastIron", (0.22, 0.22, 0.23), roughness=0.65, metallic=0.85)
# Stone abutments: gray masonry
stone_abut = make_mat("StoneAbutment", (0.48, 0.46, 0.42), roughness=0.82)
# Deck surface: slightly lighter iron/stone
deck_mat = make_mat("DeckSurface", (0.38, 0.36, 0.34), roughness=0.75)
# Urn material: weathered cast iron
urn_mat = make_mat("UrnIron", (0.25, 0.25, 0.22), roughness=0.70, metallic=0.80)

# ── Dimensions ──
SPAN = 26.6         # total span (m)
HALF_SPAN = SPAN / 2.0
DECK_W = 4.78       # deck width (m)
HALF_W = DECK_W / 2.0
RISE = 2.90          # arch rise (m) — center of arch above abutment
DECK_T = 0.15        # deck surface thickness
ARCH_T = 0.30        # arch rib thickness (iron)
RAILING_H = 1.10     # railing height above deck
RAILING_T = 0.08     # railing thickness
RAILING_L = 43.0     # total balustrade length
HALF_RAIL = RAILING_L / 2.0
ABUT_W = DECK_W + 0.4  # abutment slightly wider than deck
ABUT_H = 2.5         # abutment height (above water to deck)
ABUT_D = 3.0         # abutment depth (along bridge axis)
N_URNS = 8           # planting urns along balustrade
URN_H = 1.07         # urn height (3.5 ft)
URN_R = 0.35         # urn radius

all_parts = []

# ── Helper: segmental arc points ──
def segmental_arc(half_span, rise, n_pts):
    """Generate points for a very flat segmental arch.
    Returns [(x, z)] from -half_span to +half_span.
    Uses circular arc geometry: R = (h² + d²) / (2h)
    where h = rise, d = half_span."""
    R = (rise * rise + half_span * half_span) / (2.0 * rise)
    cx = 0.0
    cz = rise - R  # center of the arc circle (below deck for flat arch)

    pts = []
    for i in range(n_pts + 1):
        t = i / n_pts
        x = -half_span + t * SPAN
        # Solve for z on circle: (x-cx)² + (z-cz)² = R²
        dx = x - cx
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


# ── 1. Arch ribs (the main structural arch underneath the deck) ──
# Two parallel ribs, one on each side of the deck
arc_pts = segmental_arc(HALF_SPAN, RISE, 40)

for side in (-1, 1):
    rib_y = side * (HALF_W - 0.15)  # inset slightly from edge
    mesh = bpy.data.meshes.new(f"arch_rib_{side}")
    verts = []
    faces = []

    # Extrude arc profile: inner and outer surfaces
    for px, pz in arc_pts:
        # Shift Z so deck surface is at Z=0, arch hangs below
        z = pz - RISE
        verts.append((px, rib_y - ARCH_T / 2, z))
        verts.append((px, rib_y + ARCH_T / 2, z))
        verts.append((px, rib_y - ARCH_T / 2, z - ARCH_T))
        verts.append((px, rib_y + ARCH_T / 2, z - ARCH_T))

    n = len(arc_pts)
    for i in range(n - 1):
        b = i * 4
        nb = (i + 1) * 4
        # Outer face (top of rib)
        faces.append((b, nb, nb + 1, b + 1))
        # Inner face (bottom of rib)
        faces.append((b + 2, b + 3, nb + 3, nb + 2))
        # Side faces
        faces.append((b, b + 2, nb + 2, nb))
        faces.append((b + 1, nb + 1, nb + 3, b + 3))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(f"arch_rib_{side}", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(cast_iron)
    all_parts.append(obj)

# ── 2. Spandrel web (vertical iron plate between arch rib and deck) ──
# Fills the space between the arch curve and the flat deck on each side
for side in (-1, 1):
    rib_y = side * (HALF_W - 0.15)
    mesh = bpy.data.meshes.new(f"spandrel_{side}")
    verts = []
    faces = []

    for px, pz in arc_pts:
        z_arch = pz - RISE  # bottom of spandrel (arch curve)
        z_deck = -DECK_T    # top of spandrel (underside of deck)
        verts.append((px, rib_y, z_arch))
        verts.append((px, rib_y, z_deck))

    n = len(arc_pts)
    for i in range(n - 1):
        b = i * 2
        nb = (i + 1) * 2
        faces.append((b, nb, nb + 1, b + 1))

    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(f"spandrel_{side}", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(cast_iron)
    all_parts.append(obj)

# ── 3. Deck surface ──
# Flat deck with slight camber (higher in center for drainage)
box("deck", 0, 0, -DECK_T / 2,
    HALF_RAIL, HALF_W, DECK_T / 2, deck_mat)

# ── 4. Railings (solid panels with Gothic cinquefoil pattern) ──
# Simplified as solid panels — shader will add the pierced pattern
for side in (-1, 1):
    ry = side * HALF_W
    box(f"railing_{side}", 0, ry, RAILING_H / 2,
        HALF_RAIL, RAILING_T / 2, RAILING_H / 2, cast_iron)
    # Top rail (slightly wider)
    box(f"top_rail_{side}", 0, ry, RAILING_H + 0.03,
        HALF_RAIL, RAILING_T / 2 + 0.02, 0.05, cast_iron)
    # Bottom rail
    box(f"bot_rail_{side}", 0, ry, 0.0,
        HALF_RAIL, RAILING_T / 2 + 0.02, 0.04, cast_iron)

# ── 5. Planting urns (8 along balustrade) ──
urn_spacing = RAILING_L / (N_URNS + 1)
for i in range(N_URNS):
    ux = -HALF_RAIL + urn_spacing * (i + 1)
    for side in (-1, 1):
        uy = side * (HALF_W + RAILING_T / 2 + 0.05)
        # Urn base (small cylinder)
        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.15, depth=0.10,
            location=(ux, uy, RAILING_H + 0.05))
        base = bpy.context.active_object
        base.name = f"urn_base_{i}_{side}"
        base.data.materials.append(urn_mat)
        all_parts.append(base)
        # Urn body (tapered cylinder)
        bpy.ops.mesh.primitive_cone_add(
            radius1=URN_R, radius2=URN_R * 0.7, depth=URN_H,
            location=(ux, uy, RAILING_H + 0.10 + URN_H / 2))
        body = bpy.context.active_object
        body.name = f"urn_body_{i}_{side}"
        body.data.materials.append(urn_mat)
        all_parts.append(body)
        # Urn lip (torus)
        bpy.ops.mesh.primitive_torus_add(
            major_radius=URN_R * 0.75, minor_radius=0.05,
            location=(ux, uy, RAILING_H + 0.10 + URN_H))
        lip = bpy.context.active_object
        lip.name = f"urn_lip_{i}_{side}"
        lip.data.materials.append(urn_mat)
        all_parts.append(lip)

# ── 6. Abutments (stone piers at each end) ──
for end in (-1, 1):
    ax = end * (HALF_SPAN + ABUT_D / 2 - 0.5)
    # Main abutment block
    box(f"abutment_{end}", ax, 0, -ABUT_H / 2,
        ABUT_D / 2, ABUT_W / 2, ABUT_H / 2, stone_abut)
    # Wing walls (angled retaining walls)
    for wing_side in (-1, 1):
        wy = wing_side * (ABUT_W / 2 + 0.8)
        box(f"wing_{end}_{wing_side}",
            ax + end * 1.0, wy, -ABUT_H * 0.6 / 2,
            1.5, 0.4, ABUT_H * 0.6 / 2, stone_abut)

# ── 7. Cross-bracing under deck (iron struts between ribs) ──
n_braces = 12
brace_spacing = SPAN / (n_braces + 1)
for i in range(n_braces):
    bx = -HALF_SPAN + brace_spacing * (i + 1)
    # Find arch height at this x position
    R = (RISE * RISE + HALF_SPAN * HALF_SPAN) / (2.0 * RISE)
    cz = RISE - R
    inner = R * R - bx * bx
    if inner > 0:
        z_arch = cz + math.sqrt(inner) - RISE
    else:
        z_arch = -RISE
    z_mid = (z_arch + (-DECK_T)) / 2
    h = abs(-DECK_T - z_arch)
    if h > 0.2:
        box(f"brace_{i}", bx, 0, z_mid,
            0.04, HALF_W - 0.3, 0.05, cast_iron)

# ── Finalize ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

bridge = bpy.context.active_object
bridge.name = "BowBridge"
# Origin at deck center
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

# Export
out_path = "/home/chris/central-park-walk/models/furniture/cp_bow_bridge.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported Bow Bridge to {out_path}")
print(f"  Verts: {len(bridge.data.vertices)}, Faces: {len(bridge.data.polygons)}")
