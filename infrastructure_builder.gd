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
	var hedge_verts  := PackedVector3Array()
	var hedge_normals := PackedVector3Array()
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
			"hedge":
				_build_wall_segments(pts, maxf(height, 0.8), hedge_verts, hedge_normals, col_verts)
			_:
				_build_wall_segments(pts, height, wall_verts, wall_normals, col_verts)

	# Stone wall mesh
	if not wall_verts.is_empty():
		# Manhattan schist: gray stone with subtle warm weathering
		_loader._add_stone_mesh(wall_verts, wall_normals, rw_alb, rw_nrm, rw_rgh,
						Color(0.50, 0.48, 0.44), "StoneWalls")
	# Iron fence mesh — cast iron shader for weather response
	if not fence_verts.is_empty():
		_loader._add_iron_mesh(fence_verts, fence_normals,
						Color(0.15, 0.15, 0.14), "IronFences")
	# Hedge barrier mesh — uses hedge shader for seasonal foliage
	if not hedge_verts.is_empty():
		var hedge_sh: Shader = _loader._get_shader("hedge", "res://shaders/hedge.gdshader")
		var hedge_mat := ShaderMaterial.new()
		hedge_mat.shader = hedge_sh
		var hm: ArrayMesh = _loader._make_mesh(hedge_verts, hedge_normals)
		hm.surface_set_material(0, hedge_mat)
		var hmi := MeshInstance3D.new()
		hmi.mesh = hm
		hmi.name = "HedgeBarriers"
		_loader.add_child(hmi)
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
# Dog parks — chain-link fenced perimeters from landuse zones
# ---------------------------------------------------------------------------
func _build_dog_parks() -> void:
	var dog_parks: Array = []
	for zone in _loader.landuse_zones:
		if zone.get("type", "") == "dog_park":
			dog_parks.append(zone)
	if dog_parks.is_empty():
		return

	var f_verts := PackedVector3Array()
	var f_norms := PackedVector3Array()
	var c_verts := PackedVector3Array()

	for dp in dog_parks:
		var name_: String = dp.get("name", "")
		var pts: Array = dp.get("points", [])
		if pts.size() < 4:
			continue

		# Build 3D point array with terrain heights
		var pts3d: Array = []
		var cx := 0.0
		var cz := 0.0
		for pt in pts:
			var x := float(pt[0])
			var z := float(pt[1])
			var y: float = _loader._terrain_y(x, z)
			pts3d.append([x, y, z])
			cx += x
			cz += z
		cx /= pts.size()
		cz /= pts.size()
		if not _loader._in_boundary(cx, cz):
			continue

		# Close the polygon if not already closed
		var first = pts3d[0]
		var last = pts3d[pts3d.size() - 1]
		if abs(float(first[0]) - float(last[0])) > 0.5 or abs(float(first[2]) - float(last[2])) > 0.5:
			pts3d.append(first)

		# Build fence around perimeter (1.2m tall chain-link)
		_build_fence_segments(pts3d, 1.2, f_verts, f_norms, c_verts)

		# Label
		if not name_.is_empty():
			var ty: float = _loader._terrain_y(cx, cz)
			var label := Label3D.new()
			label.text = name_
			label.font_size = 22
			label.position = Vector3(cx, ty + 2.5, cz)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color(0.60, 0.50, 0.30, 0.65)
			label.outline_modulate = Color(0.08, 0.06, 0.04, 0.45)
			label.outline_size = 4
			label.no_depth_test = false
			label.pixel_size = 0.011
			_loader.add_child(label)

	# Chain-link fence mesh — dark green powder-coated iron
	if not f_verts.is_empty():
		_loader._add_iron_mesh(f_verts, f_norms,
			Color(0.18, 0.22, 0.15), "DogParkFences")

	# Collision
	if not c_verts.is_empty():
		var body := StaticBody3D.new()
		body.name = "DogPark_Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(c_verts)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_loader.add_child(body)

	print("  Dog parks: %d fenced" % dog_parks.size())


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
		if path.get("bridge", false) or path.get("tunnel", false):
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

		# No photogrammetry scan available — skip procedural geometry,
		# just place a label so the data gap stays visible.
		# Material-tinted label: bronze → warm amber, granite → cool gray
		var smat: String = str(statue.get("material", ""))
		var mat_col := Color(0.75, 0.72, 0.68, 0.65)  # default neutral
		if "bronze" in smat:
			mat_col = Color(0.72, 0.58, 0.35, 0.65)  # warm bronze
		elif "granite" in smat or "stone" in smat:
			mat_col = Color(0.62, 0.62, 0.60, 0.65)  # cool granite

		var label_text: String = sname if sname else stype.capitalize()
		# Add inscription snippet if available (first 60 chars)
		var inscription: String = str(statue.get("inscription", ""))
		if not inscription.is_empty():
			var snippet: String = inscription.substr(0, 60)
			if inscription.length() > 60:
				snippet += "..."
			label_text += "\n" + snippet

		var lbl := Label3D.new()
		lbl.text = label_text
		lbl.font_size = 48
		lbl.pixel_size = 0.02
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = mat_col
		lbl.outline_size = 6
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.50)
		lbl.position = Vector3(sx, sy + 2.0, sz)
		_loader.add_child(lbl)

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
	## Draws dirt infield and white line markings for baseball/softball fields.
	var fields: Array = []
	for zone in _loader.landuse_zones:
		var sport: String = zone.get("sport", "")
		var name: String = zone.get("name", "")
		var nl := name.to_lower()
		var is_baseball := sport == "baseball" or sport == "softball" \
			or "ballfield" in nl or "ball field" in nl or "baseball" in nl or "softball" in nl
		if not is_baseball:
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

	# Materials — weather-responsive ground surfaces
	var gs_shader: Shader = _loader._get_shader("ground_surface", "res://shaders/ground_surface.gdshader")
	var dirt_mat := ShaderMaterial.new()
	dirt_mat.shader = gs_shader
	dirt_mat.set_shader_parameter("surface_color", Vector3(0.55, 0.42, 0.30))
	dirt_mat.set_shader_parameter("base_roughness", 0.95)

	var line_mat := ShaderMaterial.new()
	line_mat.shader = gs_shader
	line_mat.set_shader_parameter("surface_color", Vector3(0.95, 0.95, 0.90))
	line_mat.set_shader_parameter("base_roughness", 0.85)

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
		var sport2: String = zone.get("sport", "")
		var name2: String = zone.get("name", "")
		var is_soccer := "soccer" in sport2 or "soccer" in name2.to_lower()
		if not is_soccer:
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
		var sport3: String = zone2.get("sport", "")
		var name3: String = zone2.get("name", "")
		var is_bball := "basketball" in sport3 or "basketball" in name3.to_lower()
		if not is_bball:
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
		var tp_r := 6.02  # 3-point radius (HS/college standard for NYC parks)
		var tp_segs := 20
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
			# 3-point arc (semicircle from basket position toward center)
			var basket_x: float = goal_cx2 + binx * 1.575  # 5'3" from baseline
			var basket_z: float = goal_cz2 + binz * 1.575
			for tpi in tp_segs:
				var ta0 := -PI * 0.5 + PI * float(tpi) / float(tp_segs)
				var ta1 := -PI * 0.5 + PI * float(tpi + 1) / float(tp_segs)
				var tp0x := basket_x + (cos(ta0) * bshort_dx + sin(ta0) * binx) * tp_r
				var tp0z := basket_z + (cos(ta0) * bshort_dz + sin(ta0) * binz) * tp_r
				var tp1x := basket_x + (cos(ta1) * bshort_dx + sin(ta1) * binx) * tp_r
				var tp1z := basket_z + (cos(ta1) * bshort_dz + sin(ta1) * binz) * tp_r
				_draw_bline.call(tp0x, tp0z, tp1x, tp1z)

		if not b_verts.is_empty():
			var bm2: ArrayMesh = _loader._make_mesh(b_verts, b_norms)
			bm2.surface_set_material(0, line_mat)
			var bmi := MeshInstance3D.new()
			bmi.mesh = bm2
			var bname := name3.replace(" ", "_") if not name3.is_empty() else str(bball_count)
			bmi.name = "Basketball_" + bname
			_loader.add_child(bmi)
			bball_count += 1

	if bball_count > 0:
		print("ParkLoader: basketball court markings = ", bball_count)

	# --- Handball court markings ---
	# American handball: ~6.1m × 10.4m wall courts (one-wall), blue/green surface
	var hball_count := 0
	var hb_verts := PackedVector3Array()
	var hb_norms := PackedVector3Array()
	var hbl_verts := PackedVector3Array()
	var hbl_norms := PackedVector3Array()
	var hblw := 0.06
	var _draw_hline := func(x0h: float, z0h: float, x1h: float, z1h: float) -> void:
		var dhx := x1h - x0h; var dhz := z1h - z0h
		var hln := sqrt(dhx * dhx + dhz * dhz)
		if hln < 0.01: return
		var hpx := -dhz / hln * hblw * 0.5; var hpz := dhx / hln * hblw * 0.5
		var hy0: float = _loader._terrain_y(x0h, z0h) + 0.025
		var hy1: float = _loader._terrain_y(x1h, z1h) + 0.025
		hbl_verts.append(Vector3(x0h + hpx, hy0, z0h + hpz))
		hbl_verts.append(Vector3(x0h - hpx, hy0, z0h - hpz))
		hbl_verts.append(Vector3(x1h + hpx, hy1, z1h + hpz))
		hbl_verts.append(Vector3(x0h - hpx, hy0, z0h - hpz))
		hbl_verts.append(Vector3(x1h - hpx, hy1, z1h - hpz))
		hbl_verts.append(Vector3(x1h + hpx, hy1, z1h + hpz))
		for _jh in 6: hbl_norms.append(Vector3.UP)
	for zone_h in _loader.landuse_zones:
		var sport_h: String = zone_h.get("sport", "")
		if sport_h != "american_handball":
			continue
		var hpts: Array = zone_h.get("points", [])
		if hpts.size() < 4:
			continue
		var hcx := 0.0; var hcz := 0.0
		for hp in hpts:
			hcx += float(hp[0]); hcz += float(hp[1])
		hcx /= hpts.size(); hcz /= hpts.size()
		# Find axes from polygon edges
		var hax := float(hpts[1][0]) - float(hpts[0][0])
		var haz := float(hpts[1][1]) - float(hpts[0][1])
		var hbx := float(hpts[2][0]) - float(hpts[1][0])
		var hbz := float(hpts[2][1]) - float(hpts[1][1])
		var ha_len := sqrt(hax * hax + haz * haz)
		var hb_len := sqrt(hbx * hbx + hbz * hbz)
		if ha_len < 0.5 or hb_len < 0.5:
			continue
		var hlong_dx: float; var hlong_dz: float; var hshort_dx: float; var hshort_dz: float
		var hcourt_l: float; var hcourt_w: float
		if ha_len >= hb_len:
			hlong_dx = hax / ha_len; hlong_dz = haz / ha_len
			hshort_dx = hbx / hb_len; hshort_dz = hbz / hb_len
			hcourt_l = ha_len; hcourt_w = hb_len
		else:
			hlong_dx = hbx / hb_len; hlong_dz = hbz / hb_len
			hshort_dx = hax / ha_len; hshort_dz = haz / ha_len
			hcourt_l = hb_len; hcourt_w = ha_len
		var hhl := hcourt_l * 0.5; var hhw := hcourt_w * 0.5
		# Court surface
		var hq0x := hcx - hlong_dx * hhl - hshort_dx * hhw
		var hq0z := hcz - hlong_dz * hhl - hshort_dz * hhw
		var hq1x := hcx + hlong_dx * hhl - hshort_dx * hhw
		var hq1z := hcz + hlong_dz * hhl - hshort_dz * hhw
		var hq2x := hcx + hlong_dx * hhl + hshort_dx * hhw
		var hq2z := hcz + hlong_dz * hhl + hshort_dz * hhw
		var hq3x := hcx - hlong_dx * hhl + hshort_dx * hhw
		var hq3z := hcz - hlong_dz * hhl + hshort_dz * hhw
		var hqy: float = _loader._terrain_y(hcx, hcz) + 0.02
		hb_verts.append_array(PackedVector3Array([
			Vector3(hq0x, hqy, hq0z), Vector3(hq1x, hqy, hq1z), Vector3(hq2x, hqy, hq2z),
			Vector3(hq0x, hqy, hq0z), Vector3(hq2x, hqy, hq2z), Vector3(hq3x, hqy, hq3z),
		]))
		for _jhs in 6: hb_norms.append(Vector3.UP)
		# Court outline
		_draw_hline.call(hq0x, hq0z, hq1x, hq1z)
		_draw_hline.call(hq1x, hq1z, hq2x, hq2z)
		_draw_hline.call(hq2x, hq2z, hq3x, hq3z)
		_draw_hline.call(hq3x, hq3z, hq0x, hq0z)
		# Short service line (4.9m from wall, parallel to short side)
		var srv_d := 4.9
		var srv0x := hcx - hlong_dx * hhl + hlong_dx * srv_d - hshort_dx * hhw
		var srv0z := hcz - hlong_dz * hhl + hlong_dz * srv_d - hshort_dz * hhw
		var srv1x := hcx - hlong_dx * hhl + hlong_dx * srv_d + hshort_dx * hhw
		var srv1z := hcz - hlong_dz * hhl + hlong_dz * srv_d + hshort_dz * hhw
		_draw_hline.call(srv0x, srv0z, srv1x, srv1z)
		hball_count += 1
	if not hb_verts.is_empty():
		var hb_gs: Shader = _loader._get_shader("ground_surface", "res://shaders/ground_surface.gdshader")
		var hb_mat := ShaderMaterial.new()
		hb_mat.shader = hb_gs
		hb_mat.set_shader_parameter("surface_color", Vector3(0.25, 0.40, 0.55))
		hb_mat.set_shader_parameter("base_roughness", 0.85)
		var hbm: ArrayMesh = _loader._make_mesh(hb_verts, hb_norms)
		hbm.surface_set_material(0, hb_mat)
		var hbmi := MeshInstance3D.new()
		hbmi.mesh = hbm
		hbmi.name = "Handball_Surfaces"
		_loader.add_child(hbmi)
	if not hbl_verts.is_empty():
		var hblm: ArrayMesh = _loader._make_mesh(hbl_verts, hbl_norms)
		hblm.surface_set_material(0, line_mat)
		var hblmi := MeshInstance3D.new()
		hblmi.mesh = hblm
		hblmi.name = "Handball_Lines"
		_loader.add_child(hblmi)
	if hball_count > 0:
		print("ParkLoader: handball court markings = ", hball_count)

	# --- Tennis court markings ---
	# Individual courts from OSM sport=tennis, plus facility subdivisions
	var tennis_count := 0
	var gs_sh: Shader = _loader._get_shader("ground_surface", "res://shaders/ground_surface.gdshader")
	var court_mat := ShaderMaterial.new()
	court_mat.shader = gs_sh
	court_mat.set_shader_parameter("surface_color", Vector3(0.35, 0.55, 0.38))
	court_mat.set_shader_parameter("base_roughness", 0.90)
	var t_verts := PackedVector3Array()
	var t_norms := PackedVector3Array()
	var tl_verts := PackedVector3Array()
	var tl_norms := PackedVector3Array()
	var tlw := 0.05  # tennis line width (~2 inches)
	var court_l := 23.77  # baseline to baseline
	var court_w := 10.97  # doubles sideline to sideline
	var singles_w := 8.23
	var service_d := 6.40  # net to service line

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

	# Helper: draw one tennis court given center + axes
	var _draw_one_court := func(ccx: float, ccz: float,
			cl_x: float, cl_z: float, cs_x: float, cs_z: float) -> void:
		var hl := court_l * 0.5
		var hw2 := court_w * 0.5
		var hsw := singles_w * 0.5
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
		# Doubles sidelines
		for tside in [-1.0, 1.0]:
			var tsf := float(tside)
			_draw_tline.call(
				ccx - cl_x * hl + cs_x * hw2 * tsf, ccz - cl_z * hl + cs_z * hw2 * tsf,
				ccx + cl_x * hl + cs_x * hw2 * tsf, ccz + cl_z * hl + cs_z * hw2 * tsf)
		# Singles sidelines
		for tside2 in [-1.0, 1.0]:
			var tsf2 := float(tside2)
			_draw_tline.call(
				ccx - cl_x * hl + cs_x * hsw * tsf2, ccz - cl_z * hl + cs_z * hsw * tsf2,
				ccx + cl_x * hl + cs_x * hsw * tsf2, ccz + cl_z * hl + cs_z * hsw * tsf2)
		# Baselines
		for tside3 in [-1.0, 1.0]:
			var tsf3 := float(tside3)
			_draw_tline.call(
				ccx + cl_x * hl * tsf3 - cs_x * hw2, ccz + cl_z * hl * tsf3 - cs_z * hw2,
				ccx + cl_x * hl * tsf3 + cs_x * hw2, ccz + cl_z * hl * tsf3 + cs_z * hw2)
		# Service lines
		for tside4 in [-1.0, 1.0]:
			var tsf4 := float(tside4)
			_draw_tline.call(
				ccx + cl_x * service_d * tsf4 - cs_x * hsw, ccz + cl_z * service_d * tsf4 - cs_z * hsw,
				ccx + cl_x * service_d * tsf4 + cs_x * hsw, ccz + cl_z * service_d * tsf4 + cs_z * hsw)
		# Center service line
		_draw_tline.call(
			ccx - cl_x * service_d, ccz - cl_z * service_d,
			ccx + cl_x * service_d, ccz + cl_z * service_d)
		# Center marks on baselines
		var cm_len := 0.1
		for tside5 in [-1.0, 1.0]:
			var tsf5 := float(tside5)
			var cmx: float = ccx + cl_x * hl * tsf5
			var cmz: float = ccz + cl_z * hl * tsf5
			_draw_tline.call(cmx - cl_x * cm_len * tsf5, cmz - cl_z * cm_len * tsf5, cmx, cmz)

	for zone3 in _loader.landuse_zones:
		var sport4: String = zone3.get("sport", "")
		var name4: String = zone3.get("name", "")
		var is_tennis := "tennis" in sport4 or "Tennis" in name4
		if not is_tennis:
			continue
		var tpts2: Array = zone3.get("points", [])
		if tpts2.size() < 4:
			continue
		# Boundary check
		var in_park := false
		for tp_chk in tpts2:
			if _loader._in_boundary(float(tp_chk[0]), float(tp_chk[1])):
				in_park = true
				break
		if not in_park:
			continue
		# Compute center and axes from polygon
		var tcx2 := 0.0; var tcz2 := 0.0
		for tp in tpts2:
			tcx2 += float(tp[0]); tcz2 += float(tp[1])
		tcx2 /= tpts2.size(); tcz2 /= tpts2.size()
		# Find longest edge
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
		# Project to get extent
		var fac_long_x := best_edge_dx; var fac_long_z := best_edge_dz
		var fac_short_x := -fac_long_z; var fac_short_z := fac_long_x
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
		var ctr_long := (min_long + max_long) * 0.5
		var ctr_short := (min_short + max_short) * 0.5
		tcx2 += fac_long_x * ctr_long + fac_short_x * ctr_short
		tcz2 += fac_long_z * ctr_long + fac_short_z * ctr_short

		# Individual court (<30m longest dimension) — draw one court directly
		if maxf(fac_l, fac_w) < 30.0:
			# Long axis of polygon = long axis of court
			var cl_x: float; var cl_z: float; var cs_x: float; var cs_z: float
			if fac_l >= fac_w:
				cl_x = fac_long_x; cl_z = fac_long_z
				cs_x = fac_short_x; cs_z = fac_short_z
			else:
				cl_x = fac_short_x; cl_z = fac_short_z
				cs_x = fac_long_x; cs_z = fac_long_z
			_draw_one_court.call(tcx2, tcz2, cl_x, cl_z, cs_x, cs_z)
			tennis_count += 1
		else:
			# Large facility — subdivide into grid of courts
			var gap_side := 3.66; var gap_end := 6.40
			var slot_x := court_w + gap_side
			var slot_z := court_l + gap_end
			var usable_l := fac_l - 20.0
			var usable_w := fac_w - 10.0
			var n_cols := maxi(int(usable_l / slot_x), 1)
			var n_rows := maxi(int(usable_w / slot_z), 1)
			while n_cols * n_rows > 30:
				if n_cols > n_rows and n_cols > 1: n_cols -= 1
				elif n_rows > 1: n_rows -= 1
				else: break
			var grid_w_total := float(n_cols) * slot_x - gap_side
			var grid_h_total := float(n_rows) * slot_z - gap_end
			var off_long := -grid_w_total * 0.5 + court_w * 0.5
			var off_short := -grid_h_total * 0.5 + court_l * 0.5
			for col in n_cols:
				for row in n_rows:
					var loc_x := off_long + float(col) * slot_x
					var loc_z := off_short + float(row) * slot_z
					var ccx := tcx2 + fac_long_x * loc_x + fac_short_x * loc_z
					var ccz := tcz2 + fac_long_z * loc_x + fac_short_z * loc_z
					_draw_one_court.call(ccx, ccz, fac_short_x, fac_short_z, fac_long_x, fac_long_z)
					tennis_count += 1

	# Build tennis meshes
	if not t_verts.is_empty():
		var tm: ArrayMesh = _loader._make_mesh(t_verts, t_norms)
		tm.surface_set_material(0, court_mat)
		var tmi := MeshInstance3D.new()
		tmi.mesh = tm
		tmi.name = "Tennis_Surfaces"
		_loader.add_child(tmi)
	if not tl_verts.is_empty():
		var tlm: ArrayMesh = _loader._make_mesh(tl_verts, tl_norms)
		tlm.surface_set_material(0, line_mat)
		var tlmi := MeshInstance3D.new()
		tlmi.mesh = tlm
		tlmi.name = "Tennis_Lines"
		_loader.add_child(tlmi)

	if tennis_count > 0:
		print("ParkLoader: tennis court markings = ", tennis_count)


