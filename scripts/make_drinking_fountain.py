"""Generate a Central Park-style drinking fountain (bubbler) model.

Classic NYC Parks drinking fountain: short granite pedestal with
cast iron basin and bubbler spout. Height ~0.85m.
Two materials: 'Stone' (grey granite) and 'Iron' (dark iron basin).
Exports to models/furniture/cp_drinking_fountain.glb
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

# --- Materials ---
stone_mat = bpy.data.materials.new(name="Stone")
stone_mat.use_nodes = True
bsdf = stone_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.55, 0.52, 0.48, 1.0)  # grey granite
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.85

iron_mat = bpy.data.materials.new(name="Iron")
iron_mat.use_nodes = True
bsdf_i = iron_mat.node_tree.nodes["Principled BSDF"]
bsdf_i.inputs["Base Color"].default_value = (0.08, 0.08, 0.06, 1.0)  # dark iron
bsdf_i.inputs["Metallic"].default_value = 0.6
bsdf_i.inputs["Roughness"].default_value = 0.70

# --- Constants ---
PED_R_BOT = 0.18    # pedestal radius at bottom
PED_R_TOP = 0.15    # pedestal radius at top
PED_H = 0.65        # pedestal height
BASIN_R = 0.20      # basin outer radius
BASIN_H = 0.08      # basin depth
BASIN_T = 0.025     # basin wall thickness
RIM_R = 0.22        # rim radius
RIM_H = 0.015       # rim thickness
SPOUT_H = 0.12      # spout height above basin rim
SPOUT_R = 0.015     # spout tube radius
TOTAL_H = PED_H + BASIN_H + SPOUT_H  # ~0.85m

all_parts = []

# --- Pedestal (tapered cylinder with chamfered edges) ---
bpy.ops.mesh.primitive_cylinder_add(
    radius=PED_R_BOT, depth=PED_H, vertices=16,
    location=(0, 0, PED_H / 2)
)
ped = bpy.context.active_object
ped.name = "pedestal"
# Taper top
mesh = ped.data
for v in mesh.vertices:
    t = (v.co.z + PED_H / 2) / PED_H
    t = max(0, min(1, t))
    scale = PED_R_BOT + t * (PED_R_TOP - PED_R_BOT)
    scale /= PED_R_BOT
    v.co.x *= scale
    v.co.y *= scale
mesh.update()
ped.data.materials.append(stone_mat)
all_parts.append(ped)

# Base molding (wider ring at bottom)
bpy.ops.mesh.primitive_cylinder_add(
    radius=PED_R_BOT + 0.03, depth=0.04, vertices=16,
    location=(0, 0, 0.02)
)
base = bpy.context.active_object
base.name = "base_molding"
base.data.materials.append(stone_mat)
all_parts.append(base)

# Top molding (transition ring)
bpy.ops.mesh.primitive_torus_add(
    major_radius=PED_R_TOP + 0.01, minor_radius=0.015,
    major_segments=16, minor_segments=6,
    location=(0, 0, PED_H)
)
top_ring = bpy.context.active_object
top_ring.name = "top_molding"
top_ring.data.materials.append(stone_mat)
all_parts.append(top_ring)

# --- Basin (hollow cylinder) ---
# Outer shell
bpy.ops.mesh.primitive_cylinder_add(
    radius=BASIN_R, depth=BASIN_H, vertices=20,
    location=(0, 0, PED_H + BASIN_H / 2)
)
basin_outer = bpy.context.active_object
basin_outer.name = "basin_outer"
basin_outer.data.materials.append(iron_mat)
all_parts.append(basin_outer)

# Inner cavity (boolean subtract would be complex, use a slightly smaller inverted disc)
# Just add a dark disc inside to simulate depth
bpy.ops.mesh.primitive_cylinder_add(
    radius=BASIN_R - BASIN_T, depth=0.003, vertices=20,
    location=(0, 0, PED_H + BASIN_H - 0.002)
)
basin_floor = bpy.context.active_object
basin_floor.name = "basin_floor"
basin_floor.data.materials.append(iron_mat)
all_parts.append(basin_floor)

# Basin rim
bpy.ops.mesh.primitive_torus_add(
    major_radius=RIM_R, minor_radius=RIM_H,
    major_segments=20, minor_segments=8,
    location=(0, 0, PED_H + BASIN_H)
)
rim = bpy.context.active_object
rim.name = "basin_rim"
rim.data.materials.append(iron_mat)
all_parts.append(rim)

# --- Spout (curved pipe in center) ---
# Vertical pipe
bpy.ops.mesh.primitive_cylinder_add(
    radius=SPOUT_R, depth=SPOUT_H, vertices=8,
    location=(0, 0, PED_H + BASIN_H + SPOUT_H / 2)
)
spout = bpy.context.active_object
spout.name = "spout"
spout.data.materials.append(iron_mat)
all_parts.append(spout)

# Spout nozzle (small sphere at top angled outward)
bpy.ops.mesh.primitive_uv_sphere_add(
    radius=SPOUT_R * 1.5, segments=8, ring_count=6,
    location=(0.01, 0, PED_H + BASIN_H + SPOUT_H)
)
nozzle = bpy.context.active_object
nozzle.name = "nozzle"
nozzle.data.materials.append(iron_mat)
all_parts.append(nozzle)

# Drain grate (small disc with holes implied by dark color)
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.03, depth=0.005, vertices=8,
    location=(0, 0, PED_H + 0.003)
)
drain = bpy.context.active_object
drain.name = "drain"
drain.data.materials.append(iron_mat)
all_parts.append(drain)

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Smooth shading
for obj in all_parts:
    for poly in obj.data.polygons:
        poly.use_smooth = True

# Join all parts
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

fountain = bpy.context.active_object
fountain.name = "CP_DrinkingFountain"

# Origin at bottom center
bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
bbox = [fountain.matrix_world @ Vector(corner) for corner in fountain.bound_box]
min_z = min(v.z for v in bbox)
fountain.location.z -= min_z
bpy.ops.object.transform_apply(location=True)

# Export GLB
out_path = "/home/chris/central-park-walk/models/furniture/cp_drinking_fountain.glb"
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported drinking fountain to {out_path}")
