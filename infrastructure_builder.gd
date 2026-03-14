## Infrastructure builder — barriers, labels, statues, amenities, facilities, viewpoints, attractions, gardens, meadow labels, special zones.

var _loader



func _init(loader) -> void:
	_loader = loader




# ---------------------------------------------------------------------------
# Barriers — stone walls, iron fences, hedges (364 features from OSM)
# ---------------------------------------------------------------------------
func _build_barriers(barriers: Array) -> void:
	if barriers.is_empty():
		return

	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")

	# Load GLB fence panel for iron fences
	var fence_panel_mesh: Mesh = null
	var fence_glb := ProjectSettings.globalize_path("res://models/furniture/fence_panel.glb")
	var fence_meshes: Dictionary = _loader._load_glb_meshes(fence_glb)
	if fence_meshes.has("FencePanel"):
		fence_panel_mesh = fence_meshes["FencePanel"] as Mesh

	var wall_verts   := PackedVector3Array()
	var wall_normals := PackedVector3Array()
	var hedge_verts  := PackedVector3Array()
	var hedge_normals := PackedVector3Array()
	var fence_xforms: Array = []
	var col_verts    := PackedVector3Array()

	for barrier in barriers:
		var btype: String = str(barrier.get("type", "wall"))
		var height: float = float(barrier.get("height", 1.2))
		var raw_pts: Array = barrier.get("points", [])
		if raw_pts.size() < 2:
			continue
		var bmx := (float(raw_pts[0][0]) + float(raw_pts[raw_pts.size()-1][0])) * 0.5
		var bmz := (float(raw_pts[0][1]) + float(raw_pts[raw_pts.size()-1][1])) * 0.5
		if not _loader._in_boundary(bmx, bmz):
			continue
		var pts: Array = _loader._subdivide_pts(raw_pts, 3.0)

		match btype:
			"fence", "guard_rail":
				if fence_panel_mesh:
					_place_fence_panels(pts, height, fence_xforms, col_verts)
				else:
					_build_wall_segments(pts, height, wall_verts, wall_normals, col_verts)
			"hedge":
				_build_wall_segments(pts, maxf(height, 0.8), hedge_verts, hedge_normals, col_verts)
			_:
				_build_wall_segments(pts, height, wall_verts, wall_normals, col_verts)

	# Stone wall mesh
	if not wall_verts.is_empty():
		var wall_mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
			Color(0.50, 0.48, 0.44))
		var mesh: ArrayMesh = _loader._make_mesh(wall_verts, wall_normals)
		mesh.surface_set_material(0, wall_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "StoneWalls"
		_loader.add_child(mi)

	# Iron fence panels via MultiMesh
	if fence_panel_mesh and not fence_xforms.is_empty():
		var iron_sh: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
		var iron_mat := ShaderMaterial.new()
		iron_mat.shader = iron_sh
		iron_mat.set_shader_parameter("iron_color", Vector3(0.05, 0.05, 0.06))
		iron_mat.set_shader_parameter("base_roughness", 0.65)
		iron_mat.set_shader_parameter("base_metallic", 0.85)
		_loader._spawn_multimesh(fence_panel_mesh, iron_mat, fence_xforms, "IronFences_Barriers")
		print("ParkLoader: barrier iron fences = %d panels" % fence_xforms.size())

	# Hedge mesh — seasonal foliage shader
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

	# Combined barrier collision
	if not col_verts.is_empty():
		var body := StaticBody3D.new()
		body.name = "Barrier_Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_verts)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_loader.add_child(body)

	print("ParkLoader: barriers = %d walls, %d hedges, %d fence panels" % [
		wall_verts.size() / 18, hedge_verts.size() / 18, fence_xforms.size()])


func _build_wall_segments(pts: Array, height: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		col_verts: PackedVector3Array) -> void:
	var ht := 0.2  # half-thickness
	for i in range(pts.size() - 1):
		var p1x := float(pts[i][0]);   var p1z := float(pts[i][2])
		var p2x := float(pts[i+1][0]); var p2z := float(pts[i+1][2])
		var p1y: float = _loader._terrain_y(p1x, p1z) - 0.02
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
			for _j in 6: normals.append(wall_n)
		# Top cap
		var tl1 := Vector3(p1x + n.x * ht, p1y + height, p1z + n.y * ht)
		var tr1 := Vector3(p1x - n.x * ht, p1y + height, p1z - n.y * ht)
		var tl2 := Vector3(p2x + n.x * ht, p2y + height, p2z + n.y * ht)
		var tr2 := Vector3(p2x - n.x * ht, p2y + height, p2z - n.y * ht)
		var cap := PackedVector3Array([tl1, tl2, tr1, tr1, tl2, tr2])
		verts.append_array(cap)
		col_verts.append_array(cap)
		for _j in 6: normals.append(Vector3.UP)


func _place_fence_panels(pts: Array, height: float,
		fence_xforms: Array, col_verts: PackedVector3Array) -> void:
	## Place fence panel GLB instances along a polyline.
	## Panel model: 2.0m wide × 1.0m tall, centered at origin, extending along X.
	var panel_w := 2.0
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
		var n_panels: int = maxi(1, int(round(seg_len / panel_w)))
		var x_scale: float = (seg_len / float(n_panels)) / panel_w
		var rot_angle := atan2(-d.y, d.x)
		for pi in n_panels:
			var t: float = (float(pi) + 0.5) / float(n_panels)
			var px: float = lerpf(p1x, p2x, t)
			var pz: float = lerpf(p1z, p2z, t)
			var py: float = lerpf(p1y, p2y, t)
			var basis := Basis(Vector3.UP, rot_angle).scaled(Vector3(x_scale, height, 1.0))
			fence_xforms.append(Transform3D(basis, Vector3(px, py, pz)))
		# Collision: thin wall for full segment
		for side in [-1.0, 1.0]:
			var ox: float = n.x * 0.02 * side
			var oz: float = n.y * 0.02 * side
			var a := Vector3(p1x + ox, p1y, p1z + oz)
			var b := Vector3(p2x + ox, p2y, p2z + oz)
			var c := Vector3(p2x + ox, p2y + height, p2z + oz)
			var dd := Vector3(p1x + ox, p1y + height, p1z + oz)
			col_verts.append_array(PackedVector3Array([a, b, c, a, c, dd]))


# ---------------------------------------------------------------------------
# Sports field markings — regulation court/field lines from OSM pitch polygons
# ---------------------------------------------------------------------------
func _build_sport_markings(landuse: Array) -> void:
	var line_verts := PackedVector3Array()
	var line_normals := PackedVector3Array()
	var line_colors := PackedColorArray()
	var court_count := 0

	for zone in landuse:
		var sport: String = str(zone.get("sport", ""))
		if sport.is_empty():
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue

		# Compute oriented bounding box: centroid + axes from polygon
		var cx := 0.0
		var cz := 0.0
		for p in pts:
			cx += float(p[0])
			cz += float(p[1])
		cx /= float(pts.size())
		cz /= float(pts.size())
		if not _loader._in_boundary(cx, cz):
			continue

		# AABB for size
		var min_x := 99999.0
		var max_x := -99999.0
		var min_z := 99999.0
		var max_z := -99999.0
		for p in pts:
			var px := float(p[0])
			var pz := float(p[1])
			if px < min_x: min_x = px
			if px > max_x: max_x = px
			if pz < min_z: min_z = pz
			if pz > max_z: max_z = pz
		var w := max_x - min_x
		var d := max_z - min_z

		# Skip facility-scale polygons (>50m in either direction = entire facility)
		if w > 50.0 or d > 50.0:
			continue
		# Skip very small polygons
		if w < 5.0 or d < 5.0:
			continue

		# Determine field orientation: longer axis is the length
		var half_w: float
		var half_d: float
		if w > d:
			half_w = w * 0.5
			half_d = d * 0.5
		else:
			half_w = d * 0.5
			half_d = w * 0.5

		var ty: float = _loader._terrain_y(cx, cz) + 0.05  # just above terrain
		var line_col := Color.WHITE

		match sport:
			"tennis":
				_add_tennis_markings(cx, cz, ty, half_w, half_d, line_verts, line_normals, line_colors)
				court_count += 1
			"basketball":
				_add_basketball_markings(cx, cz, ty, half_w, half_d, line_verts, line_normals, line_colors)
				court_count += 1
			"baseball":
				_add_baseball_markings(cx, cz, ty, half_w, half_d, line_verts, line_normals, line_colors)
				court_count += 1
			"soccer", "soccer;american_football":
				_add_soccer_markings(cx, cz, ty, half_w, half_d, line_verts, line_normals, line_colors)
				court_count += 1
			"american_handball":
				_add_handball_markings(cx, cz, ty, half_w, half_d, line_verts, line_normals, line_colors)
				court_count += 1

	if not line_verts.is_empty():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.95, 0.92)  # slightly off-white (painted lines weather)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.75  # painted surface, not glossy
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = line_verts
		arr[Mesh.ARRAY_NORMAL] = line_normals
		arr[Mesh.ARRAY_COLOR] = line_colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "SportMarkings"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_loader.add_child(mi)
		print("ParkLoader: sport markings = %d courts, %d verts" % [court_count, line_verts.size()])


