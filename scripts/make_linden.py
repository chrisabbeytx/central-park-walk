"""
Generate Linden / Basswood (Tilia americana) tree model for Central Park Walk.

Lindens have a dense, symmetrical, broadly pyramidal crown — one of the most
uniform and tidy-looking trees. Heart-shaped leaves, fragrant flowers in June.
Bark is gray with flat ridges. Very common along paths and edges in the park.

290 instances in census. Conservancy zones: scattered throughout, often lining
paths. The Mall's northern sections include some lindens mixed with the elms.

Generates 5 variants → models/trees/linden.glb
Run: blender --background --python scripts/make_linden.py
"""

import bpy
import bmesh
import math
import random
from mathutils import Vector

# ---- Configuration ----
TREE_H = 5.0              # game scales to 12-22m
TRUNK_FRAC = 0.26
CANOPY_SPREAD = 2.8       # dense, symmetrical
N_VARIANTS = 5
OUT_PATH = "/home/chris/central-park-walk/models/trees/linden.glb"

TRUNK_SEGS = 7
BRANCH_SEGS = 5
SUB_SEGS = 4
LEAF_TEX_SIZE = 128

# ---- Scene cleanup ----
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)
for block in bpy.data.images:
    if block.users == 0:
        bpy.data.images.remove(block)

# ---- Leaf texture ----
# Linden: heart-shaped leaves, dense coverage
TEX = LEAF_TEX_SIZE
leaf_img = bpy.data.images.new("LindenLeafTex", width=TEX, height=TEX, alpha=True)
pixels = [0.0] * (TEX * TEX * 4)

leaf_rng = random.Random(773)
for _ in range(90):  # dense foliage
    cx = leaf_rng.randint(5, TEX - 5)
    cy = leaf_rng.randint(5, TEX - 5)
    leaf_w = leaf_rng.randint(4, 8)
    leaf_h = leaf_rng.randint(5, 11)
    angle = leaf_rng.uniform(0, math.pi)
    # Warm green (heart-shaped leaves)
    r = leaf_rng.uniform(0.60, 0.75)
    g = leaf_rng.uniform(0.82, 0.95)
    b = leaf_rng.uniform(0.50, 0.65)
    for dy in range(-leaf_h, leaf_h + 1):
        for dx in range(-leaf_w, leaf_w + 1):
            rx = dx * math.cos(angle) + dy * math.sin(angle)
            ry = -dx * math.sin(angle) + dy * math.cos(angle)
            # Heart shape: wider at top, tapered at bottom
            width_mod = 1.0 + 0.3 * max(0, ry / max(leaf_h, 1))
            if (rx / max(leaf_w * width_mod, 1)) ** 2 + (ry / max(leaf_h, 1)) ** 2 <= 1.0:
                px = (cx + dx) % TEX
                py = (cy + dy) % TEX
                idx = (py * TEX + px) * 4
                pixels[idx + 0] = r
                pixels[idx + 1] = g
                pixels[idx + 2] = b
                pixels[idx + 3] = 1.0

leaf_img.pixels[:] = pixels
leaf_img.pack()

# ---- Materials ----
bark_mat = bpy.data.materials.new(name="LindenBark")
bark_mat.use_nodes = True
bsdf_bark = bark_mat.node_tree.nodes["Principled BSDF"]
bsdf_bark.inputs["Base Color"].default_value = (0.35, 0.30, 0.24, 1.0)
bsdf_bark.inputs["Roughness"].default_value = 0.85

leaf_mat = bpy.data.materials.new(name="LindenLeaf")
leaf_mat.use_nodes = True
leaf_mat.blend_method = 'CLIP'
leaf_mat.alpha_threshold = 0.5
tree = leaf_mat.node_tree
bsdf_leaf = tree.nodes["Principled BSDF"]
bsdf_leaf.inputs["Roughness"].default_value = 0.72

tex_node = tree.nodes.new('ShaderNodeTexImage')
tex_node.image = leaf_img
tree.links.new(tex_node.outputs['Color'], bsdf_leaf.inputs['Base Color'])
tree.links.new(tex_node.outputs['Alpha'], bsdf_leaf.inputs['Alpha'])


# ---- Geometry helpers ----

