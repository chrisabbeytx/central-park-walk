"""Generate Wollman Rink for Central Park Walk.

Wollman Rink is an outdoor ice-skating rink in the southeast
corner of Central Park. Built in 1949.

Key features:
  - Oval rink surface (~55m × 25m)
  - Concrete perimeter wall/dasher board (1.2m)
  - Small service building/skate rental on north side
  - Spectator seating/bleachers on south side
  - Low-profile, ground-level facility

Origin at center of rink.
Exports to models/furniture/cp_wollman_rink.glb
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

concrete = make_mat("Concrete", (0.62, 0.60, 0.56), 0.90)
ice_mat  = make_mat("Ice",      (0.75, 0.80, 0.85), 0.25, 0.05)
metal    = make_mat("Metal",    (0.40, 0.40, 0.40), 0.50, 0.5)
wood     = make_mat("Wood",     (0.42, 0.32, 0.22), 0.85)
roof_mat = make_mat("Roof",     (0.35, 0.33, 0.30), 0.75)

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

# Rink dimensions
RX = 27.0   # half-length
RY = 12.0   # half-width
N_SEGS = 32
WALL_H = 1.2
WALL_T = 0.15

# ════════════════════════════════════════════
# 1. RINK SURFACE — oval ice/floor
# ════════════════════════════════════════════
verts = [(0, 0, 0.02)]  # center
for i in range(N_SEGS):
    a = 2 * math.pi * i / N_SEGS
    verts.append((math.cos(a) * RX, math.sin(a) * RY, 0.02))
faces = []
for i in range(N_SEGS):
    faces.append((0, i + 1, (i % N_SEGS) + 2 if i < N_SEGS - 1 else 1))
mesh = bpy.data.meshes.new("rink_surface")
mesh.from_pydata(verts, [], faces)
mesh.update()
obj = bpy.data.objects.new("RinkSurface", mesh)
bpy.context.collection.objects.link(obj)
obj.data.materials.append(ice_mat)
all_parts.append(obj)

# ════════════════════════════════════════════
# 2. PERIMETER WALL — dasher boards around rink
# ════════════════════════════════════════════
for i in range(N_SEGS):
    a1 = 2 * math.pi * i / N_SEGS
    a2 = 2 * math.pi * ((i + 1) % N_SEGS) / N_SEGS
    x1, y1 = math.cos(a1) * (RX + WALL_T), math.sin(a1) * (RY + WALL_T)
    x2, y2 = math.cos(a2) * (RX + WALL_T), math.sin(a2) * (RY + WALL_T)
    mx, my = (x1+x2)/2, (y1+y2)/2
    dx, dy = x2-x1, y2-y1
    seg_len = math.sqrt(dx*dx + dy*dy)
    ang = math.atan2(dy, dx)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(mx, my, WALL_H/2))
    w = bpy.context.active_object
    w.name = f"dasher_{i}"
    w.scale = (seg_len/2, WALL_T, WALL_H/2)
    w.rotation_euler = (0, 0, ang)
    w.data.materials.append(concrete)
    all_parts.append(w)

# ════════════════════════════════════════════
# 3. SERVICE BUILDING — skate rental on north side
# ════════════════════════════════════════════
SB_W = 18.0
SB_D = 6.0
SB_H = 3.5
sb_y = RY + 4.0

box("service_bldg", 0, sb_y, SB_H/2, SB_W/2, SB_D/2, SB_H/2, concrete)
# Flat roof
box("service_roof", 0, sb_y, SB_H + 0.12, SB_W/2 + 0.5, SB_D/2 + 0.5, 0.15, roof_mat)
# Window strip (glass)
glass = make_mat("Glass", (0.25, 0.30, 0.35), 0.10)
box("service_windows", 0, sb_y - SB_D/2, SB_H * 0.55,
    SB_W/2 - 1.0, 0.05, SB_H * 0.25, glass)

# ════════════════════════════════════════════
# 4. SPECTATOR AREA — bleachers on south side
# ════════════════════════════════════════════
BLEACH_ROWS = 4
BLEACH_D = 1.2
BLEACH_H = 0.35
for row in range(BLEACH_ROWS):
    by = -(RY + 2.0 + row * BLEACH_D)
    bz = row * BLEACH_H
    box(f"bleacher_{row}", 0, by, bz + BLEACH_H/2 + 0.1,
        12.0, BLEACH_D/2, BLEACH_H/2, concrete)

# Concrete deck around rink
deck_r = 3.0
box("deck_n", 0,  RY + 1.5, 0.08, RX + 3, 1.5, 0.12, concrete)
box("deck_s", 0, -RY - 1.5, 0.08, RX + 3, 1.5, 0.12, concrete)
box("deck_e",  RX + 1.5, 0, 0.08, 1.5, RY + 3, 0.12, concrete)
box("deck_w", -RX - 1.5, 0, 0.08, 1.5, RY + 3, 0.12, concrete)

# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "WollmanRink"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_wollman_rink.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported Wollman Rink to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces: {len(obj.data.polygons)}")
