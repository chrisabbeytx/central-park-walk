# bridge_builder.gd
# Bridge geometry: 5 styles (stone, cast iron, brick, rustic wood, Bow Bridge)
# Extracted from park_loader.gd — all shared utilities accessed via _loader reference.

var _loader  # Reference to park_loader for shared utilities

func _init(loader) -> void:
	_loader = loader


func _build_bridge(path: Dictionary) -> void:
	var hw:   String = str(path.get("highway", "path"))
	var surf: String = str(path.get("surface", ""))
	var bridge_name: String = str(path.get("bridge_name", ""))
	var raw_pts: Array = path["points"]
	if raw_pts.size() < 2:
		return

	# Smooth curves then subdivide so we have at least 1 point per ~2 metres for smooth ramps.
	var smoothed: Array = _loader._smooth_path_catmull_rom(raw_pts) if raw_pts.size() >= 3 else raw_pts
	var pts: Array = _loader._subdivide_pts(smoothed, 2.0)
	# Snap Y to actual terrain so bridge clearance is computed from the rendered surface
	for i in range(pts.size()):
		pts[i] = [pts[i][0], _loader._terrain_y(float(pts[i][0]), float(pts[i][2])), pts[i][2]]
	var n_pts := pts.size()

	var width: float = _loader._path_width(path)
	var hw2   := width * 0.5

	# CC0 rock wall texture for parapets / abutments
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")

	# ----------------------------------------------------------------
	# Cumulative arc lengths
	# ----------------------------------------------------------------
	var cum_len := PackedFloat32Array()
	cum_len.resize(n_pts)
	cum_len[0] = 0.0
	for i in range(1, n_pts):
		var dx := float(pts[i][0]) - float(pts[i-1][0])
		var dz := float(pts[i][2]) - float(pts[i-1][2])
		cum_len[i] = cum_len[i-1] + sqrt(dx*dx + dz*dz)
	var total_len := cum_len[n_pts - 1]
	if total_len < 0.1:
		return
	var ramp_len: float = total_len * _loader.BRIDGE_RAMP_FRAC

	# Precompute miter offset direction at each path point — shared by walls/curbs/parapets
	var bridge_miter: Array[Vector2] = _loader._compute_miter_normals(pts, n_pts)

	# Determine bridge style (needs total_len for unnamed heuristics)
	var style: int = _loader._bridge_style(bridge_name, surf, total_len)
	var _style_names := {_loader.BridgeStyle.STONE: "STONE", _loader.BridgeStyle.CAST_IRON: "CAST_IRON",
		_loader.BridgeStyle.RUSTIC_WOOD: "RUSTIC_WOOD", _loader.BridgeStyle.BRICK: "BRICK",
		_loader.BridgeStyle.DRIVE: "DRIVE"}
	var _label: String = bridge_name if not bridge_name.is_empty() else "(unnamed %.0fm)" % total_len
	print("  Bridge: ", _label, " → ", _style_names.get(style, "STONE"))

	# Per-style material tints — Manhattan schist gray for stone (Wikimedia reference)
	var soffit_tint := Color(0.52, 0.50, 0.46)   # schist gray
	var parapet_tint := Color(0.56, 0.54, 0.50)  # dressed stone
	var abut_tint := Color(0.50, 0.48, 0.44)     # schist gray
	match style:
		_loader.BridgeStyle.CAST_IRON:
			soffit_tint = Color(0.46, 0.35, 0.28)  # warm reddish-brown iron paint
			parapet_tint = Color(0.50, 0.38, 0.30)  # matching iron color
			abut_tint = Color(0.48, 0.44, 0.40)     # stone abutments
		_loader.BridgeStyle.BRICK:
			soffit_tint = Color(0.60, 0.40, 0.30)
			parapet_tint = Color(0.65, 0.42, 0.32)
			abut_tint = Color(0.62, 0.41, 0.31)

	# --- GAPSTOW BRIDGE HERO TREATMENT ---
	if bridge_name == "Gapstow Bridge":
		_build_gapstow_bridge(pts, cum_len, total_len, width, rw_alb, rw_nrm, rw_rgh, bridge_miter)
		return

	# Terrain heights at the two endpoints
	var y_start := float(pts[0][1])
	var y_end   := float(pts[n_pts - 1][1])

	# Deck clearance: scale with bridge length
	#   Short bridges (< 10m): stream crossings, ~0.8m rise (gentle hump)
	#   Medium (10-25m):  scale linearly 0.8 → 3.5m
	#   Long (> 25m):     full 3.5m clearance (pedestrian underpass height)
	var eff_clearance: float
	if total_len < 10.0:
		eff_clearance = 0.8
	elif total_len < 25.0:
		eff_clearance = lerpf(0.8, _loader.BRIDGE_CLEARANCE, (total_len - 10.0) / 15.0)
	else:
		eff_clearance = _loader.BRIDGE_CLEARANCE

	var min_y_mid := INF
	for i in range(n_pts):
		if cum_len[i] >= ramp_len and cum_len[i] <= total_len - ramp_len:
			min_y_mid = minf(min_y_mid, float(pts[i][1]))
	if min_y_mid == INF:
		min_y_mid = y_start
		for pt in pts:
			min_y_mid = minf(min_y_mid, float(pt[1]))
	var deck_y := maxf(min_y_mid + eff_clearance,
					   maxf(y_start + 0.5, y_end + 0.5))

	# ----------------------------------------------------------------
	# Per-point smooth bridge height (S-curve ramp at both ends)
	# Ramp starts 0.15m BELOW terrain so collision mesh slopes into
	# the ground — prevents a vertical wall at the bridge entrance.
	# ----------------------------------------------------------------
	var pt_y := PackedFloat32Array()
	pt_y.resize(n_pts)
	var ramp_sink := 0.15
	# Bow Bridge: gentle longitudinal arch (1.2m rise at center)
	var is_bow := bridge_name == "Bow Bridge"
	var bow_rise := 1.2 if is_bow else 0.0
	for i in range(n_pts):
		var d := cum_len[i]
		var t: float
		var y: float
		if d <= ramp_len:
			t = d / ramp_len
			t = t * t * (3.0 - 2.0 * t)   # smoothstep
			y = lerpf(y_start + _loader.PATH_Y - ramp_sink, deck_y, t)
		elif d >= total_len - ramp_len:
			t = (total_len - d) / ramp_len
			t = t * t * (3.0 - 2.0 * t)   # smoothstep
			y = lerpf(y_end + _loader.PATH_Y - ramp_sink, deck_y, t)
		else:
			y = deck_y
		# Add gentle bow arch to mid-span
		if bow_rise > 0.0:
			var frac := d / total_len
			y += bow_rise * sin(frac * PI)
		pt_y[i] = y

	# ----------------------------------------------------------------
	# Deck — use outline polygon if available, otherwise ribbon
	# ----------------------------------------------------------------
	var path_cx := (float(pts[0][0]) + float(pts[n_pts-1][0])) * 0.5
	var path_cz := (float(pts[0][2]) + float(pts[n_pts-1][2])) * 0.5
	var outline_pts: Array = _loader._find_bridge_outline(path_cx, path_cz, bridge_name)

	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs     := PackedVector2Array()

	if outline_pts.size() >= 4:
		# --- Outline polygon deck ---
		# Remove closing duplicate
		var op := outline_pts.duplicate()
		if op.size() > 3:
			var odx := float(op[0][0]) - float(op[-1][0])
			var odz := float(op[0][2]) - float(op[-1][2])
			if odx * odx + odz * odz < 4.0:
				op = op.slice(0, -1)
		# Build 2D polygon for triangulation
		var poly2d := PackedVector2Array()
		poly2d.resize(op.size())
		for oi in range(op.size()):
			poly2d[oi] = Vector2(float(op[oi][0]), float(op[oi][2]))
		var tri_idx: PackedInt32Array = _loader._triangulate_polygon_2d(poly2d)
		if tri_idx.size() >= 3:
			# Compute Y for each outline vertex by projecting onto centerline
			var oy := PackedFloat32Array()
			oy.resize(op.size())
			for oi in range(op.size()):
				var arc: float = _loader._project_onto_polyline(float(op[oi][0]), float(op[oi][2]),
						pts, cum_len)
				# Interpolate pt_y at this arc length
				var yi := deck_y
				for pi in range(n_pts - 1):
					if cum_len[pi + 1] >= arc:
						var seg_t := 0.0
						var seg_d := cum_len[pi + 1] - cum_len[pi]
						if seg_d > 0.001:
							seg_t = (arc - cum_len[pi]) / seg_d
						yi = lerpf(pt_y[pi], pt_y[pi + 1], seg_t)
						break
				oy[oi] = yi
			# Compute centroid for UV mapping
			var ucx := 0.0; var ucz := 0.0
			for oi in range(op.size()):
				ucx += poly2d[oi].x; ucz += poly2d[oi].y
			ucx /= op.size(); ucz /= op.size()
			# Build triangle verts
			for ti in range(0, tri_idx.size(), 3):
				var i0 := tri_idx[ti]; var i1 := tri_idx[ti+1]; var i2 := tri_idx[ti+2]
				var v0 := Vector3(poly2d[i0].x, oy[i0], poly2d[i0].y)
				var v1 := Vector3(poly2d[i1].x, oy[i1], poly2d[i1].y)
				var v2 := Vector3(poly2d[i2].x, oy[i2], poly2d[i2].y)
				verts.append_array(PackedVector3Array([v0, v1, v2]))
				var tn := (v1 - v0).cross(v2 - v0).normalized()
				if tn.y < 0.0: tn = -tn
				for _j in 3: normals.append(tn)
				uvs.append_array(PackedVector2Array([
					Vector2((poly2d[i0].x - ucx) / width, (poly2d[i0].y - ucz) / width),
					Vector2((poly2d[i1].x - ucx) / width, (poly2d[i1].y - ucz) / width),
					Vector2((poly2d[i2].x - ucx) / width, (poly2d[i2].y - ucz) / width),
				]))
			print("    → outline deck: ", op.size(), " verts, ", tri_idx.size() / 3, " tris")
	else:
		# --- Ribbon deck (default) ---
		var u := 0.0
		for i in range(n_pts - 1):
			var p1 := Vector3(float(pts[i][0]),     pt_y[i],     float(pts[i][2]))
			var p2 := Vector3(float(pts[i+1][0]),   pt_y[i+1],   float(pts[i+1][2]))
			var seg2 := Vector2(p2.x - p1.x, p2.z - p1.z)
			if seg2.length_squared() < 0.0001:
				continue
			var seg_len := seg2.length()
			var dv := seg2 / seg_len
			var nv := Vector2(-dv.y, dv.x)
			var a  := Vector3(p1.x + nv.x * hw2, p1.y, p1.z + nv.y * hw2)
			var b  := Vector3(p1.x - nv.x * hw2, p1.y, p1.z - nv.y * hw2)
			var c  := Vector3(p2.x + nv.x * hw2, p2.y, p2.z + nv.y * hw2)
			var dd := Vector3(p2.x - nv.x * hw2, p2.y, p2.z - nv.y * hw2)
			var u2 := u + seg_len / width
			verts.append_array(PackedVector3Array([a, b, c, b, dd, c]))
			var quad_n := (b - a).cross(c - a).normalized()
			if quad_n.y < 0.0:
				quad_n = -quad_n
			for _i in range(6):
				normals.append(quad_n)
			uvs.append_array(PackedVector2Array([
				Vector2(u, 0.0), Vector2(u, 1.0), Vector2(u2, 0.0),
				Vector2(u, 1.0), Vector2(u2, 1.0), Vector2(u2, 0.0),
			]))
			u = u2

	if not verts.is_empty():
		var deck_mesh: ArrayMesh = _loader._make_mesh(verts, normals, uvs)
		deck_mesh.surface_set_material(0, _loader._make_bridge_deck_material(hw, surf))
		var deck_mi := MeshInstance3D.new()
		deck_mi.mesh = deck_mesh
		deck_mi.name = "Bridge_Deck"
		_loader.add_child(deck_mi)

		# Walkable collision from deck triangles
		var body  := StaticBody3D.new()
		body.name  = "Bridge_Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(verts)
		var col   := CollisionShape3D.new()
		col.shape  = shape
		body.add_child(col)
		_loader.add_child(body)

	# ----------------------------------------------------------------
	# Soffit (underside of deck) — arched for STONE/BRICK >= 12m, flat otherwise
	# ----------------------------------------------------------------
	var sof_verts   := PackedVector3Array()
	var sof_normals := PackedVector3Array()
	var sof_uvs     := PackedVector2Array()
	var _skip_soffit := total_len < 10.0
	var edge_verts  := PackedVector3Array()
	var edge_norms  := PackedVector3Array()
	var u_s := 0.0
	var sof_ramp_start := ramp_len * 0.15
	var sof_ramp_end   := total_len - ramp_len * 0.15
	var use_arch: bool = (total_len >= 12.0 and
		(style == _loader.BridgeStyle.STONE or style == _loader.BridgeStyle.BRICK or style == _loader.BridgeStyle.DRIVE))
	var arch_segs := 8  # semicircular segments for arch cross-section
	var arch_rise: float = eff_clearance * 0.6  # partial arch, not full semicircle

	for i in range(n_pts - 1):
		if _skip_soffit:
			break
		if cum_len[i + 1] < sof_ramp_start or cum_len[i] > sof_ramp_end:
			continue
		var p1 := Vector3(float(pts[i][0]),     pt_y[i],     float(pts[i][2]))
		var p2 := Vector3(float(pts[i+1][0]),   pt_y[i+1],   float(pts[i+1][2]))
		var seg2 := Vector2(p2.x - p1.x, p2.z - p1.z)
		if seg2.length_squared() < 0.0001:
			continue
		var seg_len := seg2.length()
		var dv := seg2 / seg_len
		var nv := Vector2(-dv.y, dv.x)
		var bot1: float = p1.y - _loader.BRIDGE_DECK_T
		var bot2: float = p2.y - _loader.BRIDGE_DECK_T
		var u2_s := u_s + seg_len / width

		if use_arch:
			# Arched soffit: semicircular cross-section from -hw2 to +hw2
			# Arch bottom center is at bot - arch_rise, springing from bot at edges
			for ai in range(arch_segs):
				var t0 := float(ai) / float(arch_segs)
				var t1 := float(ai + 1) / float(arch_segs)
				# Angle from 0 (left edge) to PI (right edge)
				var a0 := PI * t0
				var a1 := PI * t1
				# Cross-section position: lateral offset and height
				var lat0 := hw2 * cos(a0)  # -hw2 to +hw2
				var rise0 := arch_rise * sin(a0)  # 0 at edges, max at center
				var lat1 := hw2 * cos(a1)
				var rise1 := arch_rise * sin(a1)
				# 4 corners of this arch strip segment (2 cross-section points × 2 path points)
				var v0 := Vector3(p1.x + nv.x * lat0, bot1 - rise0, p1.z + nv.y * lat0)
				var v1 := Vector3(p1.x + nv.x * lat1, bot1 - rise1, p1.z + nv.y * lat1)
				var v2 := Vector3(p2.x + nv.x * lat1, bot2 - rise1, p2.z + nv.y * lat1)
				var v3 := Vector3(p2.x + nv.x * lat0, bot2 - rise0, p2.z + nv.y * lat0)
				# Normal points inward (down into arch)
				var mid_a := (a0 + a1) * 0.5
				var arch_n := Vector3(
					-nv.x * cos(mid_a),
					-sin(mid_a),
					-nv.y * cos(mid_a)).normalized()
				sof_verts.append_array(PackedVector3Array([v0, v1, v2, v0, v2, v3]))
				for _j in 6:
					sof_normals.append(arch_n)
				sof_uvs.append_array(PackedVector2Array([
					Vector2(u_s, t0), Vector2(u_s, t1), Vector2(u2_s, t1),
					Vector2(u_s, t0), Vector2(u2_s, t1), Vector2(u2_s, t0),
				]))
		else:
			# Flat soffit (CAST_IRON, RUSTIC_WOOD, short bridges)
			var sa := Vector3(p1.x + nv.x * hw2, bot1, p1.z + nv.y * hw2)
			var sb := Vector3(p1.x - nv.x * hw2, bot1, p1.z - nv.y * hw2)
			var sc := Vector3(p2.x + nv.x * hw2, bot2, p2.z + nv.y * hw2)
			var sd := Vector3(p2.x - nv.x * hw2, bot2, p2.z - nv.y * hw2)
			sof_verts.append_array(PackedVector3Array([sa, sb, sc, sb, sd, sc]))
			for _j in 6:
				sof_normals.append(Vector3.DOWN)
			sof_uvs.append_array(PackedVector2Array([
				Vector2(u_s, 0.0), Vector2(u_s, 1.0), Vector2(u2_s, 0.0),
				Vector2(u_s, 1.0), Vector2(u2_s, 1.0), Vector2(u2_s, 0.0),
			]))

		# Side edge beams (deck top to soffit bottom, both sides)
		for side in [-1.0, 1.0]:
			var s: float = side
			var ox := nv.x * hw2 * s
			var oz := nv.y * hw2 * s
			var ea := Vector3(p1.x + ox, p1.y,  p1.z + oz)
			var eb := Vector3(p2.x + ox, p2.y,  p2.z + oz)
			var ec := Vector3(p2.x + ox, bot2,  p2.z + oz)
			var ed := Vector3(p1.x + ox, bot1,  p1.z + oz)
			edge_verts.append_array(PackedVector3Array([ea, eb, ec, ea, ec, ed]))
			var en := Vector3(nv.x * s, 0.0, nv.y * s)
			for _j in 6:
				edge_norms.append(en)
		u_s = u2_s

	if not sof_verts.is_empty():
		sof_verts.append_array(edge_verts)
		sof_normals.append_array(edge_norms)
		for _j in range(edge_verts.size()):
			sof_uvs.append(Vector2.ZERO)
		var sof_mesh: ArrayMesh = _loader._make_mesh(sof_verts, sof_normals, sof_uvs)
		sof_mesh.surface_set_material(0, _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
				soffit_tint))
		var sof_mi := MeshInstance3D.new()
		sof_mi.mesh = sof_mesh
		sof_mi.name = "Bridge_Soffit"
		_loader.add_child(sof_mi)

	# ----------------------------------------------------------------
	# Parapet / railing — style-dependent
	# ----------------------------------------------------------------
	var par_ramp_start := ramp_len * 0.3
	var par_ramp_end   := total_len - ramp_len * 0.3
	var _skip_parapets := total_len < 6.0

	if not _skip_parapets:
		if bridge_name == "Bow Bridge":
			_build_bow_bridge_railings(pts, pt_y, cum_len, n_pts, hw2,
				par_ramp_start, par_ramp_end, bridge_miter)
		else:
			match style:
				_loader.BridgeStyle.CAST_IRON:
					_build_iron_railings(pts, pt_y, cum_len, n_pts, hw2,
						par_ramp_start, par_ramp_end, bridge_miter)
				_loader.BridgeStyle.RUSTIC_WOOD:
					_build_wood_railings(pts, pt_y, cum_len, n_pts, hw2,
						par_ramp_start, par_ramp_end, bridge_miter)
				_:
					_build_solid_parapets(pts, pt_y, cum_len, n_pts, hw2,
						par_ramp_start, par_ramp_end, rw_alb, rw_nrm, rw_rgh,
						parapet_tint, bridge_miter)
		# Parapet collision walls — thin vertical planes on both sides
		_add_parapet_collision(pts, pt_y, cum_len, n_pts, hw2,
			par_ramp_start, par_ramp_end, bridge_miter)

	# ----------------------------------------------------------------
	# Abutment wing walls — only on bridges with real underpasses (>= 15m)
	# ----------------------------------------------------------------
	var abut_verts   := PackedVector3Array()
	var abut_normals := PackedVector3Array()
	var span_start_i := -1
	var span_end_i   := -1
	if total_len >= 15.0:
		for i in range(n_pts):
			if cum_len[i] >= ramp_len and span_start_i < 0:
				span_start_i = i
			if cum_len[i] <= total_len - ramp_len:
				span_end_i = i

	if span_start_i >= 0 and span_end_i >= 0:
		for end_i in [span_start_i, span_end_i]:
			var px   := float(pts[end_i][0])
			var pz   := float(pts[end_i][2])
			var ty   := float(pts[end_i][1])   # terrain level
			var dy   := pt_y[end_i]             # deck level
			if dy - ty < 0.5:
				continue   # not enough gap for a visible abutment

			# Get path direction at this point for the abutment face orientation
			var other_i: int = (end_i + 1) if end_i == span_start_i else (end_i - 1)
			other_i = clampi(other_i, 0, n_pts - 1)
			var seg2 := Vector2(float(pts[other_i][0]) - px,
								float(pts[other_i][2]) - pz)
			if seg2.length_squared() < 0.01:
				continue
			var dv  := seg2.normalized()
			var nv  := Vector2(-dv.y, dv.x)
			var face_dir := -1.0 if end_i == span_start_i else 1.0
			var face_n   := Vector3(dv.x * face_dir, 0.0, dv.y * face_dir)
			var ohw: float = hw2 + _loader.PARAPET_T + 0.3   # slightly wider than parapets
			var lintel_h := 0.4   # stone lintel depth at top of opening

			# Wing walls: one on each side of the opening, from hw2 outward to ohw
			for side in [-1.0, 1.0]:
				var s: float = side
				# Wing wall: from path edge to outer edge, terrain to deck
				var wa := Vector3(px + nv.x * hw2 * s, ty,  pz + nv.y * hw2 * s)
				var wb := Vector3(px + nv.x * ohw * s, ty,  pz + nv.y * ohw * s)
				var wc := Vector3(px + nv.x * ohw * s, dy,  pz + nv.y * ohw * s)
				var wd := Vector3(px + nv.x * hw2 * s, dy,  pz + nv.y * hw2 * s)
				abut_verts.append_array(PackedVector3Array([wa, wb, wc, wa, wc, wd]))
				for _j in range(6):
					abut_normals.append(face_n)

			# Lintel across the top of the opening (deck bottom to deck, full width)
			var lt_y := dy - lintel_h
			var la := Vector3(px + nv.x * hw2, lt_y, pz + nv.y * hw2)
			var lb := Vector3(px - nv.x * hw2, lt_y, pz - nv.y * hw2)
			var lc := Vector3(px - nv.x * hw2, dy,   pz - nv.y * hw2)
			var ld := Vector3(px + nv.x * hw2, dy,   pz + nv.y * hw2)
			abut_verts.append_array(PackedVector3Array([la, lb, lc, la, lc, ld]))
			for _j in range(6):
				abut_normals.append(face_n)

	if not abut_verts.is_empty():
		var abut_mesh: ArrayMesh = _loader._make_mesh(abut_verts, abut_normals)
		abut_mesh.surface_set_material(0, _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
				abut_tint))
		var abut_mi := MeshInstance3D.new()
		abut_mi.mesh = abut_mesh
		abut_mi.name = "Bridge_Abutments"
		_loader.add_child(abut_mi)

	# ----------------------------------------------------------------
	# Approach retaining walls — along ramp where deck rises above terrain
	# ----------------------------------------------------------------
	if total_len >= 8.0:
		var appr_verts   := PackedVector3Array()
		var appr_normals := PackedVector3Array()
		for i in range(n_pts - 1):
			# Only in ramp sections
			var d1 := cum_len[i]
			var d2 := cum_len[i + 1]
			if d1 > ramp_len and d2 < total_len - ramp_len:
				continue
			var p1 := Vector3(float(pts[i][0]), pt_y[i], float(pts[i][2]))
			var p2 := Vector3(float(pts[i+1][0]), pt_y[i+1], float(pts[i+1][2]))
			var ty1 := float(pts[i][1])
			var ty2 := float(pts[i+1][1])
			# Only add wall where deck is meaningfully above terrain
			var gap1 := p1.y - ty1
			var gap2 := p2.y - ty2
			if gap1 < 0.3 and gap2 < 0.3:
				continue
			var seg2 := Vector2(p2.x - p1.x, p2.z - p1.z)
			if seg2.length_squared() < 0.0001:
				continue
			var nv := Vector2(-seg2.normalized().y, seg2.normalized().x)
			var am1 := bridge_miter[i]; var am2 := bridge_miter[i + 1]
			var ohw: float = hw2 + _loader.PARAPET_T + 0.1
			for side in [-1.0, 1.0]:
				var s: float = side
				var ox1 := am1.x * ohw * s; var oz1 := am1.y * ohw * s
				var ox2 := am2.x * ohw * s; var oz2 := am2.y * ohw * s
				var wa := Vector3(p1.x + ox1, ty1, p1.z + oz1)
				var wb := Vector3(p2.x + ox2, ty2, p2.z + oz2)
				var wc := Vector3(p2.x + ox2, p2.y, p2.z + oz2)
				var wd := Vector3(p1.x + ox1, p1.y, p1.z + oz1)
				appr_verts.append_array(PackedVector3Array([wa, wb, wc, wa, wc, wd]))
				var wall_n := Vector3(nv.x * s, 0.0, nv.y * s)
				for _j in range(6):
					appr_normals.append(wall_n)
		if not appr_verts.is_empty():
			_loader._add_stone_mesh(appr_verts, appr_normals, rw_alb, rw_nrm, rw_rgh,
					abut_tint, "Bridge_ApproachWalls")

	# ----------------------------------------------------------------
	# Deck edge curbs — raised strip along both sides, colored per style
	# ----------------------------------------------------------------
	var curb_w := 0.10   # curb width
	var curb_h := 0.08   # curb height above deck
	var curb_color := Color(0.65, 0.63, 0.60)  # default grey stone
	match style:
		_loader.BridgeStyle.CAST_IRON:
			curb_color = Color(0.15, 0.15, 0.17)  # dark iron
		_loader.BridgeStyle.RUSTIC_WOOD:
			curb_color = Color(0.40, 0.28, 0.15)  # brown wood
		_loader.BridgeStyle.BRICK:
			curb_color = Color(0.55, 0.35, 0.25)  # reddish brick
	var curb_v := PackedVector3Array()
	var curb_n := PackedVector3Array()
	for i in range(n_pts - 1):
		var d1 := cum_len[i]
		var d2 := cum_len[i + 1]
		# Only add curbs where railings would be (elevated section)
		if d2 < par_ramp_start or d1 > par_ramp_end:
			continue
		var p1 := Vector3(float(pts[i][0]), pt_y[i], float(pts[i][2]))
		var p2 := Vector3(float(pts[i+1][0]), pt_y[i+1], float(pts[i+1][2]))
		var seg2 := Vector2(p2.x - p1.x, p2.z - p1.z)
		if seg2.length_squared() < 0.0001:
			continue
		var dv := seg2.normalized()
		var nv := Vector2(-dv.y, dv.x)
		var cm1 := bridge_miter[i]; var cm2 := bridge_miter[i + 1]
		for side in [-1.0, 1.0]:
			var s: float = side
			var o_inner := hw2 - curb_w
			var o_outer := hw2
			var a := Vector3(p1.x + cm1.x * o_inner * s, p1.y, p1.z + cm1.y * o_inner * s)
			var b := Vector3(p1.x + cm1.x * o_outer * s, p1.y, p1.z + cm1.y * o_outer * s)
			var c := Vector3(p2.x + cm2.x * o_outer * s, p2.y, p2.z + cm2.y * o_outer * s)
			var d := Vector3(p2.x + cm2.x * o_inner * s, p2.y, p2.z + cm2.y * o_inner * s)
			# Top face
			var at := a + Vector3.UP * curb_h
			var bt := b + Vector3.UP * curb_h
			var ct := c + Vector3.UP * curb_h
			var dt := d + Vector3.UP * curb_h
			curb_v.append_array(PackedVector3Array([at, bt, ct, at, ct, dt]))
			for _j in range(6):
				curb_n.append(Vector3.UP)
			# Outward face
			curb_v.append_array(PackedVector3Array([b, c, ct, b, ct, bt]))
			var fn := Vector3(nv.x * s, 0.0, nv.y * s)
			for _j in range(6):
				curb_n.append(fn)
			# Inner face
			curb_v.append_array(PackedVector3Array([d, a, at, d, at, dt]))
			for _j in range(6):
				curb_n.append(-fn)
	if not curb_v.is_empty():
		_loader._add_batch_mesh(curb_v, curb_n, curb_color, 0.7, "Bridge_Curbs")

	# ----------------------------------------------------------------
	# Bridge name label — Label3D for named bridges
	# ----------------------------------------------------------------
	if not bridge_name.is_empty() and total_len >= 8.0:
		var mid_i := n_pts / 2
		var label_pos := Vector3(float(pts[mid_i][0]), pt_y[mid_i] + _loader.PARAPET_H + 1.5,
				float(pts[mid_i][2]))
		var lbl := Label3D.new()
		lbl.text = bridge_name
		lbl.font_size = 48
		lbl.pixel_size = 0.01
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED

		lbl.modulate = Color(0.75, 0.72, 0.68, 0.60)
		lbl.outline_modulate = Color(0.1, 0.1, 0.1, 0.50)
		lbl.outline_size = 8
		lbl.position = label_pos
		lbl.name = "Bridge_Label"
		_loader.add_child(lbl)


