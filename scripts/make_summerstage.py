"""Generate SummerStage (Rumsey Playfield) for Central Park Walk.

SummerStage is an open-air concert venue in Rumsey Playfield,
hosting free performances since 1986. Has a permanent covered
stage with a large open lawn seating area.

Key features:
  - Covered main stage (~15m × 10m)
  - Steel truss roof structure
  - Wing side stages
  - Sound/lighting towers
  - Open lawn bowl in front

Origin at center of stage.
Exports to models/furniture/cp_summerstage.glb
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

steel    = make_mat("Steel",    (0.45, 0.45, 0.45), 0.50, 0.6)
concrete = make_mat("Concrete", (0.60, 0.58, 0.54), 0.90)
dark_mat = make_mat("Dark",     (0.15, 0.15, 0.15), 0.70)
roof_mat = make_mat("RoofMembrane", (0.85, 0.82, 0.78), 0.60)

all_parts = []

def box(name, cx, cy, cz, hx, hy, hz, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, cz))
    o = bpy.context.active_object
    o.name = name
    o.scale = (hx * 2, hy * 2, hz * 2)
    o.data.materials.append(mat)
    all_parts.append(o)
    return o

STAGE_W = 15.0
STAGE_D = 10.0
STAGE_H = 1.0
ROOF_H = 8.0

# ════════════════════════════════════════════
# 1. STAGE PLATFORM
# ════════════════════════════════════════════
box("stage_platform", 0, 0, STAGE_H/2, STAGE_W/2, STAGE_D/2, STAGE_H/2, concrete)

# Backstage wall
box("backstage", 0, -STAGE_D/2 - 0.3, ROOF_H/2,
    STAGE_W/2, 0.30, ROOF_H/2, dark_mat)

# ════════════════════════════════════════════
# 2. STEEL TRUSS ROOF
# ════════════════════════════════════════════
# Main columns (4 corners)
for px in (-STAGE_W/2 + 0.5, STAGE_W/2 - 0.5):
    for py in (-STAGE_D/2 + 0.5, STAGE_D/2 - 0.5):
        box(f"column_{px}_{py}", px, py, ROOF_H/2 + STAGE_H,
            0.15, 0.15, ROOF_H/2, steel)

# Roof plane (slightly sloped — higher at back)
rv = [
    (-STAGE_W/2 - 1.0, -STAGE_D/2 - 1.0, ROOF_H + STAGE_H + 0.5),
    ( STAGE_W/2 + 1.0, -STAGE_D/2 - 1.0, ROOF_H + STAGE_H + 0.5),
    ( STAGE_W/2 + 1.0,  STAGE_D/2 + 2.0, ROOF_H + STAGE_H - 0.3),
    (-STAGE_W/2 - 1.0,  STAGE_D/2 + 2.0, ROOF_H + STAGE_H - 0.3),
]
rf = [(0, 1, 2, 3), (0, 3, 2, 1)]  # top and bottom
rm = bpy.data.meshes.new("roof_plane")
rm.from_pydata(rv, [], rf)
rm.update()
ro = bpy.data.objects.new("RoofPlane", rm)
bpy.context.collection.objects.link(ro)
ro.data.materials.append(roof_mat)
all_parts.append(ro)

# Horizontal truss beams along top
for py in (-STAGE_D/2 + 0.5, 0, STAGE_D/2 - 0.5):
    box(f"truss_x_{py}", 0, py, ROOF_H + STAGE_H - 0.15,
        STAGE_W/2, 0.08, 0.10, steel)
for px in (-STAGE_W/2 + 0.5, 0, STAGE_W/2 - 0.5):
    box(f"truss_y_{px}", px, 0, ROOF_H + STAGE_H - 0.15,
        0.08, STAGE_D/2, 0.10, steel)

# ════════════════════════════════════════════
# 3. WING STAGES (side platforms)
# ════════════════════════════════════════════
for side in (-1, 1):
    box(f"wing_{side}", side * (STAGE_W/2 + 2.5), 0, 0.35,
        2.5, STAGE_D/2 * 0.6, 0.35, concrete)

# ════════════════════════════════════════════
# 4. SOUND/LIGHTING TOWERS
# ════════════════════════════════════════════
tower_h = 10.0
for side in (-1, 1):
    tx = side * (STAGE_W/2 + 6.0)
    box(f"tower_{side}", tx, STAGE_D * 0.3, tower_h/2,
        0.30, 0.30, tower_h/2, steel)
    # Cross bracing (simplified)
    box(f"tower_brace_{side}", tx, STAGE_D * 0.3, tower_h * 0.35,
        0.50, 0.50, 0.08, steel)
    box(f"tower_brace2_{side}", tx, STAGE_D * 0.3, tower_h * 0.7,
        0.50, 0.50, 0.08, steel)
    # Light bar at top
    box(f"light_bar_{side}", tx, STAGE_D * 0.3, tower_h + 0.3,
        1.5, 0.20, 0.15, dark_mat)

# ════════════════════════════════════════════
# 5. FRONT STAGE EDGE
# ════════════════════════════════════════════
box("front_edge", 0, STAGE_D/2, STAGE_H/2 + 0.02,
    STAGE_W/2 + 0.1, 0.08, STAGE_H/2 + 0.02, dark_mat)


# ════════════════════════════════════════════
# FINALIZE
# ════════════════════════════════════════════
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = all_parts[0]
bpy.ops.object.join()

obj = bpy.context.active_object
obj.name = "SummerStage"
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

out_path = "/home/chris/central-park-walk/models/furniture/cp_summerstage.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB',
    use_selection=True, export_apply=True)
print(f"Exported SummerStage to {out_path}")
print(f"  Vertices: {len(obj.data.vertices)}")
print(f"  Faces: {len(obj.data.polygons)}")