func _line_quad(x1: float, z1: float, x2: float, z2: float,
		y: float, hw: float, col: Color,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	## Draw a line quad from (x1,z1) to (x2,z2) with half-width hw at height y.
	var dx := x2 - x1
	var dz := z2 - z1
	var len := sqrt(dx * dx + dz * dz)
	if len < 0.01:
		return
	var nx := -dz / len * hw
	var nz := dx / len * hw
	var a := Vector3(x1 + nx, y, z1 + nz)
	var b := Vector3(x1 - nx, y, z1 - nz)
	var c := Vector3(x2 - nx, y, z2 - nz)
	var d := Vector3(x2 + nx, y, z2 + nz)
	verts.append_array(PackedVector3Array([a, b, c, a, c, d]))
	for _i in 6:
		normals.append(Vector3.UP)
		colors.append(col)


func _arc_quads(cx: float, cz: float, y: float, radius: float,
		start_angle: float, end_angle: float, hw: float,
		col: Color, verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		segments: int = 16) -> void:
	## Draw an arc of line quads.
	var step := (end_angle - start_angle) / float(segments)
	for i in segments:
		var a := start_angle + step * float(i)
		var b := start_angle + step * float(i + 1)
		var x1 := cx + cos(a) * radius
		var z1 := cz + sin(a) * radius
		var x2 := cx + cos(b) * radius
		var z2 := cz + sin(b) * radius
		_line_quad(x1, z1, x2, z2, y, hw, col, verts, normals, colors)


func _rect_outline(cx: float, cz: float, y: float,
		hw: float, hd: float, lw: float, col: Color,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	## Draw a rectangle outline centered at (cx, cz).
	_line_quad(cx - hw, cz - hd, cx + hw, cz - hd, y, lw, col, verts, normals, colors)
	_line_quad(cx + hw, cz - hd, cx + hw, cz + hd, y, lw, col, verts, normals, colors)
	_line_quad(cx + hw, cz + hd, cx - hw, cz + hd, y, lw, col, verts, normals, colors)
	_line_quad(cx - hw, cz + hd, cx - hw, cz - hd, y, lw, col, verts, normals, colors)


func _add_tennis_markings(cx: float, cz: float, y: float,
		hw: float, hd: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	## ITF regulation tennis court: 23.77m × 10.97m (doubles), 8.23m (singles)
	## Scale to fit the OSM polygon proportionally.
	var lw := 0.05  # line half-width (5cm total = standard)
	var col := Color.WHITE
	var scale_w := hw / 12.0  # approximate court half-width
	var scale_d := hd / 5.5   # approximate court half-depth
	var s := minf(scale_w, scale_d)
	var cw := 5.485 * s   # doubles half-width
	var sw := 4.115 * s   # singles half-width
	var cd := 11.885 * s  # court half-length
	var sd := 6.40 * s    # service line distance from net

	# Outer (doubles) court outline
	_rect_outline(cx, cz, y, cw, cd, lw, col, verts, normals, colors)
	# Singles sidelines
	_line_quad(cx - sw, cz - cd, cx - sw, cz + cd, y, lw, col, verts, normals, colors)
	_line_quad(cx + sw, cz - cd, cx + sw, cz + cd, y, lw, col, verts, normals, colors)
	# Center (net) line
	_line_quad(cx - cw, cz, cx + cw, cz, y, lw, col, verts, normals, colors)
	# Service lines
	_line_quad(cx - sw, cz - sd, cx + sw, cz - sd, y, lw, col, verts, normals, colors)
	_line_quad(cx - sw, cz + sd, cx + sw, cz + sd, y, lw, col, verts, normals, colors)
	# Center service line
	_line_quad(cx, cz - sd, cx, cz + sd, y, lw, col, verts, normals, colors)


func _add_basketball_markings(cx: float, cz: float, y: float,
		hw: float, hd: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	## FIBA/park basketball court: ~28m × 15m. NYC park courts are often smaller.
	var lw := 0.05
	var col := Color.WHITE
	var s := minf(hw / 14.0, hd / 7.5)

	var cw := 7.5 * s    # half-width
	var cd := 14.0 * s   # half-length

	# Court outline
	_rect_outline(cx, cz, y, cw, cd, lw, col, verts, normals, colors)
	# Half-court line
	_line_quad(cx - cw, cz, cx + cw, cz, y, lw, col, verts, normals, colors)
	# Center circle (1.8m radius)
	_arc_quads(cx, cz, y, 1.8 * s, 0.0, TAU, lw, col, verts, normals, colors)

	# Free throw lanes + 3-point arcs at each end
	for side_val in [-1.0, 1.0]:
		var side: float = float(side_val)
		var end_z: float = cz + cd * side
		var basket_z: float = end_z - 1.575 * s * side  # basket offset from baseline
		# Free throw lane (key): 5.8m × 4.9m (FIBA)
		var key_hw: float = 2.45 * s
		var key_d: float = 5.8 * s
		_rect_outline(cx, end_z - key_d * 0.5 * side, y, key_hw, key_d * 0.5, lw, col, verts, normals, colors)
		# Free throw circle (1.8m radius)
		var ft_z: float = end_z - key_d * side
		_arc_quads(cx, ft_z, y, 1.8 * s, 0.0, TAU, lw, col, verts, normals, colors)
		# 3-point arc (6.75m radius from basket)
		var arc_r := 6.75 * s
		if side > 0:
			_arc_quads(cx, basket_z, y, arc_r, -PI * 0.75, -PI * 0.25, lw, col, verts, normals, colors, 20)
		else:
			_arc_quads(cx, basket_z, y, arc_r, PI * 0.25, PI * 0.75, lw, col, verts, normals, colors, 20)


func _add_baseball_markings(cx: float, cz: float, y: float,
		hw: float, hd: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	## Baseball diamond: 90ft (27.43m) between bases. Foul lines extend to outfield.
	var lw := 0.05
	var col := Color.WHITE
	var base_dist := minf(hw, hd) * 0.7  # scale to fit polygon
	if base_dist > 27.0: base_dist = 27.0  # cap at regulation

	# Home plate at polygon center-south
	var hx := cx
	var hz := cz + hd * 0.4  # home plate toward south edge
	# Diamond rotated 45°: bases at N, E, S, W
	var d45 := base_dist * 0.7071  # base_dist / sqrt(2)

	# Foul lines: home to 1st base, home to 3rd base (extend past bases)
	var first_x := hx + d45
	var first_z := hz - d45
	var third_x := hx - d45
	var third_z := hz - d45
	# Extend foul lines 50% past bases
	_line_quad(hx, hz, hx + d45 * 1.5, hz - d45 * 1.5, y, lw, col, verts, normals, colors)
	_line_quad(hx, hz, hx - d45 * 1.5, hz - d45 * 1.5, y, lw, col, verts, normals, colors)
	# Base paths: 1B-2B, 2B-3B
	var second_x := hx
	var second_z := hz - base_dist
	_line_quad(first_x, first_z, second_x, second_z, y, lw, col, verts, normals, colors)
	_line_quad(second_x, second_z, third_x, third_z, y, lw, col, verts, normals, colors)
	# Batter's box arcs (approximation)
	_arc_quads(hx, hz, y, base_dist * 0.35, -PI * 0.5, PI * 0.5, lw, col, verts, normals, colors, 12)


func _add_soccer_markings(cx: float, cz: float, y: float,
		hw: float, hd: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	## Soccer/football field: touchlines, goal lines, center circle, penalty areas.
	var lw := 0.05
	var col := Color.WHITE
	var fw := hw * 0.95  # field half-width (5% margin)
	var fd := hd * 0.95  # field half-depth

	# Touchlines and goal lines (outer rectangle)
	_rect_outline(cx, cz, y, fw, fd, lw, col, verts, normals, colors)
	# Half-way line
	_line_quad(cx - fw, cz, cx + fw, cz, y, lw, col, verts, normals, colors)
	# Center circle (9.15m or scaled)
	var center_r := minf(9.15, fw * 0.25)
	_arc_quads(cx, cz, y, center_r, 0.0, TAU, lw, col, verts, normals, colors, 24)
	# Center mark
	_line_quad(cx - 0.15, cz, cx + 0.15, cz, y, lw, col, verts, normals, colors)

	# Penalty areas at each end
	for side_val in [-1.0, 1.0]:
		var side: float = float(side_val)
		var end_z: float = cz + fd * side
		# Goal area: 18.32m × 5.5m (scaled)
		var ga_hw := minf(9.16, fw * 0.3)
		var ga_d := minf(5.5, fd * 0.1)
		_line_quad(cx - ga_hw, end_z, cx - ga_hw, end_z - ga_d * side, y, lw, col, verts, normals, colors)
		_line_quad(cx - ga_hw, end_z - ga_d * side, cx + ga_hw, end_z - ga_d * side, y, lw, col, verts, normals, colors)
		_line_quad(cx + ga_hw, end_z - ga_d * side, cx + ga_hw, end_z, y, lw, col, verts, normals, colors)
		# Penalty area: 40.32m × 16.5m (scaled)
		var pa_hw := minf(20.16, fw * 0.55)
		var pa_d := minf(16.5, fd * 0.25)
		_line_quad(cx - pa_hw, end_z, cx - pa_hw, end_z - pa_d * side, y, lw, col, verts, normals, colors)
		_line_quad(cx - pa_hw, end_z - pa_d * side, cx + pa_hw, end_z - pa_d * side, y, lw, col, verts, normals, colors)
		_line_quad(cx + pa_hw, end_z - pa_d * side, cx + pa_hw, end_z, y, lw, col, verts, normals, colors)


func _add_handball_markings(cx: float, cz: float, y: float,
		hw: float, hd: float,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> void:
	## American handball (1-wall): 20ft × 34ft (6.1m × 10.36m)
	## Blue court surface with white service line.
	var lw := 0.05
	var col := Color.WHITE
	var fw := minf(hw * 0.9, 3.05)   # half-width
	var fd := minf(hd * 0.9, 5.18)   # half-length

	# Court outline
	_rect_outline(cx, cz, y, fw, fd, lw, col, verts, normals, colors)
	# Service line (short line): 16ft from wall = ~4.88m from back
	var service_z := cz - fd + 4.88
	_line_quad(cx - fw, service_z, cx + fw, service_z, y, lw, col, verts, normals, colors)
	# Service zone line (receiving line): 9ft from back wall
	var recv_z := cz + fd - 2.74  # 9ft = 2.74m from front
	_line_quad(cx - fw, recv_z, cx + fw, recv_z, y, lw, col, verts, normals, colors)


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
		"cleopatra's needle": { "file": "cp_obelisk.glb", "height": 25.0 },
		"balto": { "file": "cp_balto.glb", "height": 1.8 },
		"william shakespeare": { "file": "cp_shakespeare.glb", "height": 5.5 },
		"robert burns": { "file": "cp_burns.glb", "height": 4.8 },
		"indian hunter": { "file": "cp_indian_hunter.glb", "height": 2.6 },
		"alexander hamilton": { "file": "cp_hamilton.glb", "height": 5.5 },
		"fitz-greene halleck": { "file": "cp_halleck.glb", "height": 4.2 },
		"sir walter scott": { "file": "cp_scott.glb", "height": 5.2 },
		"christopher columbus": { "file": "cp_columbus.glb", "height": 19.0 },
		"107th infantry memorial": { "file": "cp_107th_infantry.glb", "height": 4.5 },
	}
	var cache_dir := "res://cache/statues/"
	var abs_cache_dir := ProjectSettings.globalize_path(cache_dir)
	DirAccess.make_dir_recursive_absolute(abs_cache_dir)
	for skey in named_defs:
		var def: Dictionary = named_defs[skey]
		var abs_path := ProjectSettings.globalize_path("res://models/furniture/%s" % def["file"])
		if not FileAccess.file_exists(abs_path):
			continue
		# Try cached PackedScene first (much faster than GLTFDocument parsing)
		var cache_path: String = cache_dir + str(def["file"]).replace(".glb", ".scn")
		var abs_cache: String = ProjectSettings.globalize_path(cache_path)
		if FileAccess.file_exists(abs_cache):
			var packed = ResourceLoader.load(cache_path)
			if packed and packed is PackedScene:
				var root: Node = (packed as PackedScene).instantiate()
				if root:
					named_statue_glbs[skey] = { "root": root, "height": def["height"] }
					print("Statues: loaded named GLB '%s' (cached)" % skey)
					continue
		# Fall back to GLTFDocument parsing
		var gd := GLTFDocument.new()
		var gs := GLTFState.new()
		if gd.append_from_file(abs_path, gs) == OK:
			var root: Node = gd.generate_scene(gs)
			if root:
				named_statue_glbs[skey] = { "root": root, "height": def["height"] }
				# Save as PackedScene for next time
				var packed := PackedScene.new()
				if packed.pack(root) == OK:
					ResourceSaver.save(packed, cache_path)
				print("Statues: loaded named GLB '%s'" % skey)
			else:
				print("Statues: failed to generate scene for '%s'" % skey)
	print("Statues: %d named GLBs loaded" % named_statue_glbs.size())

	# Load stone pedestal GLB — 3 variant meshes for label-only statues
	# Variant 0: Standard (statues, sculptures) ~1.08m
	# Variant 1: Column (busts) ~1.36m
	# Variant 2: Memorial (memorials, monuments) ~0.68m
	var pedestal_meshes: Array = []  # [Mesh, Mesh, Mesh]
	var pedestal_heights: Array = [1.08, 1.36, 0.68]
	var ped_glb_meshes: Dictionary = _loader._load_glb_meshes(
		ProjectSettings.globalize_path("res://models/furniture/cp_pedestal.glb"))
	for mname in ped_glb_meshes:
		pedestal_meshes.append(ped_glb_meshes[mname])
	print("Statues: %d pedestal variants loaded" % pedestal_meshes.size())

	# Stone material for pedestals (gray granite)
	var ped_rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var ped_rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var ped_rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var ped_stone_mat: Material = _loader._make_stone_material(
		ped_rw_alb, ped_rw_nrm, ped_rw_rgh, Color(0.55, 0.53, 0.50))
	var ped_limestone_mat: Material = _loader._make_stone_material(
		ped_rw_alb, ped_rw_nrm, ped_rw_rgh, Color(0.65, 0.60, 0.52))
	var pedestal_count := 0

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

		# Strawberry Fields Imagine Mosaic — needs Blender model
		if sname_lower.contains("strawberry"):
			continue

		# No photogrammetry scan available — place stone pedestal with label.
		# The pedestal is real infrastructure (every CP statue sits on one);
		# the missing statue itself remains a visible data gap.
		var smat: String = str(statue.get("material", ""))
		var mat_col := Color(0.75, 0.72, 0.68, 0.65)  # default neutral
		if "bronze" in smat:
			mat_col = Color(0.72, 0.58, 0.35, 0.65)  # warm bronze
		elif "granite" in smat or "stone" in smat:
			mat_col = Color(0.62, 0.62, 0.60, 0.65)  # cool granite

		# Choose pedestal variant by type:
		# bust → column (1), memorial/monument → wide memorial (2), else → standard (0)
		var ped_idx := 0
		var ped_h := 1.08
		if stype == "bust":
			ped_idx = 1; ped_h = 1.36
		elif stype in ["memorial", "monument"]:
			ped_idx = 2; ped_h = 0.68

		# Place pedestal mesh
		if pedestal_meshes.size() > ped_idx:
			var mi := MeshInstance3D.new()
			mi.mesh = pedestal_meshes[ped_idx]
			mi.position = Vector3(sx, sy, sz)
			# Apply stone material (limestone for memorials, granite otherwise)
			var ped_mat: Material = ped_limestone_mat if ped_idx == 2 else ped_stone_mat
			for surf_i in range(mi.mesh.get_surface_count()):
				mi.mesh.surface_set_material(surf_i, ped_mat)
			mi.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_ON
			_loader.add_child(mi)
			pedestal_count += 1
			# Collision cylinder for the pedestal
			var pcyl := CylinderShape3D.new()
			pcyl.radius = 0.55 if ped_idx != 1 else 0.35
			pcyl.height = ped_h
			var pcol := CollisionShape3D.new()
			pcol.shape = pcyl
			pcol.position = Vector3(sx, sy + ped_h * 0.5, sz)
			statue_col_shapes.append(pcol)

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
		lbl.position = Vector3(sx, sy + ped_h + 0.5, sz)
		_loader.add_child(lbl)

	# Single StaticBody3D for all statue collision shapes
	if not statue_col_shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "StatueCollision"
		for shape in statue_col_shapes:
			body.add_child(shape)
		_loader.add_child(body)

	print("ParkLoader: statues/monuments = %d (%d with pedestals)" % [statues.size(), pedestal_count])


# ---------------------------------------------------------------------------
# Amenities — drinking water, toilets, theatres (inside park only)
# ---------------------------------------------------------------------------
func _build_amenities(amenities: Array) -> void:
	if amenities.is_empty():
		return

	# Load drinking fountain GLB (surface 0=Stone, surface 1=Iron)
	var df_path := ProjectSettings.globalize_path("res://models/furniture/cp_drinking_fountain.glb")
	var df_meshes: Dictionary = _loader._load_glb_meshes(df_path)
	var df_mesh: Mesh = null
	for mname in df_meshes:
		df_mesh = df_meshes[mname] as Mesh
		break
	if df_mesh:
		# Apply cast iron material to all surfaces
		var iron_sh: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
		for si in df_mesh.get_surface_count():
			var df_iron := ShaderMaterial.new()
			df_iron.shader = iron_sh
			df_iron.set_shader_parameter("iron_color", Vector3(0.12, 0.14, 0.10))
			df_mesh.surface_set_material(si, df_iron)
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

		# Drinking water: GLB pedestal fountain
		if am_type == "drinking_water":
			if df_mesh:
				df_xforms.append(Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
		# Toilets, theatres, etc: labels only (no procedural geometry)

		count += 1

	# Spawn drinking fountains via MultiMesh
	if not df_xforms.is_empty() and df_mesh:
		_loader._spawn_multimesh(df_mesh, null, df_xforms, "DrinkingFountains")
		print("  Drinking fountains: %d (CP model)" % df_xforms.size())
	print("  Amenities: %d placed (inside park)" % count)


# ---------------------------------------------------------------------------
# Garden labels — named gardens get floating text only (no procedural hedge geometry)
# ---------------------------------------------------------------------------
func _build_gardens() -> void:
	var label_count := 0
	var border_verts := PackedVector3Array()
	var border_normals := PackedVector3Array()
	var border_count := 0

	const BORDER_H := 0.15  # 15cm tall stone border
	const BORDER_W := 0.08  # 8cm wide

	for zone in _loader.landuse_zones:
		if zone.get("type", "") != "garden":
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue

		var n: int = pts.size()
		var cx := 0.0
		var cz := 0.0
		for pt in pts:
			cx += float(pt[0])
			cz += float(pt[1])
		cx /= n
		cz /= n
		if not _loader._in_boundary(cx, cz):
			continue

		# Named gardens get labels
		var name_: String = zone.get("name", "")
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

		# Build low stone border along polygon perimeter
		for pi in pts.size():
			var p0x: float = float(pts[pi][0])
			var p0z: float = float(pts[pi][1])
			var ni: int = (pi + 1) % pts.size()
			var p1x: float = float(pts[ni][0])
			var p1z: float = float(pts[ni][1])

			var dx: float = p1x - p0x
			var dz: float = p1z - p0z
			var seg_len: float = sqrt(dx * dx + dz * dz)
			if seg_len < 0.3:
				continue

			# Perpendicular for border width
			var nx: float = -dz / seg_len * BORDER_W
			var nz: float = dx / seg_len * BORDER_W

			var y0: float = _loader._terrain_y(p0x, p0z)
			var y1: float = _loader._terrain_y(p1x, p1z)

			# Outer edge
			var o0 := Vector3(p0x + nx, y0, p0z + nz)
			var o1 := Vector3(p1x + nx, y1, p1z + nz)
			# Inner edge
			var i0 := Vector3(p0x - nx, y0, p0z - nz)
			var i1 := Vector3(p1x - nx, y1, p1z - nz)
			# Top versions
			var o0t := Vector3(o0.x, o0.y + BORDER_H, o0.z)
			var o1t := Vector3(o1.x, o1.y + BORDER_H, o1.z)
			var i0t := Vector3(i0.x, i0.y + BORDER_H, i0.z)
			var i1t := Vector3(i1.x, i1.y + BORDER_H, i1.z)

			# Top face
			border_verts.append_array(PackedVector3Array([i0t, o0t, i1t, i1t, o0t, o1t]))
			for _j in 6: border_normals.append(Vector3.UP)

			# Outer face
			var out_n := Vector3(nx / BORDER_W, 0.0, nz / BORDER_W)
			border_verts.append_array(PackedVector3Array([o0, o1, o0t, o0t, o1, o1t]))
			for _j in 6: border_normals.append(out_n)

		border_count += 1

	# Create single combined mesh for all garden borders
	if not border_verts.is_empty():
		var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
		var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
		var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
		var mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
			Color(0.58, 0.55, 0.48))
		var mesh: ArrayMesh = _loader._make_mesh(border_verts, border_normals)
		mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "GardenBorders"
		_loader.add_child(mi)

	print("  Gardens: %d labeled, %d with stone borders (%d verts)" % [label_count, border_count, border_verts.size()])


# ---------------------------------------------------------------------------
# Facilities — visitor centers, dining, buildings with named labels
# ---------------------------------------------------------------------------
func _build_facilities(facilities: Array) -> void:
	if facilities.is_empty():
		return
	var count := 0
	var model_count := 0
	var type_colors: Dictionary = {
		"visitor_center": Color(0.25, 0.50, 0.70, 0.70),
		"facility":       Color(0.50, 0.45, 0.35, 0.70),
		"building":       Color(0.55, 0.50, 0.42, 0.70),
		"dining":         Color(0.70, 0.45, 0.25, 0.70),
	}

	# Named facility GLB models — keyword in facility name → GLB file
	var facility_glbs: Dictionary = {
		"swedish cottage": { "file": "cp_swedish_cottage.glb", "rot": PI },
		"dairy": { "file": "cp_dairy.glb", "rot": PI },
		"chess": { "file": "cp_chess_house.glb", "rot": 0.0 },
		"loeb boathouse": { "file": "cp_boathouse.glb", "rot": PI * 0.5 },
		"kerbs boathouse": { "file": "cp_boathouse.glb", "rot": PI * 0.5 },
		"delacorte": { "file": "cp_delacorte.glb", "rot": PI },
		"tavern": { "file": "cp_tavern.glb", "rot": PI },
		"wollman": { "file": "cp_wollman_rink.glb", "rot": 0.0 },
		"dana": { "file": "cp_discovery_center.glb", "rot": PI },
		"gate house": { "file": "cp_gate_house.glb", "rot": 0.0 },
		"summerstage": { "file": "cp_summerstage.glb", "rot": PI },
		"arsenal": { "file": "cp_arsenal.glb", "rot": PI },
		"zoo": { "file": "cp_zoo.glb", "rot": PI },
		"lasker": { "file": "cp_lasker.glb", "rot": 0.0 },
		"mineral springs": { "file": "cp_mineral_springs.glb", "rot": PI },
		"le pain": { "file": "cp_mineral_springs.glb", "rot": PI },
		"precinct": { "file": "cp_precinct.glb", "rot": PI },
		"police": { "file": "cp_precinct.glb", "rot": PI },
		"north meadow rec": { "file": "cp_rec_center.glb", "rot": 0.0 },
		"columbus circle": { "file": "cp_columbus_kiosk.glb", "rot": 0.0 },
	}

	# Load stone material for facility models
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")

	for fac in facilities:
		var name_: String = fac.get("name", "")
		var pos: Array = fac.get("pos", [])
		var ftype: String = fac.get("type", "facility")
		if pos.size() < 2:
			continue
		var x: float = float(pos[0])
		var z: float = float(pos[1])
		# Don't filter facilities by boundary — curated data, some are at park edges
		var ty: float = _loader._terrain_y(x, z)
		var col: Color = type_colors.get(ftype, Color(0.5, 0.5, 0.5, 0.70))

		# Check for named facility model
		var name_lower := name_.to_lower()
		var placed_model := false
		for key in facility_glbs:
			if name_lower.contains(key):
				var def_: Dictionary = facility_glbs[key]
				var glb_file: String = def_["file"]
				var abs_path := ProjectSettings.globalize_path("res://models/furniture/" + glb_file)
				if not FileAccess.file_exists(abs_path):
					break
				var gltf_doc := GLTFDocument.new()
				var gltf_state := GLTFState.new()
				if gltf_doc.append_from_file(abs_path, gltf_state) != OK:
					break
				var root: Node3D = gltf_doc.generate_scene(gltf_state)
				if root == null:
					break
				root.position = Vector3(x, ty, z)
				root.rotation.y = float(def_.get("rot", 0.0))
				root.name = name_.replace(" ", "_").replace("&", "and")
				# Apply stone material
				var default_mat: Material = _loader._make_stone_material(
					rw_alb, rw_nrm, rw_rgh, Color(0.55, 0.52, 0.46))
				var stack: Array = [root]
				while not stack.is_empty():
					var n: Node = stack.pop_back()
					if n is MeshInstance3D:
						var mi := n as MeshInstance3D
						if mi.mesh:
							for si in range(mi.mesh.get_surface_count()):
								mi.mesh.surface_set_material(si, default_mat)
					for c in n.get_children():
						stack.append(c)
				_loader.add_child(root)
				placed_model = true
				model_count += 1
				print("  Facility model '%s' placed at (%.0f, %.1f, %.0f)" % [name_, x, ty, z])
				break

		# Label (always, even with model — label floats above)
		if not name_.is_empty():
			var label_h := 4.0 if not placed_model else 12.0
			var label := Label3D.new()
			label.text = name_
			label.font_size = 28
			label.position = Vector3(x, ty + label_h, z)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = col
			label.outline_modulate = Color(0.05, 0.05, 0.05, 0.50)
			label.outline_size = 5
			label.no_depth_test = false
			label.pixel_size = 0.012
			_loader.add_child(label)
		count += 1
	print("  Facilities: %d placed (%d with 3D models)" % [count, model_count])


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

	# Named attraction GLB models
	var attraction_glbs: Dictionary = {
		"carousel": { "file": "cp_carousel.glb", "rot": 0.0 },
		"blockhouse": { "file": "cp_blockhouse.glb", "rot": PI * 0.25 },
		"cop cot": { "file": "cp_cop_cot.glb", "rot": PI },
		"fort clinton": { "file": "cp_fort_clinton.glb", "rot": PI * 0.75 },
		"nutter": { "file": "cp_fort_clinton.glb", "rot": PI * 0.75 },
		"musical clock": { "file": "cp_musical_clock.glb", "rot": 0.0 },
	}

	# Load stone material for attraction models
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")

	var subtype_colors: Dictionary = {
		"museum":  Color(0.60, 0.45, 0.30, 0.70),
		"fort":    Color(0.50, 0.50, 0.50, 0.70),
		"cannon":  Color(0.50, 0.50, 0.50, 0.70),
		"castle":  Color(0.55, 0.48, 0.40, 0.70),
	}
	var default_col := Color(0.50, 0.60, 0.70, 0.65)
	var count := 0
	var model_count := 0
	var placed_names: Dictionary = {}  # Dedup
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
			continue
		# Skip duplicate entries
		var dedup_key: String = name_ + str(int(x))
		if placed_names.has(dedup_key):
			continue
		placed_names[dedup_key] = true
		var subtype: String = att.get("subtype", "")
		var ty: float = _loader._terrain_y(x, z)
		var col: Color = subtype_colors.get(subtype, default_col)

		# Check for named GLB model
		var name_lower := name_.to_lower()
		var placed_model := false
		for key in attraction_glbs:
			if name_lower.contains(key):
				var def_: Dictionary = attraction_glbs[key]
				var abs_path := ProjectSettings.globalize_path("res://models/furniture/" + def_["file"])
				if not FileAccess.file_exists(abs_path):
					break
				var gltf_doc := GLTFDocument.new()
				var gltf_state := GLTFState.new()
				if gltf_doc.append_from_file(abs_path, gltf_state) != OK:
					break
				var root: Node3D = gltf_doc.generate_scene(gltf_state)
				if root == null:
					break
				root.position = Vector3(x, ty, z)
				root.rotation.y = float(def_.get("rot", 0.0))
				root.name = name_.replace(" ", "_")
				var default_mat: Material = _loader._make_stone_material(
					rw_alb, rw_nrm, rw_rgh, Color(0.50, 0.48, 0.44))
				var stack: Array = [root]
				while not stack.is_empty():
					var n: Node = stack.pop_back()
					if n is MeshInstance3D:
						var mi := n as MeshInstance3D
						if mi.mesh:
							for si in range(mi.mesh.get_surface_count()):
								mi.mesh.surface_set_material(si, default_mat)
					for c in n.get_children():
						stack.append(c)
				_loader.add_child(root)
				placed_model = true
				model_count += 1
				print("  Attraction model '%s' placed at (%.0f, %.1f, %.0f)" % [name_, x, ty, z])
				break

		var label_h := 3.5 if not placed_model else 12.0
		var label := Label3D.new()
		label.text = name_
		label.font_size = 26
		label.position = Vector3(x, ty + label_h, z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = col
		label.outline_modulate = Color(0.05, 0.05, 0.05, 0.45)
		label.outline_size = 5
		label.no_depth_test = false
		label.pixel_size = 0.012
		_loader.add_child(label)
		count += 1
	print("  Attractions: %d placed (%d with 3D models)" % [count, model_count])


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


# ---------------------------------------------------------------------------
# Bethesda Terrace — place the pre-built GLB model south of Bethesda Fountain
# ---------------------------------------------------------------------------
func _build_bethesda_terrace() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_bethesda_terrace.glb")
	if not FileAccess.file_exists(glb_path):
		print("  Bethesda Terrace: GLB not found, skipping")
		return

	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		print("WARNING: failed to load Bethesda Terrace GLB")
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return

	# Bethesda Fountain is at approx (-457, 17.6, 949). The terrace sits
	# directly south (+Z). The arcade passage center is ~35m south of the
	# fountain center.  Model origin = arcade floor center (lower terrace).
	var tx := -457.0
	var tz := 986.0
	var ty: float = _loader._terrain_y(tx, tz)

	# Blender +Y = south → glTF -Z. Our park +Z = south. Rotate 180° around Y.
	root.position = Vector3(tx, ty, tz)
	root.rotation.y = PI
	root.name = "BethesdaTerrace"

	# Apply stone material to all mesh surfaces
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")

	# Material lookup by Blender material name
	var mat_map: Dictionary = {}
	mat_map["Sandstone"] = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.72, 0.65, 0.52))
	mat_map["Brownstone"] = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.42, 0.32, 0.24))
	mat_map["VaultTile"] = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.82, 0.72, 0.55))
	mat_map["StairStone"] = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.60, 0.56, 0.48))
	# Default sandstone fallback
	var default_mat: Material = mat_map["Sandstone"]

	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				for si in range(mi.mesh.get_surface_count()):
					var surf_mat := mi.mesh.surface_get_material(si)
					var applied := false
					if surf_mat:
						var mname: String = surf_mat.resource_name
						for key in mat_map:
							if mname.contains(key):
								mi.mesh.surface_set_material(si, mat_map[key])
								applied = true
								break
					if not applied:
						mi.mesh.surface_set_material(si, default_mat)
		for c in n.get_children():
			stack.append(c)

	_loader.add_child(root)
	print("ParkLoader: Bethesda Terrace placed at (%.0f, %.1f, %.0f)" % [tx, ty, tz])