def make_tube(name, points, r_start, r_end, segments, mat):
    bm = bmesh.new()
    rings = []
    n = len(points)
    for i, pt in enumerate(points):
        t = i / max(n - 1, 1)
        r = r_start + (r_end - r_start) * t
        if i < n - 1:
            fwd = (points[i + 1] - pt).normalized()
        else:
            fwd = (pt - points[i - 1]).normalized()
        if abs(fwd.dot(Vector((0, 0, 1)))) < 0.95:
            side = fwd.cross(Vector((0, 0, 1))).normalized()
        else:
            side = fwd.cross(Vector((1, 0, 0))).normalized()
        up = side.cross(fwd).normalized()
        ring = []
        for j in range(segments):
            a = 2.0 * math.pi * j / segments
            offset = side * math.cos(a) * r + up * math.sin(a) * r
            ring.append(bm.verts.new(pt + offset))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    for i in range(len(rings) - 1):
        for j in range(segments):
            j2 = (j + 1) % segments
            bm.faces.new([rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j]])
    if len(rings) > 0 and len(rings[0]) >= 3:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings) > 0 and len(rings[-1]) >= 3:
        bm.faces.new(rings[-1])
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def make_leaf_cluster(name, center, radius, flatten, rng_local):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1, radius=radius, location=tuple(center))
    obj = bpy.context.active_object
    obj.name = name
    for v in obj.data.vertices:
        v.co.z *= flatten
        noise = (math.sin(v.co.x * 6.0 + v.co.z * 3.5) *
                 math.cos(v.co.y * 5.4 + v.co.x * 2.8) * 0.13 * radius)
        v.co.x += noise
        v.co.y += noise * 0.7
        v.co.z += noise * 0.4
    obj.data.materials.append(leaf_mat)
    return obj


def bezier_point(p0, p1, p2, p3, t):
    u = 1.0 - t
    return (p0 * u * u * u + p1 * 3.0 * u * u * t +
            p2 * 3.0 * u * t * t + p3 * t * t * t)


