# boundary_builder.gd
# Park boundary: collision walls, building labels.
# Extracted from park_loader.gd — all shared utilities accessed via _loader reference.

var _loader  # Reference to park_loader for shared utilities

func _init(loader) -> void:
	_loader = loader


func _build_boundary(boundary: Array) -> void:
	if boundary.size() < 3:
		push_warning("ParkLoader: boundary too small – skipping walls")
		return

	# Polygon already populated early in _ready() — just build collision walls
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


func _label_boundary_buildings(buildings: Array) -> void:
	## Add Label3D name tags to named buildings near the park boundary.
	## Uses real building height data for label placement.
	var count := 0
	for b in buildings:
		var bname: String = str(b.get("name", ""))
		if bname.is_empty():
			continue
		var pts: Array = b.get("points", [])
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

		# Skip buildings inside the park — we only want perimeter buildings
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
		var label_y := ty + bld_h * 0.6  # place label at ~60% building height

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
