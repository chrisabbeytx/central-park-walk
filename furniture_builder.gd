var _loader

func _init(loader) -> void:
	_loader = loader


func _build_furniture(bench_data: Array, lamppost_data: Array, paths: Array) -> void:
	# --- Load GLB furniture models (cache for reuse by _build_trash_cans) ---
	if _loader._furn_glb_meshes.is_empty():
		var furn_path := ProjectSettings.globalize_path("res://models/furniture/park_furniture/glb/parkfurnitures.glb")
		_loader._furn_glb_meshes = _loader._load_glb_meshes(furn_path)
	var furn_meshes: Dictionary = _loader._furn_glb_meshes
	if furn_meshes.is_empty():
		print("WARNING: furniture GLB not loaded, skipping furniture")
		return
	print("Furniture: loaded %d meshes from GLB" % furn_meshes.size())

	# --- Lamp meshes ---
	# Load CP-specific lamppost (Henry Bacon Type B + Kent Bloomer luminaire)
	# GLB contains two objects: CP_Lamppost (iron) + CP_Lamppost_Globe (glass)
	var cp_lamp_path := ProjectSettings.globalize_path("res://models/furniture/cp_lamppost.glb")
	var cp_lamp_meshes: Dictionary = _loader._load_glb_meshes(cp_lamp_path)
	var lamp_iron_mesh: Mesh = null
	var lamp_globe_mesh: Mesh = null
	if cp_lamp_meshes.has("CP_Lamppost"):
		lamp_iron_mesh = cp_lamp_meshes["CP_Lamppost"] as Mesh
		if cp_lamp_meshes.has("CP_Lamppost_Globe"):
			lamp_globe_mesh = cp_lamp_meshes["CP_Lamppost_Globe"] as Mesh
		print("Lamp: loaded CP lamppost model (Type B + Bloomer luminaire, %d meshes)" % cp_lamp_meshes.size())
	else:
		# Fallback to generic furniture GLB
		for lname in ["ParkFurn_Lamp_A", "ParkFurn_Lamp_B", "ParkFurn_Lamp_C"]:
			if furn_meshes.has(lname):
				lamp_iron_mesh = furn_meshes[lname] as Mesh
				break
	if lamp_iron_mesh == null:
		print("WARNING: no lamp meshes found in GLB")
		return
	# Cast iron shader for weather-responsive lamppost posts
	var iron_shader: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
	var lamp_post_mat := ShaderMaterial.new()
	lamp_post_mat.shader = iron_shader
	lamp_post_mat.set_shader_parameter("iron_color", Vector3(0.08, 0.08, 0.06))
	# Emissive globe material (main.gd modulates emission for day/night)
	var lamp_globe_mat := StandardMaterial3D.new()
	lamp_globe_mat.albedo_color = Color(1.0, 0.88, 0.65, 0.85)  # warm frosted glass
	lamp_globe_mat.roughness    = 0.25
	lamp_globe_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lamp_globe_mat.emission_enabled = true
	lamp_globe_mat.emission         = Color(0.0, 0.0, 0.0)  # start dark; main.gd modulates
	lamp_globe_mat.emission_energy_multiplier = 0.0
	_loader.lamppost_material = lamp_globe_mat

	# --- Bench mesh (CP-specific model with iron + wood materials baked in) ---
	var cp_bench_path := ProjectSettings.globalize_path("res://models/furniture/cp_bench.glb")
	var cp_bench_meshes: Dictionary = _loader._load_glb_meshes(cp_bench_path)
	var bench_mesh: Mesh = null
	if cp_bench_meshes.has("ParkFurn_Bench_CP"):
		bench_mesh = cp_bench_meshes["ParkFurn_Bench_CP"] as Mesh
		print("Bench: loaded CP bench model (iron + wood)")
	else:
		# Fallback: first available bench from furniture GLB
		for bname in ["ParkFurn_Bench_A", "ParkFurn_Bench_B", "ParkFurn_Bench_C"]:
			if furn_meshes.has(bname):
				bench_mesh = furn_meshes[bname] as Mesh
				break
	if bench_mesh == null:
		print("WARNING: no bench mesh found in GLB")
		return

	# --- Place lampposts: all identical Type B, heights pre-baked from LiDAR ---
	var lamp_xf: Array = []
	for lp in lamppost_data:
		var lx := float(lp[0])
		var ly := float(lp[1])  # pre-baked LiDAR height from pipeline
		var lz := float(lp[2])
		if not _loader._in_boundary(lx, lz):
			continue
		lamp_xf.append(Transform3D(Basis.IDENTITY, Vector3(lx, ly, lz)))

	# --- Place benches: heights pre-baked from LiDAR ---
	var bench_xf: Array = []
	for b in bench_data:
		var bx := float(b[0])
		var by := float(b[1]) + 0.42  # pre-baked height + bench seat lift
		var bz := float(b[2])
		if not _loader._in_boundary(bx, bz):
			continue
		var dir_deg := float(b[3]) if b.size() > 3 else 0.0
		var angle := deg_to_rad(-dir_deg)
		bench_xf.append(Transform3D(Basis(Vector3.UP, angle), Vector3(bx, by, bz)))

	print("ParkLoader: lampposts = %d  benches = %d (pre-baked heights)" % [lamp_xf.size(), bench_xf.size()])

	# Spawn lamppost iron parts (cast iron shader for weather response)
	if not lamp_xf.is_empty():
		_loader._spawn_multimesh(lamp_iron_mesh, lamp_post_mat, lamp_xf, "Lampposts")
		# Spawn globe separately with emissive material (same transforms — globe is part of model)
		if lamp_globe_mesh:
			_loader._spawn_multimesh(lamp_globe_mesh, lamp_globe_mat, lamp_xf, "Lamppost_Globes")
	# Spawn all benches with the CP bench model (materials baked into GLB)
	if not bench_xf.is_empty():
		_loader._spawn_multimesh(bench_mesh, null, bench_xf, "Benches_0")