# ---------------------------------------------------------------------------
# Gapstow Bridge — custom hero geometry
# Single stone arch, fieldstone texture, semicircular profile, humped deck
# ---------------------------------------------------------------------------
func _build_gapstow_bridge(pts: Array, cum_len: PackedFloat32Array,
		total_len: float, width: float,
		rw_alb: Texture2D, rw_nrm: Texture2D, rw_rgh: Texture2D,
		bridge_miter: Array[Vector2]) -> void:
	var n_pts := pts.size()
	var hw2 := width * 0.5 + 0.5  # wider than normal
	var y_start := float(pts[0][1])
	var y_end   := float(pts[n_pts - 1][1])
	var mid_terrain := y_start
	for i in range(n_pts):
		mid_terrain = minf(mid_terrain, float(pts[i][1]))
	# Gapstow: low arch, ~2.5m clearance at crown
	var arch_clearance := 2.5
	var crown_y := mid_terrain + arch_clearance
	var deck_y := crown_y + 0.35  # deck thickness above arch crown

	# Build arch profile: semicircular arch visible from below (soffit)
	var arch_segs := 12
	var arch_span := total_len * 0.7  # arch covers 70% of bridge length
	var arch_rise := arch_clearance
	var arch_start_d := total_len * 0.15  # arch starts 15% from each end

	# Per-point deck height: humped profile (higher at center)
	var pt_y := PackedFloat32Array()
	pt_y.resize(n_pts)
	for i in range(n_pts):
		var d := cum_len[i]
		var t_along := d / total_len
		# Parabolic hump: peaks at center
		var hump := 1.0 - (2.0 * t_along - 1.0) * (2.0 * t_along - 1.0)
		var ramp_frac := 0.15
		var base_y: float
		if t_along < ramp_frac:
			var rt := t_along / ramp_frac
			rt = rt * rt * (3.0 - 2.0 * rt)
			base_y = lerpf(y_start + _loader.PATH_Y, deck_y, rt)
		elif t_along > 1.0 - ramp_frac:
			var rt := (1.0 - t_along) / ramp_frac
			rt = rt * rt * (3.0 - 2.0 * rt)
			base_y = lerpf(y_end + _loader.PATH_Y, deck_y, rt)
		else:
			base_y = deck_y
		pt_y[i] = base_y + hump * 0.6  # subtle hump

	# Build deck + soffit geometry
	var stone_tint := Color(0.75, 0.72, 0.68)
	var stone_mat: ShaderMaterial = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh, stone_tint)
	var deck_v := PackedVector3Array()
	var deck_n := PackedVector3Array()
	var deck_uv := PackedVector2Array()
	var col_faces := PackedVector3Array()
	var u_d := 0.0

	for i in range(n_pts - 1):
		var x1 := float(pts[i][0]);   var z1 := float(pts[i][2])
		var x2 := float(pts[i+1][0]); var z2 := float(pts[i+1][2])
		var dy1 := pt_y[i]; var dy2 := pt_y[i+1]
		var seg2 := Vector2(x2 - x1, z2 - z1)
		if seg2.length_squared() < 0.0001:
			continue
		var seg_len := seg2.length()
		var nv1 := bridge_miter[i]; var nv2 := bridge_miter[i + 1]
		var u2 := u_d + seg_len / width
		# Deck top (faces up)
		var d0l := Vector3(x1 + nv1.x * hw2, dy1, z1 + nv1.y * hw2)
		var d0r := Vector3(x1 - nv1.x * hw2, dy1, z1 - nv1.y * hw2)
		var d1l := Vector3(x2 + nv2.x * hw2, dy2, z2 + nv2.y * hw2)
		var d1r := Vector3(x2 - nv2.x * hw2, dy2, z2 - nv2.y * hw2)
		deck_v.append_array([d0l, d0r, d1r, d0l, d1r, d1l])
		for _j in 6: deck_n.append(Vector3.UP)
		deck_uv.append_array([Vector2(0, u_d), Vector2(1, u_d), Vector2(1, u2),
			Vector2(0, u_d), Vector2(1, u2), Vector2(0, u2)])
		# Collision
		col_faces.append_array([d0l, d0r, d1r, d0l, d1r, d1l])
		# Soffit (faces down) — only in arch span
		var d_mid := (cum_len[i] + cum_len[i+1]) * 0.5
		if d_mid >= arch_start_d and d_mid <= total_len - arch_start_d:
			var s_thick := 0.35
			var s0l := Vector3(d0l.x, dy1 - s_thick, d0l.z)
			var s0r := Vector3(d0r.x, dy1 - s_thick, d0r.z)
			var s1l := Vector3(d1l.x, dy2 - s_thick, d1l.z)
			var s1r := Vector3(d1r.x, dy2 - s_thick, d1r.z)
			deck_v.append_array([s0r, s0l, s1l, s0r, s1l, s1r])
			for _j in 6: deck_n.append(Vector3.DOWN)
			deck_uv.append_array([Vector2(0, u_d), Vector2(1, u_d), Vector2(1, u2),
				Vector2(0, u_d), Vector2(1, u2), Vector2(0, u2)])
		u_d = u2

	if not deck_v.is_empty():
		_loader._add_stone_mesh(deck_v, deck_n, rw_alb, rw_nrm, rw_rgh, stone_tint, "GapstowDeck")

	# Collision
	if not col_faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_faces)
		var body := StaticBody3D.new()
		body.name = "GapstowCollision"
		var coll := CollisionShape3D.new()
		coll.shape = shape
		body.add_child(coll)
		_loader.add_child(body)

	# Wider stone parapets (0.35m thick, 1.0m tall)
	var par_h := 1.0; var par_t := 0.35
	var par_v := PackedVector3Array()
	var par_n := PackedVector3Array()
	var par_uv := PackedVector2Array()
	for side in [-1.0, 1.0]:
		var u_p := 0.0
		for i in range(n_pts - 1):
			var x1 := float(pts[i][0]); var z1 := float(pts[i][2])
			var x2 := float(pts[i+1][0]); var z2 := float(pts[i+1][2])
			var nv1 := bridge_miter[i]; var nv2 := bridge_miter[i+1]
			var seg_len := Vector2(x2-x1, z2-z1).length()
			if seg_len < 0.001: continue
			var u2_p := u_p + seg_len / par_h
			var outer_off := hw2 + par_t * 0.5
			var inner_off := hw2 - par_t * 0.5
			# Outer face
			var o1 := Vector3(x1 + nv1.x*outer_off*side, pt_y[i], z1 + nv1.y*outer_off*side)
			var o2 := Vector3(x2 + nv2.x*outer_off*side, pt_y[i+1], z2 + nv2.y*outer_off*side)
			var o1t := o1 + Vector3(0, par_h, 0); var o2t := o2 + Vector3(0, par_h, 0)
			par_v.append_array([o1, o2, o2t, o1, o2t, o1t])
			var fn := Vector3(nv1.x * side, 0, nv1.y * side).normalized()
			for _j in 6: par_n.append(fn)
			par_uv.append_array([Vector2(u_p, 0), Vector2(u2_p, 0), Vector2(u2_p, 1),
				Vector2(u_p, 0), Vector2(u2_p, 1), Vector2(u_p, 1)])
			# Top cap
			var i1 := Vector3(x1 + nv1.x*inner_off*side, pt_y[i]+par_h, z1 + nv1.y*inner_off*side)
			var i2 := Vector3(x2 + nv2.x*inner_off*side, pt_y[i+1]+par_h, z2 + nv2.y*inner_off*side)
			par_v.append_array([o1t, o2t, i2, o1t, i2, i1])
			for _j in 6: par_n.append(Vector3.UP)
			par_uv.append_array([Vector2(u_p, 0), Vector2(u2_p, 0), Vector2(u2_p, 0.3),
				Vector2(u_p, 0), Vector2(u2_p, 0.3), Vector2(u_p, 0.3)])
			u_p = u2_p

	if not par_v.is_empty():
		_loader._add_stone_mesh(par_v, par_n, rw_alb, rw_nrm, rw_rgh,
			Color(0.72, 0.70, 0.66), "GapstowParapets")

	# Stone arch face at each end — semicircular voussoir profile
	var arch_v := PackedVector3Array()
	var arch_n := PackedVector3Array()
	var arch_uv_a := PackedVector2Array()
	for end_i in [0, n_pts - 1]:
		var ex := float(pts[end_i][0]); var ez := float(pts[end_i][2])
		var ey := pt_y[end_i]
		# Direction: inward from end
		var dir_sign := 1.0 if end_i == 0 else -1.0
		var seg_idx := 0 if end_i == 0 else n_pts - 2
		var dx := float(pts[seg_idx + 1][0]) - float(pts[seg_idx][0])
		var dz := float(pts[seg_idx + 1][2]) - float(pts[seg_idx][2])
		var seg_l := sqrt(dx*dx + dz*dz)
		if seg_l < 0.001: continue
		var fwd := Vector3(dx/seg_l, 0, dz/seg_l) * dir_sign
		var face_n := -fwd
		var right := Vector3(fwd.z, 0, -fwd.x)  # perpendicular
		# Draw rough-cut voussoir arch
		var arch_w := hw2 + par_t
		var arch_base_y := ey - 0.5
		var arch_top_y := ey
		# Rectangular frame around arch
		var n_arch := 10
		for ai in range(n_arch):
			var a0 := PI * float(ai) / float(n_arch)
			var a1 := PI * float(ai + 1) / float(n_arch)
			var ax0 := cos(a0) * arch_w; var ay0 := sin(a0) * arch_rise + arch_base_y
			var ax1 := cos(a1) * arch_w; var ay1 := sin(a1) * arch_rise + arch_base_y
			var p0 := Vector3(ex, ay0, ez) + right * ax0
			var p1 := Vector3(ex, ay1, ez) + right * ax1
			# Keystone voussoir — small trapezoidal face
			var p0o := p0 + Vector3(0, 0.15, 0)
			var p1o := p1 + Vector3(0, 0.15, 0)
			arch_v.append_array([p0, p1, p1o, p0, p1o, p0o])
			for _j in 6: arch_n.append(face_n)
			arch_uv_a.append_array([Vector2(0, 0), Vector2(0.2, 0), Vector2(0.2, 0.2),
				Vector2(0, 0), Vector2(0.2, 0.2), Vector2(0, 0.2)])

	if not arch_v.is_empty():
		_loader._add_stone_mesh(arch_v, arch_n, rw_alb, rw_nrm, rw_rgh,
			Color(0.68, 0.65, 0.60), "GapstowArch")

	# Label
	var cx := (float(pts[0][0]) + float(pts[n_pts-1][0])) * 0.5
	var cz := (float(pts[0][2]) + float(pts[n_pts-1][2])) * 0.5
	var cy := deck_y + 2.0
	var lbl := Label3D.new()
	lbl.text = "Gapstow Bridge"
	lbl.font_size = 64; lbl.pixel_size = 0.04
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(1.0, 1.0, 1.0, 0.95)
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.0, 0.08, 0.25, 0.85)
	lbl.position = Vector3(cx, cy, cz)
	lbl.name = "Label_GapstowBridge"
	_loader.add_child(lbl)
	print("  Gapstow Bridge: hero treatment applied")


