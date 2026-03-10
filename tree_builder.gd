# tree_builder.gd
# Tree geometry: GLB-based trees with spatially chunked MultiMesh instances
# Extracted from park_loader.gd — all shared utilities accessed via _loader reference.

var _loader  # Reference to park_loader for shared utilities

# Maps data species archetype → phenology index for GPU seasonal color (12 species)
const PHENOLOGY_INDEX := {
	"oak": 0, "maple": 1, "elm": 2, "birch": 3, "deciduous": 4, "conifer": 5,
	"honeylocust": 6, "callery_pear": 7, "ginkgo": 8, "london_plane": 9,
	"linden": 10, "cherry": 11, "zelkova": 2,  # zelkova shares elm phenology
	"dead": 4,  # dead trees use deciduous phenology (no leaves rendered anyway)
	"willow": 3,  # willow shares birch phenology (early fall yellow, early spring)
}
# Maps archetype → base GLB model name
const ARCHETYPE_MODEL := {
	"oak": "oak", "maple": "maple", "elm": "elm", "birch": "birch",
	"deciduous": "deciduous", "conifer": "pine",
	"honeylocust": "honeylocust", "callery_pear": "callery_pear", "ginkgo": "ginkgo",
	"london_plane": "london_plane", "linden": "linden", "cherry": "cherry",
	"zelkova": "elm", "dead": "dead", "willow": "willow",
}

func _init(loader) -> void:
	_loader = loader


