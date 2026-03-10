# grass_builder.gd
# Wind-responsive 3D grass scattered across grass terrain surfaces.
# Cross-billboard MultiMesh clumps with procedural blade shader.
# Density varies by landuse zone: mowed lawn vs wild meadow.

var _loader  # Reference to park_loader for shared utilities

# Landuse raw data for fast zone queries (from landuse_map.png)
var _landuse_data: PackedByteArray
var _landuse_res: int = 0

const CHUNK := 40.0      # spatial chunk size in metres
const VIS_END := 120.0   # grass beyond this distance not rendered
const VIS_FADE := 20.0   # fade-out starts this far before VIS_END
const STRIDE := 3        # sample every Nth atlas cell (~1.83m spacing)


func _init(loader) -> void:
	_loader = loader


func _build_grass() -> void:
	var t0 := Time.get_ticks_msec()

	# Load landuse map for zone classification
	_load_landuse()

	# Create shared grass mesh and material
	var mesh := _create_grass_mesh()
	var mat := _create_grass_material()
	mesh.surface_set_material(0, mat)

	# Atlas data for surface queries
	var res: int = _loader._atlas_res
	var data: PackedByteArray = _loader._atlas_data
	if data.is_empty() or res == 0:
		print("Grass: no atlas data — skipping")
		return

	var ws: float = _loader._hm_world_size
	var half := ws * 0.5
	var cell_m := ws / float(res)

	# Collect instances grouped by spatial chunk
	# Key: "cx|cz" -> { "xf": Array[Transform3D], "cd": Array[Color] }
	var chunks: Dictionary = {}
	var total := 0
	var rng := RandomNumberGenerator.new()

	for gz in range(0, res, STRIDE):
		for gx in range(0, res, STRIDE):
			var idx := (gz * res + gx) * 2
			var surf: int = data[idx]
			if surf != 1:  # not grass
				continue
			var occ: int = data[idx + 1]
			if occ & 0x1F != 0:  # occupied (tree, bench, lamp, trash, barrier)
				continue

			# World position with deterministic jitter within cell
			rng.seed = gx * 73856093 + gz * 19349663
			var wx := float(gx) * cell_m - half + rng.randf_range(-0.4, 0.4) * cell_m
			var wz := float(gz) * cell_m - half + rng.randf_range(-0.4, 0.4) * cell_m

			# Determine grass type from landuse zone
			var zone := _landuse_at(wx, wz)
			# Skip non-grass zones: playground(4), dog_park(6), pool(8), track(9)
			if zone == 4 or zone == 6 or zone == 8 or zone == 9:
				continue
			# Meadow zones: nature_reserve(5), wood(10), forest(11)
			var is_meadow := (zone == 5 or zone == 10 or zone == 11)

			# Terrain height (slight offset to prevent Z-fighting with ground)
			var wy: float = _loader._terrain_y(wx, wz) + 0.005

			# Instance dimensions
			var grass_type := 1.0 if is_meadow else 0.0
			var h_base := 0.35 if is_meadow else 0.09
			var w_base := 0.40 if is_meadow else 0.28
			var height := h_base * rng.randf_range(0.7, 1.3)
			var width := w_base * rng.randf_range(0.85, 1.15)

			# Random Y rotation
			var y_rot := rng.randf() * TAU
			var basis := Basis(Vector3.UP, y_rot).scaled(Vector3(width, height, width))
			var tf := Transform3D(basis, Vector3(wx, wy, wz))

			# Bucket into spatial chunk
			var cx := int(floorf(wx / CHUNK))
			var cz := int(floorf(wz / CHUNK))
			var ck := "%d|%d" % [cx, cz]
			if not chunks.has(ck):
				chunks[ck] = {"xf": [], "cd": []}
			chunks[ck]["xf"].append(tf)
			chunks[ck]["cd"].append(Color(grass_type, rng.randf(), 0.0, 0.0))
			total += 1

	# Build MultiMesh per chunk
	var chunk_count := 0
	for ck in chunks:
		var info: Dictionary = chunks[ck]
		var xf_list: Array = info["xf"]
		var cd_list: Array = info["cd"]
		if xf_list.is_empty():
			continue

		# Compute chunk centroid for accurate visibility culling
		var cx_sum := 0.0; var cy_sum := 0.0; var cz_sum := 0.0
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
			mm.set_instance_transform(i, Transform3D(tf.basis, tf.origin - chunk_origin))
			mm.set_instance_custom_data(i, cd_list[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = chunk_origin
		mmi.name = "Grass_%s" % ck.replace("|", "_")
		mmi.visibility_range_end = VIS_END
		mmi.visibility_range_begin = 0.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_loader.add_child(mmi)
		chunk_count += 1

	print("Grass: %d clumps in %d chunks (%.0fms)" % [total, chunk_count,
		Time.get_ticks_msec() - t0])


func _create_grass_mesh() -> ArrayMesh:
	## Cross-billboard: 3 quads at 0°, 60°, 120° around Y axis.
	## Each quad has 4 vertices and 2 triangles with upward normals.
	## Per-quad UV.x offset (0, 1/3, 2/3) varies blade pattern across quads.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for i in 3:
		var angle := float(i) * PI / 3.0   # 0°, 60°, 120°
		var ca := cos(angle)
		var sa := sin(angle)
		var vi := i * 4
		var u_off := float(i) / 3.0        # UV.x offset per quad for blade variation

		# Bottom-left, bottom-right, top-right, top-left
		verts.append(Vector3(-0.5 * ca, 0.0, -0.5 * sa))
		verts.append(Vector3( 0.5 * ca, 0.0,  0.5 * sa))
		verts.append(Vector3( 0.5 * ca, 1.0,  0.5 * sa))
		verts.append(Vector3(-0.5 * ca, 1.0, -0.5 * sa))

		uvs.append(Vector2(u_off, 0.0))
		uvs.append(Vector2(u_off + 1.0, 0.0))
		uvs.append(Vector2(u_off + 1.0, 1.0))
		uvs.append(Vector2(u_off, 1.0))

		# Upward normals for consistent natural lighting on both faces
		for _j in 4:
			normals.append(Vector3(0.0, 1.0, 0.0))

		indices.append(vi + 0); indices.append(vi + 1); indices.append(vi + 2)
		indices.append(vi + 0); indices.append(vi + 2); indices.append(vi + 3)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _create_grass_material() -> ShaderMaterial:
	var shader: Shader = _loader._get_shader("grass_blade", "res://shaders/grass_blade.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _load_landuse() -> void:
	## Load landuse_map.png as raw bytes for fast zone queries.
	for path in ["res://landuse_map.png"]:
		var img: Image = null
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
		else:
			var global_path := ProjectSettings.globalize_path(path)
			if FileAccess.file_exists(global_path):
				img = Image.load_from_file(global_path)
		if img:
			if img.get_format() != Image.FORMAT_R8:
				img.convert(Image.FORMAT_R8)
			_landuse_data = img.get_data()
			_landuse_res = img.get_width()
			return


func _landuse_at(wx: float, wz: float) -> int:
	## Returns landuse zone ID at world position.
	## 0=unzoned, 1=garden, 2=grass, 3=pitch, 5=nature_reserve, 10=wood, 11=forest
	if _landuse_data.is_empty():
		return 0
	var half := _loader._hm_world_size * 0.5
	var scale := float(_landuse_res) / _loader._hm_world_size
	var px := clampi(int((wx + half) * scale), 0, _landuse_res - 1)
	var pz := clampi(int((wz + half) * scale), 0, _landuse_res - 1)
	return _landuse_data[pz * _landuse_res + px]
