"""Generate a Central Park-style bench model.

Classic design: cast iron curved armrests/legs + horizontal wood slats.
Dimensions: ~1.5m long, ~0.8m tall, ~0.55m deep.
Two materials: 'Iron' (dark green) and 'Wood' (warm brown slats).
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

# Remove orphan data
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
bsdf.inputs["Base Color"].default_value = (0.12, 0.18, 0.10, 1.0)  # dark green
bsdf.inputs["Metallic"].default_value = 0.6
bsdf.inputs["Roughness"].default_value = 0.65

wood_mat = bpy.data.materials.new(name="Wood")
wood_mat.use_nodes = True
bsdf_w = wood_mat.node_tree.nodes["Principled BSDF"]
bsdf_w.inputs["Base Color"].default_value = (0.45, 0.30, 0.18, 1.0)  # warm brown
bsdf_w.inputs["Metallic"].default_value = 0.0
bsdf_w.inputs["Roughness"].default_value = 0.75

# --- Constants ---
BENCH_LEN = 1.52  # metres (5 feet)
SEAT_H = 0.44     # seat height from ground
SEAT_D = 0.42     # seat depth
BACK_H = 0.78     # top of backrest from ground
BACK_ANGLE = math.radians(10)  # slight recline
SLAT_T = 0.025    # slat thickness
SLAT_W = 0.055    # slat width (height on back, depth on seat)
SLAT_GAP = 0.012  # gap between slats

IRON_T = 0.035    # iron frame tube thickness (radius)
LEG_INSET = 0.10  # how far iron legs are inset from bench ends


def make_iron_side(x_pos):
    """Create one cast-iron side frame at the given X position."""
    bm = bmesh.new()

    # Profile points for the side frame (YZ plane, then extruded slightly in X)
    # Front leg -> seat support -> back support -> armrest
    # Ground contact points
    front_foot = Vector((0.0, 0.0, 0.0))
    front_seat = Vector((0.0, 0.04, SEAT_H))
    back_seat = Vector((0.0, SEAT_D - 0.04, SEAT_H))
    back_bottom = Vector((0.0, SEAT_D, 0.0))

    # Back rest support
    back_top_y = SEAT_D - 0.02 + math.sin(BACK_ANGLE) * (BACK_H - SEAT_H)
    back_top = Vector((0.0, back_top_y, BACK_H))

    # Armrest
    arm_front = Vector((0.0, -0.03, BACK_H - 0.06))
    arm_curve_mid = Vector((0.0, 0.10, BACK_H + 0.02))

    # Create the frame as a series of connected cylinders
    segments = [
        # Front leg
        (front_foot, front_seat),
        # Seat rail
        (front_seat, back_seat),
        # Back leg
        (back_bottom, back_seat),
        # Back upright
        (back_seat, back_top),
        # Armrest curve (simplified as 2 segments)
        (back_top, arm_curve_mid),
        (arm_curve_mid, arm_front),
        # Armrest down to front
        (arm_front, Vector((0.0, 0.0, SEAT_H + 0.10))),
    ]

    bm.free()

    # Use actual mesh creation with bpy for each segment
    all_objects = []
    for i, (start, end) in enumerate(segments):
        s = start.copy()
        e = end.copy()
        s.x = x_pos
        e.x = x_pos

        direction = e - s
        length = direction.length
        if length < 0.001:
            continue

        bpy.ops.mesh.primitive_cylinder_add(
            radius=IRON_T,
            depth=length,
            vertices=8,
            location=(0, 0, 0)
        )
        cyl = bpy.context.active_object
        cyl.name = f"iron_seg_{i}"

        # Position and orient the cylinder
        mid = (s + e) / 2
        cyl.location = mid

        # Orient cylinder along direction
        up = Vector((0, 0, 1))
        d_norm = direction.normalized()
        axis = up.cross(d_norm)
        if axis.length > 0.001:
            angle = up.angle(d_norm)
            cyl.rotation_mode = 'AXIS_ANGLE'
            cyl.rotation_axis_angle = (angle, axis.x, axis.y, axis.z)

        cyl.data.materials.append(iron_mat)
        all_objects.append(cyl)

    # Decorative scroll under armrest (a small torus arc)
    # Add a small curved brace between front and mid
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.08,
        minor_radius=IRON_T * 0.7,
        major_segments=12,
        minor_segments=6,
        location=(x_pos, 0.10, SEAT_H + 0.18),
        rotation=(math.radians(90), 0, 0)
    )
    scroll = bpy.context.active_object
    scroll.name = "iron_scroll"
    scroll.data.materials.append(iron_mat)
    # Cut to quarter arc using a boolean-like approach (just scale/clip)
    scroll.scale = (0.5, 0.5, 0.5)
    all_objects.append(scroll)

    # Foot pads (small flattened cylinders at each foot)
    for foot_y in [0.0, SEAT_D]:
        bpy.ops.mesh.primitive_cylinder_add(
            radius=0.04,
            depth=0.015,
            vertices=8,
            location=(x_pos, foot_y, 0.0075)
        )
        pad = bpy.context.active_object
        pad.name = "foot_pad"
        pad.data.materials.append(iron_mat)
        all_objects.append(pad)

    return all_objects


def make_slats():
    """Create horizontal wood slats for seat and backrest."""
    all_objects = []
    half_len = BENCH_LEN / 2

    # Seat slats (horizontal, in Y direction from front to back)
    n_seat_slats = int(SEAT_D / (SLAT_W + SLAT_GAP))
    seat_start_y = (SEAT_D - n_seat_slats * (SLAT_W + SLAT_GAP) + SLAT_GAP) / 2

    for i in range(n_seat_slats):
        y = seat_start_y + i * (SLAT_W + SLAT_GAP) + SLAT_W / 2
        bpy.ops.mesh.primitive_cube_add(
            size=1.0,
            location=(0, y, SEAT_H + SLAT_T / 2)
        )
        slat = bpy.context.active_object
        slat.name = f"seat_slat_{i}"
        slat.scale = (half_len - LEG_INSET + 0.03, SLAT_W / 2, SLAT_T / 2)
        slat.data.materials.append(wood_mat)
        all_objects.append(slat)

    # Back slats (angled slightly, running horizontally)
    back_slat_region = BACK_H - SEAT_H - 0.08  # leave margins top and bottom
    n_back_slats = int(back_slat_region / (SLAT_W + SLAT_GAP))
    back_start_z = SEAT_H + 0.04 + SLAT_W / 2

    for i in range(n_back_slats):
        z = back_start_z + i * (SLAT_W + SLAT_GAP)
        # Back surface Y position (with slight angle)
        frac = (z - SEAT_H) / (BACK_H - SEAT_H)
        y = SEAT_D - 0.02 + frac * math.sin(BACK_ANGLE) * (BACK_H - SEAT_H)

        bpy.ops.mesh.primitive_cube_add(
            size=1.0,
            location=(0, y, z)
        )
        slat = bpy.context.active_object
        slat.name = f"back_slat_{i}"
        slat.scale = (half_len - LEG_INSET + 0.03, SLAT_T / 2, SLAT_W / 2)
        # Apply slight rotation for back recline
        slat.rotation_euler = (BACK_ANGLE, 0, 0)
        slat.data.materials.append(wood_mat)
        all_objects.append(slat)

    return all_objects


def make_cross_braces():
    """Cross-braces connecting the two iron sides under the seat."""
    all_objects = []
    half_len = BENCH_LEN / 2
    x_left = -(half_len - LEG_INSET)
    x_right = half_len - LEG_INSET

    # Front brace
    for y in [0.06, SEAT_D - 0.06]:
        z = 0.15
        bpy.ops.mesh.primitive_cylinder_add(
            radius=IRON_T * 0.8,
            depth=BENCH_LEN - 2 * LEG_INSET,
            vertices=8,
            location=(0, y, z),
            rotation=(0, math.radians(90), 0)
        )
        brace = bpy.context.active_object
        brace.name = "cross_brace"
        brace.data.materials.append(iron_mat)
        all_objects.append(brace)

    # Seat support rail (under slats)
    for y in [0.10, SEAT_D - 0.10]:
        bpy.ops.mesh.primitive_cylinder_add(
            radius=IRON_T * 0.7,
            depth=BENCH_LEN - 2 * LEG_INSET,
            vertices=8,
            location=(0, y, SEAT_H - 0.02),
            rotation=(0, math.radians(90), 0)
        )
        rail = bpy.context.active_object
        rail.name = "seat_rail"
        rail.data.materials.append(iron_mat)
        all_objects.append(rail)

    return all_objects


# --- Build the bench ---
all_parts = []

# Two iron side frames
half_len = BENCH_LEN / 2
all_parts.extend(make_iron_side(-(half_len - LEG_INSET)))
all_parts.extend(make_iron_side(half_len - LEG_INSET))

# Wood slats
all_parts.extend(make_slats())

# Cross braces
all_parts.extend(make_cross_braces())

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

# Join all parts into one object
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

bench = bpy.context.active_object
bench.name = "ParkFurn_Bench_CP"

# Center the bench origin at ground level, centered
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
# Move origin to bottom center
bench.location = (0, 0, 0)
bpy.ops.object.transform_apply(location=True)

# Export GLB
out_path = os.path.join(os.path.dirname(os.path.dirname(bpy.data.filepath or __file__)),
                         "models", "furniture", "cp_bench.glb")
if not os.path.isabs(out_path):
    out_path = "/home/chris/central-park-walk/models/furniture/cp_bench.glb"

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported bench to {out_path}")