# ---------------------------------------------------------------------------
# Belvedere Castle — Victorian folly on Vista Rock
# ---------------------------------------------------------------------------
func _build_belvedere_castle() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_belvedere_castle.glb")
	if not FileAccess.file_exists(glb_path):
		print("  Belvedere Castle: GLB not found, skipping")
		return

	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		print("WARNING: failed to load Belvedere Castle GLB")
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return

	# Belvedere Castle sits on Vista Rock at approximately (0, ?, 525)
	var cx := 0.0
	var cz := 525.0
	var cy: float = _loader._terrain_y(cx, cz)

	# The castle faces south (toward the Turtle Pond and Great Lawn).
	# Blender +Y = south → glTF -Z. Park +Z = south. Rotate 180° around Y.
	root.position = Vector3(cx, cy, cz)
	root.rotation.y = PI
	root.name = "BelvedereCastle"

	# Apply stone material to all surfaces
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")

	var mat_map: Dictionary = {}
	mat_map["Schist"] = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.38, 0.36, 0.33))
	mat_map["Granite"] = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.52, 0.50, 0.46))
	mat_map["Slate"] = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.30, 0.28, 0.26))
	var default_mat: Material = mat_map["Schist"]

	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				for si in range(mi.mesh.get_surface_count()):
					var surf_mat := mi.mesh.surface_get_material(si)
					var applied := false
					if surf_mat:
						var mname: String = surf_mat.resource_name
						for key in mat_map:
							if mname.contains(key):
								mi.mesh.surface_set_material(si, mat_map[key])
								applied = true
								break
					if not applied:
						mi.mesh.surface_set_material(si, default_mat)
		for c in n.get_children():
			stack.append(c)

	_loader.add_child(root)
	print("ParkLoader: Belvedere Castle placed at (%.0f, %.1f, %.0f)" % [cx, cy, cz])