# ---------------------------------------------------------------------------
# Bridge parapet collision — thin vertical wall on each side of the bridge deck
# ---------------------------------------------------------------------------
func _add_parapet_collision(pts: Array, pt_y: PackedFloat32Array,
		cum_len: PackedFloat32Array, n_pts: int, hw2: float,
		ramp_start: float, ramp_end: float,
		miter_nv: Array[Vector2] = []) -> void:
	var col_faces := PackedVector3Array()
	var _mnv: Array[Vector2] = miter_nv
	if _mnv.is_empty():
		_mnv = _loader._compute_miter_normals(pts, n_pts)
	var par_h: float = _loader.PARAPET_H + 0.1  # slightly taller than visual for safety
	for i in range(n_pts - 1):
		if cum_len[i + 1] < ramp_start or cum_len[i] > ramp_end:
			continue
		var p1y: float = pt_y[i]
		var p2y: float = pt_y[i + 1]
		var p1x := float(pts[i][0]);   var p1z := float(pts[i][2])
		var p2x := float(pts[i+1][0]); var p2z := float(pts[i+1][2])
		var m1 := _mnv[i]; var m2 := _mnv[i + 1]
		for side in [-1.0, 1.0]:
			var s: float = side
			var off := hw2 + 0.12  # center of parapet wall
			var x1 := p1x + m1.x * off * s; var z1 := p1z + m1.y * off * s
			var x2 := p2x + m2.x * off * s; var z2 := p2z + m2.y * off * s
			var a := Vector3(x1, p1y - 0.1, z1)
			var b := Vector3(x2, p2y - 0.1, z2)
			var c := Vector3(x2, p2y + par_h, z2)
			var d := Vector3(x1, p1y + par_h, z1)
			col_faces.append_array(PackedVector3Array([a, b, c, a, c, d]))
	if not col_faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "BridgeParapet_Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_faces)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_loader.add_child(body)


