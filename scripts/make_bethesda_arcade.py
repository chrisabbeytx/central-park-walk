"""Generate the Bethesda Terrace Arcade for Central Park Walk.

The Arcade (1863) is a pedestrian passage beneath the 72nd Street
Transverse drive, connecting the upper terrace to the Bethesda
Fountain plaza. Features:
- Barrel-vaulted ceiling with ornate Minton tile
- Three barrel vaults (center wider, two sides narrower)
- Stone columns and pilasters
- Approximately 30m long × 15m wide × 5m tall

Located at approximately (-480, 1000) in world coords,
aligned roughly N-S connecting the upper Mall to the fountain.

Exports to models/furniture/cp_bethesda_arcade.glb
"""

import bpy
import bmesh
import math

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

objects = []

LENGTH = 30.0     # tunnel length (N-S)
MAIN_W = 6.0      # main center vault width
SIDE_W = 4.0      # side vault width
WALL_T = 0.8      # wall thickness
VAULT_H = 5.0     # vault crown height
SPRING_H = 3.0    # where vault springs from (top of columns)
COL_R = 0.3       # column radius
COL_SPACING = 3.0 # spacing between columns
N_COLS = int(LENGTH / COL_SPACING)

# --- Floor slab ---
total_w = MAIN_W + 2 * SIDE_W + 2 * WALL_T
bpy.ops.mesh.primitive_cube_add(size=1)
floor = bpy.context.active_object
floor.name = "Floor"
floor.scale = (total_w/2, 0.15, LENGTH/2)
floor.location = (0, 0.15, 0)
bpy.ops.object.transform_apply(location=True, scale=True)
objects.append(floor)

# --- Outer walls (2 side walls running the full length) ---
for sx in [-1, 1]:
    wall_x = sx * (total_w/2 - WALL_T/2)
    bpy.ops.mesh.primitive_cube_add(size=1)
    wall = bpy.context.active_object
    wall.name = f"Wall_{sx}"
    wall.scale = (WALL_T/2, VAULT_H/2, LENGTH/2)
    wall.location = (wall_x, VAULT_H/2, 0)
    bpy.ops.object.transform_apply(location=True, scale=True)
    objects.append(wall)

# --- Interior column rows (2 rows separating center from side vaults) ---
for sx in [-1, 1]:
    col_row_x = sx * (MAIN_W/2 + COL_R)
    for ci in range(N_COLS + 1):
        cz = -LENGTH/2 + ci * COL_SPACING
        bpy.ops.mesh.primitive_cylinder_add(radius=COL_R, depth=SPRING_H, vertices=10)
        col = bpy.context.active_object
        col.name = f"Col_{sx}_{ci}"
        col.location = (col_row_x, SPRING_H/2, cz)
        bpy.ops.object.transform_apply(location=True)
        objects.append(col)
        
        # Capital (wider ring at top of column)
        bpy.ops.mesh.primitive_cylinder_add(radius=COL_R * 1.3, depth=0.15, vertices=10)
        cap = bpy.context.active_object
        cap.name = f"Capital_{sx}_{ci}"
        cap.location = (col_row_x, SPRING_H + 0.075, cz)
        bpy.ops.object.transform_apply(location=True)
        objects.append(cap)

# --- Barrel vault ceilings (using half-cylinders) ---
# Center vault
bm = bmesh.new()
N_SEGS = 12
for zi in range(int(LENGTH)):
    z0 = -LENGTH/2 + zi
    z1 = z0 + 1.0
    for si in range(N_SEGS):
        a0 = math.pi * si / N_SEGS
        a1 = math.pi * (si + 1) / N_SEGS
        
        r = MAIN_W / 2
        x0 = math.cos(a0) * r
        y0 = SPRING_H + math.sin(a0) * (VAULT_H - SPRING_H)
        x1 = math.cos(a1) * r
        y1 = SPRING_H + math.sin(a1) * (VAULT_H - SPRING_H)
        
        v0 = bm.verts.new((x0, y0, z0))
        v1 = bm.verts.new((x1, y1, z0))
        v2 = bm.verts.new((x1, y1, z1))
        v3 = bm.verts.new((x0, y0, z1))
        bm.faces.new([v0, v1, v2, v3])

