"""Generate the 1939 World's Fair bench (Kenneth Lynch & Sons).

THE iconic Central Park bench. Art Deco + Victorian hybrid designed by Kenneth Lynch
in collaboration with Parks Commissioner Robert Moses. Debuted at the 1939 NY World's Fair.
~8,000 originally produced; the dominant bench type among Central Park's 10,000 benches.

Key features: circular hoop armrests with ornate scroll inserts, splayed legs,
9 horizontal wood slats (5 seat + 4 back), cross-brace stretcher bars.

Dimensions (6' model — most common in park):
  Length: 6' (1.83m)
  Height: 34" (0.86m)
  Depth:  27" (0.69m)

3 side frames for 6' bench (2 ends + 1 center divider).
Two materials: 'Iron' (black powder-coat) and 'Wood' (warm brown slats).
Exports to models/furniture/cp_bench.glb
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
bsdf.inputs["Base Color"].default_value = (0.04, 0.04, 0.035, 1.0)  # black powder coat
bsdf.inputs["Metallic"].default_value = 0.6
bsdf.inputs["Roughness"].default_value = 0.65

wood_mat = bpy.data.materials.new(name="Wood")
wood_mat.use_nodes = True
bsdf_w = wood_mat.node_tree.nodes["Principled BSDF"]
bsdf_w.inputs["Base Color"].default_value = (0.45, 0.30, 0.18, 1.0)  # warm brown Cumaru
bsdf_w.inputs["Metallic"].default_value = 0.0
bsdf_w.inputs["Roughness"].default_value = 0.75

# --- Dimensions (metres) ---
# 6' World's Fair bench — most common in Central Park
BENCH_LEN = 1.83       # 6 feet
BENCH_H = 0.86         # 34 inches total height
BENCH_DEPTH = 0.69     # 27 inches depth (front to back)
SEAT_H = 0.44          # seat surface height from ground
SEAT_DEPTH = 0.44      # seat slat region depth (front to back edge)

# Iron tube/bar dimensions
IRON_R = 0.019         # 1.5" diameter bar -> 0.75" radius = 19mm
HOOP_R = 0.15          # 12" hoop diameter / 2 = 6" = 152mm, using 150mm
CIRC_SEGS = 8          # tube cross-section segments (keep poly count low)

# Slat dimensions
SLAT_W = 0.089         # ~3.5" wide slats
SLAT_T = 0.025         # slat thickness
SLAT_GAP = 0.013       # ~0.5" gap between slats

# Back angle
BACK_ANGLE = math.radians(15)  # back reclines ~15 degrees from vertical

# Leg geometry — splayed A-frame
# Front legs angle forward, rear legs angle backward
FRONT_SPLAY = math.radians(18)   # front leg angle from vertical (forward)
REAR_SPLAY = math.radians(12)    # rear leg angle from vertical (backward)
STRETCHER_H = 0.15               # cross-brace height from ground (6 inches)

# Foot pads
FOOT_R = 0.038         # ~3" diameter foot pads
FOOT_H = 0.012         # foot pad thickness


def make_tube(name, points, radii, segments=CIRC_SEGS, mat=None, cap_ends=False):
    """Create a tube mesh following a path of points with varying radii.
    Matches make_lamppost.py pattern."""
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
    # Side faces
    for i in range(len(rings) - 1):
        for j in range(segments):
            j2 = (j + 1) % segments
            bm.faces.new([rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]])

    # End caps
    if cap_ends and len(rings) >= 2:
        # Bottom cap
        bm.faces.new(rings[0][::-1])
        # Top cap
        bm.faces.new(rings[-1])

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


def make_slat(name, length, width, thickness, location, rotation_euler=None, mat=None):
    """Create a single wood slat as a box with slightly rounded edges (just a cube)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    slat = bpy.context.active_object
    slat.name = name
    slat.scale = (length / 2, width / 2, thickness / 2)
    if rotation_euler:
        slat.rotation_euler = rotation_euler
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    if mat:
        slat.data.materials.append(mat)
    return slat