func _build_trash_cans(trash_data: Array, paths: Array) -> void:
	## Trash receptacles from OSM data.
	# Landor/Landscape Forms aluminum recycling receptacle (2013)
	var cp_tc_path := ProjectSettings.globalize_path("res://models/furniture/cp_trash_can.glb")
	var cp_tc_meshes: Dictionary = _loader._load_glb_meshes(cp_tc_path)
	var mesh: Mesh
	var mat: Material = null  # null → use embedded Aluminum material from GLB
	if cp_tc_meshes.has("CP_TrashCan"):
		mesh = cp_tc_meshes["CP_TrashCan"] as Mesh
		print("TrashCan: loaded CP trash can model (aluminum)")
	elif _loader._furn_glb_meshes.has("ParkFurn_TrashCan_A"):
		mesh = _loader._furn_glb_meshes["ParkFurn_TrashCan_A"]
		var iron_shader: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
		var trash_mat := ShaderMaterial.new()
		trash_mat.shader = iron_shader
		trash_mat.set_shader_parameter("iron_color", Vector3(0.08, 0.08, 0.06))
		mat = trash_mat
	else:
		print("WARNING: no trash can mesh found, skipping")
		return

	# Place from OSM data — heights pre-baked from LiDAR
	var xforms: Array = []
	for tc in trash_data:
		var tx := float(tc[0])
		var ty := float(tc[1])  # pre-baked LiDAR height
		var tz := float(tc[2])
		if not _loader._in_boundary(tx, tz):
			continue
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(tx, ty, tz)))

	if not xforms.is_empty():
		_loader._spawn_multimesh(mesh, mat, xforms, "TrashCans")
	print("ParkLoader: trash cans = %d (pre-baked heights)" % xforms.size())


func _build_flagpoles(flagpole_data: Array) -> void:
	## Flagpoles — thin aluminum poles at flag locations
	if flagpole_data.is_empty():
		return
	# Generate a simple tapered pole mesh
	var pole_mesh: ArrayMesh = _loader._make_cylinder(0.06, 8.0, 8)
	# Metallic silver material
	var iron_shader: Shader = _loader._get_shader("cast_iron", "res://shaders/cast_iron.gdshader")
	var pole_mat := ShaderMaterial.new()
	pole_mat.shader = iron_shader
	pole_mat.set_shader_parameter("iron_color", Vector3(0.55, 0.55, 0.58))
	pole_mat.set_shader_parameter("base_roughness", 0.30)
	pole_mat.set_shader_parameter("base_metallic", 0.60)
	var xforms: Array = []
	for fp in flagpole_data:
		var fx := float(fp[0])
		var fy := float(fp[1])  # pre-baked LiDAR height
		var fz := float(fp[2])
		if not _loader._in_boundary(fx, fz):
			continue
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(fx, fy, fz)))
	if not xforms.is_empty():
		_loader._spawn_multimesh(pole_mesh, pole_mat, xforms, "Flagpoles")
	print("ParkLoader: flagpoles = %d" % xforms.size())


