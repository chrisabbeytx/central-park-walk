"""Generate mile marker post for Central Park Walk.

Central Park loop drive has bronze mile markers embedded in the path
at quarter-mile intervals. Small bronze post ~30cm tall with distance plate.
"""

import bpy
import math
import os

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

bronze = bpy.data.materials.new("Bronze")
bronze.use_nodes = True
bsdf = bronze.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.28, 0.22, 0.12, 1.0)
bsdf.inputs["Roughness"].default_value = 0.50
bsdf.inputs["Metallic"].default_value = 0.80

concrete = bpy.data.materials.new("Concrete")
concrete.use_nodes = True
bsdf2 = concrete.node_tree.nodes["Principled BSDF"]
bsdf2.inputs["Base Color"].default_value = (0.60, 0.58, 0.55, 1.0)
bsdf2.inputs["Roughness"].default_value = 0.85


# ── Concrete base pad ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.15, depth=0.04, vertices=12,
    location=(0, 0.02, 0))
base = bpy.context.active_object
base.name = "base_pad"
base.data.materials.append(concrete)

# ── Bronze post ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.06, depth=0.30, vertices=10,
    location=(0, 0.19, 0))
post = bpy.context.active_object
post.name = "post"
post.data.materials.append(bronze)

# ── Cap (slightly wider) ──
bpy.ops.mesh.primitive_cylinder_add(
    radius=0.08, depth=0.03, vertices=10,
    location=(0, 0.355, 0))
cap = bpy.context.active_object
cap.name = "cap"
cap.data.materials.append(bronze)

# ── Distance plate (rectangular, angled) ──
bpy.ops.mesh.primitive_cube_add(
    size=1, location=(0, 0.25, 0.065))
plate = bpy.context.active_object
plate.name = "plate"
plate.scale = (0.08, 0.06, 0.005)
bpy.ops.object.transform_apply(scale=True)
plate.rotation_euler = (0.3, 0, 0)
bpy.ops.object.transform_apply(rotation=True)
plate.data.materials.append(bronze)

# ── Join and export ──
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.join()
bpy.context.active_object.name = "MileMarker"

# Fix orientation: scripts use Y-up, Blender is Z-up
bpy.context.active_object.rotation_euler = (math.pi/2, 0, 0)
bpy.ops.object.transform_apply(rotation=True)

outdir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                      "models", "furniture")
os.makedirs(outdir, exist_ok=True)
outpath = os.path.join(outdir, "cp_mile_marker.glb")
bpy.ops.export_scene.gltf(filepath=outpath, export_format='GLB')
print(f"Exported: {outpath} ({os.path.getsize(outpath)} bytes)")
