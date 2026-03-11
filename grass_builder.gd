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

	# v2 format has pre-baked Y + path proximity (no atlas lookups needed)
	var has_v2 := instances.size() >= 5
	var y_arr: PackedFloat32Array
	var prox_arr: PackedByteArray
	if has_v2:
		y_arr = instances[3]
		prox_arr = instances[4]

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

		rng.seed = int(wx * 73856.0 + wz * 19349.0) & 0x7FFFFFFF

		var wy: float
		var path_prox: float
		if has_v2:
			# v2: Y and path_prox pre-baked in Python, water already filtered
			wy = y_arr[i]
			path_prox = float(prox_arr[i]) / 255.0
		else:
			# v1 fallback: runtime lookups (slow — re-bake to get v2)
			var jx: float = wx + rng.randf_range(-0.9, 0.9)
			var jz: float = wz + rng.randf_range(-0.9, 0.9)
			wy = _loader._terrain_y(jx, jz) + 0.002
			var _s0: int = _loader._atlas_surface(jx, jz)
			if _s0 == 4:
				continue
			var near_water := false
			for _woff in [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1),
						   Vector2(1.5,0), Vector2(-1.5,0), Vector2(0,1.5), Vector2(0,-1.5)]:
				if _loader._atlas_surface(jx + _woff.x, jz + _woff.y) == 4:
					near_water = true
					break
			if near_water:
				continue
			path_prox = 0.0
			if _s0 == 2 or _s0 == 3:
				path_prox = 1.0
			else:
				for _off in [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1)]:
					var s1: int = _loader._atlas_surface(jx + _off.x, jz + _off.y)
					if s1 == 2 or s1 == 3:
						path_prox = maxf(path_prox, 0.8)
					else:
						var s2: int = _loader._atlas_surface(jx + _off.x * 2.0, jz + _off.y * 2.0)
						if s2 == 2 or s2 == 3:
							path_prox = maxf(path_prox, 0.4)

		var y_rot := rng.randf() * TAU
		var s_xz := rng.randf_range(1.0, 1.45)
		var s_y := rng.randf_range(0.85, 1.15)
		if path_prox > 0.1:
			s_y *= lerpf(1.0, 0.55, path_prox)
		var basis := Basis(Vector3.UP, y_rot).scaled(Vector3(s_xz, s_y, s_xz))
		var tf := Transform3D(basis, Vector3(wx, wy, wz))

		var cx := int(floorf(wx / CHUNK))
		var cz := int(floorf(wz / CHUNK))
		var ck := "%d|%d|%d" % [gtype, cx, cz]
		if not chunks.has(ck):
			chunks[ck] = {"type": gtype, "xf": [], "cd": []}
		chunks[ck]["xf"].append(tf)
		chunks[ck]["cd"].append(Color(float(gtype), rng.randf(), path_prox, 0.0))
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
	var abs_path := ProjectSettings.globalize_path("res://models/vegetation/%s.glb" % mname)
	if not FileAccess.file_exists(abs_path):
		return null
	# Use shared GLB loader with .res caching (much faster on repeat loads)
	var meshes: Dictionary = _loader._load_glb_meshes(abs_path)
	if meshes.is_empty():
		return null
	var mesh: Mesh = meshes.values()[0]
	for si in mesh.get_surface_count():
		var new_mat := ShaderMaterial.new()
		new_mat.shader = shader
		mesh.surface_set_material(si, new_mat)
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

		var magic: int = f.get_32()
		if magic == 0x47525332:  # "GRS2" — v2 format with pre-baked Y + path proximity
			var cnt: int = f.get_32()
			if cnt == 0:
				return []
			var x_bytes := f.get_buffer(cnt * 4)
			var y_bytes := f.get_buffer(cnt * 4)
			var z_bytes := f.get_buffer(cnt * 4)
			var t_bytes := f.get_buffer(cnt)
			var pp_bytes := f.get_buffer(cnt)

			var x_arr := PackedFloat32Array(); x_arr.resize(cnt)
			var y_arr := PackedFloat32Array(); y_arr.resize(cnt)
			var z_arr := PackedFloat32Array(); z_arr.resize(cnt)
			var type_arr := PackedByteArray(); type_arr.resize(cnt)
			var prox_arr := PackedByteArray(); prox_arr.resize(cnt)
			for j in cnt:
				x_arr[j] = x_bytes.decode_float(j * 4)
				y_arr[j] = y_bytes.decode_float(j * 4)
				z_arr[j] = z_bytes.decode_float(j * 4)
				type_arr[j] = t_bytes[j]
				prox_arr[j] = pp_bytes[j]
			print("Grass: loaded %d prebaked instances (v2 — Y + path_prox pre-baked)" % cnt)
			return [x_arr, z_arr, type_arr, y_arr, prox_arr]
		else:
			# v1 format — magic was actually the count
			var cnt: int = magic
			if cnt == 0:
				return []
			var x_arr := PackedFloat32Array(); x_arr.resize(cnt)
			var z_arr := PackedFloat32Array(); z_arr.resize(cnt)
			var type_arr := PackedByteArray(); type_arr.resize(cnt)
			var x_bytes := f.get_buffer(cnt * 4)
			var z_bytes := f.get_buffer(cnt * 4)
			var t_bytes := f.get_buffer(cnt)
			for j in cnt:
				x_arr[j] = x_bytes.decode_float(j * 4)
				z_arr[j] = z_bytes.decode_float(j * 4)
				type_arr[j] = t_bytes[j]
			print("Grass: loaded %d prebaked instances (v1 — needs re-bake)" % cnt)
			return [x_arr, z_arr, type_arr]

	return []
