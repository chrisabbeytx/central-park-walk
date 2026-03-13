## Infrastructure builder — labels, statues, amenities, facilities, viewpoints, attractions, gardens, meadow labels, special zones.

var _loader



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