# ---------------------------------------------------------------------------
# Comfort stations — small stone restroom buildings at 30 OSM toilet locations
# ---------------------------------------------------------------------------
func _build_comfort_stations(amenities: Array) -> void:
	# Load comfort station GLB model
	var cs_path := ProjectSettings.globalize_path("res://models/furniture/cp_comfort_station.glb")
	if not FileAccess.file_exists(cs_path):
		print("  Comfort stations: GLB not found, skipping")
		return

	var cs_meshes: Dictionary = _loader._load_glb_meshes(cs_path)
	var cs_mesh: Mesh = null
	for mname in cs_meshes:
		cs_mesh = cs_meshes[mname] as Mesh
		break  # take first mesh
	if cs_mesh == null:
		print("  Comfort stations: no mesh found in GLB")
		return

	# Apply stone material
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var stone_mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.58, 0.54, 0.48))
	for si in range(cs_mesh.get_surface_count()):
		cs_mesh.surface_set_material(si, stone_mat)

	var xforms: Array = []
	for am in amenities:
		if am.get("type", "") != "toilets":
			continue
		var pos: Array = am.get("position", [])
		if pos.size() < 3:
			continue
		var x: float = pos[0]
		var z: float = pos[2]
		if not _loader._in_boundary(x, z):
			continue
		var y: float = _loader._terrain_y(x, z)
		# Random rotation from position hash for variety
		var rot := fmod(absf(x * 73.17 + z * 137.29), TAU)
		var basis := Basis(Vector3.UP, rot)
		xforms.append(Transform3D(basis, Vector3(x, y, z)))

	if not xforms.is_empty():
		_loader._spawn_multimesh(cs_mesh, null, xforms, "ComfortStations")
	print("  Comfort stations: %d placed" % xforms.size())


# ---------------------------------------------------------------------------
# Vanderbilt Gate — ornamental iron gate at Conservatory Garden entrance
# ---------------------------------------------------------------------------
func _build_vanderbilt_gate() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_vanderbilt_gate.glb")
	if not FileAccess.file_exists(glb_path):
		print("  Vanderbilt Gate: GLB not found, skipping")
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	# Gate at Conservatory Garden entrance — east side, 105th St
	var gx := 1063.0
	var gz := -1088.0
	var gy: float = _loader._terrain_y(gx, gz)
	root.position = Vector3(gx, gy, gz)
	root.rotation.y = PI * 0.5  # Faces west into garden
	root.name = "VanderbiltGate"
	# Apply iron material to gate parts, stone to piers
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var stone_mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.58, 0.55, 0.50))
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				for si in range(mi.mesh.get_surface_count()):
					mi.mesh.surface_set_material(si, stone_mat)
		for c in n.get_children():
			stack.append(c)
	_loader.add_child(root)
	print("  Vanderbilt Gate placed at (%.0f, %.1f, %.0f)" % [gx, gy, gz])


# ---------------------------------------------------------------------------
# Naumburg Bandshell — Neoclassical concert stage on the Mall
# ---------------------------------------------------------------------------
func _build_bandshell() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_bandshell.glb")
	if not FileAccess.file_exists(glb_path):
		print("  Bandshell: GLB not found, skipping")
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	var bx := -473.0
	var bz := 1131.0
	var by: float = _loader._terrain_y(bx, bz)
	root.position = Vector3(bx, by, bz)
	root.rotation.y = PI  # Shell faces south toward Mall
	root.name = "NaumburgBandshell"
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var stone_mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.68, 0.64, 0.58))
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				for si in range(mi.mesh.get_surface_count()):
					mi.mesh.surface_set_material(si, stone_mat)
		for c in n.get_children():
			stack.append(c)
	_loader.add_child(root)
	print("  Bandshell placed at (%.0f, %.1f, %.0f)" % [bx, by, bz])


# ---------------------------------------------------------------------------
# Conservatory Garden pergola — wisteria pergola in the North Garden
# ---------------------------------------------------------------------------
func _build_pergola() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_pergola.glb")
	if not FileAccess.file_exists(glb_path):
		print("  Pergola: GLB not found, skipping")
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	# Pergola in the North Garden of Conservatory Garden
	var px := 1100.0
	var pz := -1200.0
	var py: float = _loader._terrain_y(px, pz)
	root.position = Vector3(px, py, pz)
	root.rotation.y = PI * 0.15  # Slightly angled to garden axis
	root.name = "WisteriaPergola"
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var stone_mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.65, 0.60, 0.54))
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				for si in range(mi.mesh.get_surface_count()):
					mi.mesh.surface_set_material(si, stone_mat)
		for c in n.get_children():
			stack.append(c)
	_loader.add_child(root)
	print("  Pergola placed at (%.0f, %.1f, %.0f)" % [px, py, pz])


# ---------------------------------------------------------------------------
# Ladies' Pavilion — Victorian cast-iron gazebo on the Lake shore
# ---------------------------------------------------------------------------
func _build_ladies_pavilion() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_ladies_pavilion.glb")
	if not FileAccess.file_exists(glb_path):
		print("  Ladies' Pavilion: GLB not found, skipping")
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	var lx := -636.0
	var lz := 578.0
	var ly: float = _loader._terrain_y(lx, lz)
	root.position = Vector3(lx, ly, lz)
	root.rotation.y = PI * 0.3
	root.name = "LadiesPavilion"
	_loader.add_child(root)
	print("  Ladies' Pavilion placed at (%.0f, %.1f, %.0f)" % [lx, ly, lz])


# ---------------------------------------------------------------------------
# Cherry Hill Fountain — Victorian ornamental fountain
# ---------------------------------------------------------------------------
func _build_cherry_hill_fountain() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_cherry_hill_fountain.glb")
	if not FileAccess.file_exists(glb_path):
		print("  Cherry Hill Fountain: GLB not found, skipping")
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	var cx := -615.9
	var cz := 906.9
	var cy: float = _loader._terrain_y(cx, cz)
	root.position = Vector3(cx, cy, cz)
	root.name = "CherryHillFountain"
	_loader.add_child(root)
	print("  Cherry Hill Fountain placed at (%.0f, %.1f, %.0f)" % [cx, cy, cz])


# ---------------------------------------------------------------------------
# Summerhouse at the Dene — small rustic stone shelter
# ---------------------------------------------------------------------------
func _build_summerhouse() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_summerhouse.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	var sx := -372.0
	var sz := 1433.0
	var sy: float = _loader._terrain_y(sx, sz)
	root.position = Vector3(sx, sy, sz)
	root.rotation.y = PI
	root.name = "SummerhouseDene"
	_loader.add_child(root)
	print("  Summerhouse placed at (%.0f, %.1f, %.0f)" % [sx, sy, sz])


# ---------------------------------------------------------------------------
# Kerbs Model Boathouse — small pavilion at Conservatory Water
# ---------------------------------------------------------------------------
func _build_model_boathouse() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_model_boathouse.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	# West shore of Conservatory Water
	var mx := -190.0
	var mz := 960.0
	var my: float = _loader._terrain_y(mx, mz)
	root.position = Vector3(mx, my, mz)
	root.rotation.y = PI * 0.5  # Faces east toward water
	root.name = "KerbsModelBoathouse"
	_loader.add_child(root)
	print("  Model Boathouse placed at (%.0f, %.1f, %.0f)" % [mx, my, mz])


# ---------------------------------------------------------------------------
# Boat landings — wooden docks on the Lake shore
# ---------------------------------------------------------------------------
func _build_boat_landings() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_boat_landing.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var dock_positions: Array = [
		[-688.0, 593.0, PI * 0.7],   # Hernshead
		[-692.0, 770.0, PI * 0.5],   # Western Shore
		[-669.0, 895.0, PI * 0.4],   # Wagner Cove
	]
	var dock_meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var dock_mesh: Mesh = null
	for mname in dock_meshes:
		dock_mesh = dock_meshes[mname] as Mesh
		break
	if dock_mesh == null:
		return
	var xforms: Array = []
	for dock in dock_positions:
		var dx: float = dock[0]
		var dz: float = dock[1]
		var dr: float = dock[2]
		var dy: float = _loader._terrain_y(dx, dz)
		var basis := Basis(Vector3.UP, dr)
		xforms.append(Transform3D(basis, Vector3(dx, dy, dz)))
	if not xforms.is_empty():
		_loader._spawn_multimesh(dock_mesh, null, xforms, "BoatLandings")
	print("  Boat landings: %d placed" % xforms.size())


# ---------------------------------------------------------------------------
# Cop Cot — rustic timber shelter on rocky knoll overlooking the Lake
# ---------------------------------------------------------------------------
func _build_cop_cot() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_cop_cot.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	# Cop Cot sits on a rocky knoll southwest of the Lake
	var cx := -750.0
	var cz := 930.0
	var cy: float = _loader._terrain_y(cx, cz)
	root.position = Vector3(cx, cy, cz)
	root.rotation.y = PI * 0.8
	root.name = "CopCot"
	_loader.add_child(root)
	print("  Cop Cot placed at (%.0f, %.1f, %.0f)" % [cx, cy, cz])


# ---------------------------------------------------------------------------
# Imagine mosaic — Strawberry Fields memorial
# ---------------------------------------------------------------------------
func _build_imagine_mosaic() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_imagine_mosaic.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	var ix := -787.4
	var iz := 826.8
	var iy: float = _loader._terrain_y(ix, iz) + 0.02  # Flush with ground
	root.position = Vector3(ix, iy, iz)
	root.name = "ImagineMosaic"
	_loader.add_child(root)
	print("  Imagine mosaic placed at (%.0f, %.1f, %.0f)" % [ix, iy, iz])


# ---------------------------------------------------------------------------
# Tennis House — Tudor Revival building at the Tennis Center
# ---------------------------------------------------------------------------
func _build_tennis_house() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_tennis_house.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	var tx := 297.0
	var tz := -721.0
	var ty: float = _loader._terrain_y(tx, tz)
	root.position = Vector3(tx, ty, tz)
	root.rotation.y = PI
	root.name = "TennisHouse"
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var stone_mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.52, 0.28, 0.20))
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				for si in range(mi.mesh.get_surface_count()):
					mi.mesh.surface_set_material(si, stone_mat)
		for c in n.get_children():
			stack.append(c)
	_loader.add_child(root)
	print("  Tennis House placed at (%.0f, %.1f, %.0f)" % [tx, ty, tz])


# ---------------------------------------------------------------------------
# 79th Street Maintenance Yard
# ---------------------------------------------------------------------------
func _build_maintenance_yard() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_maintenance_yard.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	var mx := -476.0
	var mz := 266.0
	var my: float = _loader._terrain_y(mx, mz)
	root.position = Vector3(mx, my, mz)
	root.rotation.y = PI * 0.5
	root.name = "MaintenanceYard"
	_loader.add_child(root)
	print("  Maintenance Yard placed at (%.0f, %.1f, %.0f)" % [mx, my, mz])


# ---------------------------------------------------------------------------
# Dana Pier — stone pier at Harlem Meer
# ---------------------------------------------------------------------------
func _build_dana_pier() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_dana_pier.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	# Near Dana Discovery Center, extending into Harlem Meer
	var dx := 420.0
	var dz := -1830.0
	var dy: float = _loader._terrain_y(dx, dz)
	root.position = Vector3(dx, dy, dz)
	root.rotation.y = PI  # Points north into Meer
	root.name = "DanaPier"
	_loader.add_child(root)
	print("  Dana Pier placed at (%.0f, %.1f, %.0f)" % [dx, dy, dz])


# ---------------------------------------------------------------------------
# Stone weirs — low dams along The Loch and other streams
# ---------------------------------------------------------------------------
func _build_stone_weirs() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_stone_weir.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var weir_meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var weir_mesh: Mesh = null
	for mname in weir_meshes:
		weir_mesh = weir_meshes[mname] as Mesh
		break
	if weir_mesh == null:
		return
	# Weir positions along The Loch and other waterfall locations
	var weir_positions: Array = [
		[600.0, -1200.0, PI * 0.3],    # The Loch upper
		[700.0, -1380.0, PI * 0.5],    # The Loch middle
		[850.0, -1480.0, PI * 0.2],    # The Loch lower
		[-600.0, 430.0, PI * 0.7],     # Gill stream
	]
	var xforms: Array = []
	for w in weir_positions:
		var wx: float = w[0]
		var wz: float = w[1]
		var wr: float = w[2]
		var wy: float = _loader._terrain_y(wx, wz)
		var basis := Basis(Vector3.UP, wr)
		xforms.append(Transform3D(basis, Vector3(wx, wy, wz)))
	if not xforms.is_empty():
		_loader._spawn_multimesh(weir_mesh, null, xforms, "StoneWeirs")
	print("  Stone weirs: %d placed" % xforms.size())


# ---------------------------------------------------------------------------
# Bethesda Terrace Arcade — tiled barrel-vault passage beneath 72nd St
# ---------------------------------------------------------------------------
func _build_bethesda_arcade() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_bethesda_arcade.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	if gltf_doc.append_from_file(glb_path, gltf_state) != OK:
		return
	var root: Node3D = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return
	# Centered between upper Mall terrace and Bethesda Fountain
	var ax := -480.0
	var az := 1020.0
	var ay: float = _loader._terrain_y(ax, az) - 1.0  # slightly below grade (arcade is sunken)
	root.position = Vector3(ax, ay, az)
	root.rotation.y = PI * 0.05  # slight rotation matching terrace alignment
	root.name = "BethesdaArcade"
	_loader.add_child(root)
	print("  Bethesda Arcade placed at (%.0f, %.1f, %.0f)" % [ax, ay, az])


# ---------------------------------------------------------------------------
# Conservatory Garden fountains — Untermyer + Burnett Memorial
# ---------------------------------------------------------------------------
func _build_conservatory_fountains() -> void:
	# Untermyer Fountain (Three Dancing Maidens) — south/Italian garden
	var u_path := ProjectSettings.globalize_path("res://models/furniture/cp_untermyer_fountain.glb")
	if FileAccess.file_exists(u_path):
		var gd := GLTFDocument.new()
		var gs := GLTFState.new()
		if gd.append_from_file(u_path, gs) == OK:
			var root: Node3D = gd.generate_scene(gs)
			if root:
				var ux := 1134.0
				var uz := -1256.0
				var uy: float = _loader._terrain_y(ux, uz)
				root.position = Vector3(ux, uy, uz)
				root.name = "UntermyerFountain"
				_loader.add_child(root)
				print("  Untermyer Fountain placed at (%.0f, %.1f, %.0f)" % [ux, uy, uz])

	# Burnett Memorial Fountain (Secret Garden) — north/English garden
	var b_path := ProjectSettings.globalize_path("res://models/furniture/cp_burnett_fountain.glb")
	if FileAccess.file_exists(b_path):
		var gd := GLTFDocument.new()
		var gs := GLTFState.new()
		if gd.append_from_file(b_path, gs) == OK:
			var root: Node3D = gd.generate_scene(gs)
			if root:
				var bx := 1065.0
				var bz := -1134.0
				var by: float = _loader._terrain_y(bx, bz)
				root.position = Vector3(bx, by, bz)
				root.name = "BurnettFountain"
				_loader.add_child(root)
				print("  Burnett Fountain placed at (%.0f, %.1f, %.0f)" % [bx, by, bz])


