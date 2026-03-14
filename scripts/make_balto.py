"""Generate Balto statue for Central Park Walk.

The Balto statue (Frederick Roth, 1925) — a bronze sled dog standing
on a rock outcrop pedestal. Located west of the Literary Walk.
- Rock base: ~1.2m × 0.8m × 0.6m irregular
- Dog figure: standing, ~0.8m tall at shoulder, 1m long
- Simplified as geometric primitives suggesting the form

Exports to models/furniture/cp_balto.glb
"""

import bpy
import bmesh
import math

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

objects = []

# --- Rock pedestal (irregular squashed sphere) ---
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.6, segments=8, ring_count=6)
rock = bpy.context.active_object
rock.name = "RockBase"
rock.scale = (1.0, 0.5, 0.7)
rock.location = (0, 0.3, 0)
bpy.ops.object.transform_apply(location=True, scale=True)
objects.append(rock)

# --- Plaque on front of rock ---
bpy.ops.mesh.primitive_cube_add(size=1)
plaque = bpy.context.active_object
plaque.name = "Plaque"
plaque.scale = (0.3, 0.15, 0.01)
plaque.location = (0, 0.3, 0.55)
bpy.ops.object.transform_apply(location=True, scale=True)
objects.append(plaque)

# --- Dog body (elongated ellipsoid) ---
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, segments=10, ring_count=8)
body = bpy.context.active_object
body.name = "DogBody"
body.scale = (2.0, 1.0, 1.0)
body.location = (0, 0.85, 0)
bpy.ops.object.transform_apply(location=True, scale=True)
objects.append(body)

# --- Dog head (sphere) ---
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, segments=8, ring_count=6)
head = bpy.context.active_object
head.name = "DogHead"
head.location = (0.35, 0.95, 0)
bpy.ops.object.transform_apply(location=True)
objects.append(head)

# --- Snout ---
bpy.ops.mesh.primitive_cone_add(radius1=0.06, radius2=0.02, depth=0.12, vertices=6)
snout = bpy.context.active_object
snout.name = "Snout"
snout.rotation_euler = (0, 0, -math.pi/2)
snout.location = (0.47, 0.93, 0)
bpy.ops.object.transform_apply(location=True, rotation=True)
objects.append(snout)

# --- 4 Legs ---
leg_positions = [
    (0.25, 0, 0.12),   # front right
    (0.25, 0, -0.12),  # front left
    (-0.25, 0, 0.12),  # back right
    (-0.25, 0, -0.12), # back left
]
for i, (lx, ly, lz) in enumerate(leg_positions):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=0.25, vertices=6)
    leg = bpy.context.active_object
    leg.name = f"Leg_{i}"
    leg.location = (lx, 0.72, lz)
    bpy.ops.object.transform_apply(location=True)
    objects.append(leg)

# --- Tail (curved cylinder) ---
bpy.ops.mesh.primitive_cylinder_add(radius=0.025, depth=0.25, vertices=6)
tail = bpy.context.active_object
tail.name = "Tail"
tail.rotation_euler = (0.3, 0, 0.5)
tail.location = (-0.4, 1.0, 0)
bpy.ops.object.transform_apply(location=True, rotation=True)
objects.append(tail)

# --- Ears (small cones) ---
for ez in [-0.07, 0.07]:
    bpy.ops.mesh.primitive_cone_add(radius1=0.03, radius2=0.01, depth=0.06, vertices=4)
    ear = bpy.context.active_object
    ear.name = f"Ear_{ez}"
    ear.location = (0.32, 1.05, ez)
    bpy.ops.object.transform_apply(location=True)
    objects.append(ear)

# --- Materials ---
bronze_mat = bpy.data.materials.new("Bronze")
bronze_mat.use_nodes = True
bsdf = bronze_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.25, 0.18, 0.08, 1.0)  # dark bronze patina
bsdf.inputs["Metallic"].default_value = 0.85
bsdf.inputs["Roughness"].default_value = 0.5

rock_mat = bpy.data.materials.new("Rock")
rock_mat.use_nodes = True
bsdf2 = rock_mat.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.42, 0.40, 0.38, 1.0)  # gray schist
bsdf2.inputs["Roughness"].default_value = 0.85

plaque_mat = bpy.data.materials.new("BronzePlaque")
plaque_mat.use_nodes = True
bsdf3 = plaque_mat.node_tree.nodes["Principled BSDF"]
bsdf3.inputs["Base Color"].default_value = (0.35, 0.28, 0.15, 1.0)
bsdf3.inputs["Metallic"].default_value = 0.9
bsdf3.inputs["Roughness"].default_value = 0.35

for obj in objects:
    obj.data.materials.clear()
    if "Rock" in obj.name:
        obj.data.materials.append(rock_mat)
    elif "Plaque" in obj.name:
        obj.data.materials.append(plaque_mat)
    else:
        obj.data.materials.append(bronze_mat)

# Join
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.join()
obj = bpy.context.active_object
obj.name = "Balto"

# Fix orientation: scripts use Y-up, Blender is Z-up
import math
obj.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

out_path = "/home/chris/central-park-walk/models/furniture/cp_balto.glb"
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB')
vcount = len(obj.data.vertices)
fcount = len(obj.data.polygons)
print(f"Exported Balto to {out_path} ({vcount} verts, {fcount} faces)")