def make_hoop_armrest(x_pos):
    """Create a circular hoop armrest at the given X position.

    The hoop is a full circle of iron tube in the YZ plane.
    The hoop center sits where the seat meets the backrest, slightly above seat height.
    From the product photo: the hoop circle spans from just below seat level
    to roughly the top of the back. The legs emerge from the bottom of the hoop.
    """
    # Hoop center: vertically centered between the bottom of the legs-at-seat
    # and the top of the back. Looking at the reference, the hoop center
    # is approximately at seat height, slightly above.
    hoop_cx = x_pos
    hoop_cy = SEAT_DEPTH * 0.42   # slightly behind center of seat depth
    hoop_cz = SEAT_H + 0.06       # just above seat height

    # Generate hoop as a ring of tube segments
    n_hoop_pts = 24  # points around the circle
    pts = []
    for i in range(n_hoop_pts + 1):  # +1 to close the loop
        angle = 2 * math.pi * i / n_hoop_pts
        # Circle in YZ plane: Y = cos, Z = sin
        py = hoop_cy + HOOP_R * math.cos(angle)
        pz = hoop_cz + HOOP_R * math.sin(angle)
        pts.append(Vector((hoop_cx, py, pz)))

    hoop = make_tube("hoop", pts, IRON_R, CIRC_SEGS, iron_mat)
    return [hoop], (hoop_cx, hoop_cy, hoop_cz)


def make_scroll_insert(x_pos, hoop_center):
    """Create a simplified scroll insert inside the hoop armrest.

    From the close-up photo (11_scroll_insert_on_bench.jpg):
    - Central vertical bar
    - Two S-curves branching left and right from center
    - Small spiral volutes at the ends
    Simplified to: vertical bar + 2 S-shaped curves + 4 small spirals.
    """
    _, cy, cz = hoop_center
    objs = []
    scroll_r = IRON_R * 0.70  # scroll bars slightly thinner than hoop

    # Central vertical bar (from bottom of hoop interior to ~2/3 up)
    bar_bot_z = cz - HOOP_R * 0.75
    bar_top_z = cz + HOOP_R * 0.50
    pts = [Vector((x_pos, cy, bar_bot_z)), Vector((x_pos, cy, bar_top_z))]
    objs.append(make_tube("scroll_vert", pts, scroll_r, CIRC_SEGS, iron_mat))

    # Two S-curves (mirror about centerline Y=cy)
    # Each S-curve: starts from center bar, curves out, back in, ends in a volute
    for side in [-1, 1]:
        n_pts = 12
        s_pts = []
        for i in range(n_pts):
            t = i / (n_pts - 1)
            # S-curve in YZ plane
            # Vertical: goes from mid to upper portion
            sz = cz - HOOP_R * 0.30 + t * HOOP_R * 1.10
            # Horizontal: S-shape oscillation outward
            sy = cy + side * HOOP_R * 0.50 * math.sin(t * math.pi * 1.5) * (0.4 + 0.6 * t)
            s_pts.append(Vector((x_pos, sy, sz)))
        objs.append(make_tube(f"scroll_s_{side}", s_pts, scroll_r, 6, iron_mat))

        # Small volute spiral at the top end of each S-curve
        vol_cy = s_pts[-1].y
        vol_cz = s_pts[-1].z
        vol_pts = []
        n_vol = 8
        vol_r_start = HOOP_R * 0.10
        for i in range(n_vol):
            t = i / (n_vol - 1)
            angle = t * math.pi * 1.5
            r = vol_r_start * (1 - t * 0.7)
            vy = vol_cy + side * r * math.cos(angle)
            vz = vol_cz + r * math.sin(angle)
            vol_pts.append(Vector((x_pos, vy, vz)))
        objs.append(make_tube(f"scroll_vol_top_{side}", vol_pts, scroll_r * 0.8, 6, iron_mat))

        # Lower volute (smaller, near bottom of S-curve)
        low_cy = cy + side * HOOP_R * 0.25
        low_cz = cz - HOOP_R * 0.55
        vol_pts2 = []
        for i in range(n_vol):
            t = i / (n_vol - 1)
            angle = t * math.pi * 1.3 + math.pi
            r = vol_r_start * 0.7 * (1 - t * 0.7)
            vy = low_cy + side * r * math.cos(angle)
            vz = low_cz + r * math.sin(angle)
            vol_pts2.append(Vector((x_pos, vy, vz)))
        objs.append(make_tube(f"scroll_vol_bot_{side}", vol_pts2, scroll_r * 0.8, 6, iron_mat))

    return objs