# ---------------------------------------------------------------------------
# Rustic bridges — log bridges at woodland stream crossings
# ---------------------------------------------------------------------------
func _build_rustic_bridges() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_rustic_bridge.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var bridge_meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var bridge_mesh: Mesh = null
	for mname in bridge_meshes:
		bridge_mesh = bridge_meshes[mname] as Mesh
		break
	if bridge_mesh == null:
		return
	# Known rustic bridge locations at stream crossings in woodland areas
	# The Loch (North Woods) — multiple crossings along its 71-point course
	# The Gill (Ramble area) — crossings along cascading streams
	var bridge_positions: Array = [
		[560.0, -1180.0, PI * 0.4],    # The Loch — upper crossing near North Woods
		[650.0, -1300.0, PI * 0.6],    # The Loch — middle crossing
		[750.0, -1420.0, PI * 0.3],    # The Loch — lower crossing near Pool
		[-380.0, 500.0, PI * 0.8],     # The Gill — upper Ramble crossing
		[-420.0, 600.0, PI * 0.5],     # The Gill — lower cascade crossing
		[-500.0, 350.0, PI * 0.6],     # Ramble stream crossing near Azalea Pond
	]
	var xforms: Array = []
	for b in bridge_positions:
		var bx: float = b[0]
		var bz: float = b[1]
		var br: float = b[2]
		var by: float = _loader._terrain_y(bx, bz)
		var basis := Basis(Vector3.UP, br)
		xforms.append(Transform3D(basis, Vector3(bx, by, bz)))
	if not xforms.is_empty():
		_loader._spawn_multimesh(bridge_mesh, null, xforms, "RusticBridges")
	print("  Rustic bridges: %d placed" % xforms.size())


# ---------------------------------------------------------------------------
# Dog run fencing — chain-link fence around 3 off-leash dog areas
# ---------------------------------------------------------------------------
func _build_dog_run_fences(landuse: Array) -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_dog_run_fence.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var fence_meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var fence_mesh: Mesh = null
	for mname in fence_meshes:
		fence_mesh = fence_meshes[mname] as Mesh
		break
	if fence_mesh == null:
		return

	# Fence section is 3m wide — instance along polygon perimeters
	const SECTION_W := 3.0
	var xforms: Array = []
	var run_count := 0

	for zone in landuse:
		if str(zone.get("type", "")) != "dog_park":
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue
		run_count += 1

		# Walk polygon perimeter, placing fence sections every SECTION_W metres
		for pi in pts.size():
			var p0x: float = float(pts[pi][0])
			var p0z: float = float(pts[pi][1])
			var ni: int = (pi + 1) % pts.size()
			var p1x: float = float(pts[ni][0])
			var p1z: float = float(pts[ni][1])

			var dx: float = p1x - p0x
			var dz: float = p1z - p0z
			var seg_len: float = sqrt(dx * dx + dz * dz)
			if seg_len < 0.5:
				continue

			var n_sections: int = maxi(1, int(round(seg_len / SECTION_W)))
			var yaw: float = atan2(dx, dz)

			for si in n_sections:
				var t: float = (float(si) + 0.5) / float(n_sections)
				var fx: float = p0x + dx * t
				var fz: float = p0z + dz * t
				var fy: float = _loader._terrain_y(fx, fz)
				var basis := Basis(Vector3.UP, yaw)
				xforms.append(Transform3D(basis, Vector3(fx, fy, fz)))

	if not xforms.is_empty():
		_loader._spawn_multimesh(fence_mesh, null, xforms, "DogRunFences")
	print("  Dog run fences: %d sections around %d runs" % [xforms.size(), run_count])


# ---------------------------------------------------------------------------
# Park wayfinding signs — brown wooden signs at major path intersections
# ---------------------------------------------------------------------------
func _build_park_signs(paths: Array) -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_park_sign.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var sign_meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var sign_mesh: Mesh = null
	for mname in sign_meshes:
		sign_mesh = sign_meshes[mname] as Mesh
		break
	if sign_mesh == null:
		return

	# Apply wood shader if available, otherwise keep GLB material
	var wood_sh: Shader = _loader._get_shader("wood", "res://shaders/wood.gdshader")
	if wood_sh:
		for si in sign_mesh.get_surface_count():
			var wood_mat := ShaderMaterial.new()
			wood_mat.shader = wood_sh
			wood_mat.set_shader_parameter("wood_color", Vector3(0.25, 0.15, 0.08))
			sign_mesh.surface_set_material(si, wood_mat)

	# Find path intersections — collect all path endpoints, cluster them
	const GRID_SIZE := 10.0
	var grid: Dictionary = {}  # "gx|gz" -> Array of [x, z]

	for path in paths:
		var hw: String = str(path.get("highway", ""))
		if hw in ["secondary", "service", "tertiary", "residential"]:
			continue  # skip roads
		var pts: Array = path.get("points", [])
		if pts.size() < 2:
			continue
		# Start and end points
		for pidx in [0, pts.size() - 1]:
			var pt: Array = pts[pidx]
			var px: float = float(pt[0])
			var pz: float = float(pt[2]) if pt.size() > 2 else float(pt[1])
			var gx: int = int(floorf(px / GRID_SIZE))
			var gz: int = int(floorf(pz / GRID_SIZE))
			var gk: String = "%d|%d" % [gx, gz]
			if not grid.has(gk):
				grid[gk] = []
			grid[gk].append([px, pz])

	# Find cells with 3+ path endpoints = intersection
	var intersections: Array = []
	for gk in grid:
		var pts: Array = grid[gk]
		if pts.size() >= 3:
			var cx := 0.0
			var cz := 0.0
			for p in pts:
				cx += float(p[0])
				cz += float(p[1])
			cx /= float(pts.size())
			cz /= float(pts.size())
			intersections.append([cx, cz, pts.size()])

	# Sort by connectivity (most paths first), deduplicate within 20m
	intersections.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	var final: Array = []
	for inter in intersections:
		var ix: float = float(inter[0])
		var iz: float = float(inter[1])
		if not _loader._in_boundary(ix, iz):
			continue
		var too_close := false
		for f in final:
			var fdx: float = ix - float(f[0])
			var fdz: float = iz - float(f[1])
			if fdx * fdx + fdz * fdz < 400.0:  # 20m minimum spacing
				too_close = true
				break
		if not too_close:
			final.append(inter)
		if final.size() >= 80:  # cap at ~80 signs (realistic for CP)
			break

	# Place signs
	var xforms: Array = []
	var rng := RandomNumberGenerator.new()
	for f in final:
		var fx: float = float(f[0])
		var fz: float = float(f[1])
		var fy: float = _loader._terrain_y(fx, fz)
		rng.seed = int(fx * 73856.0 + fz * 19349.0) & 0x7FFFFFFF
		var yaw: float = rng.randf() * TAU  # random facing
		var basis := Basis(Vector3.UP, yaw)
		xforms.append(Transform3D(basis, Vector3(fx, fy, fz)))

	if not xforms.is_empty():
		_loader._spawn_multimesh(sign_mesh, null, xforms, "ParkSigns")
	print("  Park signs: %d placed at path intersections" % xforms.size())

	# Named gate labels at park entrances
	var gate_names: Array = [
		["Merchants' Gate", -1050.0, 2025.0],
		["Women's Gate", -1100.0, 1800.0],
		["Artisans' Gate", -1050.0, 1575.0],
		["Naturalists' Gate", -1100.0, 1200.0],
		["Hunters' Gate", -1100.0, 750.0],
		["Mariners' Gate", -1100.0, 225.0],
		["Gate of All Saints", -1100.0, -375.0],
		["Boys' Gate", -1100.0, -900.0],
		["Strangers' Gate", -1100.0, -1500.0],
		["Farmers' Gate", 300.0, -2000.0],
		["Warriors' Gate", 700.0, -2000.0],
		["Pioneers' Gate", 1200.0, -2000.0],
		["Woodsmen's Gate", 1200.0, -1350.0],
		["Girls' Gate", 1200.0, -750.0],
		["Engineers' Gate", 1200.0, -225.0],
		["Inventors' Gate", 1200.0, 225.0],
		["Miners' Gate", 1200.0, 750.0],
		["Children's Gate", 1200.0, 1125.0],
		["Scholars' Gate", 1200.0, 1950.0],
	]
	var gate_label_count := 0
	for g in gate_names:
		var gname: String = str(g[0])
		var gx: float = float(g[1])
		var gz: float = float(g[2])
		var gy: float = _loader._terrain_y(gx, gz)
		var label := Label3D.new()
		label.text = gname
		label.font_size = 32
		label.position = Vector3(gx, gy + 3.5, gz)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.45, 0.35, 0.20, 0.75)
		label.outline_modulate = Color(0.1, 0.08, 0.05, 0.55)
		label.outline_size = 5
		label.no_depth_test = false
		label.pixel_size = 0.012
		_loader.add_child(label)
		gate_label_count += 1
	print("  Gate labels: %d named entrances" % gate_label_count)

	# Named path labels at midpoints of major park paths
	var path_label_count := 0
	var labeled_paths: Dictionary = {}  # dedup by name
	for path in paths:
		var pname: String = str(path.get("name", ""))
		if pname.is_empty():
			continue
		var hw: String = str(path.get("highway", ""))
		if hw in ["secondary", "tertiary", "residential", "service"]:
			continue  # skip roads
		if pname in labeled_paths:
			continue
		var pts: Array = path.get("points", [])
		if pts.size() < 5:
			continue
		# Use midpoint
		var mid: int = pts.size() / 2
		var mx: float = float(pts[mid][0])
		var mz: float = float(pts[mid][2]) if len(pts[mid]) > 2 else float(pts[mid][1])
		if not _loader._in_boundary(mx, mz):
			continue
		var my: float = _loader._terrain_y(mx, mz)
		var label := Label3D.new()
		label.text = pname
		label.font_size = 22
		label.position = Vector3(mx, my + 2.5, mz)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.50, 0.45, 0.35, 0.55)
		label.outline_modulate = Color(0.08, 0.06, 0.04, 0.40)
		label.outline_size = 4
		label.no_depth_test = false
		label.pixel_size = 0.01
		_loader.add_child(label)
		labeled_paths[pname] = true
		path_label_count += 1
	print("  Path labels: %d named paths" % path_label_count)


# ---------------------------------------------------------------------------
# Reservoir fence — tall chain-link around JKO Reservoir running track
# ---------------------------------------------------------------------------
func _build_reservoir_fence(water: Array) -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_reservoir_fence.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var fence_meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var fence_mesh: Mesh = null
	for mname in fence_meshes:
		fence_mesh = fence_meshes[mname] as Mesh
		break
	if fence_mesh == null:
		return

	# Find the reservoir polygon
	var res_pts: Array = []
	for wb in water:
		var wname: String = str(wb.get("name", ""))
		if "reservoir" in wname.to_lower():
			res_pts = wb.get("points", wb.get("polygon", []))
			break
	if res_pts.size() < 10:
		return

	# Place fence sections around the perimeter, offset 3m outward from water edge
	const SECTION_W := 3.0
	const FENCE_OFFSET := 5.0  # metres outside water polygon

	# Compute polygon centroid for outward offset direction
	var cx := 0.0
	var cz := 0.0
	for pt in res_pts:
		cx += float(pt[0])
		cz += float(pt[1])
	cx /= float(res_pts.size())
	cz /= float(res_pts.size())

	var xforms: Array = []

	for pi in res_pts.size():
		var p0x: float = float(res_pts[pi][0])
		var p0z: float = float(res_pts[pi][1])
		var ni: int = (pi + 1) % res_pts.size()
		var p1x: float = float(res_pts[ni][0])
		var p1z: float = float(res_pts[ni][1])

		var dx: float = p1x - p0x
		var dz: float = p1z - p0z
		var seg_len: float = sqrt(dx * dx + dz * dz)
		if seg_len < 0.5:
			continue

		# Outward normal (away from centroid)
		var nx: float = -dz / seg_len
		var nz: float = dx / seg_len
		# Ensure it points away from centroid
		var mx: float = (p0x + p1x) * 0.5 - cx
		var mz: float = (p0z + p1z) * 0.5 - cz
		if nx * mx + nz * mz < 0.0:
			nx = -nx
			nz = -nz

		var n_sections: int = maxi(1, int(round(seg_len / SECTION_W)))
		var yaw: float = atan2(dx, dz)

		for si in n_sections:
			var t: float = (float(si) + 0.5) / float(n_sections)
			var fx: float = p0x + dx * t + nx * FENCE_OFFSET
			var fz: float = p0z + dz * t + nz * FENCE_OFFSET
			var fy: float = _loader._terrain_y(fx, fz)
			var basis := Basis(Vector3.UP, yaw)
			xforms.append(Transform3D(basis, Vector3(fx, fy, fz)))

	if not xforms.is_empty():
		_loader._spawn_multimesh(fence_mesh, null, xforms, "ReservoirFence")
	print("  Reservoir fence: %d sections around running track" % xforms.size())


# ---------------------------------------------------------------------------
# Playground equipment — swing sets + play structures at playground zones
# ---------------------------------------------------------------------------
func _build_playground_equipment(landuse: Array) -> void:
	var swing_path := ProjectSettings.globalize_path("res://models/furniture/cp_swing_set.glb")
	var play_path := ProjectSettings.globalize_path("res://models/furniture/cp_play_structure.glb")

	var swing_mesh: Mesh = null
	var play_mesh: Mesh = null

	var sw_meshes: Dictionary = _loader._load_glb_meshes(swing_path)
	for mname in sw_meshes:
		swing_mesh = sw_meshes[mname] as Mesh
		break

	var pl_meshes: Dictionary = _loader._load_glb_meshes(play_path)
	for mname in pl_meshes:
		play_mesh = pl_meshes[mname] as Mesh
		break

	if swing_mesh == null and play_mesh == null:
		return

	var swing_xforms: Array = []
	var play_xforms: Array = []
	var rng := RandomNumberGenerator.new()

	for zone in landuse:
		if str(zone.get("type", "")) != "playground":
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue

		# Compute centroid
		var cx := 0.0
		var cz := 0.0
		for pt in pts:
			cx += float(pt[0])
			cz += float(pt[1])
		cx /= float(pts.size())
		cz /= float(pts.size())

		if not _loader._in_boundary(cx, cz):
			continue

		rng.seed = int(cx * 73856.0 + cz * 19349.0) & 0x7FFFFFFF
		var yaw: float = rng.randf() * TAU
		var cy: float = _loader._terrain_y(cx, cz)

		# Place swing set offset from center
		if swing_mesh:
			var sx: float = cx + cos(yaw) * 4.0
			var sz: float = cz + sin(yaw) * 4.0
			var sy: float = _loader._terrain_y(sx, sz)
			swing_xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(sx, sy, sz)))

		# Place play structure at center
		if play_mesh:
			var py: float = cy
			play_xforms.append(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(cx, py, cz)))

	if not swing_xforms.is_empty() and swing_mesh:
		_loader._spawn_multimesh(swing_mesh, null, swing_xforms, "SwingSets")
	if not play_xforms.is_empty() and play_mesh:
		_loader._spawn_multimesh(play_mesh, null, play_xforms, "PlayStructures")
	print("  Playground equipment: %d swing sets, %d play structures" % [swing_xforms.size(), play_xforms.size()])


