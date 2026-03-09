## Infrastructure builder — labels, barriers, staircases, statues,
## amenities, and field markings.  Extracted from park_loader.gd.

var _loader

const STEP_RISE  := 0.17
const STEP_DEPTH := 0.30
const HANDRAIL_H := 0.9


func _init(loader) -> void:
	_loader = loader




# ---------------------------------------------------------------------------
# POI name labels – billboard Label3D above each named water body
# ---------------------------------------------------------------------------
func _build_labels(water: Array) -> void:
	for body in water:
		var label_text: String = str(body.get("name", ""))
		if label_text.is_empty():
			continue
		var pts: Array = body["points"]
		if pts.is_empty():
			continue

		# Centroid and bounding-box diagonal for sizing
		var cx := 0.0
		var cz := 0.0
		# (boundary check after centroid computed below)
		var min_x :=  1e9; var max_x := -1e9
		var min_z :=  1e9; var max_z := -1e9
		for pt in pts:
			var px := float(pt[0]); var pz := float(pt[1])
			cx += px; cz += pz
			if px < min_x: min_x = px
			if px > max_x: max_x = px
			if pz < min_z: min_z = pz
			if pz > max_z: max_z = pz
		cx /= pts.size()
		cz /= pts.size()
		if not _loader._in_boundary(cx, cz):
			continue
		var diag := Vector2(max_x - min_x, max_z - min_z).length()

		# Taller label for larger features, clamped to a sensible range
		var height     := clampf(diag * 0.05, 8.0, 40.0)
		var pixel_size := clampf(diag * 0.00006, 0.03, 0.10)

		var lbl := Label3D.new()
		lbl.text              = label_text
		lbl.font_size         = 64
		lbl.pixel_size        = pixel_size
		lbl.billboard         = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.render_priority   = 1
		lbl.modulate          = Color(0.55, 0.55, 0.55, 0.55)
		lbl.outline_size      = 8
		lbl.outline_modulate  = Color(0.0, 0.08, 0.25, 0.55)
		var water_y: float = float(body.get("water_y", 0.0))
		lbl.position          = Vector3(cx, water_y + height, cz)
		_loader.add_child(lbl)


# ---------------------------------------------------------------------------
# Barriers – stone walls, iron fences, retaining walls, hedges
# ---------------------------------------------------------------------------
func _build_barriers(barriers: Array) -> void:
	if barriers.is_empty():
		return

	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")

	var wall_verts   := PackedVector3Array()
	var wall_normals := PackedVector3Array()
	var fence_verts  := PackedVector3Array()
	var fence_normals := PackedVector3Array()
	var col_verts    := PackedVector3Array()

	for barrier in barriers:
		var btype: String = str(barrier.get("type", "wall"))
		var height: float = float(barrier.get("height", 1.2))
		var raw_pts: Array = barrier.get("points", [])
		if raw_pts.size() < 2:
			continue
		# Skip barriers whose midpoint is outside the park
		var _bmx := (float(raw_pts[0][0]) + float(raw_pts[raw_pts.size()-1][0])) * 0.5
		var _bmz := (float(raw_pts[0][1]) + float(raw_pts[raw_pts.size()-1][1])) * 0.5
		if not _loader._in_boundary(_bmx, _bmz):
			continue
		var pts: Array = _loader._subdivide_pts(raw_pts, 3.0)

		match btype:
			"fence", "guard_rail":
				_build_fence_segments(pts, height, fence_verts, fence_normals, col_verts)
			_:
				_build_wall_segments(pts, height, wall_verts, wall_normals, col_verts)

	# Stone wall mesh
	if not wall_verts.is_empty():
		# Manhattan schist: gray stone with subtle warm weathering
		_loader._add_stone_mesh(wall_verts, wall_normals, rw_alb, rw_nrm, rw_rgh,
						Color(0.50, 0.48, 0.44), "StoneWalls")
	# Iron fence mesh
	if not fence_verts.is_empty():
		_loader._add_batch_mesh(fence_verts, fence_normals,
						Color(0.15, 0.15, 0.14), 0.45, "IronFences", true)
	# Combined collision
	if not col_verts.is_empty():
		var body := StaticBody3D.new()
		body.name = "Barrier_Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_verts)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_loader.add_child(body)

	print("ParkLoader: barriers = %d wall tris, %d fence tris" % [
		wall_verts.size() / 3, fence_verts.size() / 3])


func _build_wall_segments(pts: Array, height: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		col_verts: PackedVector3Array) -> void:
	var ht := 0.2  # half-thickness

	for i in range(pts.size() - 1):
		var p1x := float(pts[i][0]);   var p1z := float(pts[i][2])
		var p2x := float(pts[i+1][0]); var p2z := float(pts[i+1][2])
		var p1y: float = _loader._terrain_y(p1x, p1z) - 0.02  # sink base below terrain
		var p2y: float = _loader._terrain_y(p2x, p2z) - 0.02

		var seg2 := Vector2(p2x - p1x, p2z - p1z)
		if seg2.length_squared() < 0.01:
			continue
		var d := seg2.normalized()
		var n := Vector2(-d.y, d.x)

		# Front and back faces
		for side in [-1.0, 1.0]:
			var sf: float = side
			var ox: float = n.x * ht * sf
			var oz: float = n.y * ht * sf
			var a := Vector3(p1x + ox, p1y, p1z + oz)
			var b := Vector3(p2x + ox, p2y, p2z + oz)
			var c := Vector3(p2x + ox, p2y + height, p2z + oz)
			var dd := Vector3(p1x + ox, p1y + height, p1z + oz)
			var wall_n := Vector3(n.x * sf, 0.0, n.y * sf)
			var tri := PackedVector3Array([a, b, c, a, c, dd])
			verts.append_array(tri)
			col_verts.append_array(tri)
			for _j in range(6):
				normals.append(wall_n)

		# Top cap
		var tl1 := Vector3(p1x + n.x * ht, p1y + height, p1z + n.y * ht)
		var tr1 := Vector3(p1x - n.x * ht, p1y + height, p1z - n.y * ht)
		var tl2 := Vector3(p2x + n.x * ht, p2y + height, p2z + n.y * ht)
		var tr2 := Vector3(p2x - n.x * ht, p2y + height, p2z - n.y * ht)
		var cap := PackedVector3Array([tl1, tl2, tr1, tr1, tl2, tr2])
		verts.append_array(cap)
		col_verts.append_array(cap)
		for _j in range(6):
			normals.append(Vector3.UP)


func _build_fence_segments(pts: Array, height: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		col_verts: PackedVector3Array) -> void:
	var rail_h := 0.04
	var post_spacing := 2.0

	for i in range(pts.size() - 1):
		var p1x := float(pts[i][0]);   var p1z := float(pts[i][2])
		var p2x := float(pts[i+1][0]); var p2z := float(pts[i+1][2])
		var p1y: float = _loader._terrain_y(p1x, p1z)
		var p2y: float = _loader._terrain_y(p2x, p2z)
		var seg := Vector2(p2x - p1x, p2z - p1z)
		var seg_len := seg.length()
		if seg_len < 0.1:
			continue
		var d := seg / seg_len
		var n := Vector2(-d.y, d.x)

		# 3 horizontal rails
		for rail_frac in [0.15, 0.50, 0.95]:
			var rf: float = rail_frac
			var ry1: float = p1y + height * rf
			var ry2: float = p2y + height * rf
			var rh := rail_h * 0.5
			var a := Vector3(p1x, ry1 - rh, p1z)
			var b := Vector3(p2x, ry2 - rh, p2z)
			var c := Vector3(p2x, ry2 + rh, p2z)
			var dd := Vector3(p1x, ry1 + rh, p1z)
			var face_n := Vector3(n.x, 0.0, n.y)
			verts.append_array(PackedVector3Array([a, b, c, a, c, dd]))
			for _j in range(6):
				normals.append(face_n)

		# Vertical posts every ~2m
		var n_posts := int(ceil(seg_len / post_spacing)) + 1
		for pi in range(n_posts):
			var t: float = float(pi) / float(max(n_posts - 1, 1))
			var px: float = p1x + (p2x - p1x) * t
			var pz: float = p1z + (p2z - p1z) * t
			var py := lerpf(p1y, p2y, t)
			var ph := 0.04
			var post_a := Vector3(px + n.x * ph, py, pz + n.y * ph)
			var post_b := Vector3(px - n.x * ph, py, pz - n.y * ph)
			var post_c := Vector3(px - n.x * ph, py + height, pz - n.y * ph)
			var post_d := Vector3(px + n.x * ph, py + height, pz + n.y * ph)
			var tri := PackedVector3Array([post_a, post_b, post_c, post_a, post_c, post_d])
			verts.append_array(tri)
			col_verts.append_array(tri)
			for _j in range(6):
				normals.append(Vector3(d.x, 0.0, d.y))


