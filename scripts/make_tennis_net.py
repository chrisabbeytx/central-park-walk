"""Generate tennis net for Central Park Walk.

Standard tennis net:
- Two steel posts at each end (1.07m tall at posts, 0.914m at center)
- Net mesh (simplified as flat plane with wire detail)
- White top band

Sized for a single court (~10.97m wide = 36ft)

Exports to models/furniture/cp_tennis_net.glb
"""

import bpy
import math

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

objects = []

NET_W = 12.8      # full doubles court width (42ft)
NET_H_POST = 1.07  # 3.5ft at posts
NET_H_CENTER = 0.914  # 3ft at center
POST_R = 0.04
WIRE_R = 0.003

# --- Two end posts ---
for sx in [-NET_W/2, NET_W/2]:
    bpy.ops.mesh.primitive_cylinder_add(radius=POST_R, depth=NET_H_POST + 0.1, vertices=8)
    post = bpy.context.active_object
    post.name = f"Post_{sx}"
    post.location = (sx, (NET_H_POST + 0.1)/2, 0)
    bpy.ops.object.transform_apply(location=True)
    objects.append(post)

# --- Net surface (slightly catenary — higher at posts, lower at center) ---
# Build as a flat mesh with vertices curved
import bmesh
bm = bmesh.new()
N_COLS = 20
N_ROWS = 8

verts_grid = []
for col in range(N_COLS + 1):
    t = col / N_COLS
    x = -NET_W/2 + NET_W * t
    # Height varies: catenary curve (higher at edges)
    center_t = abs(t - 0.5) * 2.0  # 0 at center, 1 at edges
    h = NET_H_CENTER + (NET_H_POST - NET_H_CENTER) * center_t
    
    col_verts = []
    for row in range(N_ROWS + 1):
        rt = row / N_ROWS
        y = h * rt
        v = bm.verts.new((x, y, 0))
        col_verts.append(v)
    verts_grid.append(col_verts)

bm.verts.ensure_lookup_table()

# Create faces
for col in range(N_COLS):
    for row in range(N_ROWS):
        v00 = verts_grid[col][row]
        v10 = verts_grid[col+1][row]
        v11 = verts_grid[col+1][row+1]
        v01 = verts_grid[col][row+1]
        bm.faces.new([v00, v10, v11, v01])

mesh_data = bpy.data.meshes.new("NetMesh")
bm.to_mesh(mesh_data)
bm.free()

net_obj = bpy.data.objects.new("Net", mesh_data)
bpy.context.collection.objects.link(net_obj)
objects.append(net_obj)

# --- Top band (white strip along top of net) ---
bpy.ops.mesh.primitive_cube_add(size=1)
band = bpy.context.active_object
band.name = "TopBand"
band.scale = (NET_W/2, 0.03, 0.01)
band.location = (0, NET_H_CENTER + 0.015, 0)
bpy.ops.object.transform_apply(location=True, scale=True)
objects.append(band)

# --- Materials ---
post_mat = bpy.data.materials.new("PostSteel")
post_mat.use_nodes = True
bsdf = post_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.30, 0.30, 0.28, 1.0)
bsdf.inputs["Metallic"].default_value = 0.7
bsdf.inputs["Roughness"].default_value = 0.5

net_mat = bpy.data.materials.new("NetMaterial")
net_mat.use_nodes = True
bsdf2 = net_mat.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.12, 0.12, 0.10, 1.0)  # dark net
bsdf2.inputs["Roughness"].default_value = 0.8

band_mat = bpy.data.materials.new("WhiteBand")
band_mat.use_nodes = True
bsdf3 = band_mat.node_tree.nodes["Principled BSDF"]
bsdf3.inputs["Base Color"].default_value = (0.95, 0.95, 0.95, 1.0)
bsdf3.inputs["Roughness"].default_value = 0.6

for obj in objects:
    obj.data.materials.clear()
    if "Net" in obj.name:
        obj.data.materials.append(net_mat)
    elif "Band" in obj.name:
        obj.data.materials.append(band_mat)
    else:
        obj.data.materials.append(post_mat)

# Select all and join
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.join()
obj = bpy.context.active_object
obj.name = "TennisNet"

out_path = "/home/chris/central-park-walk/models/furniture/cp_tennis_net.glb"
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB')
vcount = len(obj.data.vertices)
fcount = len(obj.data.polygons)
print(f"Exported Tennis Net to {out_path} ({vcount} verts, {fcount} faces)")