# ---------------------------------------------------------------------------
# Sports equipment — backstops at baseball diamonds, hoops at basketball courts
# ---------------------------------------------------------------------------
func _build_sports_equipment(landuse: Array) -> void:
	var backstop_path := ProjectSettings.globalize_path("res://models/furniture/cp_backstop.glb")
	var hoop_path := ProjectSettings.globalize_path("res://models/furniture/cp_basketball_hoop.glb")

	var backstop_mesh: Mesh = null
	var hoop_mesh: Mesh = null

	var bs_meshes: Dictionary = _loader._load_glb_meshes(backstop_path)
	for mname in bs_meshes:
		backstop_mesh = bs_meshes[mname] as Mesh
		break

	var hp_meshes: Dictionary = _loader._load_glb_meshes(hoop_path)
	for mname in hp_meshes:
		hoop_mesh = hp_meshes[mname] as Mesh
		break

	if backstop_mesh == null and hoop_mesh == null:
		return

	var backstop_xforms: Array = []
	var hoop_xforms: Array = []
	var rng := RandomNumberGenerator.new()

	for zone in landuse:
		if str(zone.get("type", "")) != "pitch":
			continue
		var sport: String = str(zone.get("sport", ""))
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue

		# Compute centroid
		var cx := 0.0
		var cz := 0.0
		for pt in pts:
			cx += float(pt[0])
			cz += float(pt[1])
		cx /= float(pts.size())
		cz /= float(pts.size())

		var cy: float = _loader._terrain_y(cx, cz)

		if sport == "baseball" and backstop_mesh:
			# Find "home plate" corner — typically the vertex farthest from centroid
			# of the infield diamond shape, or use first vertex as approximation
			var home_x: float = float(pts[0][0])
			var home_z: float = float(pts[0][1])
			# Find direction from home plate to centroid (outfield direction)
			var dx: float = cx - home_x
			var dz: float = cz - home_z
			var d: float = sqrt(dx * dx + dz * dz)
			if d > 0.1:
				# Backstop goes BEHIND home plate, facing outfield
				var yaw: float = atan2(dx, dz)
				var bx: float = home_x - dx / d * 3.0  # 3m behind home
				var bz: float = home_z - dz / d * 3.0
				var by: float = _loader._terrain_y(bx, bz)
				backstop_xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(bx, by, bz)))

		elif sport == "basketball" and hoop_mesh:
			# Place hoops at both ends of the court
			if pts.size() >= 4:
				# Find long axis by checking edge lengths
				var e0x: float = float(pts[1][0]) - float(pts[0][0])
				var e0z: float = float(pts[1][1]) - float(pts[0][1])
				var e1x: float = float(pts[2][0]) - float(pts[1][0])
				var e1z: float = float(pts[2][1]) - float(pts[1][1])
				var l0: float = sqrt(e0x * e0x + e0z * e0z)
				var l1: float = sqrt(e1x * e1x + e1z * e1z)

				var long_dx: float
				var long_dz: float
				var long_l: float
				if l0 > l1:
					long_dx = e0x; long_dz = e0z; long_l = l0
				else:
					long_dx = e1x; long_dz = e1z; long_l = l1

				if long_l > 0.1:
					var ndx: float = long_dx / long_l
					var ndz: float = long_dz / long_l
					var yaw: float = atan2(ndx, ndz)
					# Hoop at each end, 1.5m from edge
					for end_val in [-1.0, 1.0]:
						var end: float = float(end_val)
						var hx: float = cx + ndx * (long_l * 0.5 - 1.5) * end
						var hz: float = cz + ndz * (long_l * 0.5 - 1.5) * end
						var hy: float = _loader._terrain_y(hx, hz)
						var h_yaw: float = yaw + (PI if end > 0.0 else 0.0)
						hoop_xforms.append(Transform3D(Basis(Vector3.UP, h_yaw), Vector3(hx, hy, hz)))

	if not backstop_xforms.is_empty() and backstop_mesh:
		_loader._spawn_multimesh(backstop_mesh, null, backstop_xforms, "BaseballBackstops")
	if not hoop_xforms.is_empty() and hoop_mesh:
		_loader._spawn_multimesh(hoop_mesh, null, hoop_xforms, "BasketballHoops")
	# Tennis nets
	var net_path := ProjectSettings.globalize_path("res://models/furniture/cp_tennis_net.glb")
	var net_mesh: Mesh = null
	var nt_meshes: Dictionary = _loader._load_glb_meshes(net_path)
	for mname in nt_meshes:
		net_mesh = nt_meshes[mname] as Mesh
		break
	var net_xforms: Array = []

	if net_mesh:
		for zone in landuse:
			if str(zone.get("type", "")) != "pitch":
				continue
			var sport2: String = str(zone.get("sport", ""))
			if sport2 != "tennis":
				continue
			var pts2: Array = zone.get("points", [])
			if pts2.size() < 4:
				continue

			var cx2 := 0.0
			var cz2 := 0.0
			for pt in pts2:
				cx2 += float(pt[0])
				cz2 += float(pt[1])
			cx2 /= float(pts2.size())
			cz2 /= float(pts2.size())

			var cy2: float = _loader._terrain_y(cx2, cz2)

			# Find short axis (net runs along short axis at center)
			var e0x2: float = float(pts2[1][0]) - float(pts2[0][0])
			var e0z2: float = float(pts2[1][1]) - float(pts2[0][1])
			var e1x2: float = float(pts2[2][0]) - float(pts2[1][0])
			var e1z2: float = float(pts2[2][1]) - float(pts2[1][1])
			var l0: float = sqrt(e0x2 * e0x2 + e0z2 * e0z2)
			var l1: float = sqrt(e1x2 * e1x2 + e1z2 * e1z2)

			# Short axis direction = net direction
			var short_dx: float
			var short_dz: float
			if l0 < l1:
				short_dx = e0x2; short_dz = e0z2
			else:
				short_dx = e1x2; short_dz = e1z2
			var short_l: float = sqrt(short_dx * short_dx + short_dz * short_dz)
			if short_l < 0.1:
				continue
			var yaw: float = atan2(short_dx, short_dz)
			net_xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(cx2, cy2, cz2)))

	if not net_xforms.is_empty() and net_mesh:
		_loader._spawn_multimesh(net_mesh, null, net_xforms, "TennisNets")

	# Soccer goals
	var goal_path := ProjectSettings.globalize_path("res://models/furniture/cp_soccer_goal.glb")
	var goal_mesh: Mesh = null
	var gl_meshes: Dictionary = _loader._load_glb_meshes(goal_path)
	for mname in gl_meshes:
		goal_mesh = gl_meshes[mname] as Mesh
		break
	var goal_xforms: Array = []

	if goal_mesh:
		for zone in landuse:
			if str(zone.get("type", "")) != "pitch":
				continue
			var sport3: String = str(zone.get("sport", ""))
			if not ("soccer" in sport3):
				continue
			var pts3: Array = zone.get("points", [])
			if pts3.size() < 4:
				continue

			var cx3 := 0.0
			var cz3 := 0.0
			for pt in pts3:
				cx3 += float(pt[0])
				cz3 += float(pt[1])
			cx3 /= float(pts3.size())
			cz3 /= float(pts3.size())
			var cy3: float = _loader._terrain_y(cx3, cz3)

			# Find short axis (goals at each end of long axis)
			var e0x3: float = float(pts3[1][0]) - float(pts3[0][0])
			var e0z3: float = float(pts3[1][1]) - float(pts3[0][1])
			var e1x3: float = float(pts3[2][0]) - float(pts3[1][0])
			var e1z3: float = float(pts3[2][1]) - float(pts3[1][1])
			var l0g: float = sqrt(e0x3 * e0x3 + e0z3 * e0z3)
			var l1g: float = sqrt(e1x3 * e1x3 + e1z3 * e1z3)

			var long_dx3: float
			var long_dz3: float
			var long_l3: float
			if l0g > l1g:
				long_dx3 = e0x3; long_dz3 = e0z3; long_l3 = l0g
			else:
				long_dx3 = e1x3; long_dz3 = e1z3; long_l3 = l1g
			if long_l3 < 1.0:
				continue
			var ndx3: float = long_dx3 / long_l3
			var ndz3: float = long_dz3 / long_l3

			for end_val3 in [-1.0, 1.0]:
				var end3: float = float(end_val3)
				var gx: float = cx3 + ndx3 * (long_l3 * 0.5 - 1.0) * end3
				var gz: float = cz3 + ndz3 * (long_l3 * 0.5 - 1.0) * end3
				var gy: float = _loader._terrain_y(gx, gz)
				# Goal faces inward toward center
				var g_yaw: float = atan2(ndx3, ndz3) + (PI if end3 > 0.0 else 0.0)
				goal_xforms.append(Transform3D(Basis(Vector3.UP, g_yaw), Vector3(gx, gy, gz)))

	if not goal_xforms.is_empty() and goal_mesh:
		_loader._spawn_multimesh(goal_mesh, null, goal_xforms, "SoccerGoals")

	# Handball walls
	var hwall_path := ProjectSettings.globalize_path("res://models/furniture/cp_handball_wall.glb")
	var hwall_mesh: Mesh = null
	var hw_meshes: Dictionary = _loader._load_glb_meshes(hwall_path)
	for mname in hw_meshes:
		hwall_mesh = hw_meshes[mname] as Mesh
		break
	var hwall_xforms: Array = []

	if hwall_mesh:
		for zone in landuse:
			if str(zone.get("type", "")) != "pitch":
				continue
			if str(zone.get("sport", "")) != "american_handball":
				continue
			var pts_h: Array = zone.get("points", [])
			if pts_h.size() < 4:
				continue

			var cx_h := 0.0
			var cz_h := 0.0
			for pt in pts_h:
				cx_h += float(pt[0])
				cz_h += float(pt[1])
			cx_h /= float(pts_h.size())
			cz_h /= float(pts_h.size())
			var cy_h: float = _loader._terrain_y(cx_h, cz_h)

			# Find short axis (wall at one short end)
			var e0x_h: float = float(pts_h[1][0]) - float(pts_h[0][0])
			var e0z_h: float = float(pts_h[1][1]) - float(pts_h[0][1])
			var e1x_h: float = float(pts_h[2][0]) - float(pts_h[1][0])
			var e1z_h: float = float(pts_h[2][1]) - float(pts_h[1][1])
			var l0_h: float = sqrt(e0x_h * e0x_h + e0z_h * e0z_h)
			var l1_h: float = sqrt(e1x_h * e1x_h + e1z_h * e1z_h)

			var long_dx_h: float
			var long_dz_h: float
			var long_l_h: float
			if l0_h > l1_h:
				long_dx_h = e0x_h; long_dz_h = e0z_h; long_l_h = l0_h
			else:
				long_dx_h = e1x_h; long_dz_h = e1z_h; long_l_h = l1_h
			if long_l_h < 1.0:
				continue
			var ndx_h: float = long_dx_h / long_l_h
			var ndz_h: float = long_dz_h / long_l_h
			# Wall at one end of the long axis, facing inward
			var wx_h: float = cx_h + ndx_h * (long_l_h * 0.5 - 0.3)
			var wz_h: float = cz_h + ndz_h * (long_l_h * 0.5 - 0.3)
			var wy_h: float = _loader._terrain_y(wx_h, wz_h)
			# Short axis direction for wall alignment
			var short_dx_h: float
			var short_dz_h: float
			if l0_h < l1_h:
				short_dx_h = e0x_h; short_dz_h = e0z_h
			else:
				short_dx_h = e1x_h; short_dz_h = e1z_h
			var h_yaw: float = atan2(short_dx_h, short_dz_h)
			hwall_xforms.append(Transform3D(Basis(Vector3.UP, h_yaw), Vector3(wx_h, wy_h, wz_h)))

	if not hwall_xforms.is_empty() and hwall_mesh:
		_loader._spawn_multimesh(hwall_mesh, null, hwall_xforms, "HandballWalls")

	print("  Sports equipment: %d backstops, %d hoops, %d nets, %d goals, %d walls" % [backstop_xforms.size(), hoop_xforms.size(), net_xforms.size(), goal_xforms.size(), hwall_xforms.size()])


