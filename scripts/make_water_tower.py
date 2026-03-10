"""Generate a NYC rooftop water tower (Rosenwach/Isseks style).

The distinctive wooden water towers on NYC rooftops are cedar barrel-stave
construction with steel band hoops, conical cedar roof, and a welded steel
frame (typically 4–6 legs with cross-bracing).

Typical dimensions (10,000-gallon tank):
  Barrel: ~2.4m (8ft) diameter × ~3.0m (10ft) tall
  Roof:   conical, ~15° pitch, slight overhang
  Frame:  ~2.8m (9ft) tall steel legs, 4 legs in square pattern
  Hoops:  5–6 steel bands around barrel

Materials:
  'Cedar'  — weathered gray-brown wood for barrel staves + roof
  'Steel'  — dark structural steel for frame legs + hoops + bracing

Exports: models/furniture/cp_water_tower.glb
  Two objects: CP_WaterTower_Wood + CP_WaterTower_Steel
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector

# Clear scene
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# --- Materials ---
cedar_mat = bpy.data.materials.new(name="Cedar")
cedar_mat.use_nodes = True
bsdf = cedar_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.38, 0.30, 0.20, 1.0)  # weathered cedar
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.88

steel_mat = bpy.data.materials.new(name="Steel")
steel_mat.use_nodes = True
bsdf2 = steel_mat.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.10, 0.10, 0.08, 1.0)  # dark structural steel
bsdf2.inputs["Metallic"].default_value = 0.7
bsdf2.inputs["Roughness"].default_value = 0.45

# --- Dimensions (metres) ---
BARREL_R = 1.20       # barrel radius (2.4m diameter, ~8ft)
BARREL_H = 3.00       # barrel height (~10ft)
STAVE_COUNT = 20      # number of visible staves
STAVE_GAP = 0.003     # gap between staves (visible seams)

ROOF_OVERHANG = 0.08  # roof extends past barrel
ROOF_PITCH = math.radians(18)  # conical roof angle
ROOF_APEX_H = (BARREL_R + ROOF_OVERHANG) * math.tan(ROOF_PITCH)

HOOP_COUNT = 5        # steel bands around barrel
HOOP_W = 0.04         # hoop band width
HOOP_T = 0.005        # hoop thickness (stands off barrel)

LEG_COUNT = 4         # steel frame legs
LEG_R = 0.05          # leg pipe radius
LEG_H = 2.80          # leg height
LEG_OFFSET = 0.85     # leg distance from center (square pattern)

BRACE_R = 0.03        # cross-brace pipe radius

CIRC_SEGS = 20        # segments for circular geometry

# Total height: LEG_H + BARREL_H + ROOF_APEX_H ≈ 2.8 + 3.0 + 0.41 ≈ 6.2m
BARREL_Z = LEG_H      # barrel bottom Z


def make_barrel_staves():
    """Cedar barrel staves — vertical planks forming the cylindrical tank."""
    objs = []
    for i in range(STAVE_COUNT):
        a0 = 2 * math.pi * i / STAVE_COUNT + STAVE_GAP / BARREL_R
        a1 = 2 * math.pi * (i + 1) / STAVE_COUNT - STAVE_GAP / BARREL_R

        bm = bmesh.new()
        n_a = 3  # angular subdivisions per stave
        rings = []
        for j in range(2):  # bottom and top
            z = BARREL_Z + j * BARREL_H
            ring = []
            for k in range(n_a + 1):
                t = k / n_a
                a = a0 + t * (a1 - a0)
                # Slight barrel bulge (cooper's swell) — radius increases ~2% at mid-height
                bulge = 1.0 + 0.02 * (1.0 - abs(2.0 * j - 1.0))
                r = BARREL_R * bulge
                ring.append(bm.verts.new(Vector((
                    math.cos(a) * r,
                    math.sin(a) * r,
                    z
                ))))
            rings.append(ring)

        bm.verts.ensure_lookup_table()
        # Front face (outer surface)
        for k in range(n_a):
            bm.faces.new([rings[0][k], rings[0][k+1], rings[1][k+1], rings[1][k]])
        # End caps (top and bottom of stave)
        bm.faces.new(rings[0][::-1])
        bm.faces.new(rings[1])

        mesh = bpy.data.meshes.new(f"stave_{i}")
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(f"stave_{i}", mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(cedar_mat)
        for poly in obj.data.polygons:
            poly.use_smooth = True
        objs.append(obj)

    # Inner liner (water-tight cylinder behind staves)
    bpy.ops.mesh.primitive_cylinder_add(
        radius=BARREL_R - 0.02, depth=BARREL_H, vertices=CIRC_SEGS,
        location=(0, 0, BARREL_Z + BARREL_H / 2)
    )
    liner = bpy.context.active_object
    liner.name = "barrel_liner"
    liner.data.materials.append(cedar_mat)
    objs.append(liner)

    return objs


def make_roof():
    """Conical cedar roof with slight overhang."""
    objs = []
    bm = bmesh.new()
    roof_r = BARREL_R + ROOF_OVERHANG
    roof_base_z = BARREL_Z + BARREL_H
    apex_z = roof_base_z + ROOF_APEX_H

    # Apex vertex
    apex = bm.verts.new(Vector((0, 0, apex_z)))

    # Base ring
    ring = []
    for i in range(CIRC_SEGS):
        a = 2 * math.pi * i / CIRC_SEGS
        ring.append(bm.verts.new(Vector((
            math.cos(a) * roof_r,
            math.sin(a) * roof_r,
            roof_base_z
        ))))

    bm.verts.ensure_lookup_table()
    # Cone faces
    for i in range(CIRC_SEGS):
        i2 = (i + 1) % CIRC_SEGS
        bm.faces.new([ring[i], ring[i2], apex])

    # Base cap (underside)
    bm.faces.new(ring[::-1])

    mesh = bpy.data.meshes.new("roof")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("roof", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(cedar_mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    objs.append(obj)

    return objs


def make_hoops():
    """Steel band hoops around barrel."""
    objs = []
    for i in range(HOOP_COUNT):
        t = (i + 0.5) / HOOP_COUNT
        z = BARREL_Z + t * BARREL_H
        # Barrel bulge at this height
        bulge = 1.0 + 0.02 * (1.0 - abs(2.0 * t - 1.0))
        r = BARREL_R * bulge + HOOP_T

        bpy.ops.mesh.primitive_torus_add(
            major_radius=r, minor_radius=HOOP_W / 2,
            major_segments=CIRC_SEGS, minor_segments=6,
            location=(0, 0, z)
        )
        hoop = bpy.context.active_object
        hoop.name = f"hoop_{i}"
        hoop.data.materials.append(steel_mat)
        objs.append(hoop)

    return objs


def make_frame():
    """Steel frame — 4 legs with X-bracing."""
    objs = []

    # Leg positions (square pattern)
    leg_positions = []
    for lx_sign in [-1, 1]:
        for ly_sign in [-1, 1]:
            leg_positions.append((lx_sign * LEG_OFFSET, ly_sign * LEG_OFFSET))

    # Legs — vertical pipes
    for i, (lx, ly) in enumerate(leg_positions):
        bpy.ops.mesh.primitive_cylinder_add(
            radius=LEG_R, depth=LEG_H, vertices=8,
            location=(lx, ly, LEG_H / 2)
        )
        leg = bpy.context.active_object
        leg.name = f"leg_{i}"
        leg.data.materials.append(steel_mat)
        objs.append(leg)

    # Horizontal braces at top and bottom of frame
    for brace_z in [0.3, LEG_H - 0.1]:
        for side in range(4):
            i0 = side
            i1 = (side + 1) % 4
            p0 = leg_positions[i0]
            p1 = leg_positions[i1]
            mx = (p0[0] + p1[0]) / 2
            my = (p0[1] + p1[1]) / 2
            dx = p1[0] - p0[0]
            dy = p1[1] - p0[1]
            length = math.sqrt(dx*dx + dy*dy)
            angle = math.atan2(dy, dx)

            bpy.ops.mesh.primitive_cylinder_add(
                radius=BRACE_R, depth=length, vertices=6,
                location=(mx, my, brace_z)
            )
            brace = bpy.context.active_object
            brace.name = f"brace_{side}_{brace_z:.0f}"
            brace.rotation_euler = (math.pi/2, 0, angle)
            brace.data.materials.append(steel_mat)
            objs.append(brace)

    # Diagonal X-bracing on two opposite faces
    for side in [0, 2]:
        i0 = side
        i1 = (side + 1) % 4
        p0 = leg_positions[i0]
        p1 = leg_positions[i1]

        # Diagonal from bottom-left to top-right
        start = Vector((p0[0], p0[1], 0.3))
        end = Vector((p1[0], p1[1], LEG_H - 0.1))
        mid = (start + end) / 2
        diff = end - start
        length = diff.length
        # Rotation to align Z-up cylinder with the diagonal
        pitch = math.acos(diff.z / length)
        yaw = math.atan2(diff.y, diff.x)

        bpy.ops.mesh.primitive_cylinder_add(
            radius=BRACE_R * 0.8, depth=length, vertices=6,
            location=tuple(mid)
        )
        diag = bpy.context.active_object
        diag.name = f"xbrace_{side}"
        diag.rotation_euler = (pitch, 0, yaw)
        diag.data.materials.append(steel_mat)
        objs.append(diag)

    # Top plate — flat disc connecting legs to barrel bottom
    bpy.ops.mesh.primitive_cylinder_add(
        radius=LEG_OFFSET + LEG_R + 0.05, depth=0.03, vertices=CIRC_SEGS,
        location=(0, 0, LEG_H - 0.015)
    )
    plate = bpy.context.active_object
    plate.name = "top_plate"
    plate.data.materials.append(steel_mat)
    objs.append(plate)

    return objs


# --- Build the water tower ---
wood_parts = []
steel_parts = []

wood_parts.extend(make_barrel_staves())
wood_parts.extend(make_roof())
steel_parts.extend(make_hoops())
steel_parts.extend(make_frame())

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Join wood parts
bpy.ops.object.select_all(action='DESELECT')
for obj in wood_parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = wood_parts[0]
bpy.ops.object.join()
wood_obj = bpy.context.active_object
wood_obj.name = "CP_WaterTower_Wood"

# Join steel parts
bpy.ops.object.select_all(action='DESELECT')
for obj in steel_parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = steel_parts[0]
bpy.ops.object.join()
steel_obj = bpy.context.active_object
steel_obj.name = "CP_WaterTower_Steel"

# Set origin so bottom of frame legs is at Z=0
bpy.ops.object.select_all(action='SELECT')
bbox_all = []
for obj in [wood_obj, steel_obj]:
    bbox_all.extend([obj.matrix_world @ Vector(c) for c in obj.bound_box])
min_z = min(v.z for v in bbox_all)
for obj in [wood_obj, steel_obj]:
    obj.location.z -= min_z
bpy.ops.object.transform_apply(location=True)

# Export GLB
out_path = "/home/chris/central-park-walk/models/furniture/cp_water_tower.glb"
os.makedirs(os.path.dirname(out_path), exist_ok=True)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)

# Print stats
total_faces = sum(len(obj.data.polygons) for obj in [wood_obj, steel_obj])
max_z = max(v.z for v in bbox_all) - min_z
print(f"Exported NYC water tower to {out_path}")
print(f"  Height: {max_z:.2f}m  ({max_z * 39.37:.1f} in)")
print(f"  Wood faces: {len(wood_obj.data.polygons)}")
print(f"  Steel faces: {len(steel_obj.data.polygons)}")
print(f"  Total faces: {total_faces}")