# ---------------------------------------------------------------------------
# Bridge railing helpers
# ---------------------------------------------------------------------------
func _build_solid_parapets(pts: Array, pt_y: PackedFloat32Array,
		cum_len: PackedFloat32Array, n_pts: int, hw2: float,
		ramp_start: float, ramp_end: float,
		rw_alb: ImageTexture, rw_nrm: ImageTexture, rw_rgh: ImageTexture,
		tint: Color, miter_nv: Array[Vector2] = []) -> void:
	## Solid stone balustrade walls with thickness, coping stone overhang, and pilaster columns.
	var par_verts   := PackedVector3Array()
	var par_normals := PackedVector3Array()
	var wall_t := 0.25  # wall thickness
	var coping_overhang := 0.05  # coping extends past wall on each side
	var coping_h := 0.08  # coping stone height
	var pilaster_relief := 0.05  # how far pilasters protrude
	var pilaster_w := 0.30  # pilaster width
	var pilaster_spacing := 3.5  # metres between pilasters

	# Use caller-provided miter or fall back to per-segment normals
	var _mnv: Array[Vector2] = miter_nv
	if _mnv.is_empty():
		_mnv = _loader._compute_miter_normals(pts, n_pts)

	for i in range(n_pts - 1):
		if cum_len[i + 1] < ramp_start or cum_len[i] > ramp_end:
			continue
		var p1 := Vector3(float(pts[i][0]),     pt_y[i],     float(pts[i][2]))
		var p2 := Vector3(float(pts[i+1][0]),   pt_y[i+1],   float(pts[i+1][2]))
		var seg2 := Vector2(p2.x - p1.x, p2.z - p1.z)
		if seg2.length_squared() < 0.0001:
			continue
		var dv  := seg2.normalized()
		var nv  := Vector2(-dv.y, dv.x)  # per-segment normal (for face normals only)
		var m1 := _mnv[i]
		var m2 := _mnv[i + 1]

		for side in [-1.0, 1.0]:
			var s: float = side
			var inner_off := hw2  # inner face at deck edge
			var outer_off := hw2 + wall_t
			# Per-point miter offsets (seal gaps between segments)
			var ix1 := m1.x * inner_off * s; var iz1 := m1.y * inner_off * s
			var ix2 := m2.x * inner_off * s; var iz2 := m2.y * inner_off * s
			var ox1 := m1.x * outer_off * s; var oz1 := m1.y * outer_off * s
			var ox2 := m2.x * outer_off * s; var oz2 := m2.y * outer_off * s
			var wall_top1: float = p1.y + _loader.PARAPET_H - coping_h
			var wall_top2: float = p2.y + _loader.PARAPET_H - coping_h

			# Inner face (facing path) — extend 0.02m below deck to seal gap
			var ia := Vector3(p1.x + ix1, p1.y - 0.02, p1.z + iz1)
			var ib := Vector3(p2.x + ix2, p2.y - 0.02, p2.z + iz2)
			var ic := Vector3(p2.x + ix2, wall_top2, p2.z + iz2)
			var id := Vector3(p1.x + ix1, wall_top1, p1.z + iz1)
			par_verts.append_array(PackedVector3Array([ia, ib, ic, ia, ic, id]))
			var inner_n := Vector3(-nv.x * s, 0.0, -nv.y * s)
			for _j in range(6):
				par_normals.append(inner_n)

			# Outer face (facing outward) — extend 0.02m below deck to seal gap
			var oa := Vector3(p1.x + ox1, p1.y - 0.02, p1.z + oz1)
			var ob := Vector3(p2.x + ox2, p2.y - 0.02, p2.z + oz2)
			var oc := Vector3(p2.x + ox2, wall_top2, p2.z + oz2)
			var od := Vector3(p1.x + ox1, wall_top1, p1.z + oz1)
			par_verts.append_array(PackedVector3Array([ob, oa, od, ob, od, oc]))
			var outer_n := Vector3(nv.x * s, 0.0, nv.y * s)
			for _j in range(6):
				par_normals.append(outer_n)

			# Top face of wall (below coping)
			par_verts.append_array(PackedVector3Array([id, ic, oc, id, oc, od]))
			for _j in range(6):
				par_normals.append(Vector3.UP)

			# Coping stone — overhangs wall by coping_overhang on each side
			var cop_inner := inner_off  # flush with deck edge (no inset gap)
			var cop_outer := outer_off + coping_overhang
			var cix1 := m1.x * cop_inner * s; var ciz1 := m1.y * cop_inner * s
			var cix2 := m2.x * cop_inner * s; var ciz2 := m2.y * cop_inner * s
			var cox1 := m1.x * cop_outer * s; var coz1 := m1.y * cop_outer * s
			var cox2 := m2.x * cop_outer * s; var coz2 := m2.y * cop_outer * s
			var cop_top1: float = p1.y + _loader.PARAPET_H
			var cop_top2: float = p2.y + _loader.PARAPET_H
			# Top of coping
			var ct_a := Vector3(p1.x + cix1, cop_top1, p1.z + ciz1)
			var ct_b := Vector3(p2.x + cix2, cop_top2, p2.z + ciz2)
			var ct_c := Vector3(p2.x + cox2, cop_top2, p2.z + coz2)
			var ct_d := Vector3(p1.x + cox1, cop_top1, p1.z + coz1)
			par_verts.append_array(PackedVector3Array([ct_a, ct_b, ct_c, ct_a, ct_c, ct_d]))
			for _j in range(6):
				par_normals.append(Vector3.UP)
			# Coping inner drip edge (vertical face)
			var cd_a := Vector3(p1.x + cix1, wall_top1, p1.z + ciz1)
			var cd_b := Vector3(p2.x + cix2, wall_top2, p2.z + ciz2)
			par_verts.append_array(PackedVector3Array([cd_a, cd_b, ct_b, cd_a, ct_b, ct_a]))
			for _j in range(6):
				par_normals.append(inner_n)
			# Coping outer drip edge
			var co_a := Vector3(p1.x + cox1, wall_top1, p1.z + coz1)
			var co_b := Vector3(p2.x + cox2, wall_top2, p2.z + coz2)
			par_verts.append_array(PackedVector3Array([co_b, co_a, ct_d, co_b, ct_d, ct_c]))
			for _j in range(6):
				par_normals.append(outer_n)

	# Pilaster columns on outer face — protruding stone columns every ~3.5m
	var pil_d := ramp_start
	while pil_d <= ramp_end:
		# Find point along path at this distance
		var idx := 0
		for k in range(n_pts - 1):
			if cum_len[k + 1] >= pil_d:
				idx = k
				break
		var seg_d := cum_len[idx + 1] - cum_len[idx]
		var t_val := 0.0
		if seg_d > 0.001:
			t_val = (pil_d - cum_len[idx]) / seg_d
		var px := lerpf(float(pts[idx][0]), float(pts[idx + 1][0]), t_val)
		var pz := lerpf(float(pts[idx][2]), float(pts[idx + 1][2]), t_val)
		var py := lerpf(pt_y[idx], pt_y[idx + 1], t_val)
		var seg2 := Vector2(float(pts[idx+1][0]) - float(pts[idx][0]),
							float(pts[idx+1][2]) - float(pts[idx][2]))
		if seg2.length_squared() < 0.001:
			pil_d += pilaster_spacing
			continue
		var dv := seg2.normalized()
		var nv := Vector2(-dv.y, dv.x)
		# Along-path direction for pilaster width
		var along := Vector2(dv.x, dv.y)

		for side in [-1.0, 1.0]:
			var s: float = side
			var base_off := hw2 + wall_t
			var pil_off := base_off + pilaster_relief
			var phw := pilaster_w * 0.5  # half width along path direction
			var pil_top: float = py + _loader.PARAPET_H - 0.08  # just below coping
			# 4 visible faces of pilaster (front, left, right, top)
			var bl := Vector3(px - along.x * phw + nv.x * base_off * s,
							  py, pz - along.y * phw + nv.y * base_off * s)
			var br := Vector3(px + along.x * phw + nv.x * base_off * s,
							  py, pz + along.y * phw + nv.y * base_off * s)
			var fl := Vector3(px - along.x * phw + nv.x * pil_off * s,
							  py, pz - along.y * phw + nv.y * pil_off * s)
			var fr := Vector3(px + along.x * phw + nv.x * pil_off * s,
							  py, pz + along.y * phw + nv.y * pil_off * s)
			var fl_t := Vector3(fl.x, pil_top, fl.z)
			var fr_t := Vector3(fr.x, pil_top, fr.z)
			var bl_t := Vector3(bl.x, pil_top, bl.z)
			var br_t := Vector3(br.x, pil_top, br.z)
			# Front face
			var pil_n := Vector3(nv.x * s, 0.0, nv.y * s)
			par_verts.append_array(PackedVector3Array([fl, fr, fr_t, fl, fr_t, fl_t]))
			for _j in range(6):
				par_normals.append(pil_n)
			# Left side
			var side_n_l := Vector3(-along.x, 0.0, -along.y)
			par_verts.append_array(PackedVector3Array([bl, fl, fl_t, bl, fl_t, bl_t]))
			for _j in range(6):
				par_normals.append(side_n_l)
			# Right side
			var side_n_r := Vector3(along.x, 0.0, along.y)
			par_verts.append_array(PackedVector3Array([fr, br, br_t, fr, br_t, fr_t]))
			for _j in range(6):
				par_normals.append(side_n_r)
			# Top
			par_verts.append_array(PackedVector3Array([fl_t, fr_t, br_t, fl_t, br_t, bl_t]))
			for _j in range(6):
				par_normals.append(Vector3.UP)
		pil_d += pilaster_spacing

	if par_verts.is_empty():
		return
	var par_mesh: ArrayMesh = _loader._make_mesh(par_verts, par_normals)
	par_mesh.surface_set_material(0, _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh, tint))
	var par_mi := MeshInstance3D.new()
	par_mi.mesh = par_mesh
	par_mi.name = "Bridge_Parapets"
	_loader.add_child(par_mi)