# ---------------------------------------------------------------------------
# Bridle path posts — split-rail wooden fence along horseback riding trails
# ---------------------------------------------------------------------------
func _build_bridle_posts(paths: Array) -> void:
	# Use a simple cylinder + rail from park_loader utilities
	# Bridle paths have wooden split-rail fencing every ~5m
	var wood_sh: Shader = _loader._get_shader("wood", "res://shaders/wood.gdshader")

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()

	const POST_H := 1.0       # 1m tall posts
	const POST_R := 0.04      # 4cm radius
	const RAIL_R := 0.03      # 3cm radius rail
	const SPACING := 5.0      # 5m between posts
	const OFFSET := 1.2       # 1.2m from path centerline
	const SEGS := 6           # cylinder segments

	var post_count := 0
	for path in paths:
		if str(path.get("highway", "")) != "bridleway":
			continue
		var pts: Array = path.get("points", [])
		if pts.size() < 2:
			continue

		# Walk along path placing posts on both sides
		var dist := 0.0
		for pi in range(pts.size() - 1):
			var ax: float = float(pts[pi][0])
			var az: float = float(pts[pi][2]) if len(pts[pi]) > 2 else float(pts[pi][1])
			var bx: float = float(pts[pi + 1][0])
			var bz: float = float(pts[pi + 1][2]) if len(pts[pi + 1]) > 2 else float(pts[pi + 1][1])
			var sdx: float = bx - ax
			var sdz: float = bz - az
			var seg_len: float = sqrt(sdx * sdx + sdz * sdz)
			if seg_len < 0.1:
				continue

			# Perpendicular for offset
			var px: float = -sdz / seg_len
			var pz: float = sdx / seg_len

			while dist < seg_len:
				var t: float = dist / seg_len
				var wx: float = ax + sdx * t
				var wz: float = az + sdz * t
				if not _loader._in_boundary(wx, wz):
					dist += SPACING
					continue
				var wy: float = _loader._terrain_y(wx, wz)

				# Place post on both sides
				for side_val in [-1.0, 1.0]:
					var side: float = float(side_val)
					var ppx: float = wx + px * OFFSET * side
					var ppz: float = wz + pz * OFFSET * side
					var ppy: float = _loader._terrain_y(ppx, ppz)
					# Simple cylinder post
					for si in SEGS:
						var a0: float = TAU * float(si) / float(SEGS)
						var a1: float = TAU * float(si + 1) / float(SEGS)
						var c0x: float = cos(a0) * POST_R
						var c0z: float = sin(a0) * POST_R
						var c1x: float = cos(a1) * POST_R
						var c1z: float = sin(a1) * POST_R
						var n0 := Vector3(cos(a0), 0, sin(a0))
						var n1 := Vector3(cos(a1), 0, sin(a1))
						# Two triangles for the side quad
						verts.append(Vector3(ppx + c0x, ppy, ppz + c0z))
						normals.append(n0)
						verts.append(Vector3(ppx + c1x, ppy, ppz + c1z))
						normals.append(n1)
						verts.append(Vector3(ppx + c1x, ppy + POST_H, ppz + c1z))
						normals.append(n1)
						verts.append(Vector3(ppx + c0x, ppy, ppz + c0z))
						normals.append(n0)
						verts.append(Vector3(ppx + c1x, ppy + POST_H, ppz + c1z))
						normals.append(n1)
						verts.append(Vector3(ppx + c0x, ppy + POST_H, ppz + c0z))
						normals.append(n0)
					post_count += 1
				dist += SPACING
			dist -= seg_len  # carry remainder to next segment

	if verts.is_empty():
		return

	# Build mesh with wood material
	var mesh: ArrayMesh = _loader._make_mesh(verts, normals)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.22, 0.12)  # warm wood brown
	mat.roughness = 0.85
	mesh.surface_set_material(0, mat)
	if wood_sh:
		var wood_mat := ShaderMaterial.new()
		wood_mat.shader = wood_sh
		wood_mat.set_shader_parameter("wood_color", Vector3(0.35, 0.22, 0.12))
		mesh.surface_set_material(0, wood_mat)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "BridlePosts"
	_loader.add_child(mi)
	print("  Bridle path posts: %d along horseback trails" % post_count)


# ---------------------------------------------------------------------------
# Stone staircases — 250 OSM highway=steps paths built as stepped geometry
# ---------------------------------------------------------------------------
func _build_staircases(paths: Array) -> void:
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.52, 0.50, 0.46))

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var col_verts := PackedVector3Array()
	var rail_verts := PackedVector3Array()
	var rail_normals := PackedVector3Array()
	var stair_count := 0

	for path in paths:
		if str(path.get("highway", "")) != "steps":
			continue
		var pts: Array = path.get("points", [])
		if pts.size() < 2:
			continue
		var mx := (float(pts[0][0]) + float(pts[pts.size()-1][0])) * 0.5
		var mz := (float(pts[0][2]) + float(pts[pts.size()-1][2])) * 0.5
		if not _loader._in_boundary(mx, mz):
			continue
		_build_single_staircase(pts, path, verts, normals, col_verts,
			rail_verts, rail_normals)
		stair_count += 1

	if verts.is_empty():
		return

	var mesh: ArrayMesh = _loader._make_mesh(verts, normals)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Staircases"
	_loader.add_child(mi)

	# Iron handrails
	if not rail_verts.is_empty():
		var iron_sh: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
		var rail_mat := ShaderMaterial.new()
		rail_mat.shader = iron_sh
		rail_mat.set_shader_parameter("iron_color", Vector3(0.06, 0.06, 0.07))
		rail_mat.set_shader_parameter("base_roughness", 0.60)
		rail_mat.set_shader_parameter("base_metallic", 0.90)
		var rail_mesh: ArrayMesh = _loader._make_mesh(rail_verts, rail_normals)
		rail_mesh.surface_set_material(0, rail_mat)
		var rmi := MeshInstance3D.new()
		rmi.mesh = rail_mesh
		rmi.name = "StaircaseHandrails"
		_loader.add_child(rmi)
		print("  Staircase handrails: %d verts" % rail_verts.size())

	# Collision for staircases
	if not col_verts.is_empty():
		var body := StaticBody3D.new()
		body.name = "Staircase_Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_verts)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_loader.add_child(body)

	print("ParkLoader: staircases = %d (%d verts)" % [stair_count, verts.size()])


func _build_single_staircase(pts: Array, path: Dictionary,
		verts: PackedVector3Array, normals: PackedVector3Array,
		col_verts: PackedVector3Array,
		rail_verts: PackedVector3Array, rail_normals: PackedVector3Array) -> void:
	## Build stepped geometry for a single staircase path.
	## Standard Central Park granite steps: 15cm riser, 30cm tread.
	## Also generates iron handrails on both sides (for stairs with ≥4 steps).
	const RISER_H := 0.15  # metres
	const TREAD_D := 0.30  # metres (horizontal depth of each step)
	const HALF_THICK := 0.05  # half-thickness of tread slab

	# Get path width (steps usually 2-4m wide)
	var half_w: float = _loader._path_width(path) * 0.5
	half_w = clampf(half_w, 0.75, 5.0)

	# Compute total horizontal run and elevation change along the path
	var start_x := float(pts[0][0]); var start_z := float(pts[0][2])
	var end_x := float(pts[pts.size()-1][0]); var end_z := float(pts[pts.size()-1][2])
	var start_y: float = _loader._terrain_y(start_x, start_z)
	var end_y: float = _loader._terrain_y(end_x, end_z)

	var dy := end_y - start_y
	if absf(dy) < 0.1:
		return  # flat — no steps needed

	# Number of steps from elevation change
	var n_steps := maxi(1, int(round(absf(dy) / RISER_H)))
	# Clamp to reasonable range
	n_steps = mini(n_steps, 200)

	# Direction along the staircase (XZ plane)
	var dx := end_x - start_x
	var dz := end_z - start_z
	var run := sqrt(dx * dx + dz * dz)
	if run < 0.3:
		return

	var dir_x := dx / run
	var dir_z := dz / run
	# Perpendicular for width
	var perp_x := -dir_z
	var perp_z := dir_x

	# Step heights: go uphill or downhill
	var going_up := dy > 0.0
	var base_y := minf(start_y, end_y)
	# If going down, reverse iteration direction
	var step_dir := 1.0 if going_up else -1.0
	var origin_x := start_x if going_up else end_x
	var origin_z := start_z if going_up else end_z

	# Horizontal step spacing
	var step_run := run / float(n_steps)
	var step_rise := absf(dy) / float(n_steps)

	for si in n_steps:
		var t := float(si) / float(n_steps)
		# Step position along the run
		var cx := origin_x + dir_x * step_dir * step_run * (float(si) + 0.5)
		var cz := origin_z + dir_z * step_dir * step_run * (float(si) + 0.5)
		var step_top_y := base_y + step_rise * float(si + 1)

		# Four corners of the tread (top surface)
		var td := TREAD_D * 0.5  # half tread depth along run direction
		var fl_x := cx - dir_x * td + perp_x * half_w
		var fl_z := cz - dir_z * td + perp_z * half_w
		var fr_x := cx - dir_x * td - perp_x * half_w
		var fr_z := cz - dir_z * td - perp_z * half_w
		var bl_x := cx + dir_x * td + perp_x * half_w
		var bl_z := cz + dir_z * td + perp_z * half_w
		var br_x := cx + dir_x * td - perp_x * half_w
		var br_z := cz + dir_z * td - perp_z * half_w

		# Tread top face (horizontal)
		var tfl := Vector3(fl_x, step_top_y, fl_z)
		var tfr := Vector3(fr_x, step_top_y, fr_z)
		var tbl := Vector3(bl_x, step_top_y, bl_z)
		var tbr := Vector3(br_x, step_top_y, br_z)

		var tread := PackedVector3Array([tfl, tbl, tfr, tfr, tbl, tbr])
		verts.append_array(tread)
		col_verts.append_array(tread)
		for _j in 6: normals.append(Vector3.UP)

		# Riser face (vertical front of step)
		var riser_bot_y := step_top_y - step_rise
		var rfl := Vector3(fl_x, riser_bot_y, fl_z)
		var rfr := Vector3(fr_x, riser_bot_y, fr_z)
		var riser_n := Vector3(-dir_x, 0.0, -dir_z)

		var riser := PackedVector3Array([rfl, tfl, rfr, rfr, tfl, tfr])
		verts.append_array(riser)
		col_verts.append_array(riser)
		for _j in 6: normals.append(riser_n)

	# --- Iron handrails on both sides (only for staircases ≥ 4 steps) ---
	if n_steps < 4:
		return
	const RAIL_H := 0.90   # handrail height above step surface
	const RAIL_R := 0.025  # rail tube radius (25mm — standard pipe)
	const POST_R := 0.02   # post radius (20mm)
	const POST_SPACING := 4  # one post every N steps
	const RAIL_SEGS := 6   # cylinder segments

	# Rail offset slightly inside step edges
	var rail_offset := half_w - 0.05
	for side_val in [-1.0, 1.0]:
		var side: float = float(side_val)
		var rx_off := perp_x * rail_offset * side
		var rz_off := perp_z * rail_offset * side
		var out_n := Vector3(perp_x * side, 0, perp_z * side)

		# Top rail: continuous tube from bottom step to top step
		for si in n_steps:
			var cx0 := origin_x + dir_x * step_dir * step_run * float(si)
			var cz0 := origin_z + dir_z * step_dir * step_run * float(si)
			var y0 := base_y + step_rise * float(si + 1) + RAIL_H
			var cx1 := origin_x + dir_x * step_dir * step_run * float(si + 1)
			var cz1 := origin_z + dir_z * step_dir * step_run * float(si + 1)
			var y1 := base_y + step_rise * float(si + 2) + RAIL_H
			if si == n_steps - 1:
				y1 = base_y + step_rise * float(n_steps) + RAIL_H

			var p0 := Vector3(cx0 + rx_off, y0, cz0 + rz_off)
			var p1 := Vector3(cx1 + rx_off, y1, cz1 + rz_off)
			_add_rail_segment(p0, p1, RAIL_R, RAIL_SEGS, rail_verts, rail_normals)

		# Vertical posts at intervals
		for si in range(0, n_steps + 1, POST_SPACING):
			var pcx := origin_x + dir_x * step_dir * step_run * float(si)
			var pcz := origin_z + dir_z * step_dir * step_run * float(si)
			var pby: float
			if si < n_steps:
				pby = base_y + step_rise * float(si + 1)
			else:
				pby = base_y + step_rise * float(n_steps)
			var pty := pby + RAIL_H
			var p_base := Vector3(pcx + rx_off, pby, pcz + rz_off)
			var p_top := Vector3(pcx + rx_off, pty, pcz + rz_off)
			_add_rail_segment(p_base, p_top, POST_R, RAIL_SEGS, rail_verts, rail_normals)


func _add_rail_segment(p0: Vector3, p1: Vector3, radius: float, segs: int,
		verts: PackedVector3Array, normals: PackedVector3Array) -> void:
	## Add a cylindrical tube segment between two points.
	var axis := p1 - p0
	var length := axis.length()
	if length < 0.01:
		return
	var up := axis.normalized()
	# Find perpendicular vectors
	var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var right := up.cross(arbitrary).normalized()
	var fwd := right.cross(up).normalized()

	for si in segs:
		var a0 := TAU * float(si) / float(segs)
		var a1 := TAU * float(si + 1) / float(segs)
		var n0 := right * cos(a0) + fwd * sin(a0)
		var n1 := right * cos(a1) + fwd * sin(a1)
		var b0 := p0 + n0 * radius
		var b1 := p0 + n1 * radius
		var t0 := p1 + n0 * radius
		var t1 := p1 + n1 * radius
		# Two triangles for cylinder quad
		verts.append(b0); normals.append(n0)
		verts.append(b1); normals.append(n1)
		verts.append(t1); normals.append(n1)
		verts.append(b0); normals.append(n0)
		verts.append(t1); normals.append(n1)
		verts.append(t0); normals.append(n0)


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
		if not (ztype in label_types):
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


# ---------------------------------------------------------------------------
# Fitness stations — exercise equipment along running paths
# ---------------------------------------------------------------------------
func _build_fitness_stations(paths: Array) -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_fitness_station.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var mesh: Mesh = null
	for mname in meshes:
		mesh = meshes[mname] as Mesh
		break
	if mesh == null:
		return

	# Apply steel material
	var iron_sh: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
	if iron_sh:
		var mat := ShaderMaterial.new()
		mat.shader = iron_sh
		mat.set_shader_parameter("iron_color", Vector3(0.30, 0.28, 0.25))
		mat.set_shader_parameter("base_roughness", 0.55)
		mat.set_shader_parameter("base_metallic", 0.90)
		for si in mesh.get_surface_count():
			mesh.surface_set_material(si, mat)

	# Known fitness station locations along Central Park running paths
	# (North-south along the park, near the bridle path and loop drive)
	var stations: Array = [
		# North end
		[290, -1580],   # near North Meadow
		[180, -1200],   # near East Meadow
		# Upper park
		[-100, -800],   # near Reservoir east
		[-500, -600],   # near Reservoir west
		# Central
		[-200, -200],   # near Great Lawn east
		[-550, -50],    # near Tennis courts
		# South-central
		[-350, 400],    # near Ramble
		[-650, 600],    # near Lake west
		# South
		[-450, 1000],   # near Bethesda
		[-300, 1400],   # near Mall south
		# Far south
		[-500, 1650],   # near Heckscher
		[-100, 1700],   # near Wollman
	]

	var xforms: Array = []
	for st in stations:
		var wx: float = float(st[0])
		var wz: float = float(st[1])
		if not _loader._in_boundary(wx, wz):
			continue
		var wy: float = _loader._terrain_y(wx, wz)
		# Random orientation
		var rng := RandomNumberGenerator.new()
		rng.seed = int(wx * 73.0 + wz * 191.0) & 0x7FFFFFFF
		var yaw := rng.randf() * TAU
		xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(wx, wy, wz)))

	if not xforms.is_empty():
		_loader._spawn_multimesh(mesh, null, xforms, "FitnessStations")
	print("  Fitness stations: %d placed" % xforms.size())


