# boundary_builder.gd
# Park boundary: collision walls, perimeter schist wall, gate pillars, building labels.

var _loader  # Reference to park_loader for shared utilities

func _init(loader) -> void:
	_loader = loader


func _build_boundary(boundary: Array) -> void:
	if boundary.size() < 3:
		push_warning("ParkLoader: boundary too small – skipping walls")
		return

	# Invisible collision walls (functional — keep player inside park)
	var body := StaticBody3D.new()
	body.name = "BoundaryWalls"
	_loader.add_child(body)

	var n := boundary.size()
	for i in range(n):
		var p1 := Vector2(float(boundary[i][0]),           float(boundary[i][1]))
		var p2 := Vector2(float(boundary[(i + 1) % n][0]), float(boundary[(i + 1) % n][1]))

		var seg_len := p1.distance_to(p2)
		if seg_len < 0.3:
			continue

		var mid := (p1 + p2) * 0.5
		var dir := (p2 - p1) / seg_len

		var box  := BoxShape3D.new()
		box.size  = Vector3(seg_len, 80.0, 0.5)

		var col      := CollisionShape3D.new()
		col.shape     = box
		col.position  = Vector3(mid.x, 40.0, mid.y)
		col.rotation.y = atan2(-dir.y, dir.x)

		body.add_child(col)


