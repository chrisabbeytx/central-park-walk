"""Generate a Central Park-style lamppost (Bishop's Crook) model.

Classic NYC park lamp: fluted cast iron post with curved arm (bishop's crook)
and an acorn-shaped luminaire globe. Height ~4.5m.
Two materials: 'Iron' (dark wrought iron) and 'Globe' (warm amber glass).
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
bsdf.inputs["Base Color"].default_value = (0.06, 0.06, 0.05, 1.0)  # dark wrought iron
bsdf.inputs["Metallic"].default_value = 0.5
bsdf.inputs["Roughness"].default_value = 0.75

globe_mat = bpy.data.materials.new(name="Globe")
globe_mat.use_nodes = True
bsdf_g = globe_mat.node_tree.nodes["Principled BSDF"]
bsdf_g.inputs["Base Color"].default_value = (1.0, 0.72, 0.32, 1.0)  # warm amber
bsdf_g.inputs["Metallic"].default_value = 0.0
bsdf_g.inputs["Roughness"].default_value = 0.3
bsdf_g.inputs["Alpha"].default_value = 0.85

# --- Constants ---
POST_H = 3.2        # post height (base to crook start)
POST_R_BASE = 0.06  # post radius at base
POST_R_TOP = 0.04   # post radius at top
BASE_H = 0.25       # decorative base height
BASE_R = 0.10       # base radius
CROOK_R = 0.45      # crook curve radius
CROOK_SEGS = 12     # curve segments
ARM_R = 0.025       # arm tube radius
GLOBE_R = 0.14      # globe radius
GLOBE_H = 0.22      # globe height (acorn shape)
TOTAL_H = POST_H + CROOK_R + GLOBE_R  # ~4.09m

SEGS = 12  # circumference segments for tubes


def make_tube(name, points, radius, segments=SEGS, mat=None):
    """Create a tube mesh following a path of points."""
    bm = bmesh.new()
    rings = []
    for i, pt in enumerate(points):
        if i < len(points) - 1:
            direction = (points[i + 1] - pt).normalized()
        else:
            direction = (pt - points[i - 1]).normalized()
        # Build a circle perpendicular to direction
        if abs(direction.z) < 0.99:
            side = direction.cross(Vector((0, 0, 1))).normalized()
        else:
            side = direction.cross(Vector((1, 0, 0))).normalized()
        up = side.cross(direction).normalized()
        ring = []
        for j in range(segments):
            angle = 2 * math.pi * j / segments
            offset = side * math.cos(angle) * radius + up * math.sin(angle) * radius
            ring.append(bm.verts.new(pt + offset))
        rings.append(ring)

    bm.verts.ensure_lookup_table()
    for i in range(len(rings) - 1):
        for j in range(segments):
            j2 = (j + 1) % segments
            v1, v2 = rings[i][j], rings[i][j2]
            v3, v4 = rings[i + 1][j2], rings[i + 1][j]
            bm.faces.new([v1, v2, v3, v4])

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
    """Decorative fluted base."""
    all_objs = []

    # Main base cylinder (slightly wider at bottom)
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BASE_R, depth=BASE_H, vertices=12, location=(0, 0, BASE_H / 2)
    )
    base = bpy.context.active_object
    base.name = "base_main"
    base.data.materials.append(iron_mat)
    all_objs.append(base)

    # Foot pad
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BASE_R + 0.02, depth=0.03, vertices=12, location=(0, 0, 0.015)
    )
    pad = bpy.context.active_object
    pad.name = "base_pad"
    pad.data.materials.append(iron_mat)
    all_objs.append(pad)

    # Top ring
    bpy.ops.mesh.primitive_torus_add(
        major_radius=POST_R_BASE + 0.015, minor_radius=0.012,
        major_segments=12, minor_segments=6,
        location=(0, 0, BASE_H)
    )
    ring = bpy.context.active_object
    ring.name = "base_ring"
    ring.data.materials.append(iron_mat)
    all_objs.append(ring)

    return all_objs


def make_post():
    """Tapered fluted post."""
    points = []
    n_pts = 16
    for i in range(n_pts):
        t = i / (n_pts - 1)
        z = BASE_H + t * (POST_H - BASE_H)
        points.append(Vector((0, 0, z)))

    r = POST_R_BASE  # use uniform radius for simplicity, taper via scale
    obj = make_tube("post", points, r, SEGS, iron_mat)

    # Apply slight taper via mesh editing
    mesh = obj.data
    for v in mesh.vertices:
        t = (v.co.z - BASE_H) / (POST_H - BASE_H)
        t = max(0, min(1, t))
        scale = 1.0 - t * (1.0 - POST_R_TOP / POST_R_BASE)
        v.co.x *= scale
        v.co.y *= scale
    mesh.update()

    return obj


def make_crook():
    """Bishop's crook curved arm at the top of the post."""
    points = []
    # Arc from vertical to horizontal
    for i in range(CROOK_SEGS + 1):
        t = i / CROOK_SEGS
        angle = math.pi / 2 * t  # 0 to 90 degrees
        x = CROOK_R * math.sin(angle)
        z = POST_H + CROOK_R * math.cos(angle)
        points.append(Vector((x, 0, z)))

    obj = make_tube("crook", points, ARM_R, 8, iron_mat)
    return obj


def make_globe():
    """Acorn-shaped luminaire globe."""
    all_objs = []

    # Globe body — slightly elongated sphere
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=GLOBE_R, segments=16, ring_count=10,
        location=(CROOK_R, 0, POST_H)
    )
    globe = bpy.context.active_object
    globe.name = "globe"
    globe.scale = (1.0, 1.0, GLOBE_H / GLOBE_R)
    bpy.ops.object.transform_apply(scale=True)
    globe.data.materials.append(globe_mat)
    all_objs.append(globe)

    # Globe cap (small disc on top)
    bpy.ops.mesh.primitive_cylinder_add(
        radius=GLOBE_R * 0.4, depth=0.02, vertices=12,
        location=(CROOK_R, 0, POST_H + GLOBE_H * 0.95)
    )
    cap = bpy.context.active_object
    cap.name = "globe_cap"
    cap.data.materials.append(iron_mat)
    all_objs.append(cap)

    # Finial on top
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.02, segments=8, ring_count=6,
        location=(CROOK_R, 0, POST_H + GLOBE_H + 0.03)
    )
    finial = bpy.context.active_object
    finial.name = "finial"
    finial.data.materials.append(iron_mat)
    all_objs.append(finial)

    # Short stem connecting crook to globe
    bpy.ops.mesh.primitive_cylinder_add(
        radius=ARM_R * 0.8, depth=0.06, vertices=8,
        location=(CROOK_R, 0, POST_H + GLOBE_H * 0.5 + 0.15)
    )
    stem = bpy.context.active_object
    stem.name = "globe_stem"
    stem.data.materials.append(iron_mat)
    all_objs.append(stem)

    return all_objs


# --- Build the lamppost ---
all_parts = []
all_parts.extend(make_base())
all_parts.append(make_post())
all_parts.append(make_crook())
all_parts.extend(make_globe())

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Join all parts
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

lamp = bpy.context.active_object
lamp.name = "CP_Lamppost"

# Set origin to bottom center
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
# Move so bottom is at Y=0
bbox = [lamp.matrix_world @ Vector(corner) for corner in lamp.bound_box]
min_z = min(v.z for v in bbox)
lamp.location.z -= min_z
bpy.ops.object.transform_apply(location=True)

# Export GLB
out_path = "/home/chris/central-park-walk/models/furniture/cp_lamppost.glb"
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported lamppost to {out_path}")