# ---------------------------------------------------------------------------
# Staircases – 3D stepped treads + risers replacing flat ribbons
# ---------------------------------------------------------------------------
func _build_staircases(paths: Array) -> void:
	var stair_verts   := PackedVector3Array()
	var stair_normals := PackedVector3Array()
	var stair_uvs     := PackedVector2Array()
	var rail_verts    := PackedVector3Array()
	var rail_normals  := PackedVector3Array()
	var col_verts     := PackedVector3Array()

	for path in paths:
		var hw: String = str(path.get("highway", ""))
		if hw != "steps":
			continue
		if bool(path.get("bridge", false)) or bool(path.get("tunnel", false)):
			continue
		var raw_pts: Array = path.get("points", [])
		if raw_pts.size() < 2:
			continue
		# Skip staircases outside the park
		var _smx := (float(raw_pts[0][0]) + float(raw_pts[raw_pts.size()-1][0])) * 0.5
		var _smz := (float(raw_pts[0][2]) + float(raw_pts[raw_pts.size()-1][2])) * 0.5
		if not _loader._in_boundary(_smx, _smz):
			continue

		var width: float = _loader._hw_width("steps")
		var step_count: int = int(path.get("step_count", 0))
		var has_handrail: bool = path.has("handrail")

		var pts: Array = _loader._subdivide_pts(raw_pts, 2.0)
		var n_pts := pts.size()

		# Cumulative arc length
		var cum_len := PackedFloat32Array()
		cum_len.resize(n_pts)
		cum_len[0] = 0.0
		for i in range(1, n_pts):
			var dx := float(pts[i][0]) - float(pts[i-1][0])
			var dz := float(pts[i][2]) - float(pts[i-1][2])
			cum_len[i] = cum_len[i-1] + sqrt(dx * dx + dz * dz)
		var total_len := cum_len[n_pts - 1]
		if total_len < 0.1:
			continue

		# Elevation change
		var start_y: float = _loader._terrain_y(float(pts[0][0]), float(pts[0][2]))
		var end_y: float   = _loader._terrain_y(float(pts[n_pts-1][0]), float(pts[n_pts-1][2]))
		var delta_y := end_y - start_y

		if step_count <= 0:
			step_count = max(2, int(round(absf(delta_y) / STEP_RISE)))
		var rise := delta_y / float(step_count)
		var hw2 := width * 0.5

		# Build each step
		for si in range(step_count):
			var d_front := total_len * float(si) / float(step_count)
			var d_back  := total_len * float(si + 1) / float(step_count)
			var step_y  := start_y + rise * float(si)

			# Interpolate front position on polyline
			var fp := _interp_polyline(pts, cum_len, d_front)
			var fx: float = fp[0]; var fz: float = fp[1]
			# Interpolate back position
			var bp := _interp_polyline(pts, cum_len, d_back)
			var bx: float = bp[0]; var bz: float = bp[1]

			# Direction and perpendicular at midpoint
			var mid_d := (d_front + d_back) * 0.5
			var mp := _interp_polyline(pts, cum_len, mid_d)
			var seg_dir := Vector2(mp[2], mp[3]).normalized()
			var nv := Vector2(-seg_dir.y, seg_dir.x)

			# Tread corners (horizontal quad at step_y + rise)
			var tread_y := step_y + rise
			var fl := Vector3(fx + nv.x * hw2, tread_y, fz + nv.y * hw2)
			var fr := Vector3(fx - nv.x * hw2, tread_y, fz - nv.y * hw2)
			var bl := Vector3(bx + nv.x * hw2, tread_y, bx - nv.x * hw2)  # placeholder
			var br := Vector3(bx - nv.x * hw2, tread_y, bz - nv.y * hw2)
			# Fix bl properly
			bl = Vector3(bx + nv.x * hw2, tread_y, bz + nv.y * hw2)

			var tread := PackedVector3Array([fl, fr, br, fl, br, bl])
			stair_verts.append_array(tread)
			col_verts.append_array(tread)
			for _j in range(6):
				stair_normals.append(Vector3.UP)
			# UVs for tread
			var u_left := 0.0; var u_right := width
			var v_front := d_front; var v_back := d_back
			stair_uvs.append_array(PackedVector2Array([
				Vector2(u_left, v_front), Vector2(u_right, v_front),
				Vector2(u_right, v_back), Vector2(u_left, v_front),
				Vector2(u_right, v_back), Vector2(u_left, v_back)]))

			# Riser (vertical face at front of this step)
			if absf(rise) > 0.01:
				var riser_bot := step_y
				var riser_top := step_y + rise if rise > 0 else step_y
				var riser_low := step_y + rise if rise < 0 else step_y
				var rl := Vector3(fx + nv.x * hw2, riser_low, fz + nv.y * hw2)
				var rr := Vector3(fx - nv.x * hw2, riser_low, fz - nv.y * hw2)
				var rtl := Vector3(fx + nv.x * hw2, riser_low + absf(rise), fz + nv.y * hw2)
				var rtr := Vector3(fx - nv.x * hw2, riser_low + absf(rise), fz - nv.y * hw2)
				var riser_n := Vector3(-seg_dir.x, 0.0, -seg_dir.y)
				var riser := PackedVector3Array([rl, rr, rtr, rl, rtr, rtl])
				stair_verts.append_array(riser)
				col_verts.append_array(riser)
				for _j in range(6):
					stair_normals.append(riser_n)
				stair_uvs.append_array(PackedVector2Array([
					Vector2(0.0, 0.0), Vector2(width, 0.0),
					Vector2(width, absf(rise)), Vector2(0.0, 0.0),
					Vector2(width, absf(rise)), Vector2(0.0, absf(rise))]))

		# Handrails along both edges
		if has_handrail:
			for side_sign in [-1.0, 1.0]:
				var ss: float = side_sign
				var prev_x := 0.0; var prev_z := 0.0; var prev_y := 0.0
				for si in range(step_count + 1):
					var d_pos := total_len * float(si) / float(step_count)
					var hp := _interp_polyline(pts, cum_len, d_pos)
					var hx: float = hp[0]; var hz: float = hp[1]
					var hdir := Vector2(hp[2], hp[3]).normalized()
					var hnv := Vector2(-hdir.y, hdir.x)
					var hy := start_y + rise * float(si) + HANDRAIL_H
					var rx: float = hx + hnv.x * hw2 * ss
					var rz: float = hz + hnv.y * hw2 * ss

					if si > 0:
						# Rail segment: thin quad from prev to current
						var a := Vector3(prev_x, prev_y - 0.02, prev_z)
						var b := Vector3(rx, hy - 0.02, rz)
						var c := Vector3(rx, hy + 0.02, rz)
						var dd := Vector3(prev_x, prev_y + 0.02, prev_z)
						var rn := Vector3(hnv.x * ss, 0.0, hnv.y * ss)
						rail_verts.append_array(PackedVector3Array([a, b, c, a, c, dd]))
						for _j in range(6):
							rail_normals.append(rn)

						# Vertical post at this position
						var post_off: float = 0.02 * ss
						var pa := Vector3(rx + hnv.x * post_off, start_y + rise * float(si), rz + hnv.y * post_off)
						var pb := Vector3(rx - hnv.x * post_off, start_y + rise * float(si), rz - hnv.y * post_off)
						var pc := Vector3(rx - hnv.x * post_off, hy, rz - hnv.y * post_off)
						var pd := Vector3(rx + hnv.x * post_off, hy, rz + hnv.y * post_off)
						rail_verts.append_array(PackedVector3Array([pa, pb, pc, pa, pc, pd]))
						for _j in range(6):
							rail_normals.append(Vector3(hdir.x, 0.0, hdir.y))

					prev_x = rx; prev_z = rz; prev_y = hy

	# Stair mesh
	if not stair_verts.is_empty():
		var mesh: ArrayMesh = _loader._make_mesh(stair_verts, stair_normals, stair_uvs)
		mesh.surface_set_material(0, _loader._make_path_material("steps", "concrete"))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "Staircases"
		_loader.add_child(mi)

	# Handrail mesh
	if not rail_verts.is_empty():
		_loader._add_batch_mesh(rail_verts, rail_normals,
						Color(0.18, 0.18, 0.17), 0.40, "Handrails", true)

	# Stair collision
	if not col_verts.is_empty():
		var body := StaticBody3D.new()
		body.name = "Staircase_Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_verts)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_loader.add_child(body)

	print("ParkLoader: staircases = %d steps" % [col_verts.size() / 18])


