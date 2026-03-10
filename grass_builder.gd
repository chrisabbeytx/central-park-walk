# grass_builder.gd
# Data-driven grass system — 10 area-specific types from Conservancy data.
#
# Type  Model                  Area                  Blades  Stride
# ──────────────────────────────────────────────────────────────────
#  0    Grass_Tile_SheepMeadow Sheep Meadow lawns     150     2
#  1    Grass_Tile_GreatLawn   Great Lawn              140     2
#  2    Grass_Tile_NorthMeadow North Meadow            120     3
#  3    Grass_Tile_FormalGarden Conservatory Garden     130     3
#  4    Grass_Tile_SportsTurf  Tennis/baseball/etc      160     2
#  5    Grass_Tile_NorthWoods  North Woods floor        30     7
#  6    Grass_Tile_Ramble      Ramble/Dene floor        50     5
#  7    Grass_Tile_Waterside   Lake/pond shores          80     3
#  8    Grass_Tile_WildMeadow  Nature reserves           60     4
#  9    Grass_Tile_OpenLawn    Default maintained       130     3
#
# Positions prebaked in convert_to_godot.py → grass_instances.bin.

var _loader  # Reference to park_loader for shared utilities

const CHUNK := 40.0       # spatial chunk size in metres

# Model names indexed by type ID
const MODEL_NAMES: Array = [
	"Grass_Tile_SheepMeadow",   # 0
	"Grass_Tile_GreatLawn",     # 1
	"Grass_Tile_NorthMeadow",   # 2
	"Grass_Tile_FormalGarden",  # 3
	"Grass_Tile_SportsTurf",    # 4
	"Grass_Tile_NorthWoods",    # 5
	"Grass_Tile_Ramble",        # 6
	"Grass_Tile_Waterside",     # 7
	"Grass_Tile_WildMeadow",    # 8
	"Grass_Tile_OpenLawn",      # 9
]

# Visibility range per type (dense lawn=far, sparse woodland=near)
const VIS_RANGES: Array = [
	80.0,  # sheep_meadow
	80.0,  # great_lawn
	70.0,  # north_meadow
	70.0,  # formal_garden
	70.0,  # sports_turf
	50.0,  # north_woods
	50.0,  # ramble
	60.0,  # waterside
	60.0,  # wild_meadow
	70.0,  # open_lawn
]


func _init(loader) -> void:
	_loader = loader


