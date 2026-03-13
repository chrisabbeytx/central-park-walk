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
		var n_panels := max(1, int(round(seg_len / panel_w)))
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
	for side in [-1.0, 1.0]:
		var end_z := cz + cd * side
		var basket_z := end_z - 1.575 * s * side  # basket offset from baseline
		# Free throw lane (key): 5.8m × 4.9m (FIBA)
		var key_hw := 2.45 * s
		var key_d := 5.8 * s
		_rect_outline(cx, end_z - key_d * 0.5 * side, y, key_hw, key_d * 0.5, lw, col, verts, normals, colors)
		# Free throw circle (1.8m radius)
		var ft_z := end_z - key_d * side
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
	for side in [-1.0, 1.0]:
		var end_z := cz + fd * side
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
	if df_meshes.has("CP_DrinkingFountain"):
		df_mesh = df_meshes["CP_DrinkingFountain"] as Mesh
		# Apply weather-responsive materials to fountain surfaces
		if df_mesh and df_mesh.get_surface_count() >= 2:
			var rw_alb: ImageTexture = _loader._load_tex("res://textures/rock_wall_diff.jpg")
			var rw_nrm: ImageTexture = _loader._load_tex("res://textures/rock_wall_nrm.jpg")
			var rw_rgh: ImageTexture = _loader._load_tex("res://textures/rock_wall_rgh.jpg")
			df_mesh.surface_set_material(0, _loader._make_stone_material(rw_alb, rw_nrm, rw_rgh, Color(0.55, 0.52, 0.48)))
			var iron_sh: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
			var df_iron := ShaderMaterial.new()
			df_iron.shader = iron_sh
			df_iron.set_shader_parameter("iron_color", Vector3(0.08, 0.08, 0.06))
			df_mesh.surface_set_material(1, df_iron)
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
	for zone in _loader.landuse_zones:
		if zone.get("type", "") != "garden":
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 4:
			continue
		var name_: String = zone.get("name", "")
		if name_.is_empty():
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

	print("  Gardens: %d labeled (hedge geometry removed — needs Blender models)" % label_count)


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
		_build_single_staircase(pts, path, verts, normals, col_verts)
		stair_count += 1

	if verts.is_empty():
		return

	var mesh: ArrayMesh = _loader._make_mesh(verts, normals)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Staircases"
	_loader.add_child(mi)

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
		col_verts: PackedVector3Array) -> void:
	## Build stepped geometry for a single staircase path.
	## Standard Central Park granite steps: 15cm riser, 30cm tread.
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