## Interpolate a position + direction along a polyline at distance d_along.
## Returns via the reference parameters: out_x, out_z, out_dx, out_dz.
func _interp_polyline(pts: Array, cum_len: PackedFloat32Array, d_along: float) -> Array:
	var n := pts.size()
	# Clamp to valid range
	if d_along <= 0.0:
		var dx := float(pts[1][0]) - float(pts[0][0])
		var dz := float(pts[1][2]) - float(pts[0][2])
		return [float(pts[0][0]), float(pts[0][2]), dx, dz]
	if d_along >= cum_len[n - 1]:
		var dx := float(pts[n-1][0]) - float(pts[n-2][0])
		var dz := float(pts[n-1][2]) - float(pts[n-2][2])
		return [float(pts[n-1][0]), float(pts[n-1][2]), dx, dz]
	# Find segment
	for i in range(1, n):
		if cum_len[i] >= d_along:
			var seg_start: float = cum_len[i - 1]
			var seg_len: float = cum_len[i] - seg_start
			var t: float = (d_along - seg_start) / max(seg_len, 0.001)
			var x1 := float(pts[i-1][0]); var z1 := float(pts[i-1][2])
			var x2 := float(pts[i][0]);   var z2 := float(pts[i][2])
			return [lerpf(x1, x2, t), lerpf(z1, z2, t), x2 - x1, z2 - z1]
	return [float(pts[0][0]), float(pts[0][2]), 1.0, 0.0]


# ---------------------------------------------------------------------------
# Statues, monuments, memorials
# ---------------------------------------------------------------------------
func _build_statues(statues: Array) -> void:
	if statues.is_empty():
		return

	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var stone_mat: ShaderMaterial = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh, Color(0.56, 0.56, 0.54))  # gray granite pedestal

	var bronze_mat := StandardMaterial3D.new()
	bronze_mat.albedo_color = Color(0.29, 0.42, 0.29)  # aged green-brown patina per Wikimedia
	bronze_mat.roughness    = 0.65
	bronze_mat.metallic     = 0.55

	# Load GLB statue models (3 variants for variety)
	var statue_glb_meshes: Array[Mesh] = []
	var statue_glb_heights: Array[float] = []
	for glb_name in ["statue1", "statue2", "statue3"]:
		var abs_path := ProjectSettings.globalize_path("res://models/furniture/%s.glb" % glb_name)
		if not FileAccess.file_exists(abs_path):
			continue
		var meshes: Array = []
		var gd := GLTFDocument.new()
		var gs := GLTFState.new()
		if gd.append_from_file(abs_path, gs) == OK:
			var root: Node = gd.generate_scene(gs)
			if root:
				_loader._collect_meshes(root, meshes)
				# Detect node scale (these models have scale=0.33)
				var node_scale := 1.0
				for child in root.get_children():
					if child is Node3D:
						var s: Vector3 = (child as Node3D).scale
						if absf(s.x - 1.0) > 0.01:
							node_scale = s.x
							break
				if not meshes.is_empty():
					var m: Mesh = meshes[0]
					var ab: AABB = m.get_aabb()
					var raw_h := maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
					statue_glb_meshes.append(m)
					statue_glb_heights.append(raw_h * node_scale)
				root.queue_free()
	var use_glb := not statue_glb_meshes.is_empty()
	if use_glb:
		print("Statues: loaded %d GLB variants" % statue_glb_meshes.size())

	# Named statue GLBs (photogrammetry scans with own textures)
	# Each entry: { "file": glb filename, "height": desired real-world height in metres }
	var named_statue_glbs: Dictionary = {}  # key -> { "root": Node, "scale": float }
	var named_defs: Dictionary = {
		"alice in wonderland": { "file": "alice_in_wonderland.glb", "height": 3.35 },
		"hans christian andersen": { "file": "hans_christian_andersen.glb", "height": 3.4 },
		"eagles and prey": { "file": "eagles_and_prey.glb", "height": 3.8 },
	}
	for skey in named_defs:
		var def: Dictionary = named_defs[skey]
		var abs_path := ProjectSettings.globalize_path("res://models/furniture/%s" % def["file"])
		if not FileAccess.file_exists(abs_path):
			continue
		var gd := GLTFDocument.new()
		var gs := GLTFState.new()
		if gd.append_from_file(abs_path, gs) == OK:
			var root: Node = gd.generate_scene(gs)
			if root:
				named_statue_glbs[skey] = { "root": root, "height": def["height"] }
				print("Statues: loaded named GLB '%s'" % skey)
			else:
				print("Statues: failed to generate scene for '%s'" % skey)
	print("Statues: %d named GLBs loaded" % named_statue_glbs.size())

	var statue_col_shapes: Array = []

	for statue in statues:
		var stype: String = str(statue.get("type", "statue"))
		var sname: String = str(statue.get("name", ""))
		var pos: Array = statue.get("position", [0, 0, 0])
		var sx := float(pos[0]); var sz := float(pos[2])
		var sy: float = _loader._terrain_y(sx, sz)
		# Skip out-of-boundary unless it's a named photogrammetry statue
		if not _loader._in_boundary(sx, sz) and not sname.to_lower() in named_statue_glbs:
			continue

		# Skip murals/graffiti/street_art — 2D art, no 3D geometry
		if stype in ["mural", "graffiti", "street_art"]:
			continue

		var safe_name: String = sname if sname else stype.capitalize()

		# Check for named photogrammetry model (these include their own base)
		var sname_lower := sname.to_lower()
		var used_named := false
		if sname_lower in named_statue_glbs:
			var entry: Dictionary = named_statue_glbs[sname_lower]
			var scene_root: Node = (entry["root"] as Node).duplicate()
			scene_root.name = "NamedStatue_%s" % safe_name
			if scene_root is Node3D:
				(scene_root as Node3D).position = Vector3(sx, sy, sz)
			_loader.add_child(scene_root)
			# Measure actual world-space Y bounds now that it's in tree
			var y_min := 1e9
			var y_max := -1e9
			var mi_stack: Array = [scene_root]
			while not mi_stack.is_empty():
				var n: Node = mi_stack.pop_back()
				if n is MeshInstance3D:
					var mi := n as MeshInstance3D
					if mi.mesh:
						var ab: AABB = mi.mesh.get_aabb()
						var gt: Transform3D = mi.global_transform
						for ix in [0, 1]:
							for iy in [0, 1]:
								for iz in [0, 1]:
									var pt := gt * (ab.position + ab.size * Vector3(float(ix), float(iy), float(iz)))
									if pt.y < y_min:
										y_min = pt.y
									if pt.y > y_max:
										y_max = pt.y
				for c in n.get_children():
					mi_stack.append(c)
			var actual_h := y_max - y_min
			var desired_h: float = entry["height"]
			# Scale to desired height and reposition so base sits on terrain
			var s := desired_h / maxf(actual_h, 0.01)
			if scene_root is Node3D:
				var n3d := scene_root as Node3D
				n3d.scale = Vector3(s, s, s)
				# After scaling, the bottom moves: new_y_min = sy + s*(y_min - sy)
				# We want new_y_min = sy, so shift up by (1-s)*(y_min - sy)...
				# Simpler: new bottom = root_y + s*(old_y_min - root_y)
				# old_y_min - root_y = y_min - sy, so new bottom = sy + s*(y_min - sy)
				# Want new bottom = sy → shift = sy - (sy + s*(y_min - sy)) = -s*(y_min - sy)
				n3d.position.y = sy - s * (y_min - sy)
			used_named = true
			print("Named statue '%s' at (%.0f, %.1f, %.0f) actual_h=%.2f scale=%.2f y_range=[%.2f,%.2f]" % [sname, sx, sy, sz, actual_h, s, y_min, y_max])
			# Collision
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.5
			cyl.height = desired_h
			var col := CollisionShape3D.new()
			col.shape = cyl
			col.position = Vector3(sx, sy + desired_h * 0.5, sz)
			statue_col_shapes.append(col)
			# Label
			var lbl := Label3D.new()
			lbl.text = sname
			lbl.font_size = 48
			lbl.pixel_size = 0.02
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED

			lbl.modulate = Color(0.75, 0.72, 0.68, 0.65)
			lbl.outline_size = 6
			lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.50)
			lbl.position = Vector3(sx, sy + desired_h + 0.5, sz)
			_loader.add_child(lbl)
		if used_named:
			continue

		# Strawberry Fields Imagine Mosaic — flat circular disc, not a statue
		if sname_lower.contains("strawberry"):
			_loader._water_builder._build_imagine_mosaic(sx, sy, sz)
			continue

		# Generic statue placement
		var ped_h := 1.2
		var ped_r := 0.6
		var fig_h := 1.6

		if stype == "obelisk" or sname_lower.contains("needle") or sname_lower.contains("obelisk"):
			stype = "obelisk"
			ped_h = 1.5
			ped_r = 1.2
			fig_h = 21.0  # Cleopatra's Needle = 69ft (21m)
		elif stype == "monument":
			ped_h = 1.8
			ped_r = 0.9
			fig_h = 2.5

		# Pedestal (cylinder)
		_loader._water_builder._make_cylinder_mesh(sx, sy, sz, ped_r, ped_h, stone_mat,
							"Pedestal_%s" % sname if sname else "Pedestal")

		var fig_y := sy + ped_h

		if stype == "obelisk":
			# Tall tapered column — simplified geometric form
			# Cleopatra's Needle: Aswan red granite — warm pinkish-red
			var obelisk_mat: ShaderMaterial = stone_mat
			if sname_lower.contains("needle") or sname_lower.contains("cleopatra"):
				obelisk_mat = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh, Color(0.62, 0.42, 0.38))
			_loader._water_builder._make_cylinder_mesh(sx, fig_y, sz, 0.8, fig_h, obelisk_mat,
								"Obelisk_%s" % safe_name, 4)
		elif use_glb and stype != "bust":
			# Use GLB statue model
			var vi := hash(sname) % statue_glb_meshes.size()
			if vi < 0:
				vi = -vi % statue_glb_meshes.size()
			var mesh: Mesh = statue_glb_meshes[vi]
			var glb_h: float = statue_glb_heights[vi]
			# Scale to desired figure height
			var desired_h := fig_h
			var s := desired_h / maxf(glb_h, 0.01)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = bronze_mat
			# GLB models are Y-up, so just scale + position
			mi.transform = Transform3D(
				Basis().scaled(Vector3(s, s, s)),
				Vector3(sx, fig_y, sz))
			mi.name = "Statue_%s" % safe_name
			_loader.add_child(mi)
		elif stype == "bust":
			# Small bust — keep simple cylinder approximation
			_loader._water_builder._make_cylinder_mesh(sx, fig_y, sz, 0.14, 0.30, bronze_mat,
								"BustTorso_%s" % safe_name, 10)
			_loader._water_builder._make_cylinder_mesh(sx, fig_y + 0.30, sz, 0.10, 0.20, bronze_mat,
								"BustHead_%s" % safe_name, 8)

		# Label
		var lbl := Label3D.new()
		lbl.text = sname if sname else stype.capitalize()
		lbl.font_size = 48
		lbl.pixel_size = 0.02
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED

		lbl.modulate = Color(0.75, 0.72, 0.68, 0.65)
		lbl.outline_size = 6
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.50)
		lbl.position = Vector3(sx, sy + ped_h + fig_h + 0.5, sz)
		_loader.add_child(lbl)

		# Collect collision data for batching
		var cyl := CylinderShape3D.new()
		cyl.radius = ped_r
		cyl.height = ped_h + fig_h
		var col := CollisionShape3D.new()
		col.shape = cyl
		col.position = Vector3(sx, sy + (ped_h + fig_h) * 0.5, sz)
		statue_col_shapes.append(col)

	# Single StaticBody3D for all statue collision shapes
	if not statue_col_shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "StatueCollision"
		for shape in statue_col_shapes:
			body.add_child(shape)
		_loader.add_child(body)

	print("ParkLoader: statues/monuments = %d" % [statues.size()])


