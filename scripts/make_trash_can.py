"""Generate a Central Park-style wire trash can model.

Classic NYC Parks wire mesh trash can: cylindrical wire basket with
green powder-coated frame, tapered top, and swing lid.
Dimensions: ~0.45m diameter, ~0.85m tall.
One material: 'Green_Iron' (NYC Parks green).
Exports to models/furniture/cp_trash_can.glb
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# --- Material ---
green_mat = bpy.data.materials.new(name="Green_Iron")
green_mat.use_nodes = True
bsdf = green_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.12, 0.22, 0.10, 1.0)  # NYC Parks green
bsdf.inputs["Metallic"].default_value = 0.5
bsdf.inputs["Roughness"].default_value = 0.65

# --- Constants ---
CAN_R_BOT = 0.22     # radius at bottom
CAN_R_TOP = 0.20     # radius at top (slight taper)
CAN_H = 0.80         # main body height
LID_H = 0.08         # lid height
BASE_H = 0.06        # base ring height
WIRE_R = 0.006       # wire thickness (radius)
VERT_WIRES = 16      # vertical wires
HORIZ_RINGS = 5      # horizontal reinforcement rings
POST_R = 0.025       # mounting post radius
POST_H = 0.10        # post extends below can

all_parts = []


def add_ring(z, radius, wire_radius=WIRE_R):
    """Add a horizontal reinforcement ring."""
    bpy.ops.mesh.primitive_torus_add(
        major_radius=radius,
        minor_radius=wire_radius,
        major_segments=24,
        minor_segments=6,
        location=(0, 0, z)
    )
    obj = bpy.context.active_object
    obj.data.materials.append(green_mat)
    all_parts.append(obj)
    return obj


def add_vertical_wire(angle, r_bot, r_top, z_bot, z_top):
    """Add a vertical wire from bottom to top."""
    n_pts = 8
    points = []
    for i in range(n_pts):
        t = i / (n_pts - 1)
        z = z_bot + t * (z_top - z_bot)
        r = r_bot + t * (r_top - r_bot)
        x = math.cos(angle) * r
        y = math.sin(angle) * r
        points.append(Vector((x, y, z)))

    # Create a curve, then convert to mesh
    bm = bmesh.new()
    verts = []
    for pt in points:
        verts.append(bm.verts.new(pt))
    for i in range(len(verts) - 1):
        bm.edges.new([verts[i], verts[i + 1]])

    mesh = bpy.data.meshes.new(f"wire_{angle:.2f}")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(f"wire_{angle:.2f}", mesh)
    bpy.context.collection.objects.link(obj)

    # Add skin modifier for thickness
    skin = obj.modifiers.new(name="Skin", type='SKIN')
    for v in obj.data.skin_vertices[0].data:
        v.radius = (WIRE_R, WIRE_R)

    # Add subdivision for smoothness
    sub = obj.modifiers.new(name="Sub", type='SUBSURF')
    sub.levels = 1

    # Apply modifiers
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier="Skin")
    bpy.ops.object.modifier_apply(modifier="Sub")

    obj.data.materials.append(green_mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    all_parts.append(obj)
    return obj


# --- Build the trash can ---

# Bottom ring (thicker)
add_ring(BASE_H, CAN_R_BOT, WIRE_R * 1.5)

# Horizontal reinforcement rings
for i in range(HORIZ_RINGS):
    t = (i + 1) / (HORIZ_RINGS + 1)
    z = BASE_H + t * CAN_H
    r = CAN_R_BOT + t * (CAN_R_TOP - CAN_R_BOT)
    add_ring(z, r)

# Top ring (thicker)
add_ring(BASE_H + CAN_H, CAN_R_TOP, WIRE_R * 1.5)

# Vertical wires
for i in range(VERT_WIRES):
    angle = 2 * math.pi * i / VERT_WIRES
    add_vertical_wire(angle, CAN_R_BOT, CAN_R_TOP, BASE_H, BASE_H + CAN_H)

# Lid — slightly domed disc
bpy.ops.mesh.primitive_cylinder_add(
    radius=CAN_R_TOP + 0.01,
    depth=LID_H,
    vertices=16,
    location=(0, 0, BASE_H + CAN_H + LID_H / 2)
)
lid = bpy.context.active_object
lid.name = "lid"
# Dome the top vertices slightly
mesh = lid.data
for v in mesh.vertices:
    if v.co.z > 0:  # top half
        dist = math.sqrt(v.co.x ** 2 + v.co.y ** 2)
        v.co.z += 0.02 * (1.0 - dist / (CAN_R_TOP + 0.01))
mesh.update()
lid.data.materials.append(green_mat)
all_parts.append(lid)

# Lid handle — small torus on top
bpy.ops.mesh.primitive_torus_add(
    major_radius=0.04,
    minor_radius=0.008,
    major_segments=12,
    minor_segments=6,
    location=(0, 0, BASE_H + CAN_H + LID_H + 0.015),
    rotation=(math.radians(90), 0, 0)
)
handle = bpy.context.active_object
handle.name = "handle"
handle.data.materials.append(green_mat)
all_parts.append(handle)

# Base plate — solid disc at bottom
bpy.ops.mesh.primitive_cylinder_add(
    radius=CAN_R_BOT - 0.01,
    depth=0.005,
    vertices=16,
    location=(0, 0, BASE_H + 0.003)
)
base_plate = bpy.context.active_object
base_plate.name = "base_plate"
base_plate.data.materials.append(green_mat)
all_parts.append(base_plate)

# Mounting post (extends below can)
bpy.ops.mesh.primitive_cylinder_add(
    radius=POST_R,
    depth=BASE_H + POST_H,
    vertices=8,
    location=(0, 0, (BASE_H - POST_H) / 2)
)
post = bpy.context.active_object
post.name = "post"
post.data.materials.append(green_mat)
all_parts.append(post)

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Join all parts
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

can = bpy.context.active_object
can.name = "CP_TrashCan"

# Origin at bottom center
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
bbox = [can.matrix_world @ Vector(corner) for corner in can.bound_box]
min_z = min(v.z for v in bbox)
can.location.z -= min_z
bpy.ops.object.transform_apply(location=True)

# Export GLB
out_path = "/home/chris/central-park-walk/models/furniture/cp_trash_can.glb"
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported trash can to {out_path}")