def make_end_frame(x_pos, is_end=True):
    """Create one side frame (end or center divider) at the given X position.

    For END frames: full hoop armrest + scroll insert + splayed legs + foot pads
    For CENTER frame: no hoop/scroll, just legs + seat/back support rails
    """
    objs = []

    # --- Hoop center reference (even for center frame, we need the geometry reference) ---
    hoop_cy = SEAT_DEPTH * 0.42
    hoop_cz = SEAT_H + 0.06

    if is_end:
        # --- Hoop armrest ---
        hoop_objs, hoop_center = make_hoop_armrest(x_pos)
        objs.extend(hoop_objs)

        # --- Scroll insert inside hoop ---
        objs.extend(make_scroll_insert(x_pos, hoop_center))

    # --- Splayed legs ---
    # From the product photo: front leg angles forward, rear leg angles backward.
    # Each leg emerges from roughly the bottom of the hoop (for end frames)
    # or from the seat rail (for center frames).

    # Front leg: top at front edge of seat, angled forward
    front_top_y = 0.04  # near front edge
    front_top_z = SEAT_H - 0.02
    front_bot_y = front_top_y - math.sin(FRONT_SPLAY) * front_top_z
    front_bot_z = 0.0

    # Rear leg: top at rear edge of seat, angled backward
    rear_top_y = SEAT_DEPTH - 0.04
    rear_top_z = SEAT_H - 0.02
    rear_bot_y = rear_top_y + math.sin(REAR_SPLAY) * rear_top_z
    rear_bot_z = 0.0

    # Front leg with slight Art Deco curve
    n_leg = 8
    front_pts = []
    for i in range(n_leg):
        t = i / (n_leg - 1)
        # Slight convex curve (Art Deco organic feel)
        curve = math.sin(t * math.pi) * 0.015
        py = front_bot_y + t * (front_top_y - front_bot_y) - curve
        pz = front_bot_z + t * (front_top_z - front_bot_z)
        front_pts.append(Vector((x_pos, py, pz)))
    objs.append(make_tube("front_leg", front_pts, IRON_R, CIRC_SEGS, iron_mat))

    # Rear leg with slight Art Deco curve
    rear_pts = []
    for i in range(n_leg):
        t = i / (n_leg - 1)
        curve = math.sin(t * math.pi) * 0.015
        py = rear_bot_y + t * (rear_top_y - rear_bot_y) + curve
        pz = rear_bot_z + t * (rear_top_z - rear_bot_z)
        rear_pts.append(Vector((x_pos, py, pz)))
    objs.append(make_tube("rear_leg", rear_pts, IRON_R, CIRC_SEGS, iron_mat))

    # --- Back upright (from seat to top of back) ---
    # The back support goes from the rear of the seat up to the bench top height.
    # It reclines at BACK_ANGLE from vertical.
    back_bot_y = rear_top_y
    back_bot_z = rear_top_z
    back_height = BENCH_H - SEAT_H + 0.02
    back_top_y = back_bot_y + math.sin(BACK_ANGLE) * back_height
    back_top_z = back_bot_z + math.cos(BACK_ANGLE) * back_height

    back_pts = [
        Vector((x_pos, back_bot_y, back_bot_z)),
        Vector((x_pos, back_top_y, back_top_z))
    ]
    objs.append(make_tube("back_upright", back_pts, IRON_R, CIRC_SEGS, iron_mat))

    # --- Cross-brace stretcher bar between front and rear legs ---
    # At STRETCHER_H from the ground, connecting front leg to rear leg
    # Interpolate Y positions at stretcher height
    front_stretch_y = front_bot_y + (front_top_y - front_bot_y) * (STRETCHER_H / front_top_z)
    rear_stretch_y = rear_bot_y + (rear_top_y - rear_bot_y) * (STRETCHER_H / rear_top_z)
    stretch_pts = [
        Vector((x_pos, front_stretch_y, STRETCHER_H)),
        Vector((x_pos, rear_stretch_y, STRETCHER_H))
    ]
    objs.append(make_tube("stretcher", stretch_pts, IRON_R * 0.85, CIRC_SEGS, iron_mat))

    # --- Foot pads ---
    for foot_y in [front_bot_y, rear_bot_y]:
        bpy.ops.mesh.primitive_cylinder_add(
            radius=FOOT_R,
            depth=FOOT_H,
            vertices=CIRC_SEGS,
            location=(x_pos, foot_y, FOOT_H / 2)
        )
        pad = bpy.context.active_object
        pad.name = "foot_pad"
        pad.data.materials.append(iron_mat)
        objs.append(pad)

    return objs


