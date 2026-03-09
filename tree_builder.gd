# tree_builder.gd
# Tree geometry: GLB-based trees with spatially chunked MultiMesh instances
# Extracted from park_loader.gd — all shared utilities accessed via _loader reference.

var _loader  # Reference to park_loader for shared utilities

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
	# Per-species leaf and bark colors
	var leaf_tints := {
		"maple":     Vector3(0.30, 0.50, 0.18),   # bright green, warm
		"birch":     Vector3(0.34, 0.52, 0.22),   # light yellow-green
		"deciduous": Vector3(0.26, 0.44, 0.16),   # medium green
		"pine":      Vector3(0.14, 0.30, 0.10),   # dark desaturated green
		"elm":       Vector3(0.24, 0.42, 0.15),   # medium-warm green (American Elm)
	}
	var bark_colors := {
		"maple":     Color(0.50, 0.40, 0.30),     # medium brown
		"birch":     Color(0.80, 0.76, 0.68),     # distinctive white bark
		"deciduous": Color(0.42, 0.34, 0.26),     # dark brown
		"pine":      Color(0.48, 0.34, 0.22),     # reddish-brown
		"elm":       Color(0.30, 0.25, 0.18),     # gray-brown (American Elm bark)
	}
	var species_meshes: Dictionary = {}  # species_name -> Array[Mesh]
	var species_heights: Dictionary = {} # species_name -> float (mesh height in raw units)
	for species in ["maple", "birch", "deciduous", "pine", "elm"]:
		var abs_path := ProjectSettings.globalize_path("res://models/trees/%s.glb" % species)
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
			print("WARNING: generate_scene returned null for %s" % species)
			continue
		var meshes: Array = []
		var node_scale := 1.0
		_loader._collect_meshes(root, meshes)
		# Detect node scale: Quaternius models have scale=100 on mesh nodes.
		# Scene tree: root → RootNode → NormalTree_N (scale=100, has mesh).
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
		# Compute mesh height — use RAW AABB since we need the scale factor
		# to include the GLB node scale (100x for Quaternius centimetre models).
		# desired_h / raw_mesh_h gives the correct total scale factor.
		var max_h := 0.0
		for m: Mesh in meshes:
			var ab: AABB = m.get_aabb()
			# Use Z dimension for height: GLB models preserve Blender Z-up in raw
			# mesh vertices (axis conversion is a node transform, not baked into verts)
			var h := ab.size.z
			# Fallback: if Z is tiny (degenerate), use max dimension
			if h < 0.001:
				h = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
			max_h = maxf(max_h, h)
		root.queue_free()
		if meshes.is_empty():
			print("WARNING: no meshes found in %s" % species)
			continue
		# Per-species colors for leaves and bark
		var leaf_tint: Vector3 = leaf_tints.get(species, Vector3(0.28, 0.48, 0.18))
		var bark_col: Color = bark_colors.get(species, Color(0.48, 0.38, 0.28))
		var leaf_shader: Shader = _loader._get_shader("tree_leaf_glb", _tree_glb_leaf_shader_code())
		for m: Mesh in meshes:
			for si in m.get_surface_count():
				var smat: Material = m.surface_get_material(si)
				if smat is StandardMaterial3D:
					var sm: StandardMaterial3D = smat as StandardMaterial3D
					if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						# Leaves — replace with snow-aware shader
						var leaf_mat := ShaderMaterial.new()
						leaf_mat.shader = leaf_shader
						leaf_mat.set_shader_parameter("albedo_tint", leaf_tint)
						if sm.albedo_texture:
							leaf_mat.set_shader_parameter("albedo_tex", sm.albedo_texture)
						leaf_mat.set_shader_parameter("alpha_scissor", sm.alpha_scissor_threshold if sm.alpha_scissor_threshold > 0.0 else 0.5)
						m.surface_set_material(si, leaf_mat)
					else:
						# Bark — species-specific color
						sm.albedo_color = bark_col
						sm.roughness = 0.90
						sm.metallic = 0.0
		species_meshes[species] = meshes
		species_heights[species] = max_h
		print("Trees: loaded %s — %d variants, raw=%.4f actual=%.1fm" % [species, meshes.size(), max_h, max_h * node_scale])

	if species_meshes.is_empty():
		print("WARNING: no tree GLB models loaded, falling back skipped")
		return

	# Map data species to GLB model species
	var glb_species_map := {
		"oak":       "deciduous",
		"maple":     "maple",
		"elm":       "elm",      # dedicated vase-shaped American Elm model
		"conifer":   "pine",
		"deciduous": "deciduous",
		"birch":     "birch",
	}
	# Desired height ranges per species archetype (metres)
	# [min, max] — mature American Elms are 20-30m; census DBH drives interpolation
	var height_ranges := {
		"oak":       [14.0, 25.0],
		"maple":     [10.0, 20.0],
		"elm":       [18.0, 30.0],   # American Elm — tall vase shape
		"conifer":   [15.0, 30.0],
		"deciduous": [10.0, 22.0],
	}

	# Foliage zone data for deciduous sub-species assignment

	# Collect transforms per species-variant for MultiMesh batching
	# Key: "species_variantIdx" -> Array[Transform3D]
	var xf_by_key: Dictionary = {}
	var all_trunk_xf: Array = []  # for collision
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
		if not _loader._in_boundary(tx, tz):
			continue
		if _loader._is_on_path(tx, tz):
			continue
		var ty: float = _loader._terrain_y(tx, tz)
		rng.seed = i * 1234567891 + 987654321

		# Use the species from data as-is (census or OSM archetype)
		var effective_species := tree_species

		var species: String = glb_species_map.get(effective_species, "deciduous")
		if not species_meshes.has(species):
			species = "deciduous"
			if not species_meshes.has(species):
				continue
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
			var h_range: Array = height_ranges.get(effective_species, [10.0, 22.0])
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
		xf_by_key[key].append(tf)

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
		for tf: Transform3D in xf_by_key[key]:
			var cx := int(floorf(tf.origin.x / CHUNK))
			var cz := int(floorf(tf.origin.z / CHUNK))
			var ck0 := "%s|%d|%d" % [key, cx, cz]
			if not lod0_chunks.has(ck0):
				lod0_chunks[ck0] = {"mesh_key": key, "cx": cx, "cz": cz, "xf": []}
			lod0_chunks[ck0]["xf"].append(tf)

	# Spawn LOD0 chunks — position MMI at instance centroid for accurate culling
	for ckey in lod0_chunks:
		var info: Dictionary = lod0_chunks[ckey]
		var mesh_key: String = info["mesh_key"]
		var xf_list: Array = info["xf"]
		if xf_list.is_empty():
			continue
		var parts: PackedStringArray = mesh_key.split("_")
		var sp_name: String = parts[0]
		var vi: int = int(parts[1])
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
		mm.mesh = mesh
		mm.instance_count = xf_list.size()
		for i in xf_list.size():
			var tf: Transform3D = xf_list[i]
			var local_tf := Transform3D(tf.basis, tf.origin - chunk_origin)
			mm.set_instance_transform(i, local_tf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = chunk_origin
		mmi.name = "Tree_%s" % ckey.replace("|", "_")
		_loader.add_child(mmi)

	_build_tree_collision(all_trunk_xf)
	print("Trees: %d placed, %d chunks" % [all_trunk_xf.size(), lod0_chunks.size()])


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
	return """shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform vec3 albedo_tint = vec3(0.28, 0.48, 0.18);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

global uniform vec2 wind_vec;
global uniform float snow_cover;

void vertex() {
	vec3 tree_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = max(VERTEX.y, 0.0);
	float wind_str = length(wind_vec);
	float rustle = 0.3 + wind_str * 0.7;
	VERTEX.x += sin(TIME * 0.7 + tree_origin.x * 0.04 + tree_origin.z * 0.06) * 0.09 * sway * rustle;
	VERTEX.z += sin(TIME * 1.1 + tree_origin.z * 0.05) * 0.05 * sway * rustle;
	VERTEX.x += wind_vec.x * sway * 0.18;
	VERTEX.z += wind_vec.y * sway * 0.18;
	float flutter = sin(TIME * 3.5 + VERTEX.x * 11.0 + VERTEX.z * 7.0) * 0.012 * rustle;
	VERTEX.y += flutter * sway;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	// Use tint as base color, modulated by texture luminance for variation
	float lum = dot(tex.rgb, vec3(0.3, 0.6, 0.1));
	vec3 col = albedo_tint * (0.6 + lum * 0.8);
	float alpha = tex.a;
	if (alpha < alpha_scissor) discard;

	// Snow accumulation — world-space normal
	if (snow_cover > 0.01) {
		vec3 world_n = mat3(INV_VIEW_MATRIX) * NORMAL;
		float upward = max(world_n.y, 0.0);
		vec3 tree_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float noise = sin(tree_pos.x * 0.3 + tree_pos.z * 0.4) * 0.15;
		float snow_amt = clamp((0.3 + upward * 0.7 + noise) * snow_cover, 0.0, 1.0);
		col = mix(col, vec3(0.92, 0.93, 0.96), snow_amt * 0.65);
	}

	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.08;
	METALLIC = 0.0;
	BACKLIGHT = vec3(0.28, 0.20, 0.06);
}
"""