func _build_grass() -> void:
	var t0 := Time.get_ticks_msec()

	var grass_shader: Shader = _loader._get_shader("grass_blade", "res://shaders/grass_blade.gdshader")

	# Load all 10 tile models
	var meshes: Array = []
	var loaded := 0
	for mname in MODEL_NAMES:
		var mesh: Mesh = _load_tile_model(mname, grass_shader)
		meshes.append(mesh)
		if mesh != null:
			loaded += 1

	if loaded == 0:
		# Fallback: try old model names
		var old_mesh: Mesh = _load_tile_model("Grass_Patch_Lawn", grass_shader)
		if old_mesh == null:
			print("Grass: no tile models loaded — skipping")
			return
		# Use old model for all types
		for i in meshes.size():
			if meshes[i] == null:
				meshes[i] = old_mesh

	# Read prebaked instance positions
	var instances: Array = _load_instances()
	if instances.is_empty():
		print("Grass: no prebaked instances — skipping")
		return

	var x_arr: PackedFloat32Array = instances[0]
	var z_arr: PackedFloat32Array = instances[1]
	var type_arr: PackedByteArray = instances[2]
	var count: int = x_arr.size()

	# Build transforms and group by type + spatial chunk
	var chunks: Dictionary = {}
	var total := 0
	var type_counts: Array = []
	type_counts.resize(MODEL_NAMES.size())
	type_counts.fill(0)
	var rng := RandomNumberGenerator.new()

	for i in count:
		var wx: float = x_arr[i]
		var wz: float = z_arr[i]
		var gtype: int = type_arr[i]

		if gtype >= meshes.size():
			gtype = 9  # fallback to open_lawn
		if meshes[gtype] == null:
			gtype = 9  # fallback
			if meshes[gtype] == null:
				continue

		var wy: float = _loader._terrain_y(wx, wz) + 0.002

		rng.seed = int(wx * 73856.0 + wz * 19349.0) & 0x7FFFFFFF
		var y_rot := rng.randf() * TAU
		var s := rng.randf_range(0.88, 1.12)
		var basis := Basis(Vector3.UP, y_rot).scaled(Vector3(s, s, s))
		var tf := Transform3D(basis, Vector3(wx, wy, wz))

		var cx := int(floorf(wx / CHUNK))
		var cz := int(floorf(wz / CHUNK))
		var ck := "%d|%d|%d" % [gtype, cx, cz]
		if not chunks.has(ck):
			chunks[ck] = {"type": gtype, "xf": [], "cd": []}
		chunks[ck]["xf"].append(tf)
		chunks[ck]["cd"].append(Color(float(gtype), rng.randf(), 0.0, 0.0))
		total += 1
		type_counts[gtype] += 1

	# Build MultiMesh per chunk
	var chunk_count := 0
	for ck in chunks:
		var info: Dictionary = chunks[ck]
		var gtype: int = info["type"]
		var xf_list: Array = info["xf"]
		var cd_list: Array = info["cd"]
		if xf_list.is_empty():
			continue

		var mesh: Mesh = meshes[gtype]
		var vis_end: float = VIS_RANGES[gtype] if gtype < VIS_RANGES.size() else 60.0

		var sx := 0.0; var sy := 0.0; var sz := 0.0
		for tf: Transform3D in xf_list:
			sx += tf.origin.x
			sy += tf.origin.y
			sz += tf.origin.z
		var n := float(xf_list.size())
		var chunk_origin := Vector3(sx / n, sy / n, sz / n)

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
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_begin = 0.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_loader.add_child(mmi)
		chunk_count += 1

	# Print per-type counts
	var type_str := ""
	for i in MODEL_NAMES.size():
		if type_counts[i] > 0:
			type_str += "%s:%d " % [MODEL_NAMES[i].replace("Grass_Tile_", ""), type_counts[i]]
	print("Grass: %d tiles (%d chunks) in %.0fms" % [total, chunk_count, Time.get_ticks_msec() - t0])
	print("  Types: %s" % type_str)


func _load_tile_model(mname: String, shader: Shader) -> Mesh:
	var path := "res://models/vegetation/%s.glb" % mname
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null

	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_file(abs_path, gltf_state)
	if err != OK:
		print("WARNING: failed to load GLB %s (error %d)" % [abs_path, err])
		return null

	var root: Node = gltf_doc.generate_scene(gltf_state)
	if root == null:
		return null

	var mesh_list: Array = []
	_loader._collect_meshes(root, mesh_list)
	if mesh_list.is_empty():
		root.queue_free()
		return null

	var mesh: Mesh = mesh_list[0]

	for si in mesh.get_surface_count():
		var new_mat := ShaderMaterial.new()
		new_mat.shader = shader
		mesh.surface_set_material(si, new_mat)

	root.queue_free()
	return mesh


func _load_instances() -> Array:
	for path in ["res://grass_instances.bin"]:
		var abs_path := ProjectSettings.globalize_path(path)
		var f := FileAccess.open(abs_path, FileAccess.READ)
		if f == null:
			f = FileAccess.open(path, FileAccess.READ)
		if f == null:
			print("WARNING: grass_instances.bin not found")
			return []

		var cnt: int = f.get_32()
		if cnt == 0:
			return []

		var x_arr := PackedFloat32Array()
		x_arr.resize(cnt)
		var z_arr := PackedFloat32Array()
		z_arr.resize(cnt)
		var type_arr := PackedByteArray()
		type_arr.resize(cnt)

		var x_bytes := f.get_buffer(cnt * 4)
		var z_bytes := f.get_buffer(cnt * 4)
		var t_bytes := f.get_buffer(cnt)

		for j in cnt:
			x_arr[j] = x_bytes.decode_float(j * 4)
			z_arr[j] = z_bytes.decode_float(j * 4)
			type_arr[j] = t_bytes[j]

		print("Grass: loaded %d prebaked instances" % cnt)
		return [x_arr, z_arr, type_arr]

	return []
