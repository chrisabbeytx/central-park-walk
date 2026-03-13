"""Generate a rustic log bridge for Central Park Walk woodland paths.

Central Park has several small rustic log bridges in the Ramble and
North Woods — simple structures made of natural logs and branches.

Origin at ground center.
Exports to models/furniture/cp_rustic_bridge.glb
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

log_mat = make_mat("Log", (0.32, 0.24, 0.16), 0.90)
bark_mat = make_mat("Bark", (0.26, 0.19, 0.12), 0.92)
stone_mat = make_mat("Stone", (0.42, 0.40, 0.37), 0.88)
all_parts = []

L = 6.0   # bridge length
W = 2.0   # bridge width
hw = W / 2.0

# Stone abutments
for side in (-1, 1):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(side * (L/2 + 0.3), 0, 0.3))
    o = bpy.context.active_object; o.name = f"abut_{side}"
    o.scale = (0.5, W + 0.4, 0.6); o.data.materials.append(stone_mat)
    all_parts.append(o)

# Main log stringers (3 parallel logs)
for i, oy in enumerate([-hw + 0.2, 0, hw - 0.2]):
    r = 0.10 + (i % 2) * 0.02
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=L + 0.4, vertices=8,
        location=(0, oy, 0.65))
    o = bpy.context.active_object; o.name = f"stringer_{i}"
    o.rotation_euler = (0, math.pi/2, 0)
    o.data.materials.append(log_mat); all_parts.append(o)

# Cross planks (split logs, represented as flattened cylinders)
for i in range(8):
    px = -L/2 + 0.4 + i * (L - 0.8) / 7
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, 0, 0.78))
    o = bpy.context.active_object; o.name = f"plank_{i}"
    o.scale = (0.12, W - 0.1, 0.06); o.data.materials.append(bark_mat)
    all_parts.append(o)

# Railing posts (4 — at each corner)
for sx in (-1, 1):
    for sy in (-1, 1):
        px = sx * (L/2 - 0.3)
        py = sy * hw
        bpy.ops.mesh.primitive_cylinder_add(radius=0.04, depth=1.0, vertices=6,
            location=(px, py, 1.3))
        o = bpy.context.active_object; o.name = f"post_{sx}_{sy}"
        tilt = (hash(f"{sx}{sy}") % 50) / 2000.0
        o.rotation_euler = (tilt, -tilt * 0.5, 0)
        o.data.materials.append(bark_mat); all_parts.append(o)

# Railing logs (2 — one per side)
for sy in (-1, 1):
    py = sy * hw
    bpy.ops.mesh.primitive_cylinder_add(radius=0.035, depth=L - 0.3, vertices=6,
        location=(0, py, 1.75))
    o = bpy.context.active_object; o.name = f"rail_{sy}"
    o.rotation_euler = (0, math.pi/2, 0)
    o.data.materials.append(bark_mat); all_parts.append(o)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()
obj = bpy.context.active_object; obj.name = "RusticBridge"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
out_path = "/home/chris/central-park-walk/models/furniture/cp_rustic_bridge.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True, export_apply=True)
print(f"Exported Rustic Bridge to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}, Faces: {len(obj.data.polygons)}")