func _build_iron_railings(pts: Array, pt_y: PackedFloat32Array,
		cum_len: PackedFloat32Array, n_pts: int, hw2: float,
		ramp_start: float, ramp_end: float,
		bmiter: Array[Vector2] = []) -> void:
	## Cast-iron railings: posts every ~2m + 3 inner rails + continuous cap rail at top.
	var rail_verts   := PackedVector3Array()
	var rail_normals := PackedVector3Array()
	var rail_h := [_loader.PARAPET_H * 0.15, _loader.PARAPET_H * 0.50, _loader.PARAPET_H * 0.80]
	var rail_thick := 0.05   # horizontal rail thickness
	var cap_h := 0.06        # cap rail height
	var cap_hw := 0.05       # cap rail half-width (total 0.10m)
	var post_w := 0.08       # post width (square cross-section)
	var post_spacing := 2.0  # metres between posts
	var ohw := hw2            # flush with deck edge

	# Horizontal inner rails + cap rail: continuous quads per segment
	for i in range(n_pts - 1):
		if cum_len[i + 1] < ramp_start or cum_len[i] > ramp_end:
			continue
		var p1 := Vector3(float(pts[i][0]), pt_y[i], float(pts[i][2]))
		var p2 := Vector3(float(pts[i+1][0]), pt_y[i+1], float(pts[i+1][2]))
		var seg2 := Vector2(p2.x - p1.x, p2.z - p1.z)
		if seg2.length_squared() < 0.0001:
			continue
		var dv := seg2.normalized()
		var nv := Vector2(-dv.y, dv.x)
		var im1 := bmiter[i] if not bmiter.is_empty() else nv
		var im2 := bmiter[i + 1] if not bmiter.is_empty() else nv
		# Inner rails (outward-facing quads)
		for rh in rail_h:
			for side in [-1.0, 1.0]:
				var s: float = side
				var ox1 := im1.x * ohw * s; var oz1 := im1.y * ohw * s
				var ox2 := im2.x * ohw * s; var oz2 := im2.y * ohw * s
				var ra := Vector3(p1.x + ox1, p1.y + rh, p1.z + oz1)
				var rb := Vector3(p2.x + ox2, p2.y + rh, p2.z + oz2)
				var rc := Vector3(p2.x + ox2, p2.y + rh + rail_thick, p2.z + oz2)
				var rd := Vector3(p1.x + ox1, p1.y + rh + rail_thick, p1.z + oz1)
				rail_verts.append_array(PackedVector3Array([ra, rb, rc, ra, rc, rd]))
				var wall_n := Vector3(nv.x * s, 0.0, nv.y * s)
				for _j in range(6):
					rail_normals.append(wall_n)
		# Cap rail — outward face + top face per side
		for side in [-1.0, 1.0]:
			var s: float = side
			var ox1 := im1.x * ohw * s; var oz1 := im1.y * ohw * s
			var ox2 := im2.x * ohw * s; var oz2 := im2.y * ohw * s
			var cap_base: float = _loader.PARAPET_H
			var cap_top: float = _loader.PARAPET_H + cap_h
			# Outward face
			var ca := Vector3(p1.x + ox1, p1.y + cap_base, p1.z + oz1)
			var cb := Vector3(p2.x + ox2, p2.y + cap_base, p2.z + oz2)
			var cc := Vector3(p2.x + ox2, p2.y + cap_top,  p2.z + oz2)
			var cd := Vector3(p1.x + ox1, p1.y + cap_top,  p1.z + oz1)
			rail_verts.append_array(PackedVector3Array([ca, cb, cc, ca, cc, cd]))
			var wall_n := Vector3(nv.x * s, 0.0, nv.y * s)
			for _j in range(6):
				rail_normals.append(wall_n)
			# Top face (flat cap visible from above)
			var in_off := ohw - cap_hw * 2.0
			var inx1 := im1.x * in_off * s; var inz1 := im1.y * in_off * s
			var inx2 := im2.x * in_off * s; var inz2 := im2.y * in_off * s
			var ta := Vector3(p1.x + ox1,  p1.y + cap_top, p1.z + oz1)
			var tb := Vector3(p2.x + ox2,  p2.y + cap_top, p2.z + oz2)
			var tc := Vector3(p2.x + inx2, p2.y + cap_top, p2.z + inz2)
			var td := Vector3(p1.x + inx1, p1.y + cap_top, p1.z + inz1)
			rail_verts.append_array(PackedVector3Array([ta, tb, tc, ta, tc, td]))
			for _j in range(6):
				rail_normals.append(Vector3.UP)

	# Vertical posts
	var d := ramp_start
	while d <= ramp_end:
		var idx := 0
		for k in range(n_pts - 1):
			if cum_len[k + 1] >= d:
				idx = k
				break
		var seg_d := cum_len[idx + 1] - cum_len[idx]
		var t_val := 0.0
		if seg_d > 0.001:
			t_val = (d - cum_len[idx]) / seg_d
		var px := lerpf(float(pts[idx][0]), float(pts[idx + 1][0]), t_val)
		var pz := lerpf(float(pts[idx][2]), float(pts[idx + 1][2]), t_val)
		var py := lerpf(pt_y[idx], pt_y[idx + 1], t_val)
		var seg2 := Vector2(float(pts[idx+1][0]) - float(pts[idx][0]),
							float(pts[idx+1][2]) - float(pts[idx][2]))
		if seg2.length_squared() < 0.001:
			d += post_spacing
			continue
		var nv := Vector2(-seg2.normalized().y, seg2.normalized().x)

		for side in [-1.0, 1.0]:
			var s: float = side
			var cx := px + nv.x * ohw * s
			var cz := pz + nv.y * ohw * s
			_loader._add_box_post(rail_verts, rail_normals, cx, cz, py, py + _loader.PARAPET_H + cap_h, post_w)
		d += post_spacing

	if rail_verts.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.30, 0.24)  # warm reddish-brown iron paint (#6B4D3D)
	mat.metallic = 0.45
	mat.roughness = 0.40
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh: ArrayMesh = _loader._make_mesh(rail_verts, rail_normals)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Bridge_IronRailings"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_loader.add_child(mi)