# ---------------------------------------------------------------------------
# Amenities — drinking water, toilets, theatres (inside park only)
# ---------------------------------------------------------------------------
func _build_amenities(amenities: Array) -> void:
	if amenities.is_empty():
		return

	# Load drinking fountain GLB
	var df_path := ProjectSettings.globalize_path("res://models/furniture/cp_drinking_fountain.glb")
	var df_meshes: Dictionary = _loader._load_glb_meshes(df_path)
	var df_mesh: Mesh = null
	if df_meshes.has("CP_DrinkingFountain"):
		df_mesh = df_meshes["CP_DrinkingFountain"] as Mesh
	var df_xforms: Array = []

	var count := 0
	for am in amenities:
		var pos: Array = am.get("position", [])
		if pos.size() < 3:
			continue
		var x: float = pos[0]
		var y: float = pos[1]
		var z: float = pos[2]
		if not _loader._in_boundary(x, z):
			continue

		var am_type: String = am.get("type", "")
		var am_name: String = am.get("name", "")

		# Skip restaurants/cafes — they're mostly outside the park
		if am_type == "restaurant" or am_type == "cafe":
			if am_name.is_empty():
				continue

		var ty: float = _loader._terrain_y(x, z)
		y = maxf(y, ty)

		# Named amenities get Label3D
		if not am_name.is_empty():
			var label := Label3D.new()
			label.text = am_name
			label.font_size = 28
			label.position = Vector3(x, y + 2.5, z)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

			label.modulate = Color(0.70, 0.68, 0.60, 0.60)
			label.outline_modulate = Color(0.1, 0.1, 0.1, 0.45)
			label.outline_size = 4
			label.no_depth_test = false
			label.pixel_size = 0.01
			_loader.add_child(label)

		# Drinking water: granite pedestal fountain
		if am_type == "drinking_water":
			if df_mesh:
				df_xforms.append(Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
			else:
				var post: ArrayMesh = _loader._make_cylinder(0.06, 0.8, 8)
				var mi := MeshInstance3D.new()
				mi.mesh = post
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.3, 0.5, 0.8)
				mat.roughness = 0.6
				mi.material_override = mat
				mi.position = Vector3(x, y + 0.4, z)
				_loader.add_child(mi)

		# Toilets: small brown marker
		elif am_type == "toilets":
			var post: ArrayMesh = _loader._make_cylinder(0.1, 1.0, 8)
			var mi := MeshInstance3D.new()
			mi.mesh = post
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.45, 0.35, 0.25)
			mat.roughness = 0.7
			mi.material_override = mat
			mi.position = Vector3(x, y + 0.5, z)
			_loader.add_child(mi)

		count += 1

	# Spawn drinking fountains via MultiMesh
	if not df_xforms.is_empty() and df_mesh:
		_loader._spawn_multimesh(df_mesh, null, df_xforms, "DrinkingFountains")
		print("  Drinking fountains: %d (CP model)" % df_xforms.size())
	print("  Amenities: %d placed (inside park)" % count)


