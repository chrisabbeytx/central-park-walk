"""Generate dog run chain-link fence section for Central Park Walk.

Central Park has 3 dog runs — fenced off-leash areas. This generates
a fence section that can be instanced around dog run polygons.

Origin at ground center, fence section is 3m wide.
Exports to models/furniture/cp_dog_run_fence.glb
"""
import bpy, math, os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for b in bpy.data.meshes:
    if b.users == 0: bpy.data.meshes.remove(b)
for b in bpy.data.materials:
    if b.users == 0: bpy.data.materials.remove(b)

def make_mat(name, color, roughness=0.85, metallic=0.0):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m

metal = make_mat("ChainLink", (0.45, 0.45, 0.43), 0.60, 0.4)
post_mat = make_mat("Post", (0.35, 0.35, 0.33), 0.55, 0.5)
all_parts = []

SECTION_W = 3.0
FENCE_H = 1.2  # dog run fences are typically 4ft
POST_R = 0.03

# Two end posts
for side in (-1, 1):
    bpy.ops.mesh.primitive_cylinder_add(radius=POST_R, depth=FENCE_H + 0.3, vertices=8,
        location=(side * SECTION_W/2, 0, (FENCE_H + 0.3)/2))
    o = bpy.context.active_object; o.name = f"post_{side}"
    o.data.materials.append(post_mat); all_parts.append(o)
    # Post cap
    bpy.ops.mesh.primitive_cylinder_add(radius=POST_R + 0.01, depth=0.03, vertices=8,
        location=(side * SECTION_W/2, 0, FENCE_H + 0.32))
    c = bpy.context.active_object; c.name = f"cap_{side}"
    c.data.materials.append(post_mat); all_parts.append(c)

# Top rail
bpy.ops.mesh.primitive_cylinder_add(radius=0.02, depth=SECTION_W, vertices=6,
    location=(0, 0, FENCE_H + 0.15))
o = bpy.context.active_object; o.name = "top_rail"
o.rotation_euler = (0, math.pi/2, 0)
o.data.materials.append(post_mat); all_parts.append(o)

# Bottom rail
bpy.ops.mesh.primitive_cylinder_add(radius=0.02, depth=SECTION_W, vertices=6,
    location=(0, 0, 0.10))
o = bpy.context.active_object; o.name = "bot_rail"
o.rotation_euler = (0, math.pi/2, 0)
o.data.materials.append(post_mat); all_parts.append(o)

# Chain link mesh — represented as vertical wire bars
for i in range(12):
    px = -SECTION_W/2 + 0.15 + i * (SECTION_W - 0.3) / 11
    bpy.ops.mesh.primitive_cylinder_add(radius=0.008, depth=FENCE_H - 0.1, vertices=4,
        location=(px, 0, FENCE_H/2 + 0.05))
    o = bpy.context.active_object; o.name = f"wire_{i}"
    o.data.materials.append(metal); all_parts.append(o)

# Mid-height horizontal wire
bpy.ops.mesh.primitive_cylinder_add(radius=0.008, depth=SECTION_W - 0.2, vertices=4,
    location=(0, 0, FENCE_H * 0.55))
o = bpy.context.active_object; o.name = "mid_wire"
o.rotation_euler = (0, math.pi/2, 0)
o.data.materials.append(metal); all_parts.append(o)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()
obj = bpy.context.active_object; obj.name = "DogRunFence"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
out_path = "/home/chris/central-park-walk/models/furniture/cp_dog_run_fence.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True, export_apply=True)
print(f"Exported Dog Run Fence to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}, Faces: {len(obj.data.polygons)}")