# ---------------------------------------------------------------------------
# Mile markers — bronze distance markers along the loop drive
# ---------------------------------------------------------------------------
func _build_mile_markers(paths: Array) -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_mile_marker.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var mesh: Mesh = null
	for mname in meshes:
		mesh = meshes[mname] as Mesh
		break
	if mesh == null:
		return

	# Find the main loop drive paths (primary/secondary roads)
	# Place markers every ~400m (quarter mile) along drives
	const MARKER_SPACING := 400.0  # metres between markers
	var xforms: Array = []
	var placed_count := 0

	for path in paths:
		var hw: String = str(path.get("highway", ""))
		if hw != "primary" and hw != "secondary":
			continue
		var pts: Array = path.get("points", [])
		if pts.size() < 2:
			continue

		# Walk along path placing markers
		var dist := 0.0
		for pi in range(pts.size() - 1):
			var ax: float = float(pts[pi][0])
			var az: float = float(pts[pi][2]) if len(pts[pi]) > 2 else float(pts[pi][1])
			var bx: float = float(pts[pi + 1][0])
			var bz: float = float(pts[pi + 1][2]) if len(pts[pi + 1]) > 2 else float(pts[pi + 1][1])
			var sdx: float = bx - ax
			var sdz: float = bz - az
			var seg_len: float = sqrt(sdx * sdx + sdz * sdz)
			if seg_len < 0.1:
				continue

			while dist < seg_len:
				var t: float = dist / seg_len
				var wx: float = ax + sdx * t
				var wz: float = az + sdz * t
				if not _loader._in_boundary(wx, wz):
					dist += MARKER_SPACING
					continue
				var wy: float = _loader._terrain_y(wx, wz)
				# Perpendicular offset (1.5m from path center)
				var px: float = -sdz / seg_len
				var pz: float = sdx / seg_len
				var mx: float = wx + px * 1.5
				var mz: float = wz + pz * 1.5
				var my: float = _loader._terrain_y(mx, mz)
				var yaw: float = atan2(sdx, sdz)
				xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(mx, my, mz)))
				placed_count += 1
				dist += MARKER_SPACING
			dist -= seg_len

	if not xforms.is_empty():
		_loader._spawn_multimesh(mesh, null, xforms, "MileMarkers")
	print("  Mile markers: %d placed" % placed_count)


# ---------------------------------------------------------------------------
# Balustrades — ornamental stone railings at formal terraces
# ---------------------------------------------------------------------------
func _build_balustrades() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_balustrade.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var mesh: Mesh = null
	for mname in meshes:
		mesh = meshes[mname] as Mesh
		break
	if mesh == null:
		return

	# Apply stone material
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var stone_mat: Material = _loader._make_stone_material(
		rw_alb, rw_nrm, rw_rgh, Color(0.62, 0.60, 0.56))
	for si in mesh.get_surface_count():
		mesh.surface_set_material(si, stone_mat)

	# Balustrade sections at formal terrace locations
	# Each entry: [x, z, yaw, count] — count = sections along that edge
	# Bethesda Terrace — upper terrace edge (north, south, east, west sides)
	var sections: Array = [
		# Bethesda Terrace upper level — north edge (overlooking fountain)
		[-480, 1010, 0.0, 8],
		# Bethesda Terrace — east wing
		[-450, 1025, PI * 0.5, 4],
		# Bethesda Terrace — west wing
		[-510, 1025, PI * 0.5, 4],
		# Cherry Hill overlook — stone terrace edge
		[-550, 950, PI * 0.25, 3],
		# Belvedere Castle terrace — south overlook
		[-265, 600, 0.0, 4],
		# Belvedere Castle — east edge
		[-245, 615, PI * 0.5, 2],
		# Conservatory Garden — formal terrace edges
		[1100, -1180, 0.0, 6],
		[1100, -1250, 0.0, 6],
	]

	var xforms: Array = []
	const SECTION_W := 2.0  # matches model width
	for sec in sections:
		var base_x: float = float(sec[0])
		var base_z: float = float(sec[1])
		var yaw: float = float(sec[2])
		var count: int = int(sec[3])
		var dir_x := sin(yaw)
		var dir_z := cos(yaw)
		for i in count:
			var offset: float = (float(i) - float(count - 1) * 0.5) * SECTION_W
			var wx: float = base_x + dir_x * offset
			var wz: float = base_z + dir_z * offset
			var wy: float = _loader._terrain_y(wx, wz)
			xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(wx, wy, wz)))

	if not xforms.is_empty():
		_loader._spawn_multimesh(mesh, null, xforms, "Balustrades")
	print("  Balustrades: %d sections at formal terraces" % xforms.size())


# ---------------------------------------------------------------------------
# Drive-side waste bins — wire mesh trash cans along loop drives
# ---------------------------------------------------------------------------
func _build_drive_waste_bins(paths: Array) -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_wire_trash_can.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var mesh: Mesh = null
	for mname in meshes:
		mesh = meshes[mname] as Mesh
		break
	if mesh == null:
		return

	const BIN_SPACING := 120.0  # one bin every ~120m along drives
	const PATH_OFFSET := 3.5    # 3.5m from path center (at edge of drive)
	var xforms: Array = []

	for path in paths:
		var hw: String = str(path.get("highway", ""))
		# Only along drives (primary=East/West Drive, secondary=transverses)
		if hw != "primary" and hw != "secondary":
			continue
		var pts: Array = path.get("points", [])
		if pts.size() < 2:
			continue

		var dist := 60.0  # start offset to stagger from mile markers
		for pi in range(pts.size() - 1):
			var ax: float = float(pts[pi][0])
			var az: float = float(pts[pi][2]) if len(pts[pi]) > 2 else float(pts[pi][1])
			var bx: float = float(pts[pi + 1][0])
			var bz: float = float(pts[pi + 1][2]) if len(pts[pi + 1]) > 2 else float(pts[pi + 1][1])
			var sdx: float = bx - ax
			var sdz: float = bz - az
			var seg_len: float = sqrt(sdx * sdx + sdz * sdz)
			if seg_len < 0.1:
				continue

			while dist < seg_len:
				var t: float = dist / seg_len
				var wx: float = ax + sdx * t
				var wz: float = az + sdz * t
				if not _loader._in_boundary(wx, wz):
					dist += BIN_SPACING
					continue
				# Perpendicular offset to edge
				var px: float = -sdz / seg_len
				var pz: float = sdx / seg_len
				var mx: float = wx + px * PATH_OFFSET
				var mz: float = wz + pz * PATH_OFFSET
				var my: float = _loader._terrain_y(mx, mz)
				var yaw: float = atan2(px, pz)  # face away from path
				xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(mx, my, mz)))
				dist += BIN_SPACING
			dist -= seg_len

	if not xforms.is_empty():
		_loader._spawn_multimesh(mesh, null, xforms, "DriveWasteBins")
	print("  Drive waste bins: %d placed" % xforms.size())


# ---------------------------------------------------------------------------
# Retaining walls — low stone walls along steep terrain grade changes
# ---------------------------------------------------------------------------
func _build_retaining_walls(paths: Array) -> void:
	## Detect steep terrain grade changes alongside paths and build
	## low Manhattan schist retaining walls to hold the grade.
	var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
	var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
	var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
	var mat: Material = _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh,
		Color(0.48, 0.46, 0.42))

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var wall_count := 0

	const CHECK_DIST := 3.0    # metres from path center to check
	const MIN_DROP := 0.6      # minimum grade drop to trigger wall (0.6m)
	const WALL_THICK := 0.30   # wall thickness
	const SAMPLE_STEP := 4.0   # sample every 4m along path

	for path in paths:
		var hw: String = str(path.get("highway", ""))
		if hw == "steps" or hw == "bridleway":
			continue  # skip staircases and bridle paths
		var pts: Array = path.get("points", [])
		if pts.size() < 2:
			continue

		for pi in range(pts.size() - 1):
			var ax: float = float(pts[pi][0])
			var az: float = float(pts[pi][2]) if len(pts[pi]) > 2 else float(pts[pi][1])
			var bx: float = float(pts[pi + 1][0])
			var bz: float = float(pts[pi + 1][2]) if len(pts[pi + 1]) > 2 else float(pts[pi + 1][1])
			var sdx: float = bx - ax
			var sdz: float = bz - az
			var seg_len: float = sqrt(sdx * sdx + sdz * sdz)
			if seg_len < 1.0:
				continue
			var ndx := sdx / seg_len
			var ndz := sdz / seg_len
			# Perpendicular
			var px := -ndz
			var pz := ndx

			var dist := 0.0
			while dist < seg_len:
				var t: float = dist / seg_len
				var wx: float = ax + sdx * t
				var wz: float = az + sdz * t
				if not _loader._in_boundary(wx, wz):
					dist += SAMPLE_STEP
					continue
				var wy: float = _loader._terrain_y(wx, wz)

				# Check both sides for grade drop
				for side_val in [-1.0, 1.0]:
					var side: float = float(side_val)
					var cx: float = wx + px * CHECK_DIST * side
					var cz: float = wz + pz * CHECK_DIST * side
					var cy: float = _loader._terrain_y(cx, cz)
					var drop: float = wy - cy
					if drop < MIN_DROP:
						continue
					# Clamp wall height
					var wall_h: float = clampf(drop, MIN_DROP, 2.5)
					# Wall at the edge, facing outward
					var wall_x: float = wx + px * (CHECK_DIST - 0.5) * side
					var wall_z: float = wz + pz * (CHECK_DIST - 0.5) * side
					var wall_y: float = _loader._terrain_y(wall_x, wall_z)
					var out_nx := px * side
					var out_nz := pz * side
					var half_w := SAMPLE_STEP * 0.5
					# Wall face (4m wide segment)
					var fl := Vector3(wall_x - ndx * half_w, wall_y, wall_z - ndz * half_w)
					var fr := Vector3(wall_x + ndx * half_w, wall_y, wall_z + ndz * half_w)
					var tl := Vector3(fl.x, wall_y + wall_h, fl.z)
					var tr := Vector3(fr.x, wall_y + wall_h, fr.z)
					var face_n := Vector3(out_nx, 0, out_nz)
					verts.append_array(PackedVector3Array([fl, tl, fr, fr, tl, tr]))
					for _j in 6: normals.append(face_n)
					# Top face
					var tl2 := Vector3(fl.x - out_nx * WALL_THICK, tl.y, fl.z - out_nz * WALL_THICK)
					var tr2 := Vector3(fr.x - out_nx * WALL_THICK, tr.y, fr.z - out_nz * WALL_THICK)
					verts.append_array(PackedVector3Array([tl, tl2, tr, tr, tl2, tr2]))
					for _j in 6: normals.append(Vector3.UP)
					wall_count += 1
				dist += SAMPLE_STEP

	if verts.is_empty():
		return

	var mesh: ArrayMesh = _loader._make_mesh(verts, normals)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "RetainingWalls"
	_loader.add_child(mi)
	print("  Retaining walls: %d segments (%d verts)" % [wall_count, verts.size()])


# ---------------------------------------------------------------------------
# Bollards — cast iron posts at park entrances and drive restrictions
# ---------------------------------------------------------------------------
func _build_bollards() -> void:
	var glb_path := ProjectSettings.globalize_path("res://models/furniture/cp_bollard.glb")
	if not FileAccess.file_exists(glb_path):
		return
	var meshes: Dictionary = _loader._load_glb_meshes(glb_path)
	var mesh: Mesh = null
	for mname in meshes:
		mesh = meshes[mname] as Mesh
		break
	if mesh == null:
		return

	# Apply cast iron material
	var iron_sh: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
	if iron_sh:
		var mat := ShaderMaterial.new()
		mat.shader = iron_sh
		mat.set_shader_parameter("iron_color", Vector3(0.06, 0.06, 0.07))
		mat.set_shader_parameter("base_roughness", 0.60)
		mat.set_shader_parameter("base_metallic", 0.85)
		for si in mesh.get_surface_count():
			mesh.surface_set_material(si, mat)

	# Bollard positions at park gate entrances — rows of 3-5 bollards
	# across path width. Gate positions from boundary_builder gate data.
	var gate_positions: Array = [
		# South gates
		[-835, 1812, 0.0],    # Merchants' Gate (Columbus Circle)
		[-680, 1872, PI*0.5], # Scholars' Gate (60th/5th Ave)
		[-545, 1830, 0.0],    # Artists' Gate (59th/6th Ave)
		# West side
		[-855, 1550, PI*0.5], # Women's Gate (72nd/CPW)
		[-880, 1170, PI*0.5], # Hunters' Gate (81st/CPW)
		[-850, 770, PI*0.5],  # Mariners' Gate (85th/CPW)
		[-810, 340, PI*0.5],  # Gate of All Saints (96th/CPW)
		[-700, -250, PI*0.5], # Boys' Gate (100th/CPW)
		[-620, -900, PI*0.5], # Strangers' Gate (106th/CPW)
		# East side
		[700, 1570, PI*0.5],  # Inventors' Gate (72nd/5th)
		[560, 1170, PI*0.5],  # Engineers' Gate (90th/5th)
		[400, 770, PI*0.5],   # Miners' Gate (79th/5th)
		[180, -250, PI*0.5],  # Woodmen's Gate (96th/5th)
		# North
		[-250, -1850, 0.0],   # Farmers' Gate (110th/5th)
		[-500, -1880, 0.0],   # Warriors' Gate (110th/CPW)
	]

	var xforms: Array = []
	const BOLLARD_SPACING := 1.2  # 1.2m between bollards
	const BOLLARDS_PER_GATE := 5  # row of 5 bollards

	for gp in gate_positions:
		var gx: float = float(gp[0])
		var gz: float = float(gp[1])
		var yaw: float = float(gp[2])
		# Direction perpendicular to path for row placement
		var row_dx := sin(yaw)
		var row_dz := cos(yaw)
		for bi in BOLLARDS_PER_GATE:
			var offset: float = (float(bi) - float(BOLLARDS_PER_GATE - 1) * 0.5) * BOLLARD_SPACING
			var bx: float = gx + row_dx * offset
			var bz: float = gz + row_dz * offset
			var by: float = _loader._terrain_y(bx, bz)
			xforms.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(bx, by, bz)))

	if not xforms.is_empty():
		_loader._spawn_multimesh(mesh, null, xforms, "Bollards")
	print("  Bollards: %d at %d gate entrances" % [xforms.size(), gate_positions.size()])