bm.verts.ensure_lookup_table()
mesh = bpy.data.meshes.new("CenterVault")
bm.to_mesh(mesh)
bm.free()
vault_obj = bpy.data.objects.new("CenterVault", mesh)
bpy.context.collection.objects.link(vault_obj)
objects.append(vault_obj)

# Side vaults (smaller)
for sx in [-1, 1]:
    bm = bmesh.new()
    offset_x = sx * (MAIN_W/2 + SIDE_W/2)
    side_r = SIDE_W / 2
    side_spring = SPRING_H
    side_crown = SPRING_H + (VAULT_H - SPRING_H) * 0.7  # lower than center
    
    for zi in range(int(LENGTH)):
        z0 = -LENGTH/2 + zi
        z1 = z0 + 1.0
        for si in range(N_SEGS):
            a0 = math.pi * si / N_SEGS
            a1 = math.pi * (si + 1) / N_SEGS
            
            x0 = offset_x + math.cos(a0) * side_r
            y0 = side_spring + math.sin(a0) * (side_crown - side_spring)
            x1 = offset_x + math.cos(a1) * side_r
            y1 = side_spring + math.sin(a1) * (side_crown - side_spring)
            
            v0 = bm.verts.new((x0, y0, z0))
            v1 = bm.verts.new((x1, y1, z0))
            v2 = bm.verts.new((x1, y1, z1))
            v3 = bm.verts.new((x0, y0, z1))
            bm.faces.new([v0, v1, v2, v3])
    
    bm.verts.ensure_lookup_table()
    mesh = bpy.data.meshes.new(f"SideVault_{sx}")
    bm.to_mesh(mesh)
    bm.free()
    sv_obj = bpy.data.objects.new(f"SideVault_{sx}", mesh)
    bpy.context.collection.objects.link(sv_obj)
    objects.append(sv_obj)

# --- End walls (north and south, with arched openings) ---
for sz in [-1, 1]:
    end_z = sz * LENGTH/2
    # Solid wall above spring line
    bpy.ops.mesh.primitive_cube_add(size=1)
    ew = bpy.context.active_object
    ew.name = f"EndWall_{sz}"
    ew.scale = (total_w/2, (VAULT_H - SPRING_H)/2, WALL_T/2)
    ew.location = (0, SPRING_H + (VAULT_H - SPRING_H)/2, end_z)
    bpy.ops.object.transform_apply(location=True, scale=True)
    objects.append(ew)

# --- Materials ---
stone_mat = bpy.data.materials.new("SandstoneWall")
stone_mat.use_nodes = True
bsdf = stone_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.60, 0.55, 0.45, 1.0)  # warm sandstone
bsdf.inputs["Roughness"].default_value = 0.80

tile_mat = bpy.data.materials.new("MintonTile")
tile_mat.use_nodes = True
bsdf2 = tile_mat.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.70, 0.62, 0.45, 1.0)  # ornate cream/terracotta
bsdf2.inputs["Roughness"].default_value = 0.40

floor_mat = bpy.data.materials.new("FloorStone")
floor_mat.use_nodes = True
bsdf3 = floor_mat.node_tree.nodes["Principled BSDF"]
bsdf3.inputs["Base Color"].default_value = (0.45, 0.42, 0.38, 1.0)  # dark flagstone
bsdf3.inputs["Roughness"].default_value = 0.75

for obj in objects:
    obj.data.materials.clear()
    if "Vault" in obj.name:
        obj.data.materials.append(tile_mat)
    elif "Floor" in obj.name:
        obj.data.materials.append(floor_mat)
    else:
        obj.data.materials.append(stone_mat)

# Join
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.join()
obj = bpy.context.active_object
obj.name = "BethesdaArcade"

# Fix Y-up → Z-up: script built with Y as height (wrong — Blender is Z-up).
# Rotate 90° around X so the GLTF exporter maps Y→up correctly.
obj.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

out_path = "/home/chris/central-park-walk/models/furniture/cp_bethesda_arcade.glb"
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True, export_apply=True)
vcount = len(obj.data.vertices)
fcount = len(obj.data.polygons)
print(f"Exported Bethesda Arcade to {out_path} ({vcount} verts, {fcount} faces)")