func _build_bow_bridge_railings(pts: Array, pt_y: PackedFloat32Array,
		cum_len: PackedFloat32Array, n_pts: int, hw2: float,
		ramp_start: float, ramp_end: float,
		bmiter: Array[Vector2] = []) -> void:
	## Bow Bridge special: interlocking circles railing + planting urns.
	var rail_verts   := PackedVector3Array()
	var rail_normals := PackedVector3Array()
	var circle_r := 0.15     # each circle radius
	var tube_r := 0.012      # tube thickness
	var circle_spacing := 0.25  # horizontal spacing (30% overlap)
	var circle_segs := 10
	var cap_h: float = _loader.PARAPET_H + 0.06
	var ohw := hw2

	# Top + bottom horizontal rails (frame)
	for i in range(n_pts - 1):
		if cum_len[i + 1] < ramp_start or cum_len[i] > ramp_end:
			continue
		var p1 := Vector3(float(pts[i][0]), pt_y[i], float(pts[i][2]))
		var p2 := Vector3(float(pts[i+1][0]), pt_y[i+1], float(pts[i+1][2]))
		var seg2 := Vector2(p2.x - p1.x, p2.z - p1.z)
		if seg2.length_squared() < 0.0001:
			continue
		var dv := seg2.normalized()
		var nv := Vector2(-dv.y, dv.x)
		var im1 := bmiter[i] if not bmiter.is_empty() else nv
		var im2 := bmiter[i + 1] if not bmiter.is_empty() else nv
		for rh in [0.03, _loader.PARAPET_H]:
			for side in [-1.0, 1.0]:
				var s: float = side
				var ox1 := im1.x * ohw * s; var oz1 := im1.y * ohw * s
				var ox2 := im2.x * ohw * s; var oz2 := im2.y * ohw * s
				var ra := Vector3(p1.x + ox1, p1.y + rh, p1.z + oz1)
				var rb := Vector3(p2.x + ox2, p2.y + rh, p2.z + oz2)
				var rc := Vector3(p2.x + ox2, p2.y + rh + 0.04, p2.z + oz2)
				var rd := Vector3(p1.x + ox1, p1.y + rh + 0.04, p1.z + oz1)
				rail_verts.append_array(PackedVector3Array([ra, rb, rc, ra, rc, rd]))
				var wall_n := Vector3(nv.x * s, 0.0, nv.y * s)
				for _j in 6: rail_normals.append(wall_n)

	# Interlocking circles along each side
	var d := ramp_start
	while d <= ramp_end:
		# Interpolate position along path
		var idx := 0
		for k in range(n_pts - 1):
			if cum_len[k + 1] >= d:
				idx = k
				break
		var seg_d := cum_len[idx + 1] - cum_len[idx]
		var t_val := (d - cum_len[idx]) / seg_d if seg_d > 0.001 else 0.0
		var px := lerpf(float(pts[idx][0]), float(pts[idx + 1][0]), t_val)
		var pz := lerpf(float(pts[idx][2]), float(pts[idx + 1][2]), t_val)
		var py := lerpf(pt_y[idx], pt_y[idx + 1], t_val)
		var seg2 := Vector2(float(pts[idx+1][0]) - float(pts[idx][0]),
							float(pts[idx+1][2]) - float(pts[idx][2]))
		if seg2.length_squared() < 0.001:
			d += circle_spacing
			continue
		var nv := Vector2(-seg2.normalized().y, seg2.normalized().x)

		for side in [-1.0, 1.0]:
			var s: float = side
			var cx := px + nv.x * ohw * s
			var cz := pz + nv.y * ohw * s
			var cy: float = py + _loader.PARAPET_H * 0.5 + 0.03  # center of circle
			# Draw circle as tube segments
			for ci in circle_segs:
				var a0 := TAU * float(ci) / float(circle_segs)
				var a1 := TAU * float(ci + 1) / float(circle_segs)
				# Circle in the plane perpendicular to path (Y-up plane facing outward)
				var dv2 := seg2.normalized()
				var y0 := cy + sin(a0) * circle_r
				var y1 := cy + sin(a1) * circle_r
				var along0 := cos(a0) * circle_r
				var along1 := cos(a1) * circle_r
				var x0 := cx + dv2.x * along0
				var z0 := cz + dv2.y * along0
				var x1 := cx + dv2.x * along1
				var z1 := cz + dv2.y * along1
				# Tube quad (outward face) — 2 triangles (6 verts, non-indexed)
				var v0 := Vector3(x0, y0 - tube_r, z0)
				var v1 := Vector3(x1, y1 - tube_r, z1)
				var v2 := Vector3(x1, y1 + tube_r, z1)
				var v3 := Vector3(x0, y0 + tube_r, z0)
				rail_verts.append_array(PackedVector3Array([v0, v1, v2, v0, v2, v3]))
				var wall_n := Vector3(nv.x * s, 0.0, nv.y * s)
				for _j in 6: rail_normals.append(wall_n)
		d += circle_spacing

	# Planting urns — 8 evenly spaced along bridge
	var urn_verts := PackedVector3Array()
	var urn_normals := PackedVector3Array()
	var urn_indices := PackedInt32Array()
	var urn_count := 8
	var urn_spacing := (ramp_end - ramp_start) / float(urn_count + 1)
	for ui in urn_count:
		var ud := ramp_start + urn_spacing * float(ui + 1)
		var uidx := 0
		for k in range(n_pts - 1):
			if cum_len[k + 1] >= ud:
				uidx = k
				break
		var seg_d := cum_len[uidx + 1] - cum_len[uidx]
		var t_val := (ud - cum_len[uidx]) / seg_d if seg_d > 0.001 else 0.0
		var ux := lerpf(float(pts[uidx][0]), float(pts[uidx + 1][0]), t_val)
		var uz := lerpf(float(pts[uidx][2]), float(pts[uidx + 1][2]), t_val)
		var uy := lerpf(pt_y[uidx], pt_y[uidx + 1], t_val)
		var seg2 := Vector2(float(pts[uidx+1][0]) - float(pts[uidx][0]),
							float(pts[uidx+1][2]) - float(pts[uidx][2]))
		if seg2.length_squared() < 0.001:
			continue
		var nv := Vector2(-seg2.normalized().y, seg2.normalized().x)
		# Alternate sides
		var s := 1.0 if ui % 2 == 0 else -1.0
		var ucx := ux + nv.x * ohw * s
		var ucz := uz + nv.y * ohw * s
		var uby := uy + cap_h
		# Urn: pedestal + flared cylinder
		_loader._add_box_verts(urn_verts, urn_normals, urn_indices, ucx, uby + 0.075, ucz, 0.08, 0.075, 0.08)
		_loader._add_cylinder_verts(urn_verts, urn_normals, urn_indices, ucx, uby + 0.15, ucz, 0.14, 0.22, 8, 0.18)
		_loader._add_cylinder_verts(urn_verts, urn_normals, urn_indices, ucx, uby + 0.37, ucz, 0.18, 0.04, 8, 0.20)

	# Baluster posts — evenly spaced along bridge between railing sections
	var post_verts := PackedVector3Array()
	var post_normals := PackedVector3Array()
	var post_indices := PackedInt32Array()
	var post_spacing := 2.5  # metres between posts
	var pd := ramp_start
	while pd <= ramp_end:
		var pidx := 0
		for k in range(n_pts - 1):
			if cum_len[k + 1] >= pd:
				pidx = k
				break
		var seg_d := cum_len[pidx + 1] - cum_len[pidx]
		var t_val := (pd - cum_len[pidx]) / seg_d if seg_d > 0.001 else 0.0
		var ppx := lerpf(float(pts[pidx][0]), float(pts[pidx + 1][0]), t_val)
		var ppz := lerpf(float(pts[pidx][2]), float(pts[pidx + 1][2]), t_val)
		var ppy := lerpf(pt_y[pidx], pt_y[pidx + 1], t_val)
		var seg2 := Vector2(float(pts[pidx+1][0]) - float(pts[pidx][0]),
							float(pts[pidx+1][2]) - float(pts[pidx][2]))
		if seg2.length_squared() > 0.001:
			var pnv := Vector2(-seg2.normalized().y, seg2.normalized().x)
			for side in [-1.0, 1.0]:
				var s: float = side
				var pcx := ppx + pnv.x * ohw * s
				var pcz := ppz + pnv.y * ohw * s
				# Square post from deck to above parapet
				_loader._add_box_verts(post_verts, post_normals, post_indices,
					pcx, ppy + _loader.PARAPET_H * 0.5 + 0.02, pcz, 0.05, _loader.PARAPET_H * 0.5 + 0.02, 0.05)
				# Finial ball on top
				_loader._add_cylinder_verts(post_verts, post_normals, post_indices,
					pcx, ppy + _loader.PARAPET_H + 0.06, pcz, 0.04, 0.06, 6, 0.04)
		pd += post_spacing

	if rail_verts.is_empty():
		return
	# Bow Bridge: warm reddish-brown cast iron (per Wikimedia reference #7B4B3A-#8B5A4A)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.33, 0.25)
	mat.metallic = 0.35
	mat.roughness = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Build railing mesh
	var mesh: ArrayMesh = _loader._make_mesh(rail_verts, rail_normals)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "BowBridge_Railings"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_loader.add_child(mi)
	# Urn mesh — same cast iron as bridge (#7B4B3A warm reddish-brown)
	if not urn_verts.is_empty():
		var urn_mat := StandardMaterial3D.new()
		urn_mat.albedo_color = Color(0.48, 0.29, 0.23)  # cast iron, matching bridge paint
		urn_mat.roughness = 0.50
		urn_mat.metallic = 0.40
		var urn_mesh: ArrayMesh = _loader._make_mesh(urn_verts, urn_normals, null, null, urn_indices)
		urn_mesh.surface_set_material(0, urn_mat)
		var umi := MeshInstance3D.new()
		umi.mesh = urn_mesh
		umi.name = "BowBridge_Urns"
		_loader.add_child(umi)
	# Baluster post mesh (same warm reddish-brown material)
	if not post_verts.is_empty():
		var post_mesh: ArrayMesh = _loader._make_mesh(post_verts, post_normals, null, null, post_indices)
		post_mesh.surface_set_material(0, mat)
		var pmi := MeshInstance3D.new()
		pmi.mesh = post_mesh
		pmi.name = "BowBridge_Posts"
		_loader.add_child(pmi)