# ---------------------------------------------------------------------------
# Baseball / softball field markings — dirt infield + foul lines + base paths
# ---------------------------------------------------------------------------
func _build_field_markings() -> void:
	## Draws dirt infield and white line markings for named baseball/softball fields.
	var fields: Array = []
	for zone in _loader.landuse_zones:
		var name: String = zone.get("name", "")
		if name.is_empty():
			continue
		var nl := name.to_lower()
		if not ("ballfield" in nl or "ball field" in nl or "baseball" in nl or "softball" in nl):
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 6:
			continue
		# Skip aggregate zones (e.g. "Heckscher Ballfields" enclosing polygon)
		if pts.size() > 60:
			continue
		fields.append(zone)

	if fields.is_empty():
		return

	# Materials
	var dirt_mat := StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.55, 0.42, 0.30)  # baseball infield dirt
	dirt_mat.roughness = 0.95
	dirt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.95, 0.95, 0.90)  # white chalk lines
	line_mat.roughness = 0.85
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var count := 0
	for zone in fields:
		var name: String = zone["name"]
		var pts: Array = zone["points"]
		var is_softball := "softball" in name.to_lower()
		var base_dist: float = 18.3 if is_softball else 27.4  # 60ft / 90ft

		# Remove duplicate closing point
		if pts.size() > 3:
			var dx := float(pts[0][0]) - float(pts[-1][0])
			var dz := float(pts[0][1]) - float(pts[-1][1])
			if dx * dx + dz * dz < 4.0:
				pts = pts.slice(0, -1)
		var n := pts.size()
		if n < 4:
			continue

		# Find home plate: vertex with sharpest interior angle (closest to 90°)
		var best_i := 0
		var best_diff := 999.0
		for i in range(n):
			var p0x := float(pts[(i - 1 + n) % n][0])
			var p0z := float(pts[(i - 1 + n) % n][1])
			var p1x := float(pts[i][0])
			var p1z := float(pts[i][1])
			var p2x := float(pts[(i + 1) % n][0])
			var p2z := float(pts[(i + 1) % n][1])
			var v1x := p0x - p1x; var v1z := p0z - p1z
			var v2x := p2x - p1x; var v2z := p2z - p1z
			var m1 := sqrt(v1x * v1x + v1z * v1z)
			var m2 := sqrt(v2x * v2x + v2z * v2z)
			if m1 < 0.1 or m2 < 0.1:
				continue
			var dot := (v1x * v2x + v1z * v2z) / (m1 * m2)
			dot = clampf(dot, -1.0, 1.0)
			var angle := acos(dot)
			var diff := absf(angle - PI * 0.5)  # how close to 90°
			if diff < best_diff:
				best_diff = diff
				best_i = i

		var hp_x := float(pts[best_i][0])
		var hp_z := float(pts[best_i][1])
		var hp_y: float = _loader._terrain_y(hp_x, hp_z) + 0.02

		# Foul line directions: the two edges from home plate
		var prev_i := (best_i - 1 + n) % n
		var next_i := (best_i + 1) % n
		var fl1_dx := float(pts[prev_i][0]) - hp_x
		var fl1_dz := float(pts[prev_i][1]) - hp_z
		var fl2_dx := float(pts[next_i][0]) - hp_x
		var fl2_dz := float(pts[next_i][1]) - hp_z
		var fl1_len := sqrt(fl1_dx * fl1_dx + fl1_dz * fl1_dz)
		var fl2_len := sqrt(fl2_dx * fl2_dx + fl2_dz * fl2_dz)
		if fl1_len < 1.0 or fl2_len < 1.0:
			continue
		fl1_dx /= fl1_len; fl1_dz /= fl1_len
		fl2_dx /= fl2_len; fl2_dz /= fl2_len

		# Bisector direction = toward second base (center field)
		var bis_x := fl1_dx + fl2_dx
		var bis_z := fl1_dz + fl2_dz
		var bis_len := sqrt(bis_x * bis_x + bis_z * bis_z)
		if bis_len < 0.01:
			continue
		bis_x /= bis_len; bis_z /= bis_len

		# Base positions
		var first_x := hp_x + fl2_dx * base_dist
		var first_z := hp_z + fl2_dz * base_dist
		var third_x := hp_x + fl1_dx * base_dist
		var third_z := hp_z + fl1_dz * base_dist
		var second_x := hp_x + bis_x * base_dist * 1.414
		var second_z := hp_z + bis_z * base_dist * 1.414

		# --- Dirt infield: fan-shaped area ---
		var dirt_verts := PackedVector3Array()
		var dirt_norms := PackedVector3Array()
		var infield_r: float = base_dist * 1.1  # slightly beyond bases
		var arc_segs := 24
		# Fan from home plate covering the 90° arc between foul lines
		for ai in range(arc_segs):
			var t0 := float(ai) / float(arc_segs)
			var t1 := float(ai + 1) / float(arc_segs)
			# Interpolate direction between foul lines
			var d0x := fl1_dx * (1.0 - t0) + fl2_dx * t0
			var d0z := fl1_dz * (1.0 - t0) + fl2_dz * t0
			var d1x := fl1_dx * (1.0 - t1) + fl2_dx * t1
			var d1z := fl1_dz * (1.0 - t1) + fl2_dz * t1
			var l0 := sqrt(d0x * d0x + d0z * d0z)
			var l1 := sqrt(d1x * d1x + d1z * d1z)
			if l0 > 0.01: d0x /= l0; d0z /= l0
			if l1 > 0.01: d1x /= l1; d1z /= l1
			var ex0 := hp_x + d0x * infield_r
			var ez0 := hp_z + d0z * infield_r
			var ex1 := hp_x + d1x * infield_r
			var ez1 := hp_z + d1z * infield_r
			var ey0: float = _loader._terrain_y(ex0, ez0) + 0.02
			var ey1: float = _loader._terrain_y(ex1, ez1) + 0.02
			dirt_verts.append(Vector3(hp_x, hp_y, hp_z))
			dirt_verts.append(Vector3(ex0, ey0, ez0))
			dirt_verts.append(Vector3(ex1, ey1, ez1))
			for _j in 3:
				dirt_norms.append(Vector3.UP)

		if not dirt_verts.is_empty():
			var dm: ArrayMesh = _loader._make_mesh(dirt_verts, dirt_norms)
			dm.surface_set_material(0, dirt_mat)
			var dmi := MeshInstance3D.new()
			dmi.mesh = dm
			dmi.name = "Field_Dirt_" + name.replace(" ", "_")
			_loader.add_child(dmi)

		# --- Foul lines: thin white strips from home plate outward ---
		var line_w := 0.08  # ~3 inches wide
		var line_verts := PackedVector3Array()
		var line_norms := PackedVector3Array()
		var foul_len: float = base_dist * 1.6  # extend past bases
		var _foul_dirs: Array[Vector2] = [Vector2(fl1_dx, fl1_dz), Vector2(fl2_dx, fl2_dz)]
		for fl_dir in _foul_dirs:
			var perp := Vector2(-fl_dir.y, fl_dir.x) * line_w * 0.5
			var end_x: float = hp_x + fl_dir.x * foul_len
			var end_z: float = hp_z + fl_dir.y * foul_len
			var end_y: float = _loader._terrain_y(end_x, end_z) + 0.03
			var a := Vector3(hp_x + perp.x, hp_y + 0.01, hp_z + perp.y)
			var b := Vector3(hp_x - perp.x, hp_y + 0.01, hp_z - perp.y)
			var c := Vector3(end_x + perp.x, end_y, end_z + perp.y)
			var d := Vector3(end_x - perp.x, end_y, end_z - perp.y)
			line_verts.append_array(PackedVector3Array([a, b, c, b, d, c]))
			for _j in 6:
				line_norms.append(Vector3.UP)

		# --- Base paths: diamond connecting HP → 1B → 2B → 3B → HP ---
		var bases: Array[Vector3] = [
			Vector3(hp_x, hp_y + 0.01, hp_z),
			Vector3(first_x, _loader._terrain_y(first_x, first_z) + 0.03, first_z),
			Vector3(second_x, _loader._terrain_y(second_x, second_z) + 0.03, second_z),
			Vector3(third_x, _loader._terrain_y(third_x, third_z) + 0.03, third_z),
		]
		for bi in range(4):
			var ba: Vector3 = bases[bi]
			var bb: Vector3 = bases[(bi + 1) % 4]
			var seg := Vector2(bb.x - ba.x, bb.z - ba.z).normalized()
			var perp := Vector2(-seg.y, seg.x) * line_w * 0.5
			var la := Vector3(ba.x + perp.x, ba.y, ba.z + perp.y)
			var lb := Vector3(ba.x - perp.x, ba.y, ba.z - perp.y)
			var lc := Vector3(bb.x + perp.x, bb.y, bb.z + perp.y)
			var ld := Vector3(bb.x - perp.x, bb.y, bb.z - perp.y)
			line_verts.append_array(PackedVector3Array([la, lb, lc, lb, ld, lc]))
			for _j in 6:
				line_norms.append(Vector3.UP)

		# --- Base markers: small white squares at each base position ---
		var base_sz := 0.38  # 15 inches
		for bi in range(4):
			var bx: float = bases[bi].x; var by: float = bases[bi].y + 0.01; var bz: float = bases[bi].z
			var h := base_sz * 0.5
			line_verts.append_array(PackedVector3Array([
				Vector3(bx - h, by, bz - h), Vector3(bx + h, by, bz - h),
				Vector3(bx + h, by, bz + h), Vector3(bx - h, by, bz - h),
				Vector3(bx + h, by, bz + h), Vector3(bx - h, by, bz + h),
			]))
			for _j in 6:
				line_norms.append(Vector3.UP)

		if not line_verts.is_empty():
			var lm: ArrayMesh = _loader._make_mesh(line_verts, line_norms)
			lm.surface_set_material(0, line_mat)
			var lmi := MeshInstance3D.new()
			lmi.mesh = lm
			lmi.name = "Field_Lines_" + name.replace(" ", "_")
			_loader.add_child(lmi)

		count += 1

	print("ParkLoader: baseball field markings = ", count)

	# --- Soccer field markings ---
	var soccer_count := 0
	for zone in _loader.landuse_zones:
		var name2: String = zone.get("name", "")
		if name2.is_empty():
			continue
		var nl2 := name2.to_lower()
		if "soccer" not in nl2:
			continue
		var spts: Array = zone.get("points", [])
		if spts.size() < 4:
			continue
		# 4-corner polygon — compute center and axes
		var cx := 0.0; var cz := 0.0
		for sp in spts:
			cx += float(sp[0]); cz += float(sp[1])
		cx /= spts.size(); cz /= spts.size()
		# Long axis: direction from midpoint of one side to opposite
		var ax := float(spts[1][0]) - float(spts[0][0])
		var az := float(spts[1][1]) - float(spts[0][1])
		var bx := float(spts[2][0]) - float(spts[1][0])
		var bz := float(spts[2][1]) - float(spts[1][1])
		var a_len := sqrt(ax * ax + az * az)
		var b_len := sqrt(bx * bx + bz * bz)
		# Long axis is the longer side
		var long_dx: float; var long_dz: float; var field_l: float; var field_w: float
		var short_dx: float; var short_dz: float
		if a_len >= b_len:
			long_dx = ax / a_len; long_dz = az / a_len
			short_dx = bx / b_len; short_dz = bz / b_len
			field_l = a_len; field_w = b_len
		else:
			long_dx = bx / b_len; long_dz = bz / b_len
			short_dx = ax / a_len; short_dz = az / a_len
			field_l = b_len; field_w = a_len
		var cy: float = _loader._terrain_y(cx, cz) + 0.025
		var lw := 0.10  # line width
		var half_l := field_l * 0.5
		var half_w := field_w * 0.5
		var s_verts := PackedVector3Array()
		var s_norms := PackedVector3Array()
		# Helper: draw a line strip in world space
		var _draw_line := func(x0: float, z0: float, x1: float, z1: float) -> void:
			var dx2 := x1 - x0; var dz2 := z1 - z0
			var ln := sqrt(dx2 * dx2 + dz2 * dz2)
			if ln < 0.01: return
			var px := -dz2 / ln * lw * 0.5; var pz := dx2 / ln * lw * 0.5
			var y0: float = _loader._terrain_y(x0, z0) + 0.025
			var y1: float = _loader._terrain_y(x1, z1) + 0.025
			s_verts.append(Vector3(x0 + px, y0, z0 + pz))
			s_verts.append(Vector3(x0 - px, y0, z0 - pz))
			s_verts.append(Vector3(x1 + px, y1, z1 + pz))
			s_verts.append(Vector3(x0 - px, y0, z0 - pz))
			s_verts.append(Vector3(x1 - px, y1, z1 - pz))
			s_verts.append(Vector3(x1 + px, y1, z1 + pz))
			for _j2 in 6: s_norms.append(Vector3.UP)
		# Touchlines (long sides)
		for side in [-1.0, 1.0]:
			var sf: float = side
			var sx: float = cx + short_dx * half_w * sf - long_dx * half_l
			var sz: float = cz + short_dz * half_w * sf - long_dz * half_l
			var ex: float = cx + short_dx * half_w * sf + long_dx * half_l
			var ez: float = cz + short_dz * half_w * sf + long_dz * half_l
			_draw_line.call(sx, sz, ex, ez)
		# Goal lines (short sides)
		for side2 in [-1.0, 1.0]:
			var sf2 := float(side2)
			var sx2: float = cx + long_dx * half_l * sf2 - short_dx * half_w
			var sz2: float = cz + long_dz * half_l * sf2 - short_dz * half_w
			var ex2: float = cx + long_dx * half_l * sf2 + short_dx * half_w
			var ez2: float = cz + long_dz * half_l * sf2 + short_dz * half_w
			_draw_line.call(sx2, sz2, ex2, ez2)
		# Halfway line
		var hx0 := cx - short_dx * half_w; var hz0 := cz - short_dz * half_w
		var hx1 := cx + short_dx * half_w; var hz1 := cz + short_dz * half_w
		_draw_line.call(hx0, hz0, hx1, hz1)
		# Center circle (radius ~9.15m)
		var cr := 9.15
		var c_segs := 32
		for ci in c_segs:
			var a0 := TAU * float(ci) / float(c_segs)
			var a1 := TAU * float(ci + 1) / float(c_segs)
			var p0x := cx + cos(a0) * cr * long_dx + sin(a0) * cr * short_dx
			var p0z := cz + cos(a0) * cr * long_dz + sin(a0) * cr * short_dz
			var p1x := cx + cos(a1) * cr * long_dx + sin(a1) * cr * short_dx
			var p1z := cz + cos(a1) * cr * long_dz + sin(a1) * cr * short_dz
			_draw_line.call(p0x, p0z, p1x, p1z)
		# Penalty areas (16.5m from goal line, 40.3m wide)
		var pa_d := 16.5; var pa_hw := 20.15
		for side3 in [-1.0, 1.0]:
			var sf3 := float(side3)
			var goal_cx: float = cx + long_dx * half_l * sf3
			var goal_cz: float = cz + long_dz * half_l * sf3
			# Inward direction (toward center)
			var inx: float = -long_dx * sf3; var inz: float = -long_dz * sf3
			# 4 corners of penalty area
			var c0x: float = goal_cx - short_dx * pa_hw
			var c0z: float = goal_cz - short_dz * pa_hw
			var c1x: float = goal_cx + short_dx * pa_hw
			var c1z: float = goal_cz + short_dz * pa_hw
			var c2x: float = c1x + inx * pa_d; var c2z: float = c1z + inz * pa_d
			var c3x: float = c0x + inx * pa_d; var c3z: float = c0z + inz * pa_d
			_draw_line.call(c0x, c0z, c3x, c3z)
			_draw_line.call(c3x, c3z, c2x, c2z)
			_draw_line.call(c2x, c2z, c1x, c1z)

		if not s_verts.is_empty():
			var sm: ArrayMesh = _loader._make_mesh(s_verts, s_norms)
			sm.surface_set_material(0, line_mat)
			var smi := MeshInstance3D.new()
			smi.mesh = sm
			smi.name = "Soccer_" + name2.replace(" ", "_")
			_loader.add_child(smi)
			soccer_count += 1

	if soccer_count > 0:
		print("ParkLoader: soccer field markings = ", soccer_count)

	# --- Basketball court markings ---
	var bball_count := 0
	for zone2 in _loader.landuse_zones:
		var name3: String = zone2.get("name", "")
		if name3.is_empty():
			continue
		var nl3 := name3.to_lower()
		if "basketball" not in nl3:
			continue
		var bpts: Array = zone2.get("points", [])
		if bpts.size() < 4:
			continue
		# Compute center and axes
		var bcx := 0.0; var bcz := 0.0
		for bp in bpts:
			bcx += float(bp[0]); bcz += float(bp[1])
		bcx /= bpts.size(); bcz /= bpts.size()
		# Court dimensions: ~28.7m × 15.2m (NBA standard)
		var bax := float(bpts[1][0]) - float(bpts[0][0])
		var baz := float(bpts[1][1]) - float(bpts[0][1])
		var bbx := float(bpts[2][0]) - float(bpts[1][0])
		var bbz := float(bpts[2][1]) - float(bpts[1][1])
		var ba_len := sqrt(bax * bax + baz * baz)
		var bb_len := sqrt(bbx * bbx + bbz * bbz)
		var blong_dx: float; var blong_dz: float; var bcourt_l: float; var bcourt_w: float
		var bshort_dx: float; var bshort_dz: float
		if ba_len >= bb_len:
			blong_dx = bax / ba_len; blong_dz = baz / ba_len
			bshort_dx = bbx / bb_len; bshort_dz = bbz / bb_len
			bcourt_l = ba_len; bcourt_w = bb_len
		else:
			blong_dx = bbx / bb_len; blong_dz = bbz / bb_len
			bshort_dx = bax / ba_len; bshort_dz = baz / ba_len
			bcourt_l = bb_len; bcourt_w = ba_len
		var bcy: float = _loader._terrain_y(bcx, bcz) + 0.025
		var blw := 0.08  # line width
		var bhalf_l := bcourt_l * 0.5
		var bhalf_w := bcourt_w * 0.5
		var b_verts := PackedVector3Array()
		var b_norms := PackedVector3Array()
		var _draw_bline := func(x0b: float, z0b: float, x1b: float, z1b: float) -> void:
			var dbx := x1b - x0b; var dbz := z1b - z0b
			var bln := sqrt(dbx * dbx + dbz * dbz)
			if bln < 0.01: return
			var bpx := -dbz / bln * blw * 0.5; var bpz := dbx / bln * blw * 0.5
			var by0: float = _loader._terrain_y(x0b, z0b) + 0.025
			var by1: float = _loader._terrain_y(x1b, z1b) + 0.025
			b_verts.append(Vector3(x0b + bpx, by0, z0b + bpz))
			b_verts.append(Vector3(x0b - bpx, by0, z0b - bpz))
			b_verts.append(Vector3(x1b + bpx, by1, z1b + bpz))
			b_verts.append(Vector3(x0b - bpx, by0, z0b - bpz))
			b_verts.append(Vector3(x1b - bpx, by1, z1b - bpz))
			b_verts.append(Vector3(x1b + bpx, by1, z1b + bpz))
			for _j3 in 6: b_norms.append(Vector3.UP)
		# Court outline
		var corners: Array[Vector2] = [
			Vector2(bcx - blong_dx * bhalf_l - bshort_dx * bhalf_w, bcz - blong_dz * bhalf_l - bshort_dz * bhalf_w),
			Vector2(bcx + blong_dx * bhalf_l - bshort_dx * bhalf_w, bcz + blong_dz * bhalf_l - bshort_dz * bhalf_w),
			Vector2(bcx + blong_dx * bhalf_l + bshort_dx * bhalf_w, bcz + blong_dz * bhalf_l + bshort_dz * bhalf_w),
			Vector2(bcx - blong_dx * bhalf_l + bshort_dx * bhalf_w, bcz - blong_dz * bhalf_l + bshort_dz * bhalf_w),
		]
		for ci2 in 4:
			_draw_bline.call(corners[ci2].x, corners[ci2].y, corners[(ci2 + 1) % 4].x, corners[(ci2 + 1) % 4].y)
		# Halfway line
		_draw_bline.call(
			bcx - bshort_dx * bhalf_w, bcz - bshort_dz * bhalf_w,
			bcx + bshort_dx * bhalf_w, bcz + bshort_dz * bhalf_w)
		# Center circle (radius ~1.8m)
		var bcr := 1.83
		var bc_segs := 24
		for bci in bc_segs:
			var ba0 := TAU * float(bci) / float(bc_segs)
			var ba1 := TAU * float(bci + 1) / float(bc_segs)
			var bp0x := bcx + cos(ba0) * bcr * blong_dx + sin(ba0) * bcr * bshort_dx
			var bp0z := bcz + cos(ba0) * bcr * blong_dz + sin(ba0) * bcr * bshort_dz
			var bp1x := bcx + cos(ba1) * bcr * blong_dx + sin(ba1) * bcr * bshort_dx
			var bp1z := bcz + cos(ba1) * bcr * blong_dz + sin(ba1) * bcr * bshort_dz
			_draw_bline.call(bp0x, bp0z, bp1x, bp1z)
		# Free throw lanes + 3-point arcs at each end
		var ft_d := 5.8; var ft_hw := 2.44  # free throw lane 4.88m wide, 5.8m deep
		for bside in [-1.0, 1.0]:
			var bsf := float(bside)
			var goal_cx2: float = bcx + blong_dx * bhalf_l * bsf
			var goal_cz2: float = bcz + blong_dz * bhalf_l * bsf
			var binx: float = -blong_dx * bsf; var binz: float = -blong_dz * bsf
			# Free throw lane rectangle
			var fc0x: float = goal_cx2 - bshort_dx * ft_hw
			var fc0z: float = goal_cz2 - bshort_dz * ft_hw
			var fc1x: float = goal_cx2 + bshort_dx * ft_hw
			var fc1z: float = goal_cz2 + bshort_dz * ft_hw
			var fc2x: float = fc1x + binx * ft_d; var fc2z: float = fc1z + binz * ft_d
			var fc3x: float = fc0x + binx * ft_d; var fc3z: float = fc0z + binz * ft_d
			_draw_bline.call(fc0x, fc0z, fc3x, fc3z)
			_draw_bline.call(fc3x, fc3z, fc2x, fc2z)
			_draw_bline.call(fc2x, fc2z, fc1x, fc1z)

		if not b_verts.is_empty():
			var bm2: ArrayMesh = _loader._make_mesh(b_verts, b_norms)
			bm2.surface_set_material(0, line_mat)
			var bmi := MeshInstance3D.new()
			bmi.mesh = bm2
			bmi.name = "Basketball_" + name3.replace(" ", "_")
			_loader.add_child(bmi)
			bball_count += 1

	if bball_count > 0:
		print("ParkLoader: basketball court markings = ", bball_count)

	# --- Tennis court markings ---
	# Central Park Tennis Center: Har-Tru green clay, white lines
	var tennis_count := 0
	for zone3 in _loader.landuse_zones:
		var name4: String = zone3.get("name", "")
		if name4.is_empty():
			continue
		if "Tennis" not in name4:
			continue
		var tpts2: Array = zone3.get("points", [])
		if tpts2.size() < 4:
			continue
		# Skip facilities outside park boundary
		var in_park := false
		for tp_chk in tpts2:
			if _loader._in_boundary(float(tp_chk[0]), float(tp_chk[1])):
				in_park = true
				break
		if not in_park:
			continue
		# Compute bounding box center and axes from polygon
		var tcx2 := 0.0; var tcz2 := 0.0
		for tp in tpts2:
			tcx2 += float(tp[0]); tcz2 += float(tp[1])
		tcx2 /= tpts2.size(); tcz2 /= tpts2.size()
		# Find longest edge to determine facility orientation
		var best_edge_len := 0.0
		var best_edge_dx := 0.0; var best_edge_dz := 0.0
		for ei in tpts2.size():
			var ei2 := (ei + 1) % tpts2.size()
			var edx := float(tpts2[ei2][0]) - float(tpts2[ei][0])
			var edz := float(tpts2[ei2][1]) - float(tpts2[ei][1])
			var elen := sqrt(edx * edx + edz * edz)
			if elen > best_edge_len:
				best_edge_len = elen
				best_edge_dx = edx / elen; best_edge_dz = edz / elen
		if best_edge_len < 1.0:
			continue
		var fac_long_x := best_edge_dx; var fac_long_z := best_edge_dz
		var fac_short_x := -fac_long_z; var fac_short_z := fac_long_x
		# Project all polygon points onto axes to get true extent
		var min_long := 1e9; var max_long := -1e9
		var min_short := 1e9; var max_short := -1e9
		for tp2 in tpts2:
			var px2 := float(tp2[0]) - tcx2; var pz2 := float(tp2[1]) - tcz2
			var proj_l := px2 * fac_long_x + pz2 * fac_long_z
			var proj_s := px2 * fac_short_x + pz2 * fac_short_z
			min_long = minf(min_long, proj_l); max_long = maxf(max_long, proj_l)
			min_short = minf(min_short, proj_s); max_short = maxf(max_short, proj_s)
		var fac_l := max_long - min_long
		var fac_w := max_short - min_short
		# Recenter on polygon extent
		var ctr_long := (min_long + max_long) * 0.5
		var ctr_short := (min_short + max_short) * 0.5
		tcx2 += fac_long_x * ctr_long + fac_short_x * ctr_short
		tcz2 += fac_long_z * ctr_long + fac_short_z * ctr_short
		# Tennis court dimensions (doubles)
		var court_l := 23.77  # baseline to baseline
		var court_w := 10.97  # doubles sideline to sideline
		var singles_w := 8.23
		var service_d := 6.40  # net to service line
		# Spacing between courts
		var gap_side := 3.66   # between sidelines
		var gap_end := 6.40    # between baselines
		var slot_x := court_w + gap_side  # ~14.6m per court across
		var slot_z := court_l + gap_end   # ~30.2m per court deep
		# Inset for walkways/fencing/clubhouse
		var usable_l := fac_l - 20.0  # margin for perimeter walkways
		var usable_w := fac_w - 10.0
		# Courts oriented with long axis along fac_short (perpendicular to facility long axis)
		var n_cols := int(usable_l / slot_x)
		var n_rows := int(usable_w / slot_z)
		if n_cols < 1: n_cols = 1
		if n_rows < 1: n_rows = 1
		# Cap to realistic count (Central Park Tennis Center has ~26 courts)
		while n_cols * n_rows > 30:
			if n_cols > n_rows and n_cols > 1:
				n_cols -= 1
			elif n_rows > 1:
				n_rows -= 1
			else:
				break
		# Offset so grid is centered
		var grid_w_total := float(n_cols) * slot_x - gap_side
		var grid_h_total := float(n_rows) * slot_z - gap_end
		var off_long := -grid_w_total * 0.5 + court_w * 0.5
		var off_short := -grid_h_total * 0.5 + court_l * 0.5

		# Materials
		var court_mat := StandardMaterial3D.new()
		court_mat.albedo_color = Color(0.35, 0.55, 0.38)  # Har-Tru green clay
		court_mat.roughness = 0.90
		court_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		var t_verts := PackedVector3Array()
		var t_norms := PackedVector3Array()
		var tl_verts := PackedVector3Array()
		var tl_norms := PackedVector3Array()
		var tlw := 0.05  # tennis line width (~2 inches)

		var _draw_tline := func(x0t: float, z0t: float, x1t: float, z1t: float) -> void:
			var dtx := x1t - x0t; var dtz := z1t - z0t
			var tln := sqrt(dtx * dtx + dtz * dtz)
			if tln < 0.01: return
			var tpx := -dtz / tln * tlw * 0.5; var tpz := dtx / tln * tlw * 0.5
			var ty0: float = _loader._terrain_y(x0t, z0t) + 0.03
			var ty1: float = _loader._terrain_y(x1t, z1t) + 0.03
			tl_verts.append(Vector3(x0t + tpx, ty0, z0t + tpz))
			tl_verts.append(Vector3(x0t - tpx, ty0, z0t - tpz))
			tl_verts.append(Vector3(x1t + tpx, ty1, z1t + tpz))
			tl_verts.append(Vector3(x0t - tpx, ty0, z0t - tpz))
			tl_verts.append(Vector3(x1t - tpx, ty1, z1t - tpz))
			tl_verts.append(Vector3(x1t + tpx, ty1, z1t + tpz))
			for _jt in 6: tl_norms.append(Vector3.UP)

		var _draw_court_quad := func(x0q: float, z0q: float, x1q: float, z1q: float,
				x2q: float, z2q: float, x3q: float, z3q: float) -> void:
			var qy0: float = _loader._terrain_y(x0q, z0q) + 0.02
			var qy1: float = _loader._terrain_y(x1q, z1q) + 0.02
			var qy2: float = _loader._terrain_y(x2q, z2q) + 0.02
			var qy3: float = _loader._terrain_y(x3q, z3q) + 0.02
			t_verts.append(Vector3(x0q, qy0, z0q))
			t_verts.append(Vector3(x1q, qy1, z1q))
			t_verts.append(Vector3(x2q, qy2, z2q))
			t_verts.append(Vector3(x0q, qy0, z0q))
			t_verts.append(Vector3(x2q, qy2, z2q))
			t_verts.append(Vector3(x3q, qy3, z3q))
			for _jq in 6: t_norms.append(Vector3.UP)

		var courts_placed := 0
		for col in n_cols:
			for row in n_rows:
				# Court center in facility-local coords
				var loc_x := off_long + float(col) * slot_x
				var loc_z := off_short + float(row) * slot_z
				# Transform to world
				var ccx := tcx2 + fac_long_x * loc_x + fac_short_x * loc_z
				var ccz := tcz2 + fac_long_z * loc_x + fac_short_z * loc_z
				# Court long axis = fac_short, court short axis = fac_long
				var cl_x := fac_short_x; var cl_z := fac_short_z  # court long (baseline-to-baseline)
				var cs_x := fac_long_x; var cs_z := fac_long_z    # court short (sideline-to-sideline)
				var hl := court_l * 0.5  # half length
				var hw2 := court_w * 0.5  # half width (doubles)
				var hsw := singles_w * 0.5  # half width (singles)
				# Court surface quad
				var q0x := ccx - cl_x * hl - cs_x * hw2
				var q0z := ccz - cl_z * hl - cs_z * hw2
				var q1x := ccx + cl_x * hl - cs_x * hw2
				var q1z := ccz + cl_z * hl - cs_z * hw2
				var q2x := ccx + cl_x * hl + cs_x * hw2
				var q2z := ccz + cl_z * hl + cs_z * hw2
				var q3x := ccx - cl_x * hl + cs_x * hw2
				var q3z := ccz - cl_z * hl + cs_z * hw2
				_draw_court_quad.call(q0x, q0z, q1x, q1z, q2x, q2z, q3x, q3z)
				# Doubles sidelines (long sides)
				for tside in [-1.0, 1.0]:
					var tsf := float(tside)
					var s0x: float = ccx - cl_x * hl + cs_x * hw2 * tsf
					var s0z: float = ccz - cl_z * hl + cs_z * hw2 * tsf
					var s1x: float = ccx + cl_x * hl + cs_x * hw2 * tsf
					var s1z: float = ccz + cl_z * hl + cs_z * hw2 * tsf
					_draw_tline.call(s0x, s0z, s1x, s1z)
				# Singles sidelines
				for tside2 in [-1.0, 1.0]:
					var tsf2 := float(tside2)
					var ss0x: float = ccx - cl_x * hl + cs_x * hsw * tsf2
					var ss0z: float = ccz - cl_z * hl + cs_z * hsw * tsf2
					var ss1x: float = ccx + cl_x * hl + cs_x * hsw * tsf2
					var ss1z: float = ccz + cl_z * hl + cs_z * hsw * tsf2
					_draw_tline.call(ss0x, ss0z, ss1x, ss1z)
				# Baselines (short ends)
				for tside3 in [-1.0, 1.0]:
					var tsf3 := float(tside3)
					var b0x: float = ccx + cl_x * hl * tsf3 - cs_x * hw2
					var b0z: float = ccz + cl_z * hl * tsf3 - cs_z * hw2
					var b1x: float = ccx + cl_x * hl * tsf3 + cs_x * hw2
					var b1z: float = ccz + cl_z * hl * tsf3 + cs_z * hw2
					_draw_tline.call(b0x, b0z, b1x, b1z)
				# Service lines (parallel to net, 6.40m from center each side)
				for tside4 in [-1.0, 1.0]:
					var tsf4 := float(tside4)
					var sv0x: float = ccx + cl_x * service_d * tsf4 - cs_x * hsw
					var sv0z: float = ccz + cl_z * service_d * tsf4 - cs_z * hsw
					var sv1x: float = ccx + cl_x * service_d * tsf4 + cs_x * hsw
					var sv1z: float = ccz + cl_z * service_d * tsf4 + cs_z * hsw
					_draw_tline.call(sv0x, sv0z, sv1x, sv1z)
				# Center service line (net to each service line, along court center)
				_draw_tline.call(
					ccx - cl_x * service_d, ccz - cl_z * service_d,
					ccx + cl_x * service_d, ccz + cl_z * service_d)
				# Center mark on baselines (short tick at center)
				var cm_len := 0.1  # 10cm tick
				for tside5 in [-1.0, 1.0]:
					var tsf5 := float(tside5)
					var cmx: float = ccx + cl_x * hl * tsf5
					var cmz: float = ccz + cl_z * hl * tsf5
					_draw_tline.call(
						cmx - cl_x * cm_len * tsf5, cmz - cl_z * cm_len * tsf5,
						cmx, cmz)
				courts_placed += 1

		# Build court surface mesh
		if not t_verts.is_empty():
			var tm: ArrayMesh = _loader._make_mesh(t_verts, t_norms)
			tm.surface_set_material(0, court_mat)
			var tmi := MeshInstance3D.new()
			tmi.mesh = tm
			tmi.name = "Tennis_Surface_" + name4.replace(" ", "_")
			_loader.add_child(tmi)
		# Build court lines mesh
		if not tl_verts.is_empty():
			var tlm: ArrayMesh = _loader._make_mesh(tl_verts, tl_norms)
			tlm.surface_set_material(0, line_mat)
			var tlmi := MeshInstance3D.new()
			tlmi.mesh = tlm
			tlmi.name = "Tennis_Lines_" + name4.replace(" ", "_")
			_loader.add_child(tlmi)
		tennis_count += courts_placed

	if tennis_count > 0:
		print("ParkLoader: tennis court markings = ", tennis_count)