def make_seat_slats():
    """Create 5 horizontal seat slats spanning the full bench length."""
    objs = []
    slat_len = BENCH_LEN - 0.06  # slightly shorter than total length for overhang look

    # 5 seat slats evenly distributed across SEAT_DEPTH
    n_slats = 5
    total_slat_width = n_slats * SLAT_W + (n_slats - 1) * SLAT_GAP
    start_y = (SEAT_DEPTH - total_slat_width) / 2 + SLAT_W / 2

    # Seat has a very slight backward tilt (~5-8 deg for drainage/comfort)
    seat_tilt = math.radians(5)

    for i in range(n_slats):
        y = start_y + i * (SLAT_W + SLAT_GAP)
        # Slight tilt: front edge higher than back
        z_offset = (y - SEAT_DEPTH / 2) * math.sin(seat_tilt)
        loc = (0, y, SEAT_H + SLAT_T / 2 - z_offset)
        slat = make_slat(
            f"seat_slat_{i}", slat_len, SLAT_W, SLAT_T,
            loc, rotation_euler=(seat_tilt, 0, 0), mat=wood_mat
        )
        objs.append(slat)

    return objs


def make_back_slats():
    """Create 4 horizontal back slats, angled to match the back recline."""
    objs = []
    slat_len = BENCH_LEN - 0.06

    # 4 back slats, spaced evenly along the back
    n_slats = 4
    back_start_z = SEAT_H + 0.04  # small gap above seat
    back_end_z = BENCH_H - 0.03   # small gap below top

    # Back surface Y position (at rear of seat)
    back_base_y = SEAT_DEPTH - 0.04

    for i in range(n_slats):
        frac = (i + 0.5) / n_slats
        z = back_start_z + frac * (back_end_z - back_start_z)
        # Y shifts backward as we go up (recline angle)
        height_above_seat = z - SEAT_H
        y = back_base_y + math.sin(BACK_ANGLE) * height_above_seat
        loc = (0, y, z)
        slat = make_slat(
            f"back_slat_{i}", slat_len, SLAT_W, SLAT_T,
            loc, rotation_euler=(BACK_ANGLE, 0, 0), mat=wood_mat
        )
        objs.append(slat)

    return objs


