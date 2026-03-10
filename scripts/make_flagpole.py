"""Generate a Central Park flagpole.

Standard aluminum flagpole: tapered cylindrical pole with ball finial,
truck (pulley assembly) near top, and concrete base sleeve.

Dimensions: ~9.14m (30ft) typical park flagpole.
Materials: 'Aluminum' (satin silver anodized)
Exports: models/furniture/cp_flagpole.glb
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
alum_mat = bpy.data.materials.new(name="Aluminum")
alum_mat.use_nodes = True
bsdf = alum_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.72, 0.72, 0.70, 1.0)  # satin silver
bsdf.inputs["Metallic"].default_value = 0.85
bsdf.inputs["Roughness"].default_value = 0.30

# --- Dimensions ---
POLE_H = 9.0           # pole height
POLE_R_BASE = 0.065    # radius at base
POLE_R_TOP = 0.035     # radius at top (tapered)
BASE_SLEEVE_H = 0.40   # concrete/metal base sleeve visible portion
BASE_SLEEVE_R = 0.10   # base sleeve radius
BALL_R = 0.06          # finial ball radius
TRUCK_H = 0.12         # truck (pulley housing) height
TRUCK_R = 0.045        # truck radius
CLEAT_H = 0.10         # cleat height (rope tie-off)
CLEAT_R = 0.025        # cleat radius

CIRC_SEGS = 10


def make_pole():
    """Tapered pole — cone geometry."""
    objs = []

    # Base sleeve (wider at ground)
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BASE_SLEEVE_R, depth=BASE_SLEEVE_H, vertices=CIRC_SEGS,
        location=(0, 0, BASE_SLEEVE_H / 2)
    )
    sleeve = bpy.context.active_object
    sleeve.name = "base_sleeve"
    sleeve.data.materials.append(alum_mat)
    objs.append(sleeve)

    # Main tapered pole
    bpy.ops.mesh.primitive_cone_add(
        radius1=POLE_R_BASE, radius2=POLE_R_TOP,
        depth=POLE_H - BASE_SLEEVE_H - TRUCK_H,
        vertices=CIRC_SEGS,
        location=(0, 0, BASE_SLEEVE_H + (POLE_H - BASE_SLEEVE_H - TRUCK_H) / 2)
    )
    pole = bpy.context.active_object
    pole.name = "pole_shaft"
    pole.data.materials.append(alum_mat)
    objs.append(pole)

    # Truck (pulley housing at top)
    truck_z = POLE_H - TRUCK_H / 2
    bpy.ops.mesh.primitive_cylinder_add(
        radius=TRUCK_R, depth=TRUCK_H, vertices=CIRC_SEGS,
        location=(0, 0, truck_z)
    )
    truck = bpy.context.active_object
    truck.name = "truck"
    truck.data.materials.append(alum_mat)
    objs.append(truck)

    # Ball finial at top
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=BALL_R, segments=8, ring_count=6,
        location=(0, 0, POLE_H + BALL_R * 0.7)
    )
    ball = bpy.context.active_object
    ball.name = "ball_finial"
    ball.data.materials.append(alum_mat)
    for poly in ball.data.polygons:
        poly.use_smooth = True
    objs.append(ball)

    # Cleat (rope tie-off at ~1.5m height)
    cleat_z = 1.5
    bpy.ops.mesh.primitive_cylinder_add(
        radius=CLEAT_R, depth=CLEAT_H, vertices=6,
        location=(POLE_R_BASE + 0.02, 0, cleat_z),
    )
    cleat = bpy.context.active_object
    cleat.name = "cleat"
    cleat.rotation_euler = (0, math.pi / 2, 0)
    cleat.data.materials.append(alum_mat)
    objs.append(cleat)

    return objs


# --- Build ---
all_parts = make_pole()

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Join all parts
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

pole = bpy.context.active_object
pole.name = "CP_Flagpole"

# Set origin so bottom at Z=0
bbox = [pole.matrix_world @ Vector(c) for c in pole.bound_box]
min_z = min(v.z for v in bbox)
pole.location.z -= min_z
bpy.ops.object.transform_apply(location=True)

# Export GLB
out_path = "/home/chris/central-park-walk/models/furniture/cp_flagpole.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)

bbox2 = [pole.matrix_world @ Vector(c) for c in pole.bound_box]
height = max(v.z for v in bbox2) - min(v.z for v in bbox2)
print(f"Exported flagpole to {out_path}")
print(f"  Height: {height:.2f}m  ({height * 39.37:.1f} in)")
print(f"  Faces: {len(pole.data.polygons)}")
