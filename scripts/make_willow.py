"""
Generate weeping willow tree model for Central Park Walk.

Weeping willows (Salix babylonica / S. × sepulcralis) are among the most
recognizable trees in Central Park, found along The Lake, The Pool, Turtle
Pond, and Harlem Meer. Their cascading curtain of fine branches is iconic.

Key characteristics:
  - Wide, dome-shaped crown formed by drooping branches
  - Short-to-medium trunk that branches early (3-5m)
  - 4-7 main limbs arching upward and outward
  - Dense curtain of thin whip-like branches hanging down 2-4m
  - Narrow lance-shaped leaves (not modeled individually — leaf clusters)
  - Gray-brown deeply furrowed bark on trunk, smooth gray on branches
  - Fast-growing, often 12-18m tall in Central Park

Generates 5 variants → models/trees/willow.glb
Run: blender --background --python scripts/make_willow.py
"""

import bpy
import bmesh
import math
import random
from mathutils import Vector

# ---- Configuration ----
TREE_H = 5.0              # model scale height
N_VARIANTS = 5
OUT_PATH = "/home/chris/central-park-walk/models/trees/willow.glb"

TRUNK_SEGS = 7
BRANCH_SEGS = 5
DROOP_SEGS = 4
SUB_SEGS = 4

# ---- Scene cleanup ----
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.meshes:
    if block.users == 0:
        bpy.data.meshes.remove(block)
for block in bpy.data.materials:
    if block.users == 0:
        bpy.data.materials.remove(block)

# ---- Materials ----
# Bark: gray-brown, deeply furrowed
bark_mat = bpy.data.materials.new(name="WillowBark")
bark_mat.use_nodes = True
bsdf = bark_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.40, 0.35, 0.28, 1.0)
bsdf.inputs["Roughness"].default_value = 0.88

# Leaves: narrow willow leaves, yellow-green
leaf_mat = bpy.data.materials.new(name="WillowLeaf")
leaf_mat.use_nodes = True
bsdf_l = leaf_mat.node_tree.nodes["Principled BSDF"]
bsdf_l.inputs["Base Color"].default_value = (0.30, 0.48, 0.15, 1.0)
bsdf_l.inputs["Roughness"].default_value = 0.82
# Enable transparency for leaf alpha cutout
leaf_mat.blend_method = 'CLIP' if hasattr(leaf_mat, 'blend_method') else 'OPAQUE'


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


def make_leaf_cluster(name, center, radius, n_quads, rng, mat):
    """Create a cluster of leaf billboard quads — elongated for willow."""
    bm = bmesh.new()
    for _ in range(n_quads):
        # Random position within cluster sphere
        dx = rng.gauss(0, radius * 0.45)
        dy = rng.gauss(0, radius * 0.45)
        dz = rng.gauss(0, radius * 0.35)
        qc = Vector((center.x + dx, center.y + dy, center.z + dz))
        # Elongated leaf quad — narrower and longer than typical broadleaf
        w = rng.uniform(0.04, 0.08)
        h = rng.uniform(0.12, 0.22)  # elongated willow leaf shape
        angle = rng.uniform(0, math.pi)
        ax = math.cos(angle) * w
        az = math.sin(angle) * w
        v0 = bm.verts.new((qc.x - ax, qc.y - h * 0.5, qc.z - az))
        v1 = bm.verts.new((qc.x + ax, qc.y - h * 0.5, qc.z + az))
        v2 = bm.verts.new((qc.x + ax, qc.y + h * 0.5, qc.z + az))
        v3 = bm.verts.new((qc.x - ax, qc.y + h * 0.5, qc.z - az))
        try:
            bm.faces.new([v0, v1, v2, v3])
        except ValueError:
            pass
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def bezier_point(p0, p1, p2, p3, t):
    u = 1.0 - t
    return (p0 * u * u * u +
            p1 * 3.0 * u * u * t +
            p2 * 3.0 * u * t * t +
            p3 * t * t * t)