func _build_trees(trees: Array) -> void:
	if trees.is_empty():
		return

	var rng := RandomNumberGenerator.new()

	# --- Load GLB tree models (Quaternius CC0) via GLTFDocument ---
	# Each GLB has 5 tree variants as separate MeshInstance3D children.
	# Models use centimetre scale (node scale=100 in GLB) and Z-up orientation.
	# We load at runtime via GLTFDocument since the project has no editor import cache.
	# Per-archetype leaf and bark colors (12 species)
	var leaf_tints := {
		"oak":           Vector3(0.24, 0.40, 0.14),   # dark green
		"maple":         Vector3(0.30, 0.50, 0.18),   # bright green, warm
		"elm":           Vector3(0.24, 0.42, 0.15),   # medium-warm green (American Elm)
		"birch":         Vector3(0.34, 0.52, 0.22),   # light yellow-green
		"deciduous":     Vector3(0.26, 0.44, 0.16),   # medium green
		"pine":          Vector3(0.14, 0.30, 0.10),   # dark desaturated green
		"honeylocust":   Vector3(0.32, 0.52, 0.20),   # light airy green (compound leaves)
		"callery_pear":  Vector3(0.28, 0.48, 0.18),   # fresh green, dense crown
		"ginkgo":        Vector3(0.30, 0.50, 0.22),   # yellow-green (fan-shaped leaves)
		"london_plane":  Vector3(0.24, 0.44, 0.16),   # medium green, large leaves
		"linden":        Vector3(0.26, 0.48, 0.18),   # warm green (heart-shaped leaves)
		"cherry":        Vector3(0.30, 0.50, 0.20),   # fresh green, small ornamental
		"zelkova":       Vector3(0.22, 0.40, 0.14),   # dark warm green (elm family)
		"dead":          Vector3(0.42, 0.38, 0.34),   # gray weathered (no leaves)
		"willow":        Vector3(0.30, 0.50, 0.15),   # yellow-green, narrow leaves
	}
	var bark_colors := {
		"oak":           Color(0.40, 0.32, 0.24),     # dark brown, deeply furrowed
		"maple":         Color(0.50, 0.40, 0.30),     # medium brown
		"elm":           Color(0.30, 0.25, 0.18),     # gray-brown (American Elm bark)
		"birch":         Color(0.80, 0.76, 0.68),     # distinctive white bark
		"deciduous":     Color(0.42, 0.34, 0.26),     # dark brown
		"pine":          Color(0.48, 0.34, 0.22),     # reddish-brown
		"honeylocust":   Color(0.45, 0.38, 0.28),     # dark gray-brown
		"callery_pear":  Color(0.42, 0.36, 0.28),     # gray-brown, smooth
		"ginkgo":        Color(0.50, 0.42, 0.32),     # gray, furrowed with age
		"london_plane":  Color(0.60, 0.56, 0.48),     # distinctive mottled cream-gray
		"linden":        Color(0.42, 0.36, 0.28),     # gray-brown, ridged
		"cherry":        Color(0.52, 0.32, 0.22),     # reddish-brown, glossy
		"zelkova":       Color(0.38, 0.30, 0.22),     # gray, exfoliating
		"dead":          Color(0.42, 0.38, 0.34),     # weathered gray dead wood
		"willow":        Color(0.40, 0.35, 0.28),     # gray-brown, deeply furrowed
	}
	# --- Load 5 base GLB models, then create per-archetype colored copies ---
	var species_meshes: Dictionary = {}  # archetype_name -> Array[Mesh]
	var species_heights: Dictionary = {} # archetype_name -> float (mesh height in raw units)

	# Step 1: Load raw meshes + heights from 5 GLB files
	var base_meshes: Dictionary = {}     # model_name -> Array[Mesh]
	var base_heights: Dictionary = {}    # model_name -> float
	var base_leaf_textures: Dictionary = {} # model_name -> Array[Texture2D or null]
	var base_alpha_thresholds: Dictionary = {} # model_name -> Array[float]
	var leaf_shader: Shader = _loader._get_shader("tree_leaf_glb", _tree_glb_leaf_shader_code())
	var bark_shader: Shader = _loader._get_shader("tree_bark", "res://shaders/tree_bark.gdshader")

	for model_name in ["maple", "birch", "deciduous", "pine", "elm", "oak", "cherry", "ginkgo", "honeylocust", "linden", "london_plane", "callery_pear", "dead", "willow"]:
		var abs_path := ProjectSettings.globalize_path("res://models/trees/%s.glb" % model_name)
		if not FileAccess.file_exists(abs_path):
			print("WARNING: tree model not found: %s" % abs_path)
			continue
		var gltf_doc := GLTFDocument.new()
		var gltf_state := GLTFState.new()
		var err := gltf_doc.append_from_file(abs_path, gltf_state)
		if err != OK:
			print("WARNING: failed to load GLB %s (error %d)" % [abs_path, err])
			continue
		var root: Node = gltf_doc.generate_scene(gltf_state)
		if root == null:
			print("WARNING: generate_scene returned null for %s" % model_name)
			continue
		var meshes: Array = []
		var node_scale := 1.0
		_loader._collect_meshes(root, meshes)
		for child in root.get_children():
			if child is Node3D:
				var s: Vector3 = (child as Node3D).scale
				if s.x > 1.0:
					node_scale = s.x
					break
				for gc in child.get_children():
					if gc is Node3D:
						var gs: Vector3 = (gc as Node3D).scale
						if gs.x > 1.0:
							node_scale = gs.x
							break
				if node_scale > 1.0:
					break
		var max_h := 0.0
		for m: Mesh in meshes:
			var ab: AABB = m.get_aabb()
			var h := ab.size.z
			if h < 0.001:
				h = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
			max_h = maxf(max_h, h)
		# Extract leaf textures and alpha thresholds before freeing scene
		var ltexs: Array = []
		var lalphas: Array = []
		for m: Mesh in meshes:
			var tex: Texture2D = null
			var alpha := 0.5
			for si in m.get_surface_count():
				var smat: Material = m.surface_get_material(si)
				if smat is StandardMaterial3D:
					var sm: StandardMaterial3D = smat as StandardMaterial3D
					if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						if sm.albedo_texture:
							tex = sm.albedo_texture
						if sm.alpha_scissor_threshold > 0.0:
							alpha = sm.alpha_scissor_threshold
			ltexs.append(tex)
			lalphas.append(alpha)
		root.queue_free()
		if meshes.is_empty():
			print("WARNING: no meshes found in %s" % model_name)
			continue
		base_meshes[model_name] = meshes
		base_heights[model_name] = max_h
		base_leaf_textures[model_name] = ltexs
		base_alpha_thresholds[model_name] = lalphas
		print("Trees: loaded %s — %d variants, raw=%.4f actual=%.1fm" % [model_name, meshes.size(), max_h, max_h * node_scale])

	# Step 2: Create per-archetype mesh copies with distinct leaf/bark colors
	for archetype in ARCHETYPE_MODEL:
		var model_name: String = ARCHETYPE_MODEL[archetype]
		if not base_meshes.has(model_name):
			continue
		var src_meshes: Array = base_meshes[model_name]
		var leaf_tint: Vector3 = leaf_tints.get(archetype, Vector3(0.28, 0.48, 0.18))
		var bark_col: Color = bark_colors.get(archetype, Color(0.48, 0.38, 0.28))
		var ltexs: Array = base_leaf_textures[model_name]
		var lalphas: Array = base_alpha_thresholds[model_name]
		var arch_meshes: Array = []
		for mi in src_meshes.size():
			var m: Mesh = src_meshes[mi].duplicate(true)
			for si in m.get_surface_count():
				var smat: Material = m.surface_get_material(si)
				if smat is StandardMaterial3D:
					var sm: StandardMaterial3D = smat as StandardMaterial3D
					if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						var leaf_mat := ShaderMaterial.new()
						leaf_mat.shader = leaf_shader
						leaf_mat.set_shader_parameter("albedo_tint", leaf_tint)
						if ltexs[mi]:
							leaf_mat.set_shader_parameter("albedo_tex", ltexs[mi])
						leaf_mat.set_shader_parameter("alpha_scissor", lalphas[mi])
						m.surface_set_material(si, leaf_mat)
					else:
						# Bark: shader for weather/season response
						var bark_mat := ShaderMaterial.new()
						bark_mat.shader = bark_shader
						bark_mat.set_shader_parameter("bark_color", Vector3(bark_col.r, bark_col.g, bark_col.b))
						m.surface_set_material(si, bark_mat)
				elif smat is ShaderMaterial:
					# Already a shader material from a previous archetype's duplicate
					var sm: ShaderMaterial = smat as ShaderMaterial
					var new_mat := sm.duplicate()
					new_mat.set_shader_parameter("albedo_tint", leaf_tint)
					m.surface_set_material(si, new_mat)
			arch_meshes.append(m)
		species_meshes[archetype] = arch_meshes
		species_heights[archetype] = base_heights[model_name]
	print("Trees: %d archetypes from %d base models" % [species_meshes.size(), base_meshes.size()])

	if species_meshes.is_empty():
		print("WARNING: no tree GLB models loaded, falling back skipped")
		return

	# Desired height ranges per species archetype (metres)
	# [min, max] — census DBH drives interpolation within range
	var height_ranges := {
		"oak":           [14.0, 25.0],
		"maple":         [10.0, 20.0],
		"elm":           [18.0, 30.0],   # American Elm — tall vase shape
		"conifer":       [15.0, 30.0],
		"deciduous":     [10.0, 22.0],
		"birch":         [10.0, 18.0],
		"honeylocust":   [12.0, 22.0],   # open, airy crown
		"callery_pear":  [8.0, 14.0],    # medium street tree
		"ginkgo":        [12.0, 20.0],   # slow-growing, columnar
		"london_plane":  [15.0, 30.0],   # tall broad crown, like sycamore
		"linden":        [12.0, 22.0],   # dense symmetrical crown
		"cherry":        [6.0, 12.0],    # small ornamental
		"zelkova":       [12.0, 22.0],   # upright vase shape
		"dead":          [8.0, 16.0],    # shorter (broken top)
		"willow":        [10.0, 18.0],   # weeping willow — wide, medium height
	}

	# Foliage zone data for deciduous sub-species assignment

	# Collect transforms + season data per species-variant for MultiMesh batching
	# Key: "species_variantIdx" -> Array[Transform3D]
	var xf_by_key: Dictionary = {}
	var cd_by_key: Dictionary = {}  # parallel Color arrays for custom_data (season info)
	var all_trunk_xf: Array = []  # for collision
	var _skip_surface := 0
	for i in trees.size():
		var tree_entry = trees[i]
		var pt: Array
		var tree_species := "deciduous"
		var dbh := 12
		# Support both new dict format and legacy [x, h, z] arrays
		if typeof(tree_entry) == TYPE_DICTIONARY:
			pt = tree_entry["pos"]
			tree_species = str(tree_entry.get("species", "deciduous"))
			dbh = int(tree_entry.get("dbh", 12))
		else:
			pt = tree_entry
		var tx := float(pt[0]); var tz := float(pt[2])
		# Use atlas surface type instead of boundary polygon — atlas correctly covers
		# the full park area while the OSM boundary polygon may be undersized.
		var surf: int = _loader._atlas_surface(tx, tz)
		if surf != 1 and surf != 7:  # only place on grass (1) or rock (7)
			_skip_surface += 1
			continue
		var ty: float = _loader._terrain_y(tx, tz)
		rng.seed = i * 1234567891 + 987654321

		# Use the species from data as-is (census or OSM archetype)
		var species: String = tree_species
		if not species_meshes.has(species):
			species = "deciduous"
			if not species_meshes.has(species):
				continue
		# Standing dead trees (snags): ~3% of non-conifer trees become dead snags
		# Natural feature of mature woodland — adds dramatic silhouettes in winter
		if species != "conifer" and species != "dead" and species_meshes.has("dead"):
			var dead_hash := fmod(abs(sin(float(i) * 127.1 + tx * 311.7 + tz * 183.3) * 43758.5453), 1.0)
			if dead_hash < 0.03:  # 3% chance
				species = "dead"
		var variants: Array = species_meshes[species]
		var n_variants := variants.size()
		if n_variants == 0:
			continue

		# Pick variant based on tree index
		var variant_idx := i % n_variants

		# Desired height: use LiDAR measurement if available, else DBH estimate
		var desired_h: float
		if typeof(tree_entry) == TYPE_DICTIONARY and tree_entry.has("lidar_h"):
			desired_h = float(tree_entry["lidar_h"])
			if desired_h < 3.0:
				desired_h = 3.0  # clamp tiny LiDAR readings
		else:
			var h_range: Array = height_ranges.get(species, [10.0, 22.0])
			var h_min := float(h_range[0])
			var h_max := float(h_range[1])
			var dbh_t := clampf((float(dbh) - 3.0) / 30.0, 0.0, 1.0)
			desired_h = lerpf(h_min, h_max, dbh_t)

		# Scale factor: desired_height / mesh_height_in_raw_units
		var mesh_h: float = species_heights[species]
		if mesh_h < 0.001:
			mesh_h = 0.06
		var sy := desired_h / mesh_h

		# Crown width: blend uniform scale with LiDAR crown data for subtle variation
		var sx := sy
		if typeof(tree_entry) == TYPE_DICTIONARY and tree_entry.has("crown_a"):
			var crown_a := float(tree_entry["crown_a"])
			if crown_a > 0.0 and desired_h > 1.0:
				var crown_d := 2.0 * sqrt(crown_a / PI)
				# Ratio of crown spread to height (typical trees: 0.3–1.0)
				var crown_ratio := clampf(crown_d / desired_h, 0.3, 1.2)
				# Apply as a subtle modifier (30% blend) to avoid extreme stretching
				sx = sy * lerpf(1.0, crown_ratio, 0.3)

		# Random Y rotation for variety
		var y_rot := rng.randf() * TAU

		# Build transform: Y rotation × Z-up fix (rotate -90° around X) × non-uniform scale
		# The GLB meshes grow along +Z (Blender convention). We need +Y up.
		# sx scales crown width (XZ), sy scales height (Y after rotation)
		var basis := Basis(Vector3.UP, y_rot) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis().scaled(Vector3(sx, sy, sx))
		var tf := Transform3D(basis, Vector3(tx, ty, tz))

		var key := "%s_%d" % [species, variant_idx]
		if not xf_by_key.has(key):
			xf_by_key[key] = []
			cd_by_key[key] = []
		xf_by_key[key].append(tf)
		# Pack season data: R=species phenology index, G=timing offset, B=evergreen flag
		var pheno_idx: int = PHENOLOGY_INDEX.get(species, 4)
		var timing_off := rng.randf_range(-0.15, 0.15)
		var is_evergreen := 1.0 if species == "conifer" else 0.0
		cd_by_key[key].append(Color(float(pheno_idx) / 11.0, timing_off + 0.5, is_evergreen, 0.0))

		# Collision: simplified cylinder at trunk position
		var trunk_r := desired_h * 0.02
		var col_basis := Basis(
			Vector3(trunk_r, 0.0,      0.0),
			Vector3(0.0,     desired_h, 0.0),
			Vector3(0.0,     0.0,      trunk_r))
		all_trunk_xf.append(Transform3D(col_basis, Vector3(tx, ty + desired_h * 0.5, tz)))

	# --- Spatial chunking for culling ---
	# Each chunk's MMI is positioned at its spatial centre so that
	# visibility_range works per-chunk (distance from camera to node).
	const CHUNK := 80.0

	# Bucket transforms by spatial chunk per-species-variant
	var lod0_chunks: Dictionary = {}

	for key in xf_by_key:
		var xf_arr: Array = xf_by_key[key]
		var cd_arr: Array = cd_by_key[key]
		for j in xf_arr.size():
			var tf: Transform3D = xf_arr[j]
			var cx := int(floorf(tf.origin.x / CHUNK))
			var cz := int(floorf(tf.origin.z / CHUNK))
			var ck0 := "%s|%d|%d" % [key, cx, cz]
			if not lod0_chunks.has(ck0):
				lod0_chunks[ck0] = {"mesh_key": key, "cx": cx, "cz": cz, "xf": [], "cd": []}
			lod0_chunks[ck0]["xf"].append(tf)
			lod0_chunks[ck0]["cd"].append(cd_arr[j])

	# Spawn LOD0 chunks — position MMI at instance centroid for accurate culling
	for ckey in lod0_chunks:
		var info: Dictionary = lod0_chunks[ckey]
		var mesh_key: String = info["mesh_key"]
		var xf_list: Array = info["xf"]
		var cd_list: Array = info["cd"]
		if xf_list.is_empty():
			continue
		var last_us := mesh_key.rfind("_")
		var sp_name: String = mesh_key.substr(0, last_us)
		var vi: int = int(mesh_key.substr(last_us + 1))
		var mesh: Mesh = species_meshes[sp_name][vi]
		var cx_sum := 0.0
		var cy_sum := 0.0
		var cz_sum := 0.0
		for tf: Transform3D in xf_list:
			cx_sum += tf.origin.x
			cy_sum += tf.origin.y
			cz_sum += tf.origin.z
		var n := float(xf_list.size())
		var chunk_origin := Vector3(cx_sum / n, cy_sum / n, cz_sum / n)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = xf_list.size()
		for i in xf_list.size():
			var tf: Transform3D = xf_list[i]
			var local_tf := Transform3D(tf.basis, tf.origin - chunk_origin)
			mm.set_instance_transform(i, local_tf)
			mm.set_instance_custom_data(i, cd_list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = chunk_origin
		mmi.name = "Tree_%s" % ckey.replace("|", "_")
		_loader.add_child(mmi)

	_build_tree_collision(all_trunk_xf)
	print("Trees: %d placed, %d chunks (skipped %d non-grass)" % [
		all_trunk_xf.size(), lod0_chunks.size(), _skip_surface])


func _build_tree_collision(trunk_xf: Array) -> void:
	if trunk_xf.is_empty():
		return
	# One StaticBody3D with a CylinderShape3D per trunk.
	# trunk_xf basis encodes scale + Y rotation. Extract via column lengths.
	var body := StaticBody3D.new()
	body.name = "TreeTrunkCollision"
	for tf: Transform3D in trunk_xf:
		var r: float = tf.basis.x.length()   # trunk_r (x column length)
		var h: float = tf.basis.y.y           # trunk_h (y unaffected by Y rotation)
		var shape        := CylinderShape3D.new()
		shape.radius      = r
		shape.height      = h
		var col          := CollisionShape3D.new()
		col.shape         = shape
		col.position      = tf.origin  # already at trunk centre (base + h/2)
		body.add_child(col)
	_loader.add_child(body)


func _tree_glb_leaf_shader_code() -> String:
	return "res://shaders/tree_leaf.gdshader"
