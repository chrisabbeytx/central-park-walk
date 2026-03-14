"""Generate Alice in Wonderland statue for Central Park Walk.

The Alice in Wonderland statue (José de Creeft, 1959) — bronze group
sculpture north of Conservatory Water. Alice sits on a giant mushroom
surrounded by the Mad Hatter, March Hare, Dormouse, and Cheshire Cat.
- Mushroom base: ~2m diameter, 1.5m tall
- Alice figure: seated, ~1.2m from mushroom to top of head
- Surrounding smaller figures on mushroom rim
- One of the most climbed-on statues in any park

Exports to models/furniture/cp_alice_statue.glb
"""

import bpy
import math

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

objects = []

# --- Giant mushroom cap (flattened sphere, 2m diameter) ---
bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=12, ring_count=8)
cap = bpy.context.active_object
cap.name = "MushroomCap"
cap.scale = (1.0, 0.35, 1.0)
cap.location = (0, 1.2, 0)
bpy.ops.object.transform_apply(location=True, scale=True)
objects.append(cap)

# --- Mushroom stem ---
bpy.ops.mesh.primitive_cylinder_add(radius=0.35, depth=1.0, vertices=10)
stem = bpy.context.active_object
stem.name = "Stem"
stem.location = (0, 0.5, 0)
bpy.ops.object.transform_apply(location=True)
objects.append(stem)

# --- Alice figure (seated on top of mushroom) ---
# Torso
bpy.ops.mesh.primitive_cylinder_add(radius=0.15, depth=0.5, vertices=8)
torso = bpy.context.active_object
torso.name = "AliceTorso"
torso.location = (0, 1.65, 0)
bpy.ops.object.transform_apply(location=True)
objects.append(torso)

# Head
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.1, segments=8, ring_count=6)
head = bpy.context.active_object
head.name = "AliceHead"
head.location = (0, 2.0, 0)
bpy.ops.object.transform_apply(location=True)
objects.append(head)

# --- Mad Hatter (seated figure on rim, left side) ---
bpy.ops.mesh.primitive_cylinder_add(radius=0.12, depth=0.4, vertices=6)
hatter = bpy.context.active_object
hatter.name = "MadHatter"
hatter.location = (-0.7, 1.45, 0)
bpy.ops.object.transform_apply(location=True)
objects.append(hatter)

# Hatter's top hat
bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.2, vertices=6)
hat = bpy.context.active_object
hat.name = "TopHat"
hat.location = (-0.7, 1.75, 0)
bpy.ops.object.transform_apply(location=True)
objects.append(hat)

# --- March Hare (right side) ---
bpy.ops.mesh.primitive_cylinder_add(radius=0.10, depth=0.35, vertices=6)
hare = bpy.context.active_object
hare.name = "MarchHare"
hare.location = (0.65, 1.4, 0.2)
bpy.ops.object.transform_apply(location=True)
objects.append(hare)

# Ears
for ez in [-0.04, 0.04]:
    bpy.ops.mesh.primitive_cylinder_add(radius=0.02, depth=0.15, vertices=4)
    ear = bpy.context.active_object
    ear.name = f"HareEar_{ez}"
    ear.location = (0.65, 1.65, 0.2 + ez)
    bpy.ops.object.transform_apply(location=True)
    objects.append(ear)

# --- Cheshire Cat (draped on back of mushroom) ---
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.15, segments=8, ring_count=6)
cat = bpy.context.active_object
cat.name = "CheshireCat"
cat.scale = (1.8, 0.8, 0.8)
cat.location = (0, 1.35, -0.65)
bpy.ops.object.transform_apply(location=True, scale=True)
objects.append(cat)

# --- Dormouse (small, front of mushroom) ---
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.08, segments=6, ring_count=5)
mouse = bpy.context.active_object
mouse.name = "Dormouse"
mouse.location = (0.3, 1.3, 0.6)
bpy.ops.object.transform_apply(location=True)
objects.append(mouse)

# --- Granite pedestal base ---
bpy.ops.mesh.primitive_cylinder_add(radius=1.5, depth=0.3, vertices=12)
pedestal = bpy.context.active_object
pedestal.name = "Pedestal"
pedestal.location = (0, 0.15, 0)
bpy.ops.object.transform_apply(location=True)
objects.append(pedestal)

# --- Material: bronze patina ---
bronze_mat = bpy.data.materials.new("Bronze")
bronze_mat.use_nodes = True
bsdf = bronze_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.22, 0.20, 0.10, 1.0)  # green-bronze patina
bsdf.inputs["Metallic"].default_value = 0.80
bsdf.inputs["Roughness"].default_value = 0.55

granite_mat = bpy.data.materials.new("Granite")
granite_mat.use_nodes = True
bsdf2 = granite_mat.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.55, 0.53, 0.50, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.75

for obj in objects:
    obj.data.materials.clear()
    if "Pedestal" in obj.name:
        obj.data.materials.append(granite_mat)
    else:
        obj.data.materials.append(bronze_mat)

# Join
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.join()
obj = bpy.context.active_object
obj.name = "AliceStatue"

# Fix orientation: scripts use Y-up, Blender is Z-up
import math
obj.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

out_path = "/home/chris/central-park-walk/models/furniture/cp_alice_statue.glb"
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB')
vcount = len(obj.data.vertices)
fcount = len(obj.data.polygons)
print(f"Exported Alice in Wonderland to {out_path} ({vcount} verts, {fcount} faces)")