# ---------------------------------------------------------------------------
# Perimeter wall — Central Park's Manhattan schist wall
# ---------------------------------------------------------------------------
func _build_perimeter_wall(boundary: Array, paths: Array) -> void:
	## Real dimensions: 1.17m tall, 0.45m thick, batted inner cap (~15°).
	## Gate openings where park paths cross the boundary polygon.
	## Granite gate pillars (2.4m tall, capstone overhang) flank each gate.
	if boundary.size() < 3:
		return

	var WALL_H := 1.17
	var WALL_T := 0.45
	var BATTER := tan(deg_to_rad(15.0))  # inner cap slope
	var GATE_R := 4.0  # gate half-width (metres)

	# Stone material — Manhattan schist (weather-responsive)
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var wall_mat: ShaderMaterial = _loader._make_stone_material(
		rw_alb, rw_nrm, rw_rgh, Color(0.48, 0.46, 0.42))

	# --- Find gate positions: path segments crossing the boundary ---
	var gate_positions: Array = []  # Array of Vector2
	for path in paths:
		if path.get("bridge", false) or path.get("tunnel", false):
			continue
		var hw: String = str(path.get("highway", "path"))
		if hw == "steps" or hw == "track" or hw == "bridleway":
			continue
		var ppts: Array = path["points"]
		if ppts.size() < 2:
			continue
		for pi in range(ppts.size() - 1):
			var ax := float(ppts[pi][0]);   var az := float(ppts[pi][2])
			var bx := float(ppts[pi+1][0]); var bz := float(ppts[pi+1][2])
			if _loader._in_boundary(ax, az) == _loader._in_boundary(bx, bz):
				continue
			# Boundary crossing — gate at midpoint
			var gx := (ax + bx) * 0.5
			var gz := (az + bz) * 0.5
			var too_close := false
			for gp in gate_positions:
				if Vector2(gx, gz).distance_to(gp) < GATE_R * 2.5:
					too_close = true
					break
			if not too_close:
				gate_positions.append(Vector2(gx, gz))
	print("ParkLoader: perimeter wall gates = %d" % gate_positions.size())

	# --- Boundary centroid for determining inward normal ---
	var cx := 0.0; var cz := 0.0
	for pt in boundary:
		cx += float(pt[0]); cz += float(pt[1])
	cx /= float(boundary.size()); cz /= float(boundary.size())

	# --- Build wall geometry ---
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()

	var bn := boundary.size()
	var cum_d := 0.0
	for i in range(bn):
		var p1 := Vector2(float(boundary[i][0]), float(boundary[i][1]))
		var p2 := Vector2(float(boundary[(i + 1) % bn][0]), float(boundary[(i + 1) % bn][1]))
		var seg_len := p1.distance_to(p2)
		if seg_len < 0.5:
			cum_d += seg_len
			continue

		# Subdivide long segments for smooth curves
		var n_sub := int(ceil(seg_len / 5.0))
		for si in n_sub:
			var t0 := float(si) / float(n_sub)
			var t1 := float(si + 1) / float(n_sub)
			var a := p1.lerp(p2, t0)
			var b := p1.lerp(p2, t1)
			var sub_len := a.distance_to(b)

			# Skip segments near gate positions
			var mid := (a + b) * 0.5
			var is_gate := false
			for gp in gate_positions:
				if mid.distance_to(gp) < GATE_R:
					is_gate = true
					break
			if is_gate:
				cum_d += sub_len
				continue

			var dir := (b - a) / sub_len if sub_len > 0.01 else Vector2.RIGHT
			# Inward normal (toward park centroid)
			var nrm2 := Vector2(-dir.y, dir.x)
			if nrm2.dot(Vector2(cx - a.x, cz - a.y)) < 0.0:
				nrm2 = -nrm2
			var outward := -nrm2

			var ya: float = _loader._terrain_y(a.x, a.y) - 0.02
			var yb: float = _loader._terrain_y(b.x, b.y) - 0.02
			var ht := WALL_T * 0.5

			# 4 corners at each end: outer/inner × a/b
			var oa := Vector2(a.x + outward.x * ht, a.y + outward.y * ht)
			var ob := Vector2(b.x + outward.x * ht, b.y + outward.y * ht)
			var ia := Vector2(a.x - outward.x * ht, a.y - outward.y * ht)
			var ib := Vector2(b.x - outward.x * ht, b.y - outward.y * ht)

			var u0 := cum_d / 1.5  # UV tiling at 1.5m horizontal repeat
			var u1 := (cum_d + sub_len) / 1.5
			var v_top := WALL_H / 1.5

			# Outer face (vertical, facing away from park)
			var on3 := Vector3(outward.x, 0.0, outward.y)
			verts.append_array(PackedVector3Array([
				Vector3(oa.x, ya, oa.y), Vector3(ob.x, yb, ob.y),
				Vector3(ob.x, yb + WALL_H, ob.y), Vector3(oa.x, ya + WALL_H, oa.y)]))
			for _j in 4: normals.append(on3)
			uvs.append_array(PackedVector2Array([
				Vector2(u0, 0.0), Vector2(u1, 0.0),
				Vector2(u1, v_top), Vector2(u0, v_top)]))

			# Inner face (vertical, facing into park)
			var in3 := Vector3(-outward.x, 0.0, -outward.y)
			verts.append_array(PackedVector3Array([
				Vector3(ib.x, yb, ib.y), Vector3(ia.x, ya, ia.y),
				Vector3(ia.x, ya + WALL_H, ia.y), Vector3(ib.x, yb + WALL_H, ib.y)]))
			for _j in 4: normals.append(in3)
			uvs.append_array(PackedVector2Array([
				Vector2(u1, 0.0), Vector2(u0, 0.0),
				Vector2(u0, v_top), Vector2(u1, v_top)]))

			# Slanted cap (outer at full height, inner edge lower = batter)
			var cap_inner_h := WALL_H - WALL_T * BATTER
			var cap_n := Vector3(-outward.x * BATTER, 1.0, -outward.y * BATTER).normalized()
			verts.append_array(PackedVector3Array([
				Vector3(oa.x, ya + WALL_H, oa.y), Vector3(ob.x, yb + WALL_H, ob.y),
				Vector3(ib.x, yb + cap_inner_h, ib.y), Vector3(ia.x, ya + cap_inner_h, ia.y)]))
			for _j in 4: normals.append(cap_n)
			uvs.append_array(PackedVector2Array([
				Vector2(u0, 0.0), Vector2(u1, 0.0),
				Vector2(u1, WALL_T / 1.5), Vector2(u0, WALL_T / 1.5)]))

			cum_d += sub_len

	if verts.is_empty():
		return

	# Build indexed mesh from quad data
	var indices := PackedInt32Array()
	var n_quads := verts.size() / 4
	for qi in n_quads:
		var b2 := qi * 4
		indices.append_array(PackedInt32Array([b2, b2+1, b2+2, b2, b2+2, b2+3]))
	var mesh: ArrayMesh = _loader._make_mesh(verts, normals, uvs, null, indices)
	mesh.surface_set_material(0, wall_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "PerimeterWall"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_loader.add_child(mi)

	# Wall collision
	var col_body := StaticBody3D.new()
	col_body.name = "PerimeterWallCollision"
	var tri_verts := PackedVector3Array()
	for qi in n_quads:
		var b2 := qi * 4
		tri_verts.append(verts[b2]); tri_verts.append(verts[b2+1]); tri_verts.append(verts[b2+2])
		tri_verts.append(verts[b2]); tri_verts.append(verts[b2+2]); tri_verts.append(verts[b2+3])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tri_verts)
	var col := CollisionShape3D.new()
	col.shape = shape
	col_body.add_child(col)
	_loader.add_child(col_body)

	print("ParkLoader: perimeter wall = %d segments, %d quads" % [bn, n_quads])

	# --- Gate pillars — dressed granite posts flanking each gate opening ---
	_build_gate_pillars(boundary, gate_positions, cx, cz, GATE_R,
		rw_alb, rw_nrm, rw_rgh)


