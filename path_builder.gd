# path_builder.gd
# Builds 3D path mesh strips from OSM polyline data.
# Each path is extruded as a flat ribbon following the terrain surface.
# The path.gdshader snaps vertices to terrain height and adds weather effects.
# Replaces the old vertex-color path blending in the terrain shader.

var _loader  # Reference to park_loader for shared utilities

func _init(loader) -> void:
	_loader = loader


func _build_paths(paths: Array) -> void:
	var t0 := Time.get_ticks_msec()

	# Separate bridges from ground-level paths, skip steps (built by infrastructure_builder)
	var ground_groups: Dictionary = {}  # "hw|surface" -> Array of paths
	var bridge_groups: Dictionary = {}  # "hw|surface" -> Array of paths
	var skipped_steps := 0
	var skipped_grass := 0

	for path in paths:
		var hw: String = str(path.get("highway", "path"))
		# Steps are built as staircases by infrastructure_builder
		if hw == "steps":
			skipped_steps += 1
			continue
		var surface: String = str(path.get("surface", ""))
		# Grass surface paths are just grass — no visible path needed
		if surface == "grass":
			skipped_grass += 1
			continue

		var is_bridge: bool = path.get("bridge", false)
		if not is_bridge:
			var layer = path.get("layer", 0)
			if layer is String:
				is_bridge = int(layer) >= 1
			elif layer is int:
				is_bridge = layer >= 1
			elif layer is float:
				is_bridge = int(layer) >= 1

		var key := hw + "|" + surface
		if is_bridge:
			if not bridge_groups.has(key):
				bridge_groups[key] = []
			bridge_groups[key].append(path)
		else:
			if not ground_groups.has(key):
				ground_groups[key] = []
			ground_groups[key].append(path)

	var total_paths := 0
	var total_verts := 0
	var total_groups := 0

	# Build ground-level path meshes
	for key in ground_groups:
		var parts: PackedStringArray = str(key).split("|")
		var hw: String = parts[0]
		var surface: String = parts[1]
		var group_paths: Array = ground_groups[key]

		var result := _build_group_mesh(group_paths)
		if result.verts.is_empty():
			continue

		var mat: Material = _loader._make_path_material(hw, surface)
		var amesh: ArrayMesh = _build_array_mesh(result.verts, result.normals, result.uvs, result.indices)
		var mi := MeshInstance3D.new()
		mi.mesh = amesh
		mi.material_override = mat
		mi.name = "Paths_%s_%s" % [hw, surface if not surface.is_empty() else "default"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_loader.add_child(mi)

		# Add walkable collision from path mesh
		if result.verts.size() > 0:
			var col_body := StaticBody3D.new()
			col_body.name = "PathCol_%s_%s" % [hw, surface if not surface.is_empty() else "default"]
			var col_shape := ConcavePolygonShape3D.new()
			col_shape.set_faces(amesh.get_faces())
			var col_node := CollisionShape3D.new()
			col_node.shape = col_shape
			col_body.add_child(col_node)
			_loader.add_child(col_body)

		total_paths += group_paths.size()
		total_verts += result.verts.size()
		total_groups += 1

	# Build bridge deck path meshes (no terrain snapping)
	for key in bridge_groups:
		var parts: PackedStringArray = str(key).split("|")
		var hw: String = parts[0]
		var surface: String = parts[1]
		var group_paths: Array = bridge_groups[key]

		var result := _build_group_mesh(group_paths)
		if result.verts.is_empty():
			continue

		var mat: Material = _loader._make_bridge_deck_material(hw, surface)
		var b_amesh: ArrayMesh = _build_array_mesh(result.verts, result.normals, result.uvs, result.indices)
		var mi := MeshInstance3D.new()
		mi.mesh = b_amesh
		mi.material_override = mat
		mi.name = "BridgePaths_%s_%s" % [hw, surface if not surface.is_empty() else "default"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_loader.add_child(mi)

		# Add walkable collision for bridge deck paths
		if result.verts.size() > 0:
			var col_body := StaticBody3D.new()
			col_body.name = "BridgePathCol_%s_%s" % [hw, surface if not surface.is_empty() else "default"]
			var col_shape := ConcavePolygonShape3D.new()
			col_shape.set_faces(b_amesh.get_faces())
			var col_node := CollisionShape3D.new()
			col_node.shape = col_shape
			col_body.add_child(col_node)
			_loader.add_child(col_body)

		total_paths += group_paths.size()
		total_verts += result.verts.size()
		total_groups += 1

	print("Paths: %d paths → %d verts (%d groups, %d steps skipped, %d grass skipped) in %d ms" % [
		total_paths, total_verts, total_groups, skipped_steps, skipped_grass,
		Time.get_ticks_msec() - t0])


func _build_group_mesh(group_paths: Array) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for path in group_paths:
		_extrude_path(path, verts, normals, uvs, indices)

	return {"verts": verts, "normals": normals, "uvs": uvs, "indices": indices}


func _build_array_mesh(verts: PackedVector3Array, normals: PackedVector3Array,
		mesh_uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = mesh_uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _extrude_path(path: Dictionary, verts: PackedVector3Array, normals: PackedVector3Array,
		mesh_uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var pts: Array = path.get("points", [])
	if pts.size() < 2:
		return

	# Subdivide long segments to ~2m for smoother terrain following
	pts = _subdivide_points(pts, 2.0)
	var n_pts := pts.size()
	if n_pts < 2:
		return

	var half_w: float = _loader._path_width(path) * 0.5
	# Clamp width to prevent absurdly wide strips
	half_w = minf(half_w, 8.0)

	# Compute miter normals for smooth joins at bends
	var miter: Array[Vector2] = _loader._compute_miter_normals(pts, n_pts)

	var base_idx := verts.size()
	var cum_dist := 0.0
	var up := Vector3.UP

	for i in n_pts:
		var px := float(pts[i][0])
		var py := float(pts[i][1])
		var pz := float(pts[i][2])

		# Miter offset in XZ plane
		var m: Vector2 = miter[i]
		var lx := px + m.x * half_w
		var lz := pz + m.y * half_w
		var rx := px - m.x * half_w
		var rz := pz - m.y * half_w

		# Y values: shader does terrain snapping, but provide reasonable heights
		# for correct bounding box (frustum culling). Use the path data Y.
		var left := Vector3(lx, py, lz)
		var right := Vector3(rx, py, rz)

		# Accumulate distance for texture V coordinate
		if i > 0:
			var prev_x := float(pts[i - 1][0])
			var prev_z := float(pts[i - 1][2])
			var dx := px - prev_x
			var dz := pz - prev_z
			cum_dist += sqrt(dx * dx + dz * dz)

		# UV: u = 0-1 across width, v = distance / width for square tiling
		var tile_v := cum_dist / (half_w * 2.0)
		verts.append(left)
		normals.append(up)
		mesh_uvs.append(Vector2(0.0, tile_v))
		verts.append(right)
		normals.append(up)
		mesh_uvs.append(Vector2(1.0, tile_v))

		# Quad between this row and previous row (2 triangles)
		if i > 0:
			var bl := base_idx + (i - 1) * 2      # bottom-left
			var br := base_idx + (i - 1) * 2 + 1  # bottom-right
			var tl := base_idx + i * 2             # top-left
			var tr := base_idx + i * 2 + 1         # top-right
			indices.append(bl)
			indices.append(tl)
			indices.append(br)
			indices.append(br)
			indices.append(tl)
			indices.append(tr)


func _subdivide_points(pts: Array, max_seg: float) -> Array:
	## Insert interpolated points so no segment exceeds max_seg metres.
	if pts.size() < 2:
		return pts
	var out: Array = [pts[0]]
	for i in range(1, pts.size()):
		var ax := float(pts[i - 1][0]); var ay := float(pts[i - 1][1]); var az := float(pts[i - 1][2])
		var bx := float(pts[i][0]); var by := float(pts[i][1]); var bz := float(pts[i][2])
		var dx := bx - ax; var dz := bz - az
		var d := sqrt(dx * dx + dz * dz)
		if d > max_seg:
			var steps := int(ceil(d / max_seg))
			for s in range(1, steps):
				var t := float(s) / float(steps)
				out.append([ax + dx * t, ay + (by - ay) * t, az + dz * t])
		out.append(pts[i])
	return out
