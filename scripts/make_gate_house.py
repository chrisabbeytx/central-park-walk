"""Generate Gate House model for Central Park Walk.

The North and South Gate Houses (1862) sit at the south end of the
Jacqueline Kennedy Onassis Reservoir. Originally pump stations for
the Croton Aqueduct. Built in Victorian Gothic granite.

Key features:
  - Small octagonal stone tower (~5m diameter, ~10m tall)
  - Conical stone roof with finial
  - Gothic pointed-arch windows
  - Coursed granite masonry
  - Foundation on rock outcrop

Origin at ground center.
Exports to models/furniture/cp_gate_house.glb
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

def make_mat(name, color, roughness=0.85, metallic=0.0):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m

granite = make_mat("Granite", (0.48, 0.46, 0.42), 0.90)
slate   = make_mat("Slate",   (0.30, 0.28, 0.26), 0.78)
trim    = make_mat("Trim",    (0.58, 0.55, 0.50), 0.82)
iron    = make_mat("Iron",    (0.12, 0.11, 0.10), 0.60, 0.3)

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

R = 2.8      # tower radius
H = 8.0      # wall height
ROOF_H = 3.5 # conical roof
N = 8        # octagonal

# ════════════════════════════════════════════
# 1. FOUNDATION
# ════════════════════════════════════════════
bpy.ops.mesh.primitive_cylinder_add(radius=R + 0.5, depth=0.5, vertices=N,
    location=(0, 0, -0.10))
f = bpy.context.active_object
f.name = "Foundation"
f.data.materials.append(granite)
all_parts.append(f)

# ════════════════════════════════════════════
# 2. TOWER WALLS
# ════════════════════════════════════════════
bpy.ops.mesh.primitive_cylinder_add(radius=R, depth=H, vertices=N,
    location=(0, 0, H/2 + 0.15))
t = bpy.context.active_object
t.name = "TowerWall"
t.data.materials.append(granite)
all_parts.append(t)

# Cornice band at top
bpy.ops.mesh.primitive_cylinder_add(radius=R + 0.12, depth=0.25, vertices=N,
    location=(0, 0, H + 0.15))
c = bpy.context.active_object
c.name = "Cornice"
c.data.materials.append(trim)
all_parts.append(c)

# ════════════════════════════════════════════
# 3. CONICAL ROOF
# ════════════════════════════════════════════
rv = []
for i in range(N):
    a = 2 * math.pi * i / N
    rv.append((math.cos(a) * (R + 0.3), math.sin(a) * (R + 0.3), H + 0.30))
rv.append((0, 0, H + 0.30 + ROOF_H))
rf = []
for i in range(N):
    rf.append((i, (i+1) % N, N))
rf.append(list(range(N)))
rm = bpy.data.meshes.new("roof_mesh")
rm.from_pydata(rv, [], rf)
rm.update()
ro = bpy.data.objects.new("ConicalRoof", rm)
bpy.context.collection.objects.link(ro)
ro.data.materials.append(slate)
all_parts.append(ro)

# Finial spike
bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=1.0, vertices=6,
    location=(0, 0, H + 0.30 + ROOF_H + 0.5))
fin = bpy.context.active_object
fin.name = "Finial"
fin.data.materials.append(iron)
all_parts.append(fin)

# ════════════════════════════════════════════
# 4. GOTHIC WINDOWS — pointed arch windows on alternating faces
# ════════════════════════════════════════════
win_h = 2.0
win_w = 0.8
win_z = H * 0.45 + 0.15

for i in range(0, N, 2):
    a = 2 * math.pi * i / N + math.pi / N
    wx = math.cos(a) * R
    wy = math.sin(a) * R
    # Window surround (projected slightly)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(wx, wy, win_z))
    w = bpy.context.active_object
    w.name = f"window_{i}"
    w.scale = (win_w, 0.12, win_h)
    w.rotation_euler = (0, 0, a)
    w.data.materials.append(trim)
    all_parts.append(w)
    # Pointed arch top
    bpy.ops.mesh.primitive_cube_add(size=1.0,
        location=(wx, wy, win_z + win_h/2 + 0.25))
    p = bpy.context.active_object
    p.name = f"arch_top_{i}"
    p.scale = (win_w * 0.5, 0.14, 0.30)
    p.rotation_euler = (0, 0, a)
    p.data.materials.append(trim)
    all_parts.append(p)

# ════════════════════════════════════════════
# 5. ENTRANCE DOOR — on one face (south)
# ════════════════════════════════════════════
door_a = math.pi * 0.5  # south face
door_x = math.cos(door_a) * (R + 0.05)
door_y = math.sin(door_a) * (R + 0.05)
door_h = 2.8
box("door_surround", door_x, door_y, door_h/2 + 0.15,
    0.90, 0.15, door_h/2, trim)


# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "GateHouse"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_gate_house.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported Gate House to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces: {len(obj.data.polygons)}")
