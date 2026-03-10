"""Generate stone pedestals for Central Park statues and monuments.

Central Park's 106+ statues sit on a variety of stone bases. Most are
gray granite (Westerly or Barre granite) with classical molding profiles.
Three variants cover the main pedestal types:

  Variant 0 — Standard rectangular pedestal (statues, sculptures)
    ~1.2m tall, 0.8m × 0.8m shaft, stepped base + cornice with molding
  Variant 1 — Column pedestal (busts)
    ~1.5m tall, 0.45m × 0.45m shaft, chamfered cap for bust mounting
  Variant 2 — Wide memorial base (memorials, monuments)
    ~0.8m tall, 1.4m × 0.9m, low stepped profile with wide inscription face

Materials:
  'GrayGranite' — polished gray granite (Roughness 0.55 on faces, 0.78 on base)
  'Limestone' — warm buff limestone for some memorial bases

Exports: models/furniture/cp_pedestal.glb (3 variants as separate objects)
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector

# --- Clear scene ---
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# --- Materials ---
granite_mat = bpy.data.materials.new(name="GrayGranite")
granite_mat.use_nodes = True
bsdf = granite_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.52, 0.50, 0.47, 1.0)
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.62

limestone_mat = bpy.data.materials.new(name="Limestone")
limestone_mat.use_nodes = True
bsdf_l = limestone_mat.node_tree.nodes["Principled BSDF"]
bsdf_l.inputs["Base Color"].default_value = (0.65, 0.60, 0.52, 1.0)
bsdf_l.inputs["Metallic"].default_value = 0.0
bsdf_l.inputs["Roughness"].default_value = 0.75


def make_box(bm, cx, cy, cz, sx, sy, sz):
    """Create a box centered at (cx, cy+sy/2, cz) with half-sizes sx, sy, sz."""
    verts = []
    for dx in [-sx, sx]:
        for dy in [0, sy]:
            for dz in [-sz, sz]:
                verts.append(bm.verts.new((cx + dx, cy + dy, cz + dz)))
    bm.verts.ensure_lookup_table()
    # Faces: bottom, top, 4 sides
    faces = [
        (0, 2, 6, 4),  # front
        (1, 5, 7, 3),  # back
        (0, 1, 3, 2),  # bottom
        (4, 6, 7, 5),  # top
        (0, 4, 5, 1),  # left
        (2, 3, 7, 6),  # right
    ]
    base = len(bm.verts) - 8
    for f in faces:
        bm.faces.new([bm.verts[base + i] for i in f])
    return verts


def make_chamfered_box(bm, cx, cy, cz, sx, sy, sz, chamfer=0.03):
    """Box with beveled top edges for classical molding look."""
    # Main shaft
    make_box(bm, cx, cy, cz, sx, sy, sz)
    # Slight inset ledge at top (cornice)
    make_box(bm, cx, cy + sy, cz, sx + chamfer, chamfer * 0.6, sz + chamfer)


# ==========================================================================
# Variant 0: Standard rectangular pedestal (statues, sculptures)
# ==========================================================================
def build_standard_pedestal():
    bm = bmesh.new()

    # Stepped base (3 tiers)
    # Bottom step: widest
    make_box(bm, 0, 0, 0, 0.55, 0.10, 0.55)
    # Middle step
    make_box(bm, 0, 0.10, 0, 0.48, 0.08, 0.48)
    # Top step / plinth
    make_box(bm, 0, 0.18, 0, 0.43, 0.06, 0.43)

    # Main shaft
    make_box(bm, 0, 0.24, 0, 0.38, 0.72, 0.38)

    # Cornice molding at top (wider ledge)
    make_box(bm, 0, 0.96, 0, 0.42, 0.04, 0.42)
    # Cap plate
    make_box(bm, 0, 1.00, 0, 0.44, 0.05, 0.44)
    # Slight crown
    make_box(bm, 0, 1.05, 0, 0.40, 0.03, 0.40)

    mesh = bpy.data.meshes.new("pedestal_standard")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Pedestal_Standard", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(granite_mat)
    return obj


# ==========================================================================
# Variant 1: Column pedestal (busts)
# ==========================================================================
def build_column_pedestal():
    bm = bmesh.new()

    # Square base
    make_box(bm, 0, 0, 0, 0.40, 0.08, 0.40)
    make_box(bm, 0, 0.08, 0, 0.35, 0.05, 0.35)

    # Tall narrow shaft
    make_box(bm, 0, 0.13, 0, 0.25, 1.10, 0.25)

    # Capital / top molding
    make_box(bm, 0, 1.23, 0, 0.30, 0.04, 0.30)
    make_box(bm, 0, 1.27, 0, 0.33, 0.06, 0.33)
    # Flat mounting plate for bust
    make_box(bm, 0, 1.33, 0, 0.28, 0.03, 0.28)

    mesh = bpy.data.meshes.new("pedestal_column")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Pedestal_Column", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(granite_mat)
    return obj


# ==========================================================================
# Variant 2: Wide memorial base (memorials, monuments)
# ==========================================================================
def build_memorial_base():
    bm = bmesh.new()

    # Wide low stepped base
    make_box(bm, 0, 0, 0, 0.80, 0.08, 0.55)
    make_box(bm, 0, 0.08, 0, 0.72, 0.06, 0.48)

    # Main body — wide rectangular, good for inscriptions
    make_box(bm, 0, 0.14, 0, 0.65, 0.45, 0.42)

    # Top ledge
    make_box(bm, 0, 0.59, 0, 0.68, 0.04, 0.45)
    # Cap
    make_box(bm, 0, 0.63, 0, 0.62, 0.05, 0.40)

    mesh = bpy.data.meshes.new("pedestal_memorial")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("Pedestal_Memorial", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(limestone_mat)
    return obj


# ==========================================================================
# Build all variants and export
# ==========================================================================
objs = []
objs.append(build_standard_pedestal())
objs.append(build_column_pedestal())
objs.append(build_memorial_base())

# Position variants side by side for inspection (doesn't matter for game)
objs[0].location = (0, 0, 0)
objs[1].location = (2, 0, 0)
objs[2].location = (4, 0, 0)

# Select all and export
bpy.ops.object.select_all(action='SELECT')
out_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         "models", "furniture", "cp_pedestal.glb")
os.makedirs(os.path.dirname(out_path), exist_ok=True)

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
    export_yup=True,
)

print(f"Exported pedestal variants to {out_path}")
print(f"  Standard: ~1.08m tall, 3 stepped tiers + shaft + cornice")
print(f"  Column:   ~1.36m tall, narrow shaft for bust mounting")
print(f"  Memorial: ~0.68m tall, wide inscription face")