def make_longitudinal_rails():
    """Create iron rails that run the length of the bench under the seat slats
    and behind the back slats, connecting the side frames."""
    objs = []
    rail_len = BENCH_LEN - 0.04
    rail_r = IRON_R * 0.80

    # Front seat rail (under seat, near front)
    pts_front = [
        Vector((-rail_len / 2, 0.06, SEAT_H - 0.02)),
        Vector((rail_len / 2, 0.06, SEAT_H - 0.02))
    ]
    objs.append(make_tube("rail_seat_front", pts_front, rail_r, CIRC_SEGS, iron_mat))

    # Rear seat rail (under seat, near back)
    pts_rear = [
        Vector((-rail_len / 2, SEAT_DEPTH - 0.06, SEAT_H - 0.02)),
        Vector((rail_len / 2, SEAT_DEPTH - 0.06, SEAT_H - 0.02))
    ]
    objs.append(make_tube("rail_seat_rear", pts_rear, rail_r, CIRC_SEGS, iron_mat))

    # Top back rail (behind top back slat)
    back_top_y = SEAT_DEPTH - 0.04 + math.sin(BACK_ANGLE) * (BENCH_H - SEAT_H - 0.02)
    pts_back = [
        Vector((-rail_len / 2, back_top_y + 0.02, BENCH_H - 0.01)),
        Vector((rail_len / 2, back_top_y + 0.02, BENCH_H - 0.01))
    ]
    objs.append(make_tube("rail_back_top", pts_back, rail_r, CIRC_SEGS, iron_mat))

    # Middle back rail (behind mid back slats)
    mid_z = (SEAT_H + BENCH_H) / 2
    mid_y = SEAT_DEPTH - 0.04 + math.sin(BACK_ANGLE) * (mid_z - SEAT_H)
    pts_mid = [
        Vector((-rail_len / 2, mid_y + 0.02, mid_z)),
        Vector((rail_len / 2, mid_y + 0.02, mid_z))
    ]
    objs.append(make_tube("rail_back_mid", pts_mid, rail_r, CIRC_SEGS, iron_mat))

    return objs


# --- Build the bench ---
all_parts = []

# 3 side frames: left end, center divider, right end
half_len = BENCH_LEN / 2
frame_positions = [
    (-half_len + 0.03, True),   # left end (with hoop)
    (0.0, False),               # center divider (no hoop)
    (half_len - 0.03, True),    # right end (with hoop)
]

for x_pos, is_end in frame_positions:
    all_parts.extend(make_end_frame(x_pos, is_end=is_end))

# Wood slats
all_parts.extend(make_seat_slats())
all_parts.extend(make_back_slats())

# Longitudinal iron rails
all_parts.extend(make_longitudinal_rails())

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Join all parts into one object
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

bench = bpy.context.active_object
bench.name = "ParkFurn_Bench_CP"

# Set origin so bottom is at Z=0
bbox = [bench.matrix_world @ Vector(corner) for corner in bench.bound_box]
min_z = min(v.z for v in bbox)
bench.location.z -= min_z
bpy.ops.object.transform_apply(location=True)

# Export GLB
out_dir = "/home/chris/central-park-walk/models/furniture"
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "cp_bench.glb")
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)

# Report dimensions
bbox2 = [bench.matrix_world @ Vector(corner) for corner in bench.bound_box]
dims = Vector((
    max(v.x for v in bbox2) - min(v.x for v in bbox2),
    max(v.y for v in bbox2) - min(v.y for v in bbox2),
    max(v.z for v in bbox2) - min(v.z for v in bbox2),
))
faces = len(bench.data.polygons)
print(f"Exported 1939 World's Fair bench to {out_path}")
print(f"  Length: {dims.x:.2f}m ({dims.x * 39.37:.1f}in)")
print(f"  Depth:  {dims.y:.2f}m ({dims.y * 39.37:.1f}in)")
print(f"  Height: {dims.z:.2f}m ({dims.z * 39.37:.1f}in)")
print(f"  Faces:  {faces}")
print(f"  Object: ParkFurn_Bench_CP")