def make_linden_variant(vi, seed):
    """Generate one Linden tree variant.

    Key characteristics:
    - Symmetrical, broadly pyramidal crown
    - Very dense foliage (more leaf clusters than other species)
    - Regular branching pattern
    - Medium trunk, straight
    """
    rng = random.Random(seed)
    bark_parts = []
    leaf_parts = []

    split_h = TREE_H * TRUNK_FRAC
    trunk_r_base = 0.14
    trunk_r_top = 0.08
    lean_x = rng.uniform(-0.02, 0.02)  # very straight
    lean_y = rng.uniform(-0.02, 0.02)

    # ---- Trunk: straight, regular ----
    n_trunk = 7
    trunk_pts = []
    for i in range(n_trunk):
        t = i / (n_trunk - 1)
        z = t * split_h
        trunk_pts.append(Vector((
            lean_x * t + math.sin(t * math.pi * 1.0) * 0.015,
            lean_y * t + math.cos(t * math.pi * 0.7) * 0.01,
            z)))
    bark_parts.append(make_tube(f"trunk_{vi}", trunk_pts,
                                trunk_r_base, trunk_r_top, TRUNK_SEGS, bark_mat))

    # Root flare
    n_roots = rng.randint(3, 5)
    for r_idx in range(n_roots):
        angle = (r_idx / n_roots) * 2 * math.pi + rng.uniform(-0.3, 0.3)
        dx = math.cos(angle)
        dy = math.sin(angle)
        root_len = rng.uniform(0.12, 0.22)
        root_pts = [
            Vector((0, 0, 0.07)),
            Vector((dx * root_len * 0.5, dy * root_len * 0.5, 0.02)),
            Vector((dx * root_len, dy * root_len, 0.0)),
        ]
        bark_parts.append(make_tube(f"root_{vi}_{r_idx}", root_pts,
                                    trunk_r_base * 0.50, 0.012, SUB_SEGS, bark_mat))

    # ---- Major limbs: regular, ascending ----
    n_limbs = rng.randint(5, 7)
    limb_data = []

    for b in range(n_limbs):
        # Very regular angular spacing (symmetrical tree)
        base_angle = (b / n_limbs) * 2.0 * math.pi + rng.uniform(-0.15, 0.15)
        dx = math.cos(base_angle)
        dy = math.sin(base_angle)

        end_spread = CANOPY_SPREAD * rng.uniform(0.65, 0.95)
        end_h = TREE_H * rng.uniform(0.72, 0.92)

        p0 = trunk_pts[-1].copy()
        p1 = Vector((lean_x + dx * end_spread * 0.15,
                      lean_y + dy * end_spread * 0.15,
                      split_h + (end_h - split_h) * 0.40))
        p2 = Vector((dx * end_spread * 0.55,
                      dy * end_spread * 0.55,
                      split_h + (end_h - split_h) * 0.75))
        p3 = Vector((dx * end_spread, dy * end_spread, end_h))

        n_pts = 8
        limb_pts = [bezier_point(p0, p1, p2, p3, t / (n_pts - 1))
                    for t in range(n_pts)]

        r_start = trunk_r_top * rng.uniform(0.45, 0.65)
        bark_parts.append(make_tube(f"limb_{vi}_{b}", limb_pts,
                                    r_start, 0.012, BRANCH_SEGS, bark_mat))
        limb_data.append((limb_pts, base_angle, end_spread))

        # Secondary branches
        n_subs = rng.randint(2, 4)
        for s in range(n_subs):
            t_start = rng.uniform(0.30, 0.80)
            idx = int(t_start * (len(limb_pts) - 1))
            origin = limb_pts[idx].copy()
            sub_angle = base_angle + rng.uniform(-0.8, 0.8)
            sub_dx = math.cos(sub_angle)
            sub_dy = math.sin(sub_angle)
            sub_len = rng.uniform(0.4, 0.9)
            sub_pts = []
            for sp in range(4):
                st = sp / 3.0
                sub_pts.append(Vector((
                    origin.x + sub_dx * sub_len * st,
                    origin.y + sub_dy * sub_len * st,
                    origin.z + sub_len * st * 0.25 + rng.uniform(-0.06, 0.06))))
            bark_parts.append(make_tube(f"sub_{vi}_{b}_{s}", sub_pts,
                                        0.018, 0.005, SUB_SEGS, bark_mat))

    # ---- Canopy: very dense, symmetrical, pyramidal ----

    # Along branches (dense)
    for b, (limb_pts, angle, spread) in enumerate(limb_data):
        n_cl = rng.randint(12, 18)
        for c in range(n_cl):
            t = rng.uniform(0.30, 1.0)
            idx = int(t * (len(limb_pts) - 1))
            idx2 = min(idx + 1, len(limb_pts) - 1)
            frac = t * (len(limb_pts) - 1) - idx
            pos = limb_pts[idx].lerp(limb_pts[idx2], frac)
            pos.x += rng.uniform(-0.5, 0.5)
            pos.y += rng.uniform(-0.5, 0.5)
            pos.z += rng.uniform(-0.15, 0.35)
            r = rng.uniform(0.28, 0.55)
            leaf_parts.append(make_leaf_cluster(
                f"lc_{vi}_{b}_{c}", pos, r, rng.uniform(0.45, 0.65), rng))

    # Dense dome fill (pyramidal: narrower at top)
    n_dome = rng.randint(18, 28)
    for f in range(n_dome):
        angle_f = rng.uniform(0, 2.0 * math.pi)
        z = TREE_H * rng.uniform(0.50, 0.95)
        # Pyramidal: spread narrows toward top
        max_dist = CANOPY_SPREAD * (1.0 - (z / TREE_H) * 0.5) * 0.65
        dist = rng.uniform(0, max_dist)
        x = math.cos(angle_f) * dist + rng.uniform(-0.25, 0.25)
        y = math.sin(angle_f) * dist + rng.uniform(-0.25, 0.25)
        r = rng.uniform(0.30, 0.55)
        leaf_parts.append(make_leaf_cluster(
            f"dome_{vi}_{f}", Vector((x, y, z)), r,
            rng.uniform(0.45, 0.60), rng))

    # Lower skirt (linden canopy extends lower than most trees)
    n_skirt = rng.randint(8, 14)
    for d in range(n_skirt):
        angle_d = rng.uniform(0, 2.0 * math.pi)
        dist = CANOPY_SPREAD * rng.uniform(0.65, 0.95)
        z = TREE_H * rng.uniform(0.30, 0.55)  # lower canopy
        x = math.cos(angle_d) * dist + rng.uniform(-0.25, 0.25)
        y = math.sin(angle_d) * dist + rng.uniform(-0.25, 0.25)
        r = rng.uniform(0.25, 0.50)
        leaf_parts.append(make_leaf_cluster(
            f"skirt_{vi}_{d}", Vector((x, y, z)), r,
            rng.uniform(0.50, 0.70), rng))

    # Inner fill
    n_inner = rng.randint(8, 14)
    for i_c in range(n_inner):
        angle_i = rng.uniform(0, 2.0 * math.pi)
        dist = rng.uniform(0.3, CANOPY_SPREAD * 0.50)
        z = split_h + (TREE_H - split_h) * rng.uniform(0.25, 0.65)
        x = math.cos(angle_i) * dist
        y = math.sin(angle_i) * dist
        r = rng.uniform(0.22, 0.45)
        leaf_parts.append(make_leaf_cluster(
            f"inner_{vi}_{i_c}", Vector((x, y, z)), r,
            rng.uniform(0.48, 0.65), rng))

    # ---- Finalize ----
    all_parts = bark_parts + leaf_parts
    for obj in all_parts:
        for poly in obj.data.polygons:
            poly.use_smooth = True

    bpy.ops.object.select_all(action='DESELECT')
    for obj in all_parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = all_parts[0]
    bpy.ops.object.join()

    final = bpy.context.active_object
    final.name = f"LindenTree_{vi + 1}"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    bbox = [final.matrix_world @ Vector(corner) for corner in final.bound_box]
    min_z = min(v.z for v in bbox)
    final.location.z -= min_z
    bpy.ops.object.transform_apply(location=True)

    bpy.ops.object.select_all(action='DESELECT')
    return final


# ---- Generate 5 variants ----
print("\n" + "=" * 60)
print("Building 5 Linden variants")
print("=" * 60 + "\n")

variants = []
for i in range(N_VARIANTS):
    v = make_linden_variant(i, seed=500 + i * 37)
    n_faces = len(v.data.polygons)
    d = v.dimensions
    print(f"  Variant {i+1}: {n_faces} faces, "
          f"size={d.x:.1f}x{d.y:.1f}x{d.z:.1f}")
    variants.append(v)

# ---- Export GLB ----
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(
    filepath=OUT_PATH,
    export_format='GLB',
    use_selection=True,
    export_apply=True,
)
print(f"\nExported {len(variants)} Linden variants to {OUT_PATH}")