# ---------------------------------------------------------------------------
# Garden borders — low hedge/border outlines for named gardens
# ---------------------------------------------------------------------------
func _build_gardens() -> void:
	var gardens: Array = []
	for zone in _loader.landuse_zones:
		if zone.get("type", "") != "garden":
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 4:
			continue
		gardens.append(zone)

	if gardens.is_empty():
		return

	# Hedge material — seasonal foliage with weather response
	var hedge_sh: Shader = _loader._get_shader("hedge", "res://shaders/hedge.gdshader")
	var hedge_mat := ShaderMaterial.new()
	hedge_mat.shader = hedge_sh

	# Build hedge geometry — low box along polygon perimeter
	var h_verts := PackedVector3Array()
	var h_norms := PackedVector3Array()
	var hedge_h := 0.7   # 70cm tall hedges
	var hedge_w := 0.25  # 25cm wide

	var label_count := 0
	for zone in gardens:
		var name_: String = zone.get("name", "")
		var pts: Array = zone.get("points", [])
		var n: int = pts.size()

		# Centroid for label placement
		var cx := 0.0
		var cz := 0.0
		for pt in pts:
			cx += float(pt[0])
			cz += float(pt[1])
		cx /= n
		cz /= n
		if not _loader._in_boundary(cx, cz):
			continue

		# Build hedge segments along perimeter
		for i in range(n):
			var j := (i + 1) % n
			var x1 := float(pts[i][0])
			var z1 := float(pts[i][1])
			var x2 := float(pts[j][0])
			var z2 := float(pts[j][1])

			var dx := x2 - x1
			var dz := z2 - z1
			var seg_len := sqrt(dx * dx + dz * dz)
			if seg_len < 0.5:
				continue

			# Normal perpendicular to segment
			var nx := -dz / seg_len * hedge_w
			var nz := dx / seg_len * hedge_w

			var y1: float = _loader._terrain_y(x1, z1)
			var y2: float = _loader._terrain_y(x2, z2)

			# Two triangles for top face
			var a := Vector3(x1 - nx, y1 + hedge_h, z1 - nz)
			var b := Vector3(x1 + nx, y1 + hedge_h, z1 + nz)
			var c := Vector3(x2 + nx, y2 + hedge_h, z2 + nz)
			var d := Vector3(x2 - nx, y2 + hedge_h, z2 - nz)
			h_verts.append_array(PackedVector3Array([a, b, c, a, c, d]))
			h_norms.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP,
				Vector3.UP, Vector3.UP, Vector3.UP]))

			# Front face (outer side)
			var e := Vector3(x1 + nx, y1, z1 + nz)
			var f := Vector3(x2 + nx, y2, z2 + nz)
			var fn := Vector3(nx, 0, nz).normalized()
			h_verts.append_array(PackedVector3Array([e, b, c, e, c, f]))
			h_norms.append_array(PackedVector3Array([fn, fn, fn, fn, fn, fn]))

			# Back face (inner side)
			var g := Vector3(x1 - nx, y1, z1 - nz)
			var h := Vector3(x2 - nx, y2, z2 - nz)
			var bn := Vector3(-nx, 0, -nz).normalized()
			h_verts.append_array(PackedVector3Array([a, g, h, a, h, d]))
			h_norms.append_array(PackedVector3Array([bn, bn, bn, bn, bn, bn]))

		# Named garden label
		if not name_.is_empty():
			var ty: float = _loader._terrain_y(cx, cz)
			var label := Label3D.new()
			label.text = name_
			label.font_size = 24
			label.position = Vector3(cx, ty + 3.0, cz)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color(0.30, 0.55, 0.25, 0.65)
			label.outline_modulate = Color(0.05, 0.08, 0.03, 0.45)
			label.outline_size = 4
			label.no_depth_test = false
			label.pixel_size = 0.011
			_loader.add_child(label)
			label_count += 1

	if not h_verts.is_empty():
		var mesh: ArrayMesh = _loader._make_mesh(h_verts, h_norms)
		mesh.surface_set_material(0, hedge_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "GardenHedges"
		_loader.add_child(mi)

	print("  Gardens: %d hedged (%d labeled)" % [gardens.size(), label_count])


# ---------------------------------------------------------------------------
# Playgrounds — named locations with colored ground markers and labels
# ---------------------------------------------------------------------------
func _build_playgrounds(playgrounds: Array) -> void:
	var gs_sh2: Shader = _loader._get_shader("ground_surface", "res://shaders/ground_surface.gdshader")
	var pg_mat := ShaderMaterial.new()
	pg_mat.shader = gs_sh2
	pg_mat.set_shader_parameter("surface_color", Vector3(0.62, 0.42, 0.28))
	pg_mat.set_shader_parameter("base_roughness", 0.95)

	# Phase 1: Render playground polygons from landuse zones (real boundaries)
	var poly_count := 0
	var pg_verts := PackedVector3Array()
	var pg_normals := PackedVector3Array()
	var labeled_positions: Array = []  # avoid duplicate labels
	for zone in _loader.landuse_zones:
		if zone.get("type", "") != "playground":
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue
		var cx := 0.0; var cz := 0.0
		for pt in pts:
			cx += float(pt[0]); cz += float(pt[1])
		cx /= pts.size(); cz /= pts.size()
		if not _loader._in_boundary(cx, cz):
			continue
		var base_y: float = _loader._terrain_y(cx, cz) + 0.06
		# Triangulate polygon → flat surface
		var polygon := PackedVector2Array()
		for pt in pts:
			polygon.append(Vector2(float(pt[0]), float(pt[1])))
		var indices := Geometry2D.triangulate_polygon(polygon)
		for i in range(0, indices.size(), 3):
			pg_verts.append(Vector3(polygon[indices[i    ]].x, base_y, polygon[indices[i    ]].y))
			pg_verts.append(Vector3(polygon[indices[i + 1]].x, base_y, polygon[indices[i + 1]].y))
			pg_verts.append(Vector3(polygon[indices[i + 2]].x, base_y, polygon[indices[i + 2]].y))
			for _j in 3: pg_normals.append(Vector3.UP)
		# Label
		var name_: String = zone.get("name", "")
		if not name_.is_empty():
			var label := Label3D.new()
			label.text = name_
			label.font_size = 24
			label.position = Vector3(cx, base_y + 3.5, cz)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color(0.85, 0.55, 0.25, 0.70)
			label.outline_modulate = Color(0.1, 0.08, 0.05, 0.50)
			label.outline_size = 4
			label.no_depth_test = false
			label.pixel_size = 0.012
			_loader.add_child(label)
			labeled_positions.append(Vector2(cx, cz))
		poly_count += 1
	if not pg_verts.is_empty():
		var mesh: ArrayMesh = _loader._make_mesh(pg_verts, pg_normals)
		mesh.surface_set_material(0, pg_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "PlaygroundSurfaces"
		_loader.add_child(mi)

	# Phase 2: Point-based playgrounds (label-only, skip if polygon already covers it)
	var pt_count := 0
	for pg in playgrounds:
		var name2: String = pg.get("name", "")
		var pos: Array = pg.get("pos", [])
		if pos.size() < 2:
			continue
		var x: float = float(pos[0])
		var z: float = float(pos[1])
		if not _loader._in_boundary(x, z):
			continue
		# Skip if a polygon label is already nearby
		var has_poly := false
		for lp in labeled_positions:
			if (lp - Vector2(x, z)).length() < 50.0:
				has_poly = true
				break
		if has_poly:
			continue
		var ty: float = _loader._terrain_y(x, z)
		if not name2.is_empty():
			var label := Label3D.new()
			label.text = name2
			label.font_size = 24
			label.position = Vector3(x, ty + 3.5, z)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color(0.85, 0.55, 0.25, 0.70)
			label.outline_modulate = Color(0.1, 0.08, 0.05, 0.50)
			label.outline_size = 4
			label.no_depth_test = false
			label.pixel_size = 0.012
			_loader.add_child(label)
		pt_count += 1
	print("  Playgrounds: %d polygon + %d point" % [poly_count, pt_count])


# ---------------------------------------------------------------------------
# Facilities — visitor centers, dining, buildings with named labels
# ---------------------------------------------------------------------------
func _build_facilities(facilities: Array) -> void:
	if facilities.is_empty():
		return
	var count := 0
	var type_colors: Dictionary = {
		"visitor_center": Color(0.25, 0.50, 0.70, 0.70),
		"facility":       Color(0.50, 0.45, 0.35, 0.70),
		"building":       Color(0.55, 0.50, 0.42, 0.70),
		"dining":         Color(0.70, 0.45, 0.25, 0.70),
	}

	for fac in facilities:
		var name_: String = fac.get("name", "")
		var pos: Array = fac.get("pos", [])
		var ftype: String = fac.get("type", "facility")
		if pos.size() < 2:
			continue
		var x: float = float(pos[0])
		var z: float = float(pos[1])
		if not _loader._in_boundary(x, z):
			continue

		var ty: float = _loader._terrain_y(x, z)
		var col: Color = type_colors.get(ftype, Color(0.5, 0.5, 0.5, 0.70))

		# Label
		if not name_.is_empty():
			var label := Label3D.new()
			label.text = name_
			label.font_size = 28
			label.position = Vector3(x, ty + 4.0, z)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = col
			label.outline_modulate = Color(0.05, 0.05, 0.05, 0.50)
			label.outline_size = 5
			label.no_depth_test = false
			label.pixel_size = 0.012
			_loader.add_child(label)
		count += 1
	print("  Facilities: %d placed" % count)


# ---------------------------------------------------------------------------
# Decorative fountains — stone basin with water surface
# ---------------------------------------------------------------------------
func _build_fountains(amenities: Array) -> void:
	var fountains: Array = []
	for am in amenities:
		if am.get("type", "") == "fountain":
			fountains.append(am)
	if fountains.is_empty():
		return

	# Basin material — granite stone (uses stone shader for rain/snow/moss response)
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var basin_mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh, Color(0.58, 0.55, 0.50))

	# Water surface material — uses water shader for animated waves + weather
	var water_mat := ShaderMaterial.new()
	water_mat.shader = _loader._get_shader("water", "res://shaders/water.gdshader")
	if _loader._hm_texture:
		water_mat.set_shader_parameter("heightmap_tex", _loader._hm_texture)
		water_mat.set_shader_parameter("hm_world_size", _loader._hm_world_size)
		water_mat.set_shader_parameter("hm_min_h",      _loader._hm_min_h)
		water_mat.set_shader_parameter("hm_range",      _loader._hm_max_h - _loader._hm_min_h)
		water_mat.set_shader_parameter("hm_res",        float(mini(_loader._hm_width, 4096)))

	var count := 0
	for fnt in fountains:
		var pos: Array = fnt.get("position", [])
		if pos.size() < 3:
			continue
		var x: float = float(pos[0])
		var y: float = float(pos[1])
		var z: float = float(pos[2])
		if not _loader._in_boundary(x, z):
			continue

		var ty: float = _loader._terrain_y(x, z)
		y = maxf(y, ty)
		var name_: String = fnt.get("name", "")

		# Bethesda Fountain — handled by water_builder (photogrammetry from water body polygon)
		if "Bethesda" in name_:
			count += 1
			continue

		# Stone basin — short wide cylinder
		var basin_r := 2.5
		elif "Untermyer" in name_ or "Cherry Hill" in name_:
			basin_r = 3.5

		var basin: ArrayMesh = _loader._make_cylinder(basin_r, 0.6, 20)
		var bmi := MeshInstance3D.new()
		bmi.mesh = basin
		bmi.material_override = basin_mat
		bmi.position = Vector3(x, y + 0.3, z)
		_loader.add_child(bmi)

		# Water disc inside basin
		var water_disc: ArrayMesh = _loader._make_cylinder(basin_r - 0.15, 0.02, 20)
		var wmi := MeshInstance3D.new()
		wmi.mesh = water_disc
		wmi.material_override = water_mat
		wmi.position = Vector3(x, y + 0.55, z)
		_loader.add_child(wmi)

		# Label for named fountains
		if not name_.is_empty():
			var label := Label3D.new()
			label.text = name_
			label.font_size = 26
			label.position = Vector3(x, y + 3.0, z)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color(0.45, 0.60, 0.75, 0.65)
			label.outline_modulate = Color(0.05, 0.05, 0.05, 0.45)
			label.outline_size = 4
			label.no_depth_test = false
			label.pixel_size = 0.011
			_loader.add_child(label)

		count += 1
	print("  Fountains: %d placed" % count)


# ---------------------------------------------------------------------------
# Viewpoints — scenic overlooks with eye symbol labels
# ---------------------------------------------------------------------------
func _build_viewpoints(viewpoints: Array) -> void:
	if viewpoints.is_empty():
		return
	var count := 0
	for vp in viewpoints:
		var pos: Array = vp.get("position", [])
		if pos.size() < 3:
			continue
		var x: float = float(pos[0])
		var z: float = float(pos[2])
		if not _loader._in_boundary(x, z):
			continue
		var ty: float = _loader._terrain_y(x, z)
		var name_: String = vp.get("name", "")
		var label_text: String = name_ if not name_.is_empty() else "Viewpoint"

		var label := Label3D.new()
		label.text = label_text
		label.font_size = 22
		label.position = Vector3(x, ty + 3.0, z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.55, 0.70, 0.45, 0.60)
		label.outline_modulate = Color(0.05, 0.05, 0.05, 0.40)
		label.outline_size = 4
		label.no_depth_test = false
		label.pixel_size = 0.010
		_loader.add_child(label)
		count += 1
	print("  Viewpoints: %d placed" % count)


# ---------------------------------------------------------------------------
# Attractions — landmarks, zoo exhibits, museums, historic features
# ---------------------------------------------------------------------------
func _build_attractions(attractions: Array) -> void:
	if attractions.is_empty():
		return
	var subtype_colors: Dictionary = {
		"museum":  Color(0.60, 0.45, 0.30, 0.70),  # warm museum brown
		"fort":    Color(0.50, 0.50, 0.50, 0.70),  # gray fortification
		"cannon":  Color(0.50, 0.50, 0.50, 0.70),
		"castle":  Color(0.55, 0.48, 0.40, 0.70),
	}
	var default_col := Color(0.50, 0.60, 0.70, 0.65)  # blue-ish attraction
	var count := 0
	for att in attractions:
		var pos: Array = att.get("position", [])
		if pos.size() < 3:
			continue
		var x: float = float(pos[0])
		var z: float = float(pos[2])
		if not _loader._in_boundary(x, z):
			continue
		var name_: String = att.get("name", "")
		if name_.is_empty():
			continue  # skip unnamed attractions (zoo cages without labels, etc.)
		var subtype: String = att.get("subtype", "")
		var ty: float = _loader._terrain_y(x, z)
		var col: Color = subtype_colors.get(subtype, default_col)

		var label := Label3D.new()
		label.text = name_
		label.font_size = 26
		label.position = Vector3(x, ty + 3.5, z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = col
		label.outline_modulate = Color(0.05, 0.05, 0.05, 0.45)
		label.outline_size = 5
		label.no_depth_test = false
		label.pixel_size = 0.012
		_loader.add_child(label)
		count += 1
	print("  Attractions: %d placed" % count)


# ---------------------------------------------------------------------------
# Swimming pools — landuse polygons rendered as blue water surfaces
# ---------------------------------------------------------------------------
func _build_pools() -> void:
	var pools: Array = []
	for zone in _loader.landuse_zones:
		if zone.get("type", "") != "swimming_pool":
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue
		pools.append(zone)

	if pools.is_empty():
		return

	# Pool water material — slightly bluer and clearer than natural water
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = _loader._get_shader("water", "res://shaders/water.gdshader")
	if _loader._hm_texture:
		pool_mat.set_shader_parameter("heightmap_tex", _loader._hm_texture)
		pool_mat.set_shader_parameter("hm_world_size", _loader._hm_world_size)
		pool_mat.set_shader_parameter("hm_min_h",      _loader._hm_min_h)
		pool_mat.set_shader_parameter("hm_range",      _loader._hm_max_h - _loader._hm_min_h)
		pool_mat.set_shader_parameter("hm_res",        float(mini(_loader._hm_width, 4096)))

	var count := 0
	for pool in pools:
		var name_: String = pool.get("name", "")
		var pts: Array = pool["points"]

		# Compute centroid
		var cx := 0.0; var cz := 0.0
		for pt in pts:
			cx += float(pt[0]); cz += float(pt[1])
		cx /= pts.size(); cz /= pts.size()
		if not _loader._in_boundary(cx, cz):
			continue

		var ty: float = _loader._terrain_y(cx, cz) + 0.1

		# Triangulate polygon (fan from centroid)
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		for i in range(pts.size()):
			var j := (i + 1) % pts.size()
			var x0: float = float(pts[i][0])
			var z0: float = float(pts[i][1])
			var x1: float = float(pts[j][0])
			var z1: float = float(pts[j][1])
			verts.append(Vector3(cx, ty, cz))
			verts.append(Vector3(x0, ty, z0))
			verts.append(Vector3(x1, ty, z1))
			for _k in 3:
				normals.append(Vector3.UP)

		if verts.is_empty():
			continue

		var mesh: ArrayMesh = _loader._make_mesh(verts, normals)
		mesh.surface_set_material(0, pool_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "Pool_%s" % name_.replace(" ", "_")
		_loader.add_child(mi)

		# Pool edge — concrete rim
		var rim_verts := PackedVector3Array()
		var rim_normals := PackedVector3Array()
		var rim_h := 0.3
		for i in range(pts.size()):
			var j := (i + 1) % pts.size()
			var x0: float = float(pts[i][0])
			var z0: float = float(pts[i][1])
			var x1: float = float(pts[j][0])
			var z1: float = float(pts[j][1])
			var dx := x1 - x0; var dz := z1 - z0
			var ln := sqrt(dx * dx + dz * dz)
			if ln < 0.1:
				continue
			var fn := Vector3(-dz / ln, 0.0, dx / ln)
			var a := Vector3(x0, ty, z0)
			var b := Vector3(x1, ty, z1)
			var c := Vector3(x1, ty + rim_h, z1)
			var d := Vector3(x0, ty + rim_h, z0)
			rim_verts.append_array(PackedVector3Array([a, b, c, a, c, d]))
			for _k in 6:
				rim_normals.append(fn)

		if not rim_verts.is_empty():
			var rim_mesh: ArrayMesh = _loader._make_mesh(rim_verts, rim_normals)
			var rim_mat: Material = _loader._make_stone_material(
				_loader._load_tex("res://textures/rock_wall_diff.jpg"),
				_loader._load_tex("res://textures/rock_wall_nrm.jpg"),
				_loader._load_tex("res://textures/rock_wall_rgh.jpg"),
				Color(0.72, 0.70, 0.66))
			rim_mesh.surface_set_material(0, rim_mat)
			var rim_mi := MeshInstance3D.new()
			rim_mi.mesh = rim_mesh
			rim_mi.name = "PoolRim_%s" % name_.replace(" ", "_")
			_loader.add_child(rim_mi)

		# Label
		if not name_.is_empty():
			var label := Label3D.new()
			label.text = name_
			label.font_size = 24
			label.position = Vector3(cx, ty + 3.0, cz)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color(0.40, 0.60, 0.80, 0.65)
			label.outline_modulate = Color(0.05, 0.05, 0.05, 0.45)
			label.outline_size = 4
			label.no_depth_test = false
			label.pixel_size = 0.011
			_loader.add_child(label)

		count += 1
	if count > 0:
		print("  Swimming pools: %d placed" % count)


# ---------------------------------------------------------------------------
# Bandstands — raised concrete stage platforms
# ---------------------------------------------------------------------------
func _build_bandstands() -> void:
	var bandstands: Array = []
	for zone in _loader.landuse_zones:
		if zone.get("type", "") != "bandstand":
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue
		bandstands.append(zone)

	if bandstands.is_empty():
		return

	var stone_mat: Material = _loader._make_stone_material(
		_loader._load_tex("res://textures/rock_wall_diff.jpg"),
		_loader._load_tex("res://textures/rock_wall_nrm.jpg"),
		_loader._load_tex("res://textures/rock_wall_rgh.jpg"),
		Color(0.78, 0.76, 0.72))

	for zone in bandstands:
		var name_: String = zone.get("name", "")
		var pts: Array = zone["points"]

		# Compute centroid
		var cx := 0.0; var cz := 0.0
		for pt in pts:
			cx += float(pt[0]); cz += float(pt[1])
		cx /= pts.size(); cz /= pts.size()
		if not _loader._in_boundary(cx, cz):
			continue

		var base_y: float = _loader._terrain_y(cx, cz)
		var stage_h := 1.0  # raised 1m above ground

		# Stage floor — triangulated polygon at raised height
		var floor_verts := PackedVector3Array()
		var floor_norms := PackedVector3Array()
		var top_y := base_y + stage_h
		for i in range(pts.size()):
			var j := (i + 1) % pts.size()
			var x0 := float(pts[i][0]); var z0 := float(pts[i][1])
			var x1 := float(pts[j][0]); var z1 := float(pts[j][1])
			floor_verts.append(Vector3(cx, top_y, cz))
			floor_verts.append(Vector3(x0, top_y, z0))
			floor_verts.append(Vector3(x1, top_y, z1))
			for _k in 3: floor_norms.append(Vector3.UP)

		if not floor_verts.is_empty():
			var fm: ArrayMesh = _loader._make_mesh(floor_verts, floor_norms)
			fm.surface_set_material(0, stone_mat)
			var fmi := MeshInstance3D.new()
			fmi.mesh = fm
			fmi.name = "Bandstand_Floor_%s" % name_.replace(" ", "_")
			_loader.add_child(fmi)

		# Stage edge walls — vertical faces around perimeter
		var wall_verts := PackedVector3Array()
		var wall_norms := PackedVector3Array()
		for i in range(pts.size()):
			var j := (i + 1) % pts.size()
			var x0 := float(pts[i][0]); var z0 := float(pts[i][1])
			var x1 := float(pts[j][0]); var z1 := float(pts[j][1])
			var dx := x1 - x0; var dz := z1 - z0
			var ln := sqrt(dx * dx + dz * dz)
			if ln < 0.1:
				continue
			var fn := Vector3(-dz / ln, 0.0, dx / ln)
			var by: float = _loader._terrain_y((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var a := Vector3(x0, by, z0)
			var b := Vector3(x1, by, z1)
			var c := Vector3(x1, top_y, z1)
			var d := Vector3(x0, top_y, z0)
			wall_verts.append_array(PackedVector3Array([a, b, c, a, c, d]))
			for _k in 6: wall_norms.append(fn)

		if not wall_verts.is_empty():
			var wm: ArrayMesh = _loader._make_mesh(wall_verts, wall_norms)
			wm.surface_set_material(0, stone_mat)
			var wmi := MeshInstance3D.new()
			wmi.mesh = wm
			wmi.name = "Bandstand_Wall_%s" % name_.replace(" ", "_")
			_loader.add_child(wmi)

		# Label
		if not name_.is_empty():
			var label := Label3D.new()
			label.text = name_
			label.font_size = 28
			label.position = Vector3(cx, top_y + 3.0, cz)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = Color(0.85, 0.80, 0.70, 0.65)
			label.outline_modulate = Color(0.10, 0.08, 0.05, 0.45)
			label.outline_size = 4
			label.no_depth_test = false
			label.pixel_size = 0.011
			_loader.add_child(label)

	print("  Bandstands: %d placed" % bandstands.size())


func _build_meadow_labels() -> void:
	## Labels for named grass zones — major park landmarks like Sheep Meadow, Great Hill.
	var count := 0
	for zone in _loader.landuse_zones:
		if zone.get("type", "") != "grass":
			continue
		var name_: String = zone.get("name", "")
		if name_.is_empty():
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue
		# Compute centroid of the grass polygon
		var cx := 0.0; var cz := 0.0
		for pt in pts:
			cx += float(pt[0]); cz += float(pt[1])
		cx /= pts.size(); cz /= pts.size()
		if not _loader._in_boundary(cx, cz):
			continue
		var cy: float = _loader._terrain_y(cx, cz)
		# Ground-level label — soft green tint, visible from a distance
		var label := Label3D.new()
		label.text = name_
		label.font_size = 36
		label.position = Vector3(cx, cy + 4.0, cz)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.42, 0.56, 0.35, 0.55)
		label.outline_modulate = Color(0.08, 0.10, 0.05, 0.40)
		label.outline_size = 5
		label.no_depth_test = false
		label.pixel_size = 0.015
		_loader.add_child(label)
		count += 1
	if count > 0:
		print("  Meadow labels: %d named grass zones" % count)


func _build_shrubbery(shrubbery_data: Array) -> void:
	## Decorative shrubbery beds from OSM natural=shrubbery.
	## Rendered as low-profile hedge volumes following the polygon outline.
	if shrubbery_data.is_empty():
		return
	var hedge_sh: Shader = _loader._get_shader("hedge", "res://shaders/hedge.gdshader")
	var hedge_mat := ShaderMaterial.new()
	hedge_mat.shader = hedge_sh
	var shrub_verts := PackedVector3Array()
	var shrub_normals := PackedVector3Array()
	var col_verts := PackedVector3Array()
	var shrub_h := 0.6  # low ornamental shrubs
	for shrub in shrubbery_data:
		var pts: Array = shrub.get("points", [])
		if pts.size() < 3:
			continue
		# Build filled polygon (fan from centroid) for top surface
		var cx := 0.0; var cz := 0.0
		for pt in pts:
			cx += float(pt[0]); cz += float(pt[1])
		cx /= pts.size(); cz /= pts.size()
		if not _loader._in_boundary(cx, cz):
			continue
		var base_y: float = _loader._terrain_y(cx, cz)
		var top_y := base_y + shrub_h
		# Top surface (triangulated fan)
		for i in range(pts.size()):
			var j := (i + 1) % pts.size()
			var x0 := float(pts[i][0]); var z0 := float(pts[i][1])
			var x1 := float(pts[j][0]); var z1 := float(pts[j][1])
			shrub_verts.append(Vector3(cx, top_y, cz))
			shrub_verts.append(Vector3(x0, top_y, z0))
			shrub_verts.append(Vector3(x1, top_y, z1))
			for _k in 3: shrub_normals.append(Vector3.UP)
		# Side walls
		for i in range(pts.size()):
			var j := (i + 1) % pts.size()
			var x0 := float(pts[i][0]); var z0 := float(pts[i][1])
			var x1 := float(pts[j][0]); var z1 := float(pts[j][1])
			var dx := x1 - x0; var dz := z1 - z0
			var ln := sqrt(dx * dx + dz * dz)
			if ln < 0.05:
				continue
			var fn := Vector3(-dz / ln, 0.0, dx / ln)
			var by: float = _loader._terrain_y((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			shrub_verts.append(Vector3(x0, by, z0))
			shrub_verts.append(Vector3(x1, by, z1))
			shrub_verts.append(Vector3(x1, top_y, z1))
			shrub_verts.append(Vector3(x0, by, z0))
			shrub_verts.append(Vector3(x1, top_y, z1))
			shrub_verts.append(Vector3(x0, top_y, z0))
			for _k in 6: shrub_normals.append(fn)
			# Collision
			col_verts.append(Vector3(x0, by, z0))
			col_verts.append(Vector3(x1, by, z1))
			col_verts.append(Vector3(x1, top_y, z1))
			col_verts.append(Vector3(x0, by, z0))
			col_verts.append(Vector3(x1, top_y, z1))
			col_verts.append(Vector3(x0, top_y, z0))
	if not shrub_verts.is_empty():
		var mesh: ArrayMesh = _loader._make_mesh(shrub_verts, shrub_normals)
		mesh.surface_set_material(0, hedge_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "Shrubbery"
		_loader.add_child(mi)
	if not col_verts.is_empty():
		var body := StaticBody3D.new()
		body.name = "Shrubbery_Col"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_verts)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_loader.add_child(body)
	print("  Shrubbery: %d areas" % shrubbery_data.size())


func _build_special_zone_labels() -> void:
	## Labels for notable special landuse zones — nature reserves, sports centres, etc.
	var label_types := ["nature_reserve", "sports_centre", "industrial"]
	var type_colors: Dictionary = {
		"nature_reserve": Color(0.30, 0.55, 0.25, 0.60),  # forest green
		"sports_centre":  Color(0.45, 0.50, 0.60, 0.55),  # neutral blue-gray
		"industrial":     Color(0.55, 0.50, 0.45, 0.50),  # neutral warm
	}
	var count := 0
	for zone in _loader.landuse_zones:
		var ztype: String = zone.get("type", "")
		if ztype not in label_types:
			continue
		var name_: String = zone.get("name", "")
		if name_.is_empty():
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue
		var cx := 0.0; var cz := 0.0
		for pt in pts:
			cx += float(pt[0]); cz += float(pt[1])
		cx /= pts.size(); cz /= pts.size()
		if not _loader._in_boundary(cx, cz):
			continue
		var cy: float = _loader._terrain_y(cx, cz)
		var label := Label3D.new()
		label.text = name_
		label.font_size = 32
		label.position = Vector3(cx, cy + 4.5, cz)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = type_colors.get(ztype, Color(0.5, 0.5, 0.5, 0.55))
		label.outline_modulate = Color(0.05, 0.08, 0.05, 0.40)
		label.outline_size = 5
		label.no_depth_test = false
		label.pixel_size = 0.013
		_loader.add_child(label)
		count += 1
	if count > 0:
		print("  Special zone labels: %d" % count)
