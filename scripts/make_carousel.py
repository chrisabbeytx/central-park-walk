"""Generate Central Park Carousel pavilion for Central Park Walk.

The Central Park Carousel (originally 1871, current structure 1951)
is housed in a distinctive octagonal brick pavilion near the center
of the park. One of the largest carousels in the US with 57 hand-
carved horses.

Key features:
  - Octagonal brick pavilion (~15m diameter)
  - Conical shingled roof with cupola ventilator
  - Large open archways on all 8 sides (accessible when operating)
  - Red brick with stone trim
  - Central pole/mechanism housing

Origin at ground center.
Exports to models/furniture/cp_carousel.glb
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

brick    = make_mat("Brick",    (0.55, 0.28, 0.20), 0.88)
stone    = make_mat("Stone",    (0.62, 0.58, 0.52), 0.85)
shingle  = make_mat("Shingle",  (0.32, 0.26, 0.20), 0.80)
trim_mat = make_mat("Trim",     (0.70, 0.66, 0.58), 0.82)
iron     = make_mat("Iron",     (0.12, 0.12, 0.11), 0.60, 0.3)

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

R = 7.5       # pavilion radius
H = 5.0       # wall height to eave
ROOF_H = 4.0  # conical roof rise
N = 8         # octagonal
PIER_W = 1.2  # pier width (brick between arches)
ARCH_H = 3.8  # arch opening height

# ════════════════════════════════════════════
# 1. FOUNDATION
# ════════════════════════════════════════════
bpy.ops.mesh.primitive_cylinder_add(radius=R + 1.0, depth=0.4, vertices=N,
    location=(0, 0, 0.0))
f = bpy.context.active_object
f.name = "Foundation"
f.data.materials.append(stone)
all_parts.append(f)

# ════════════════════════════════════════════
# 2. BRICK PIERS — octagonal with arched openings between
# ════════════════════════════════════════════
for i in range(N):
    a = 2 * math.pi * i / N
    px = math.cos(a) * R
    py = math.sin(a) * R
    # Full-height brick pier
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(px, py, H/2 + 0.20))
    p = bpy.context.active_object
    p.name = f"pier_{i}"
    p.scale = (PIER_W, 0.60, H)
    p.rotation_euler = (0, 0, a)
    p.data.materials.append(brick)
    all_parts.append(p)

# Above-arch wall band (connects piers at top)
for i in range(N):
    a1 = 2 * math.pi * i / N
    a2 = 2 * math.pi * ((i+1) % N) / N
    am = (a1 + a2) / 2
    mx = math.cos(am) * (R - 0.15)
    my = math.sin(am) * (R - 0.15)
    dx = math.cos(a2) * R - math.cos(a1) * R
    dy = math.sin(a2) * R - math.sin(a1) * R
    seg_len = math.sqrt(dx*dx + dy*dy)
    ang = math.atan2(dy, dx)
    # Top band above arches
    wall_above_h = H - ARCH_H
    bpy.ops.mesh.primitive_cube_add(size=1.0,
        location=(mx, my, ARCH_H + 0.20 + wall_above_h/2))
    w = bpy.context.active_object
    w.name = f"wall_above_{i}"
    w.scale = (seg_len/2, 0.30, wall_above_h/2)
    w.rotation_euler = (0, 0, ang)
    w.data.materials.append(brick)
    all_parts.append(w)

# Cornice band
bpy.ops.mesh.primitive_cylinder_add(radius=R + 0.20, depth=0.25, vertices=N,
    location=(0, 0, H + 0.20))
c = bpy.context.active_object
c.name = "Cornice"
c.data.materials.append(trim_mat)
all_parts.append(c)

# ════════════════════════════════════════════
# 3. CONICAL ROOF
# ════════════════════════════════════════════
rv = []
for i in range(N):
    a = 2 * math.pi * i / N
    rv.append((math.cos(a) * (R + 0.6), math.sin(a) * (R + 0.6), H + 0.35))
rv.append((0, 0, H + 0.35 + ROOF_H))
rf = []
for i in range(N):
    rf.append((i, (i+1) % N, N))
rf.append(list(range(N)))
rm = bpy.data.meshes.new("roof_mesh")
rm.from_pydata(rv, [], rf)
rm.update()
ro = bpy.data.objects.new("ConicalRoof", rm)
bpy.context.collection.objects.link(ro)
ro.data.materials.append(shingle)
all_parts.append(ro)

# ════════════════════════════════════════════
# 4. CUPOLA VENTILATOR
# ════════════════════════════════════════════
cupola_z = H + 0.35 + ROOF_H
bpy.ops.mesh.primitive_cylinder_add(radius=1.2, depth=1.5, vertices=N,
    location=(0, 0, cupola_z + 0.75))
cup = bpy.context.active_object
cup.name = "Cupola"
cup.data.materials.append(trim_mat)
all_parts.append(cup)

# Cupola mini roof
cv = []
for i in range(N):
    a = 2 * math.pi * i / N
    cv.append((math.cos(a) * 1.5, math.sin(a) * 1.5, cupola_z + 1.5))
cv.append((0, 0, cupola_z + 3.0))
cf = []
for i in range(N):
    cf.append((i, (i+1) % N, N))
cf.append(list(range(N)))
cm = bpy.data.meshes.new("cupola_roof")
cm.from_pydata(cv, [], cf)
cm.update()
co = bpy.data.objects.new("CupolaRoof", cm)
bpy.context.collection.objects.link(co)
co.data.materials.append(shingle)
all_parts.append(co)

# Finial
bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.8, vertices=6,
    location=(0, 0, cupola_z + 3.4))
fin = bpy.context.active_object
fin.name = "Finial"
fin.data.materials.append(iron)
all_parts.append(fin)

# ════════════════════════════════════════════
# 5. INTERIOR — central pole housing
# ════════════════════════════════════════════
bpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=H + ROOF_H,
    vertices=12, location=(0, 0, (H + ROOF_H) / 2 + 0.20))
pole = bpy.context.active_object
pole.name = "CenterPole"
pole.data.materials.append(iron)
all_parts.append(pole)

# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "Carousel"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_carousel.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported Carousel to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces: {len(obj.data.polygons)}")