func _build_gate_pillars(boundary: Array, gate_positions: Array,
		cx: float, cz: float, gate_r: float,
		alb: ImageTexture, nrm: ImageTexture, rgh: ImageTexture) -> void:
	## Paired granite pillars (2.4m tall, capstone overhang) at each gate.
	if gate_positions.is_empty():
		return
	var PILLAR_W := 0.55
	var PILLAR_H := 2.4
	var CAP_HANG := 0.08

	# Lighter dressed granite (vs darker schist wall)
	var pillar_mat: ShaderMaterial = _loader._make_stone_material(
		alb, nrm, rgh, Color(0.62, 0.60, 0.56))

	var p_verts := PackedVector3Array()
	var p_norms := PackedVector3Array()

	for gp in gate_positions:
		# Find wall direction at nearest boundary segment
		var best_dir := Vector2.RIGHT
		var best_d := INF
		for bi in range(boundary.size()):
			var bp1 := Vector2(float(boundary[bi][0]), float(boundary[bi][1]))
			var bp2 := Vector2(float(boundary[(bi + 1) % boundary.size()][0]),
				float(boundary[(bi + 1) % boundary.size()][1]))
			var seg := bp2 - bp1
			var sl := seg.length()
			if sl < 0.5: continue
			var t := clampf(seg.dot(gp - bp1) / (sl * sl), 0.0, 1.0)
			var d: float = gp.distance_to(bp1 + seg * t)
			if d < best_d:
				best_d = d
				best_dir = seg.normalized()

		var gy: float = _loader._terrain_y(gp.x, gp.y) - 0.02

		# Two pillars at ±(gate_radius + pillar_width/2) along wall direction
		for side in [-1.0, 1.0]:
			var offset: Vector2 = best_dir * (gate_r + PILLAR_W * 0.5) * side
			var pc := gp + offset
			var phw := PILLAR_W * 0.5
			var py: float = _loader._terrain_y(pc.x, pc.y) - 0.02

			# 4 vertical faces
			var face_data := [
				[Vector3(1, 0, 0),  Vector2(phw, 0.0),  Vector2(phw, 0.0)],   # +X
				[Vector3(-1, 0, 0), Vector2(-phw, 0.0),  Vector2(-phw, 0.0)],  # -X
				[Vector3(0, 0, 1),  Vector2(0.0, phw),  Vector2(0.0, phw)],    # +Z
				[Vector3(0, 0, -1), Vector2(0.0, -phw), Vector2(0.0, -phw)],   # -Z
			]
			for face in face_data:
				var fn: Vector3 = face[0]
				# Build quad corners based on face normal direction
				var ax_dir := Vector3(1.0 - absf(fn.x), 0.0, 0.0) if absf(fn.x) < 0.5 else Vector3(0.0, 0.0, 1.0)
				var c0 := Vector3(pc.x + fn.x * phw - ax_dir.x * phw, py,
					pc.y + fn.z * phw - ax_dir.z * phw)
				var c1 := Vector3(pc.x + fn.x * phw + ax_dir.x * phw, py,
					pc.y + fn.z * phw + ax_dir.z * phw)
				var c2 := Vector3(c1.x, py + PILLAR_H, c1.z)
				var c3 := Vector3(c0.x, py + PILLAR_H, c0.z)
				p_verts.append_array(PackedVector3Array([c0, c1, c2, c0, c2, c3]))
				for _j in 6: p_norms.append(fn)

			# Capstone top face (wider than pillar body)
			var cw := phw + CAP_HANG
			var cap_y := py + PILLAR_H
			p_verts.append_array(PackedVector3Array([
				Vector3(pc.x - cw, cap_y, pc.y - cw),
				Vector3(pc.x + cw, cap_y, pc.y - cw),
				Vector3(pc.x + cw, cap_y, pc.y + cw),
				Vector3(pc.x - cw, cap_y, pc.y - cw),
				Vector3(pc.x + cw, cap_y, pc.y + cw),
				Vector3(pc.x - cw, cap_y, pc.y + cw)]))
			for _j in 6: p_norms.append(Vector3.UP)

	if not p_verts.is_empty():
		var mesh: ArrayMesh = _loader._make_mesh(p_verts, p_norms)
		mesh.surface_set_material(0, pillar_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "GatePillars"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_loader.add_child(mi)
		print("ParkLoader: gate pillars = %d" % (gate_positions.size() * 2))


func _label_boundary_buildings(buildings: Array) -> void:
	## Add Label3D name tags to named buildings near the park boundary.
	var count := 0
	for b in buildings:
		var bname: String = str(b.get("name", ""))
		if bname.is_empty():
			continue
		var pts: Array = b.get("points", [])
		if pts.size() < 3:
			continue

		var cx := 0.0
		var cz := 0.0
		for pt in pts:
			cx += float(pt[0])
			cz += float(pt[1])
		cx /= float(pts.size())
		cz /= float(pts.size())

		# Skip buildings inside the park — only perimeter buildings
		if _loader._in_boundary(cx, cz):
			continue

		# Must be close to park boundary (within 200m)
		var min_dist := 999999.0
		for bp in _loader.boundary_polygon:
			var d := Vector2(cx - bp.x, cz - bp.y).length()
			if d < min_dist:
				min_dist = d
		if min_dist > 200.0:
			continue

		var bld_h: float = float(b.get("height", 15.0))
		var ty: float = _loader._terrain_y(cx, cz)
		var label_y := ty + bld_h * 0.6

		var lbl := Label3D.new()
		lbl.text = bname
		lbl.font_size = 36
		lbl.pixel_size = 0.008
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = Color(0.70, 0.68, 0.64, 0.45)
		lbl.outline_size = 4
		lbl.outline_modulate = Color(0.08, 0.08, 0.08, 0.30)
		lbl.no_depth_test = false
		lbl.position = Vector3(cx, label_y, cz)
		_loader.add_child(lbl)
		count += 1

	if count > 0:
		print("ParkLoader: building labels = %d" % count)
