"""Generate a set of rock outcrop meshes for Central Park.

Manhattan schist — angular, layered, grey-brown.
Creates 3 variants of randomized rock shapes.
Exports to models/furniture/cp_rocks.glb
"""

import bpy
import bmesh
import math
import random
import os

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# Material — grey schist rock
rock_mat = bpy.data.materials.new(name="Schist")
rock_mat.use_nodes = True
bsdf = rock_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.42, 0.40, 0.37, 1.0)
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.85


def make_rock(name, seed, scale_x=1.0, scale_y=0.5, scale_z=1.0):
    """Create a rocky shape by deforming a subdivided cube."""
    random.seed(seed)

    bpy.ops.mesh.primitive_cube_add(size=2.0, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = name

    # Subdivide for more vertices to displace
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.subdivide(number_cuts=3)
    bpy.ops.object.mode_set(mode='OBJECT')

    # Scale to flattened rock shape
    obj.scale = (scale_x, scale_y, scale_z)
    bpy.ops.object.transform_apply(scale=True)

    # Displace vertices randomly for rocky appearance
    mesh = obj.data
    for v in mesh.vertices:
        # More displacement on top, less on bottom (stable base)
        noise_scale = 0.15 + 0.10 * max(0, v.co.y / scale_y)
        v.co.x += random.uniform(-noise_scale, noise_scale) * scale_x
        v.co.y += random.uniform(-noise_scale * 0.5, noise_scale) * scale_y
        v.co.z += random.uniform(-noise_scale, noise_scale) * scale_z

        # Flatten bottom for stable placement
        if v.co.y < -scale_y * 0.3:
            v.co.y = -scale_y * 0.3 + random.uniform(-0.02, 0.02)

    # Add layering effect — slight horizontal ridges
    for v in mesh.vertices:
        layer = math.sin(v.co.y * 8.0) * 0.03
        v.co.x += layer
        v.co.z += layer

    mesh.update()

    # Smooth shading
    for poly in mesh.polygons:
        poly.use_smooth = True

    obj.data.materials.append(rock_mat)
    return obj


# Create 3 rock variants
rocks = []
rocks.append(make_rock("Rock_A", seed=42, scale_x=1.2, scale_y=0.4, scale_z=1.0))
rocks[0].location = (0, 0, 0)

rocks.append(make_rock("Rock_B", seed=99, scale_x=0.8, scale_y=0.6, scale_z=0.9))
rocks[1].location = (3, 0, 0)

rocks.append(make_rock("Rock_C", seed=7, scale_x=1.5, scale_y=0.35, scale_z=1.3))
rocks[2].location = (6, 0, 0)

# Apply transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Export GLB
out_path = "/home/chris/central-park-walk/models/furniture/cp_rocks.glb"
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"Exported rocks to {out_path}")