func _build_wood_railings(pts: Array, pt_y: PackedFloat32Array,
		cum_len: PackedFloat32Array, n_pts: int, hw2: float,
		ramp_start: float, ramp_end: float,
		bmiter: Array[Vector2] = []) -> void:
	## Rustic wood railings: chunky posts every ~2.5m + 2 thick beam rails with depth.
	var rail_verts   := PackedVector3Array()
	var rail_normals := PackedVector3Array()
	var rail_h := [_loader.PARAPET_H * 0.35, _loader.PARAPET_H * 0.85]
	var rail_thick := 0.08   # rail height (visible from side)
	var rail_depth := 0.06   # rail depth (visible from above)
	var post_w := 0.12       # chunky square posts
	var post_spacing := 2.5
	var ohw := hw2            # flush with deck edge

	# Horizontal rails — outward face + top face per rail
	for i in range(n_pts - 1):
		if cum_len[i + 1] < ramp_start or cum_len[i] > ramp_end:
			continue
		var p1 := Vector3(float(pts[i][0]), pt_y[i], float(pts[i][2]))
		var p2 := Vector3(float(pts[i+1][0]), pt_y[i+1], float(pts[i+1][2]))
		var seg2 := Vector2(p2.x - p1.x, p2.z - p1.z)
		if seg2.length_squared() < 0.0001:
			continue
		var dv := seg2.normalized()
		var nv := Vector2(-dv.y, dv.x)
		var wm1 := bmiter[i] if not bmiter.is_empty() else nv
		var wm2 := bmiter[i + 1] if not bmiter.is_empty() else nv
		for rh in rail_h:
			for side in [-1.0, 1.0]:
				var s: float = side
				var ox1 := wm1.x * ohw * s; var oz1 := wm1.y * ohw * s
				var ox2 := wm2.x * ohw * s; var oz2 := wm2.y * ohw * s
				# Outward face
				var ra := Vector3(p1.x + ox1, p1.y + rh, p1.z + oz1)
				var rb := Vector3(p2.x + ox2, p2.y + rh, p2.z + oz2)
				var rc := Vector3(p2.x + ox2, p2.y + rh + rail_thick, p2.z + oz2)
				var rd := Vector3(p1.x + ox1, p1.y + rh + rail_thick, p1.z + oz1)
				rail_verts.append_array(PackedVector3Array([ra, rb, rc, ra, rc, rd]))
				var wall_n := Vector3(nv.x * s, 0.0, nv.y * s)
				for _j in range(6):
					rail_normals.append(wall_n)
				# Top face (makes rail look like a solid beam)
				var in_off := ohw - rail_depth
				var inx1 := wm1.x * in_off * s; var inz1 := wm1.y * in_off * s
				var inx2 := wm2.x * in_off * s; var inz2 := wm2.y * in_off * s
				var top_y1: float = p1.y + rh + rail_thick
				var top_y2: float = p2.y + rh + rail_thick
				var ta := Vector3(p1.x + ox1,  top_y1, p1.z + oz1)
				var tb := Vector3(p2.x + ox2,  top_y2, p2.z + oz2)
				var tc := Vector3(p2.x + inx2, top_y2, p2.z + inz2)
				var td := Vector3(p1.x + inx1, top_y1, p1.z + inz1)
				rail_verts.append_array(PackedVector3Array([ta, tb, tc, ta, tc, td]))
				for _j in range(6):
					rail_normals.append(Vector3.UP)

	# Vertical posts
	var d := ramp_start
	while d <= ramp_end:
		var idx := 0
		for k in range(n_pts - 1):
			if cum_len[k + 1] >= d:
				idx = k
				break
		var seg_d := cum_len[idx + 1] - cum_len[idx]
		var t_val := 0.0
		if seg_d > 0.001:
			t_val = (d - cum_len[idx]) / seg_d
		var px := lerpf(float(pts[idx][0]), float(pts[idx + 1][0]), t_val)
		var pz := lerpf(float(pts[idx][2]), float(pts[idx + 1][2]), t_val)
		var py := lerpf(pt_y[idx], pt_y[idx + 1], t_val)
		var seg2 := Vector2(float(pts[idx+1][0]) - float(pts[idx][0]),
							float(pts[idx+1][2]) - float(pts[idx][2]))
		if seg2.length_squared() < 0.001:
			d += post_spacing
			continue
		var nv := Vector2(-seg2.normalized().y, seg2.normalized().x)

		for side in [-1.0, 1.0]:
			var s: float = side
			var cx := px + nv.x * ohw * s
			var cz := pz + nv.y * ohw * s
			_loader._add_box_post(rail_verts, rail_normals, cx, cz, py, py + _loader.PARAPET_H, post_w)
		d += post_spacing

	if rail_verts.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.32, 0.25)  # weathered gray-brown (#614F3F)
	mat.roughness = 0.88
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh: ArrayMesh = _loader._make_mesh(rail_verts, rail_normals)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Bridge_WoodRailings"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_loader.add_child(mi)