def make_willow_variant(vi, seed):
    """Generate one weeping willow variant."""
    rng = random.Random(seed)
    parts = []

    trunk_r_base = rng.uniform(0.14, 0.20)
    trunk_r_top = rng.uniform(0.06, 0.10)

    # Willows are generally straight-trunked but can have slight lean
    lean_angle = rng.uniform(0, 2.0 * math.pi)
    lean_amount = rng.uniform(0.02, 0.08)
    lean_x = math.cos(lean_angle) * lean_amount
    lean_y = math.sin(lean_angle) * lean_amount

    # Trunk height fraction — willows branch early
    trunk_frac = rng.uniform(0.25, 0.35)
    trunk_h = TREE_H * trunk_frac

    # ---- Trunk ----
    n_trunk = 8
    trunk_pts = []
    for i in range(n_trunk):
        t = i / (n_trunk - 1)
        z = t * trunk_h
        trunk_pts.append(Vector((
            lean_x * t * t + rng.uniform(-0.015, 0.015),
            lean_y * t * t + rng.uniform(-0.015, 0.015),
            z)))
    parts.append(make_tube(f"trunk_{vi}", trunk_pts,
                           trunk_r_base, trunk_r_top, TRUNK_SEGS, bark_mat))

    # ---- Root flare ----
    n_roots = rng.randint(3, 6)
    for r_idx in range(n_roots):
        angle = (r_idx / n_roots) * 2 * math.pi + rng.uniform(-0.3, 0.3)
        dx = math.cos(angle)
        dy = math.sin(angle)
        root_len = rng.uniform(0.18, 0.35)
        root_pts = [
            Vector((0, 0, 0.10)),
            Vector((dx * root_len * 0.5, dy * root_len * 0.5, 0.03)),
            Vector((dx * root_len, dy * root_len, 0.0)),
        ]
        parts.append(make_tube(f"root_{vi}_{r_idx}", root_pts,
                               trunk_r_base * 0.55, 0.02, SUB_SEGS, bark_mat))

    # ---- Main branches: arching upward and outward ----
    n_branches = rng.randint(4, 7)
    top_pt = trunk_pts[-1].copy()

    branch_tips = []  # store tips for drooping branch attachment

    for b in range(n_branches):
        br_angle = (b / n_branches) * 2.0 * math.pi + rng.uniform(-0.3, 0.3)
        dx = math.cos(br_angle)
        dy = math.sin(br_angle)

        br_len = rng.uniform(1.2, 2.0)
        br_rise = rng.uniform(0.8, 1.6)  # branches rise before arching over

        # Bezier curve: rise from trunk, arch outward
        p0 = top_pt.copy()
        p1 = Vector((
            top_pt.x + dx * br_len * 0.2,
            top_pt.y + dy * br_len * 0.2,
            top_pt.z + br_rise * 0.6))
        p2 = Vector((
            top_pt.x + dx * br_len * 0.6,
            top_pt.y + dy * br_len * 0.6,
            top_pt.z + br_rise * 0.95))
        p3 = Vector((
            top_pt.x + dx * br_len,
            top_pt.y + dy * br_len,
            top_pt.z + br_rise * 0.8))  # slight droop at tip

        br_pts = []
        n_br = 6
        for i in range(n_br):
            t = i / (n_br - 1)
            pt = bezier_point(p0, p1, p2, p3, t)
            pt.x += rng.uniform(-0.03, 0.03)
            pt.y += rng.uniform(-0.03, 0.03)
            br_pts.append(pt)

        br_r_start = rng.uniform(0.04, 0.07)
        parts.append(make_tube(f"branch_{vi}_{b}", br_pts,
                               br_r_start, br_r_start * 0.3, BRANCH_SEGS, bark_mat))

        # Store intermediate and end points for drooping branch attachment
        for frac in [0.4, 0.6, 0.8, 1.0]:
            idx = min(int(frac * (n_br - 1)), n_br - 1)
            attach_pt = br_pts[idx].copy()
            attach_r = br_r_start * (1.0 - frac * 0.7)
            branch_tips.append((attach_pt, attach_r, br_angle))

        # Sub-branches splitting off main branch
        n_sub = rng.randint(1, 3)
        for s in range(n_sub):
            sub_t = rng.uniform(0.3, 0.7)
            sub_idx = min(int(sub_t * (n_br - 1)), n_br - 1)
            sub_origin = br_pts[sub_idx].copy()
            sub_angle = br_angle + rng.uniform(-0.8, 0.8)
            sub_dx = math.cos(sub_angle)
            sub_dy = math.sin(sub_angle)
            sub_len = rng.uniform(0.4, 0.9)

            sub_pts = []
            for sp in range(4):
                st = sp / 3.0
                sub_pts.append(Vector((
                    sub_origin.x + sub_dx * sub_len * st,
                    sub_origin.y + sub_dy * sub_len * st,
                    sub_origin.z + sub_len * st * 0.3 * (1.0 - st))))
            sub_r = rng.uniform(0.015, 0.030)
            parts.append(make_tube(f"sub_{vi}_{b}_{s}", sub_pts,
                                   sub_r, sub_r * 0.3, SUB_SEGS, bark_mat))
            branch_tips.append((sub_pts[-1].copy(), sub_r * 0.3, sub_angle))

    # ---- Drooping curtain branches: the signature willow feature ----
    # Each attachment point gets 2-5 long, thin drooping branches
    for tip_idx, (attach_pt, attach_r, parent_angle) in enumerate(branch_tips):
        n_droop = rng.randint(2, 5)
        for d in range(n_droop):
            # Spread drooping branches in a fan from the attachment point
            droop_angle = parent_angle + rng.uniform(-1.2, 1.2)
            droop_dx = math.cos(droop_angle)
            droop_dy = math.sin(droop_angle)

            # Length of drooping branch — can be very long
            droop_len = rng.uniform(1.5, 3.5)
            # How far it reaches out horizontally
            horiz_reach = rng.uniform(0.2, 0.8)

            # Drooping branch curves: start slightly outward, then hang down
            droop_pts = []
            n_droop_pts = 6
            for i in range(n_droop_pts):
                t = i / (n_droop_pts - 1)
                # Starts going slightly outward and down, then hangs straight
                horiz = horiz_reach * t * (1.0 - t * 0.3)  # diminishing outward
                vert = -droop_len * t  # gravity pulls down
                # Add gentle sway/waviness
                wave = math.sin(t * math.pi * 2) * 0.06
                droop_pts.append(Vector((
                    attach_pt.x + droop_dx * horiz + wave * droop_dy,
                    attach_pt.y + droop_dy * horiz - wave * droop_dx,
                    attach_pt.z + vert)))

            droop_r = rng.uniform(0.004, 0.010)
            parts.append(make_tube(f"droop_{vi}_{tip_idx}_{d}", droop_pts,
                                   droop_r, droop_r * 0.2, SUB_SEGS, bark_mat))

            # Leaf clusters along the drooping branch
            n_leaf_pts = rng.randint(3, 5)
            for lp in range(n_leaf_pts):
                lt = (lp + 0.5) / n_leaf_pts
                leaf_idx = min(int(lt * (n_droop_pts - 1)), n_droop_pts - 1)
                leaf_center = droop_pts[leaf_idx].copy()
                leaf_center.x += rng.uniform(-0.08, 0.08)
                leaf_center.y += rng.uniform(-0.08, 0.08)
                leaf_r = rng.uniform(0.12, 0.22)
                n_quads = rng.randint(6, 12)
                parts.append(make_leaf_cluster(
                    f"leaf_{vi}_{tip_idx}_{d}_{lp}",
                    leaf_center, leaf_r, n_quads, rng, leaf_mat))

    # ---- Additional leaf mass at crown ----
    # Fill in the dome with leaf clusters where branches meet
    crown_center_z = top_pt.z + 1.2
    n_crown_clusters = rng.randint(10, 18)
    for cc in range(n_crown_clusters):
        cc_angle = rng.uniform(0, 2 * math.pi)
        cc_radius = rng.uniform(0.3, 1.5)
        cc_height = rng.uniform(-0.3, 1.0)
        cc_center = Vector((
            top_pt.x + math.cos(cc_angle) * cc_radius,
            top_pt.y + math.sin(cc_angle) * cc_radius,
            crown_center_z + cc_height))
        cc_r = rng.uniform(0.25, 0.45)
        cc_quads = rng.randint(12, 20)
        parts.append(make_leaf_cluster(
            f"crown_{vi}_{cc}", cc_center, cc_r, cc_quads, rng, leaf_mat))

    # ---- Finalize ----
    for obj in parts:
        for poly in obj.data.polygons:
            poly.use_smooth = True

    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    final = bpy.context.active_object
    final.name = f"Willow_{vi + 1}"
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
print("Building 5 weeping willow variants")
print("=" * 60 + "\n")

variants = []
for i in range(N_VARIANTS):
    v = make_willow_variant(i, seed=800 + i * 41)
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
print(f"\nExported {len(variants)} weeping willow variants to {OUT_PATH}")
