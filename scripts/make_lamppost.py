"""Generate a Central Park lamppost: Henry Bacon Type B pole + Kent Bloomer luminaire.

The Type B was designed 1910-1912 by Henry Bacon for NYC parks. The Kent Bloomer
luminaire (1982, with architect Gerald Allen) replaced the original electric lamp.
~1,800 identical units throughout Central Park.

Reference: NYC Street Design Manual, Forgotten NY, Elizabeth Barlow Rogers,
WikiCommons photos of actual Central Park lampposts.

Design: straight black iron pole with fluted lower section, decorative Beaux Arts
base, and the Bloomer luminaire — a glass globe encased in 4 curved metal ribs
with abstracted leaf ornament, topped by an acorn finial.

Total height: ~4.1m (13.5 ft). Two materials: 'Iron' and 'Globe'.
Exports to models/furniture/cp_lamppost.glb
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# --- Materials ---
iron_mat = bpy.data.materials.new(name="Iron")
iron_mat.use_nodes = True
bsdf = iron_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.04, 0.04, 0.035, 1.0)  # NYC Parks black iron
bsdf.inputs["Metallic"].default_value = 0.6
bsdf.inputs["Roughness"].default_value = 0.7

globe_mat = bpy.data.materials.new(name="Globe")
globe_mat.use_nodes = True
bsdf_g = globe_mat.node_tree.nodes["Principled BSDF"]
bsdf_g.inputs["Base Color"].default_value = (0.95, 0.88, 0.75, 1.0)  # frosted glass
bsdf_g.inputs["Metallic"].default_value = 0.0
bsdf_g.inputs["Roughness"].default_value = 0.25
bsdf_g.inputs["Alpha"].default_value = 0.8
globe_mat.blend_method = 'BLEND' if hasattr(globe_mat, 'blend_method') else None

# --- Dimensions (metres, matching real Type B) ---
# Base section
FOOT_R = 0.16       # foot pad radius
FOOT_H = 0.04       # foot pad height
BASE_R_BOT = 0.14   # base body bottom radius
BASE_R_TOP = 0.08   # base body top radius (tapers)
BASE_H = 0.50       # decorative base total height
BASE_COLLAR_R = 0.065  # collar at top of base

# Shaft
SHAFT_R = 0.05      # shaft radius (lower fluted section)
SHAFT_UPPER_R = 0.04  # upper plain pipe radius
FLUTE_H = 1.60      # fluted section height
PLAIN_H = 1.60      # plain pipe section height
SHAFT_START = BASE_H
FLUTE_TOP = SHAFT_START + FLUTE_H
PLAIN_TOP = FLUTE_TOP + PLAIN_H

# Luminaire (Kent Bloomer)
LUM_NECK_Z = PLAIN_TOP          # where luminaire starts
LUM_GLOBE_R = 0.13              # globe radius
LUM_GLOBE_H = 0.28              # globe height (slightly elongated)
LUM_RIB_COUNT = 4               # number of curved ribs
LUM_FINIAL_R = 0.018            # acorn finial radius
LUM_FINIAL_H = 0.04             # finial height
LUM_CALYX_R = 0.07              # top calyx/sepal ring radius
LUM_TOTAL_H = LUM_GLOBE_H + 0.12  # globe + finial + calyx

TOTAL_H = PLAIN_TOP + LUM_TOTAL_H  # ~4.14m

CIRC_SEGS = 16  # circumference segments


def make_tube(name, points, radii, segments=CIRC_SEGS, mat=None):
    """Create a tube mesh following a path of points with varying radii."""
    if isinstance(radii, (int, float)):
        radii = [radii] * len(points)
    bm = bmesh.new()
    rings = []
    for i, pt in enumerate(points):
        if i < len(points) - 1:
            direction = (points[i + 1] - pt).normalized()
        elif i > 0:
            direction = (pt - points[i - 1]).normalized()
        else:
            direction = Vector((0, 0, 1))
        if abs(direction.z) < 0.99:
            side = direction.cross(Vector((0, 0, 1))).normalized()
        else:
            side = direction.cross(Vector((1, 0, 0))).normalized()
        up = side.cross(direction).normalized()
        r = radii[i]
        ring = []
        for j in range(segments):
            angle = 2 * math.pi * j / segments
            offset = side * math.cos(angle) * r + up * math.sin(angle) * r
            ring.append(bm.verts.new(pt + offset))
        rings.append(ring)

    bm.verts.ensure_lookup_table()
    for i in range(len(rings) - 1):
        for j in range(segments):
            j2 = (j + 1) % segments
            bm.faces.new([rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]])

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def make_base():
    """Decorative Beaux Arts base — stepped profile with flared foot."""
    objs = []
    # Foot pad (wide, short disc)
    bpy.ops.mesh.primitive_cylinder_add(
        radius=FOOT_R, depth=FOOT_H, vertices=CIRC_SEGS,
        location=(0, 0, FOOT_H / 2)
    )
    foot = bpy.context.active_object
    foot.name = "base_foot"
    foot.data.materials.append(iron_mat)
    objs.append(foot)

    # Base body — tapered from FOOT_R down to BASE_COLLAR_R
    # Profile: wider at bottom, necking in toward shaft
    n_steps = 12
    pts = []
    radii = []
    for i in range(n_steps):
        t = i / (n_steps - 1)
        z = FOOT_H + t * (BASE_H - FOOT_H)
        # Concave taper profile (wider bottom, narrow top)
        r = BASE_R_BOT + (BASE_R_TOP - BASE_R_BOT) * (t ** 0.6)
        pts.append(Vector((0, 0, z)))
        radii.append(r)
    obj = make_tube("base_body", pts, radii, CIRC_SEGS, iron_mat)
    objs.append(obj)

    # Collar ring at top of base
    bpy.ops.mesh.primitive_torus_add(
        major_radius=BASE_COLLAR_R + 0.01, minor_radius=0.012,
        major_segments=CIRC_SEGS, minor_segments=8,
        location=(0, 0, BASE_H)
    )
    collar = bpy.context.active_object
    collar.name = "base_collar"
    collar.data.materials.append(iron_mat)
    objs.append(collar)

    return objs


def make_shaft():
    """Fluted lower shaft + plain upper pipe."""
    objs = []

    # --- Lower fluted section ---
    # Use a multi-sided profile with alternating larger/smaller radii for fluting
    n_pts = 12
    flute_segs = 10  # number of flutes
    circ = flute_segs * 2  # doubled for peaks and valleys

    bm = bmesh.new()
    rings = []
    for i in range(n_pts):
        t = i / (n_pts - 1)
        z = SHAFT_START + t * FLUTE_H
        # Slight taper along length
        base_r = SHAFT_R - t * 0.005
        ring = []
        for j in range(circ):
            angle = 2 * math.pi * j / circ
            # Alternating flute profile
            if j % 2 == 0:
                r = base_r
            else:
                r = base_r * 0.88  # flute valleys
            x = math.cos(angle) * r
            y = math.sin(angle) * r
            ring.append(bm.verts.new(Vector((x, y, z))))
        rings.append(ring)

    bm.verts.ensure_lookup_table()
    for i in range(len(rings) - 1):
        for j in range(circ):
            j2 = (j + 1) % circ
            bm.faces.new([rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]])

    mesh = bpy.data.meshes.new("shaft_fluted")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("shaft_fluted", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(iron_mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    objs.append(obj)

    # Transition collar between fluted and plain
    bpy.ops.mesh.primitive_torus_add(
        major_radius=SHAFT_R + 0.005, minor_radius=0.008,
        major_segments=CIRC_SEGS, minor_segments=6,
        location=(0, 0, FLUTE_TOP)
    )
    trans = bpy.context.active_object
    trans.name = "shaft_collar"
    trans.data.materials.append(iron_mat)
    objs.append(trans)

    # --- Upper plain pipe ---
    n_pts = 8
    pts = []
    radii = []
    for i in range(n_pts):
        t = i / (n_pts - 1)
        z = FLUTE_TOP + t * PLAIN_H
        pts.append(Vector((0, 0, z)))
        radii.append(SHAFT_UPPER_R)
    obj = make_tube("shaft_plain", pts, radii, CIRC_SEGS, iron_mat)
    objs.append(obj)

    return objs


def make_number_plate():
    """Small rectangular number plate bracket, midway up the shaft."""
    plate_z = SHAFT_START + FLUTE_H * 0.5
    plate_w = 0.06
    plate_h = 0.04
    plate_depth = 0.005
    offset = SHAFT_R + 0.005  # just outside shaft

    bpy.ops.mesh.primitive_cube_add(
        size=1,
        location=(offset + plate_depth / 2, 0, plate_z)
    )
    plate = bpy.context.active_object
    plate.name = "number_plate"
    plate.scale = (plate_depth, plate_w / 2, plate_h / 2)
    bpy.ops.object.transform_apply(scale=True)
    plate.data.materials.append(iron_mat)
    return [plate]


def make_luminaire():
    """Kent Bloomer luminaire: glass globe in metal ribs with acorn finial."""
    objs = []
    globe_center_z = LUM_NECK_Z + 0.04 + LUM_GLOBE_H * 0.45

    # --- Glass globe (slightly elongated sphere) ---
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=LUM_GLOBE_R, segments=20, ring_count=12,
        location=(0, 0, globe_center_z)
    )
    globe = bpy.context.active_object
    globe.name = "globe"
    # Elongate vertically
    globe.scale = (1.0, 1.0, LUM_GLOBE_H / (LUM_GLOBE_R * 2))
    bpy.ops.object.transform_apply(scale=True)
    globe.data.materials.append(globe_mat)
    objs.append(globe)

    # --- Four curved metal ribs ---
    rib_r = 0.008  # rib tube radius
    globe_bot_z = globe_center_z - LUM_GLOBE_H * 0.5
    globe_top_z = globe_center_z + LUM_GLOBE_H * 0.5

    for rib_i in range(LUM_RIB_COUNT):
        base_angle = 2 * math.pi * rib_i / LUM_RIB_COUNT
        pts = []
        n_rib_pts = 16
        for j in range(n_rib_pts):
            t = j / (n_rib_pts - 1)
            z = globe_bot_z - 0.01 + t * (LUM_GLOBE_H + 0.04)
            # Ribs bulge outward following the globe shape
            bulge = math.sin(t * math.pi) * (LUM_GLOBE_R + 0.015)
            # Slight twist as described (leaves follow and twist)
            twist = base_angle + t * 0.15
            x = math.cos(twist) * bulge
            y = math.sin(twist) * bulge
            pts.append(Vector((x, y, z)))
        obj = make_tube(f"rib_{rib_i}", pts, rib_r, 6, iron_mat)
        objs.append(obj)

        # Small leaf-like protrusions on each rib (3 per rib)
        for leaf_i in range(3):
            lt = 0.25 + leaf_i * 0.25  # at 25%, 50%, 75% along rib
            lz = globe_bot_z - 0.01 + lt * (LUM_GLOBE_H + 0.04)
            bulge = math.sin(lt * math.pi) * (LUM_GLOBE_R + 0.015)
            twist = base_angle + lt * 0.15
            lx = math.cos(twist) * bulge
            ly = math.sin(twist) * bulge
            # Leaf as a small flattened sphere
            bpy.ops.mesh.primitive_uv_sphere_add(
                radius=0.012, segments=6, ring_count=4,
                location=(lx, ly, lz)
            )
            leaf = bpy.context.active_object
            leaf.name = f"leaf_{rib_i}_{leaf_i}"
            # Flatten radially (leaf shape)
            leaf_angle = twist + math.pi / 2
            leaf.rotation_euler = (0, 0, leaf_angle)
            leaf.scale = (0.6, 1.2, 1.0)
            bpy.ops.object.transform_apply(rotation=True, scale=True)
            leaf.data.materials.append(iron_mat)
            objs.append(leaf)

    # --- Neck collar (botanic ribbon) ---
    bpy.ops.mesh.primitive_torus_add(
        major_radius=SHAFT_UPPER_R + 0.02, minor_radius=0.01,
        major_segments=CIRC_SEGS, minor_segments=6,
        location=(0, 0, LUM_NECK_Z + 0.01)
    )
    neck = bpy.context.active_object
    neck.name = "lum_neck"
    neck.data.materials.append(iron_mat)
    objs.append(neck)

    # --- Top calyx (cupped sepals) ---
    bpy.ops.mesh.primitive_torus_add(
        major_radius=LUM_CALYX_R, minor_radius=0.012,
        major_segments=CIRC_SEGS, minor_segments=6,
        location=(0, 0, globe_top_z + 0.01)
    )
    calyx = bpy.context.active_object
    calyx.name = "lum_calyx"
    calyx.data.materials.append(iron_mat)
    objs.append(calyx)

    # --- Acorn finial ---
    # Acorn body
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=LUM_FINIAL_R, segments=10, ring_count=6,
        location=(0, 0, globe_top_z + 0.03)
    )
    acorn = bpy.context.active_object
    acorn.name = "finial_acorn"
    acorn.scale = (1.0, 1.0, LUM_FINIAL_H / (LUM_FINIAL_R * 2))
    bpy.ops.object.transform_apply(scale=True)
    acorn.data.materials.append(iron_mat)
    objs.append(acorn)

    # Acorn cap
    bpy.ops.mesh.primitive_cylinder_add(
        radius=LUM_FINIAL_R * 1.2, depth=0.01, vertices=10,
        location=(0, 0, globe_top_z + 0.03 + LUM_FINIAL_H * 0.3)
    )
    acap = bpy.context.active_object
    acap.name = "finial_cap"
    acap.data.materials.append(iron_mat)
    objs.append(acap)

    # Finial stem
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.006, depth=0.025, vertices=8,
        location=(0, 0, globe_top_z + 0.03 + LUM_FINIAL_H * 0.6)
    )
    fstem = bpy.context.active_object
    fstem.name = "finial_stem"
    fstem.data.materials.append(iron_mat)
    objs.append(fstem)

    return objs


# --- Build the lamppost ---
all_parts = []
all_parts.extend(make_base())
all_parts.extend(make_shaft())
all_parts.extend(make_number_plate())
all_parts.extend(make_luminaire())

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Join all parts into one object
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

lamp = bpy.context.active_object
lamp.name = "CP_Lamppost"

# Set origin so bottom is at Z=0
bbox = [lamp.matrix_world @ Vector(corner) for corner in lamp.bound_box]
min_z = min(v.z for v in bbox)
lamp.location.z -= min_z
bpy.ops.object.transform_apply(location=True)

# Export GLB
out_dir = "/home/chris/central-park-walk/models/furniture"
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "cp_lamppost.glb")
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)

# Report
bbox2 = [lamp.matrix_world @ Vector(corner) for corner in lamp.bound_box]
height = max(v.z for v in bbox2) - min(v.z for v in bbox2)
print(f"Exported Central Park Type B lamppost to {out_path}")
print(f"  Height: {height:.2f}m  ({height * 3.281:.1f} ft)")
print(f"  Faces: {len(lamp.data.polygons)}")
