extends Node3D

# ---------------------------------------------------------------------------
# Geo-projection constants – must match convert_to_godot.py
#   origin  = centre of Central Park
#   +X = East,  −Z = North
# ---------------------------------------------------------------------------
const REF_LAT            := 40.7829
const REF_LON            := -73.9654
const METRES_PER_DEG_LAT := 110_540.0
const METRES_PER_DEG_LON := 84_264.0   # 111320 × cos(40.7829°)

# Heightmap (loaded once, shared for player spawn positioning)
var _hm_data:          Array   = []
var _hm_width:         int     = 0
var _hm_depth:         int     = 0
var _hm_world_size:    float   = 5000.0
var _hm_origin_height: float   = 0.0

# HUD label references kept for per-frame updates
var _player:        CharacterBody3D
var _coord_label:   Label
var _heading_label: Label
var _latlon_label:  Label

# ---------------------------------------------------------------------------
# Day/night cycle
# ---------------------------------------------------------------------------
var _time_of_day: float = 6.0        # hours [0..24), start at dawn
var _time_speed: float  = 0.001      # game-hours per real-second (~400 min full cycle)
var _time_speed_idx: int = 0
const TIME_SPEEDS: Array = [0.001, 0.01, 0.1, 0.0]
const TIME_SPEED_NAMES: Array = ["1x", "10x", "100x", "Paused"]

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _lamp_mat: StandardMaterial3D
var _time_label: Label

# 5 keyframes defining the full day/night cycle
# Night (21→5) wraps seamlessly; 8 hours of steady darkness.
var _keyframes: Array = []
const _KF_HOURS: Array = [5.0, 6.5, 12.0, 19.0, 21.0]


func _ready() -> void:
	_build_keyframes()
	_load_heightmap()
	_setup_environment()
	_setup_ground()
	_setup_park()
	_player = _setup_player()
	_setup_hud()
	_apply_time_of_day()
	# Auto-screenshot for dev review (remove when done)
	get_tree().create_timer(4.0).timeout.connect(_take_screenshot)

func _take_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/godot_screenshot.png")
	print("Screenshot saved to /tmp/godot_screenshot.png")


# ---------------------------------------------------------------------------
# Heightmap helpers
# ---------------------------------------------------------------------------
func _load_heightmap() -> void:
	if not FileAccess.file_exists("res://heightmap.json"):
		return
	var fa  := FileAccess.open("res://heightmap.json", FileAccess.READ)
	var hm   = JSON.parse_string(fa.get_as_text())
	fa.close()
	if typeof(hm) != TYPE_DICTIONARY:
		return
	_hm_width         = int(hm["width"])
	_hm_depth         = int(hm["depth"])
	_hm_world_size    = float(hm["world_size"])
	_hm_origin_height = float(hm["origin_height"])
	_hm_data          = hm["data"]
	print("Heightmap loaded: %d×%d  origin_y=%.1f m" % [_hm_width, _hm_depth, _hm_origin_height])


func _terrain_height(x: float, z: float) -> float:
	## Barycentric interpolation matching the terrain mesh's triangle split.
	## The mesh diagonal runs from i00 to i11 (bottom-left to top-right).
	if _hm_data.is_empty():
		return 0.0
	var half := _hm_world_size * 0.5
	var xi   := (x + half) / _hm_world_size * (_hm_width  - 1)
	var zi   := (z + half) / _hm_world_size * (_hm_depth  - 1)
	var xi0  := clampi(int(xi), 0, _hm_width  - 2)
	var zi0  := clampi(int(zi), 0, _hm_depth  - 2)
	var fx   := xi - xi0
	var fz   := zi - zi0
	var h00  := float(_hm_data[zi0       * _hm_width + xi0    ])
	var h10  := float(_hm_data[zi0       * _hm_width + xi0 + 1])
	var h01  := float(_hm_data[(zi0 + 1) * _hm_width + xi0    ])
	var h11  := float(_hm_data[(zi0 + 1) * _hm_width + xi0 + 1])
	if fz <= fx:
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz
	else:
		return h00 + (h11 - h01) * fx + (h01 - h00) * fz


# ---------------------------------------------------------------------------
# Per-frame update: time + HUD
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Advance clock
	_time_of_day += _time_speed * delta
	if _time_of_day >= 24.0:
		_time_of_day -= 24.0
	elif _time_of_day < 0.0:
		_time_of_day += 24.0
	_apply_time_of_day()

	if not _player or not _coord_label:
		return

	var pos := _player.position

	# Local-metre coordinates
	_coord_label.text = "X: %7.1f      Z: %7.1f" % [pos.x, pos.z]

	# Compass bearing (0° = North = −Z, increases clockwise)
	var bearing := fmod(fmod(-_player.rotation_degrees.y, 360.0) + 360.0, 360.0)
	_heading_label.text = "Heading: %5.1f°  %s" % [bearing, _compass_label(bearing)]

	# Real-world lat / lon
	var lat :=  REF_LAT + (-pos.z / METRES_PER_DEG_LAT)
	var lon :=  REF_LON + ( pos.x / METRES_PER_DEG_LON)
	_latlon_label.text  = "%.6f° N    %.6f° W" % [lat, absf(lon)]

	# Time of day display
	if _time_label:
		var h12: int = int(_time_of_day) % 12
		if h12 == 0:
			h12 = 12
		var mins: int = int(fmod(_time_of_day, 1.0) * 60.0)
		var ampm: String = "AM" if _time_of_day < 12.0 else "PM"
		_time_label.text = "%d:%02d %s  [%s]" % [h12, mins, ampm, TIME_SPEED_NAMES[_time_speed_idx]]


func _compass_label(deg: float) -> String:
	var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return labels[int(fmod(deg + 22.5, 360.0) / 45.0) % 8]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_T:
		_time_speed_idx = (_time_speed_idx + 1) % TIME_SPEEDS.size()
		_time_speed = TIME_SPEEDS[_time_speed_idx]
		print("Time speed: ", TIME_SPEED_NAMES[_time_speed_idx])
	elif event.keycode == KEY_BRACKETLEFT:
		_time_of_day = fmod(_time_of_day - 1.0 + 24.0, 24.0)
		print("Time: %.1f h" % _time_of_day)
	elif event.keycode == KEY_BRACKETRIGHT:
		_time_of_day = fmod(_time_of_day + 1.0, 24.0)
		print("Time: %.1f h" % _time_of_day)


# ---------------------------------------------------------------------------
# Sky + lighting
# ---------------------------------------------------------------------------
func _load_img_tex(path: String) -> ImageTexture:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if not img:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _setup_environment() -> void:
	_sky_mat = ProceduralSkyMaterial.new()

	var sky := Sky.new()
	sky.sky_material = _sky_mat

	_env = Environment.new()
	_env.background_mode       = Environment.BG_SKY
	_env.sky                   = sky
	_env.ambient_light_source  = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode          = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled          = true
	_env.ssao_enabled          = true
	_env.ssao_detail           = 0.5
	_env.ssil_enabled          = true
	_env.ssil_radius           = 5.0
	_env.ssil_sharpness        = 0.98
	_env.adjustment_enabled    = true
	_env.fog_enabled           = true

	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_split_1      = 0.08
	_sun.directional_shadow_pancake_size = 20.0
	add_child(_sun)

	print("Sky: day/night cycle — start 6:00 AM")


# ---------------------------------------------------------------------------
# Day/night keyframes
# ---------------------------------------------------------------------------
func _build_keyframes() -> void:
	# ---- 5.0  Pre-dawn ----
	_keyframes.append({
		"hour": 5.0,
		"sky_top":        Color(0.02, 0.03, 0.08),
		"sky_horizon":    Color(0.10, 0.08, 0.14),
		"gnd_bottom":     Color(0.01, 0.01, 0.02),
		"gnd_horizon":    Color(0.06, 0.05, 0.10),
		"sun_angle_max":  3.0,
		"sun_curve":      0.01,
		"ambient_color":  Color(0.06, 0.07, 0.14),
		"ambient_energy": 0.25,
		"exposure":       1.3,
		"white":          5.0,
		"glow_intensity": 0.6,
		"glow_bloom":     0.10,
		"glow_strength":  1.4,
		"glow_threshold": 0.5,
		"glow_cap":       3.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.8,
		"ssao_power":     2.0,
		"ssil_intensity": 0.5,
		"saturation":     0.55,
		"contrast":       1.10,
		"brightness":     0.92,
		"fog_color":      Color(0.06, 0.07, 0.14),
		"fog_energy":     0.5,
		"fog_scatter":    0.05,
		"fog_density":    0.0020,
		"fog_aerial":     0.7,
		"fog_sky_affect": 0.8,
		"sun_energy":     0.6,
		"sun_color":      Color(0.65, 0.72, 0.95),
		"sun_pitch":      -10.0,
		"sun_yaw":        -100.0,
		"shadow_dist":    180.0,
		"lamp_emission":  2.0,
	})

	# ---- 6.5  Sunrise / Golden hour ----
	_keyframes.append({
		"hour": 6.5,
		"sky_top":        Color(0.20, 0.35, 0.65),
		"sky_horizon":    Color(0.90, 0.55, 0.25),
		"gnd_bottom":     Color(0.08, 0.06, 0.04),
		"gnd_horizon":    Color(0.50, 0.35, 0.18),
		"sun_angle_max":  5.0,
		"sun_curve":      0.08,
		"ambient_color":  Color(0.40, 0.30, 0.20),
		"ambient_energy": 0.35,
		"exposure":       0.85,
		"white":          4.0,
		"glow_intensity": 0.5,
		"glow_bloom":     0.08,
		"glow_strength":  1.2,
		"glow_threshold": 0.8,
		"glow_cap":       5.0,
		"ssao_radius":    1.5,
		"ssao_intensity": 2.0,
		"ssao_power":     1.8,
		"ssil_intensity": 0.7,
		"saturation":     1.05,
		"contrast":       1.08,
		"brightness":     1.0,
		"fog_color":      Color(0.55, 0.38, 0.22),
		"fog_energy":     0.8,
		"fog_scatter":    0.35,
		"fog_density":    0.0015,
		"fog_aerial":     0.6,
		"fog_sky_affect": 0.5,
		"sun_energy":     1.8,
		"sun_color":      Color(1.0, 0.72, 0.38),
		"sun_pitch":      -15.0,
		"sun_yaw":        -95.0,
		"shadow_dist":    250.0,
		"lamp_emission":  0.0,
	})

	# ---- 12.0  Noon ----
	_keyframes.append({
		"hour": 12.0,
		"sky_top":        Color(0.18, 0.38, 0.72),
		"sky_horizon":    Color(0.50, 0.62, 0.80),
		"gnd_bottom":     Color(0.10, 0.12, 0.08),
		"gnd_horizon":    Color(0.35, 0.38, 0.30),
		"sun_angle_max":  1.5,
		"sun_curve":      0.15,
		"ambient_color":  Color(0.35, 0.40, 0.50),
		"ambient_energy": 0.30,
		"exposure":       0.75,
		"white":          3.5,
		"glow_intensity": 0.3,
		"glow_bloom":     0.05,
		"glow_strength":  1.0,
		"glow_threshold": 1.2,
		"glow_cap":       8.0,
		"ssao_radius":    1.5,
		"ssao_intensity": 2.0,
		"ssao_power":     1.8,
		"ssil_intensity": 0.8,
		"saturation":     1.0,
		"contrast":       1.05,
		"brightness":     1.0,
		"fog_color":      Color(0.42, 0.48, 0.58),
		"fog_energy":     1.0,
		"fog_scatter":    0.15,
		"fog_density":    0.0012,
		"fog_aerial":     0.5,
		"fog_sky_affect": 0.3,
		"sun_energy":     2.2,
		"sun_color":      Color(1.0, 0.96, 0.88),
		"sun_pitch":      -55.0,
		"sun_yaw":        -20.0,
		"shadow_dist":    300.0,
		"lamp_emission":  0.0,
	})

	# ---- 19.0  Sunset / Golden hour ----
	_keyframes.append({
		"hour": 19.0,
		"sky_top":        Color(0.15, 0.22, 0.50),
		"sky_horizon":    Color(0.92, 0.50, 0.20),
		"gnd_bottom":     Color(0.06, 0.04, 0.03),
		"gnd_horizon":    Color(0.45, 0.30, 0.15),
		"sun_angle_max":  5.0,
		"sun_curve":      0.08,
		"ambient_color":  Color(0.35, 0.25, 0.18),
		"ambient_energy": 0.32,
		"exposure":       0.90,
		"white":          4.0,
		"glow_intensity": 0.5,
		"glow_bloom":     0.10,
		"glow_strength":  1.3,
		"glow_threshold": 0.7,
		"glow_cap":       5.0,
		"ssao_radius":    1.8,
		"ssao_intensity": 2.2,
		"ssao_power":     1.9,
		"ssil_intensity": 0.6,
		"saturation":     1.08,
		"contrast":       1.08,
		"brightness":     0.98,
		"fog_color":      Color(0.50, 0.35, 0.20),
		"fog_energy":     0.8,
		"fog_scatter":    0.40,
		"fog_density":    0.0016,
		"fog_aerial":     0.6,
		"fog_sky_affect": 0.5,
		"sun_energy":     1.6,
		"sun_color":      Color(1.0, 0.65, 0.30),
		"sun_pitch":      -12.0,
		"sun_yaw":        95.0,
		"shadow_dist":    220.0,
		"lamp_emission":  0.5,
	})

	# ---- 21.0  Night ----
	_keyframes.append({
		"hour": 21.0,
		"sky_top":        Color(0.01, 0.015, 0.04),
		"sky_horizon":    Color(0.03, 0.04, 0.08),
		"gnd_bottom":     Color(0.005, 0.008, 0.012),
		"gnd_horizon":    Color(0.02, 0.03, 0.06),
		"sun_angle_max":  3.0,
		"sun_curve":      0.01,
		"ambient_color":  Color(0.05, 0.06, 0.12),
		"ambient_energy": 0.25,
		"exposure":       1.4,
		"white":          5.0,
		"glow_intensity": 0.6,
		"glow_bloom":     0.12,
		"glow_strength":  1.5,
		"glow_threshold": 0.5,
		"glow_cap":       3.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 3.0,
		"ssao_power":     2.0,
		"ssil_intensity": 0.6,
		"saturation":     0.55,
		"contrast":       1.12,
		"brightness":     0.92,
		"fog_color":      Color(0.06, 0.08, 0.14),
		"fog_energy":     0.5,
		"fog_scatter":    0.05,
		"fog_density":    0.0020,
		"fog_aerial":     0.7,
		"fog_sky_affect": 0.8,
		"sun_energy":     0.8,
		"sun_color":      Color(0.70, 0.78, 1.00),
		"sun_pitch":      -65.0,
		"sun_yaw":        40.0,
		"shadow_dist":    200.0,
		"lamp_emission":  2.0,
	})


func _find_keyframe_pair(hour: float) -> Array:
	## Returns [kf_a: Dictionary, kf_b: Dictionary, t: float]
	var n: int = _keyframes.size()
	for i in n:
		var ha: float = float(_keyframes[i]["hour"])
		var j: int = (i + 1) % n
		var hb: float = float(_keyframes[j]["hour"])
		# Handle wrap-around (night 21→pre-dawn 5 spans midnight)
		var span: float
		var off: float
		if hb <= ha:
			# Wrapping pair (e.g. 21→5 = 8 hours through midnight)
			span = (hb + 24.0) - ha
			if hour >= ha:
				off = hour - ha
			else:
				off = (hour + 24.0) - ha
		else:
			span = hb - ha
			off = hour - ha
		if off >= 0.0 and off < span:
			var t: float = off / span
			return [_keyframes[i], _keyframes[j], t]
	# Fallback (should not happen)
	return [_keyframes[0], _keyframes[0], 0.0]


func _lerp_kf(key: String, a: Dictionary, b: Dictionary, t: float):
	var va = a[key]
	var vb = b[key]
	if va is Color:
		return (va as Color).lerp(vb as Color, t)
	else:
		return lerpf(float(va), float(vb), t)


func _apply_time_of_day() -> void:
	if not _env or not _sky_mat or not _sun:
		return
	var pair: Array = _find_keyframe_pair(_time_of_day)
	var a: Dictionary = pair[0]
	var b: Dictionary = pair[1]
	var t: float = float(pair[2])

	# Sky material
	_sky_mat.sky_top_color        = _lerp_kf("sky_top", a, b, t)
	_sky_mat.sky_horizon_color    = _lerp_kf("sky_horizon", a, b, t)
	_sky_mat.ground_bottom_color  = _lerp_kf("gnd_bottom", a, b, t)
	_sky_mat.ground_horizon_color = _lerp_kf("gnd_horizon", a, b, t)
	_sky_mat.sun_angle_max        = _lerp_kf("sun_angle_max", a, b, t)
	_sky_mat.sun_curve            = _lerp_kf("sun_curve", a, b, t)

	# Ambient
	_env.ambient_light_color  = _lerp_kf("ambient_color", a, b, t)
	_env.ambient_light_energy = _lerp_kf("ambient_energy", a, b, t)

	# Tonemapping
	_env.tonemap_exposure = _lerp_kf("exposure", a, b, t)
	_env.tonemap_white    = _lerp_kf("white", a, b, t)

	# Glow
	_env.glow_intensity         = _lerp_kf("glow_intensity", a, b, t)
	_env.glow_bloom             = _lerp_kf("glow_bloom", a, b, t)
	_env.glow_strength          = _lerp_kf("glow_strength", a, b, t)
	_env.glow_hdr_threshold     = _lerp_kf("glow_threshold", a, b, t)
	_env.glow_hdr_luminance_cap = _lerp_kf("glow_cap", a, b, t)

	# SSAO
	_env.ssao_radius    = _lerp_kf("ssao_radius", a, b, t)
	_env.ssao_intensity = _lerp_kf("ssao_intensity", a, b, t)
	_env.ssao_power     = _lerp_kf("ssao_power", a, b, t)

	# SSIL
	_env.ssil_intensity = _lerp_kf("ssil_intensity", a, b, t)

	# Colour grading
	_env.adjustment_saturation = _lerp_kf("saturation", a, b, t)
	_env.adjustment_contrast   = _lerp_kf("contrast", a, b, t)
	_env.adjustment_brightness = _lerp_kf("brightness", a, b, t)

	# Fog
	_env.fog_light_color       = _lerp_kf("fog_color", a, b, t)
	_env.fog_light_energy      = _lerp_kf("fog_energy", a, b, t)
	_env.fog_sun_scatter       = _lerp_kf("fog_scatter", a, b, t)
	_env.fog_density           = _lerp_kf("fog_density", a, b, t)
	_env.fog_aerial_perspective = _lerp_kf("fog_aerial", a, b, t)
	_env.fog_sky_affect        = _lerp_kf("fog_sky_affect", a, b, t)

	# Sun / moon directional light
	_sun.light_energy    = _lerp_kf("sun_energy", a, b, t)
	_sun.light_color     = _lerp_kf("sun_color", a, b, t)
	var pitch: float     = _lerp_kf("sun_pitch", a, b, t)
	var yaw: float       = _lerp_kf("sun_yaw", a, b, t)
	_sun.rotation_degrees = Vector3(pitch, yaw, 0.0)
	_sun.directional_shadow_max_distance = _lerp_kf("shadow_dist", a, b, t)

	# Lamppost emission
	if _lamp_mat:
		var em: float = _lerp_kf("lamp_emission", a, b, t)
		_lamp_mat.emission_energy_multiplier = em
		# Fade albedo brightness slightly when lamps are off (daytime)
		if em < 0.01:
			_lamp_mat.emission = Color(0.0, 0.0, 0.0)
		else:
			_lamp_mat.emission = Color(1.0, 0.85, 0.45) * em



# ---------------------------------------------------------------------------
# Terrain ground – 256×256 height-mapped mesh + HeightMapShape3D collision
# Falls back to a flat plane when heightmap.json is absent.
# ---------------------------------------------------------------------------
func _setup_ground() -> void:
	var tex_alb := _load_img_tex("res://textures/grass_albedo.jpg")
	var tex_nrm := _load_img_tex("res://textures/grass_normal.jpg")
	var tex_rgh := _load_img_tex("res://textures/grass_rough.jpg")
	var shader  := Shader.new()
	shader.code  = _terrain_shader_textured() if tex_alb != null else _terrain_shader_code()
	var mat     := ShaderMaterial.new()
	mat.shader   = shader
	if tex_alb != null:
		mat.set_shader_parameter("grass_albedo", tex_alb)
		mat.set_shader_parameter("grass_normal", tex_nrm)
		mat.set_shader_parameter("grass_rough",  tex_rgh)
		mat.set_shader_parameter("tile_m",       3.0)
		print("Ground: textured grass shader")

	if _hm_data.is_empty():
		# Flat fallback
		var plane            := PlaneMesh.new()
		plane.size            = Vector2(5000.0, 5000.0)
		plane.subdivide_width  = 1
		plane.subdivide_depth  = 1
		var mi                := MeshInstance3D.new()
		mi.mesh                = plane
		mi.material_override   = mat
		add_child(mi)
		var body := StaticBody3D.new()
		var col  := CollisionShape3D.new()
		col.shape = WorldBoundaryShape3D.new()
		body.add_child(col)
		add_child(body)
		return

	# ---- Build terrain ArrayMesh ----
	var W         := _hm_width
	var H         := _hm_depth
	var half      := _hm_world_size * 0.5
	var cell      := _hm_world_size / float(W - 1)
	var V         := W * H

	var verts    := PackedVector3Array(); verts.resize(V)
	var normals  := PackedVector3Array(); normals.resize(V)
	var uvs      := PackedVector2Array(); uvs.resize(V)
	var tangents := PackedFloat32Array(); tangents.resize(V * 4)

	for zi in H:
		for xi in W:
			var idx := zi * W + xi
			var xw  := -half + xi * cell
			var zw  := -half + zi * cell
			var h   := float(_hm_data[idx])
			verts[idx]   = Vector3(xw, h, zw)
			uvs[idx]     = Vector2(float(xi) / float(W - 1), float(zi) / float(H - 1))
			# Slope-based normal using central differences
			var hL := float(_hm_data[zi * W + max(xi - 1, 0)    ])
			var hR := float(_hm_data[zi * W + min(xi + 1, W - 1)])
			var hU := float(_hm_data[max(zi - 1, 0)     * W + xi])
			var hD := float(_hm_data[min(zi + 1, H - 1) * W + xi])
			normals[idx] = Vector3(hL - hR, 2.0 * cell, hU - hD).normalized()
			tangents[idx*4] = 1.0; tangents[idx*4+3] = 1.0

	var T       := (W - 1) * (H - 1) * 6
	var indices := PackedInt32Array(); indices.resize(T)
	var t       := 0
	for zi in (H - 1):
		for xi in (W - 1):
			var i00 := zi * W + xi
			var i10 := zi * W + xi + 1
			var i01 := (zi + 1) * W + xi
			var i11 := (zi + 1) * W + xi + 1
			indices[t]     = i00; indices[t + 1] = i10; indices[t + 2] = i11
			indices[t + 3] = i00; indices[t + 4] = i11; indices[t + 5] = i01
			t += 6

	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]  = verts
	arrays[Mesh.ARRAY_NORMAL]  = normals
	arrays[Mesh.ARRAY_TEX_UV]  = uvs
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX]   = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)

	var mi       := MeshInstance3D.new()
	mi.mesh       = mesh
	mi.name       = "Terrain"
	add_child(mi)

	# ---- HeightMapShape3D collision ----
	var hm_shape          := HeightMapShape3D.new()
	hm_shape.map_width     = W
	hm_shape.map_depth     = H
	var pf                := PackedFloat32Array(); pf.resize(V)
	for i in V:
		pf[i] = float(_hm_data[i])
	hm_shape.map_data      = pf

	var col               := CollisionShape3D.new()
	col.shape              = hm_shape
	col.scale              = Vector3(cell, 1.0, cell)

	var body              := StaticBody3D.new()
	body.name              = "TerrainBody"
	body.add_child(col)
	add_child(body)


func _terrain_shader_textured() -> String:
	return """shader_type spatial;
render_mode cull_disabled;

uniform sampler2D grass_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 3.0;

varying vec3 world_pos;

float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i+vec2(1.,0.)), u.x),
	           mix(hash2(i+vec2(0.,1.)), hash2(i+vec2(1.,1.)), u.x), u.y);
}
float fbm(vec2 p, int oct) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < oct; i++) { v += a*vnoise(p); p *= 2.13; a *= 0.47; }
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv  = world_pos.xz / tile_m;
	vec2 uv2 = world_pos.xz / (tile_m * 4.0) + vec2(0.37, 0.61); // coarser, offset

	vec3 alb = texture(grass_albedo, uv).rgb;

	// Blend normals at two scales — breaks up the 'wet floor' specularity
	vec3 n1 = texture(grass_normal, uv).rgb;
	vec3 n2 = texture(grass_normal, uv2).rgb;
	vec3 nrm = normalize(n1 * 0.65 + n2 * 0.35);

	// Large-scale colour variation
	float f = clamp(fbm(world_pos.xz * 0.004, 4) * 0.45
	              + fbm(world_pos.xz * 0.025, 3) * 0.35 + 0.30, 0.48, 1.1);

	// Blend toward brown dirt where noise is low (bare earth patches)
	vec3 dirt = vec3(0.22, 0.17, 0.10);
	float wear = smoothstep(0.60, 0.50, f);
	ALBEDO          = mix(alb * f, dirt, wear * 0.7);
	NORMAL_MAP      = nrm;
	NORMAL_MAP_DEPTH = 1.6;   // stronger blade-level detail
	ROUGHNESS       = clamp(texture(grass_rough, uv).r * 0.15 + 0.85, 0.0, 1.0);
	SPECULAR        = 0.0;    // no specular highlight on grass
	METALLIC        = 0.0;
}
"""


func _terrain_shader_code() -> String:
	return """shader_type spatial;
render_mode cull_disabled;

varying vec3 world_pos;

// ---- value noise helpers ----
float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash2(i),                hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0,1.0)), hash2(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

float fbm(vec2 p, int oct) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * vnoise(p);
		p *= 2.13;
		a *= 0.47;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pos = world_pos.xz;

	// Three noise scales: large terrain-scale patches, medium lawn variation, fine detail
	float f_large  = fbm(pos * 0.004, 4);   // ~250 m blobs
	float f_medium = fbm(pos * 0.028, 4);   // ~35 m patches
	float f_fine   = fbm(pos * 0.20,  3);   // ~5 m detail

	float t = clamp(f_large * 0.45 + f_medium * 0.38 + f_fine * 0.17, 0.0, 1.0);

	// Five-stop grass colour ramp
	vec3 c0 = vec3(0.07, 0.20, 0.05);   // deep shade
	vec3 c1 = vec3(0.14, 0.34, 0.10);   // shaded grass
	vec3 c2 = vec3(0.24, 0.50, 0.15);   // typical lawn
	vec3 c3 = vec3(0.38, 0.60, 0.20);   // sun-lit grass
	vec3 c4 = vec3(0.52, 0.48, 0.20);   // dry / worn patch

	vec3 color;
	if      (t < 0.25) color = mix(c0, c1, t / 0.25);
	else if (t < 0.50) color = mix(c1, c2, (t - 0.25) / 0.25);
	else if (t < 0.75) color = mix(c2, c3, (t - 0.50) / 0.25);
	else               color = mix(c3, c4, (t - 0.75) / 0.25);

	ALBEDO    = color;
	ROUGHNESS = 0.92;
	METALLIC  = 0.0;
}
"""


# ---------------------------------------------------------------------------
# Central Park geometry (paths + boundary walls from park_data.json)
# ---------------------------------------------------------------------------
func _setup_park() -> void:
	var loader = load("res://park_loader.gd").new()
	loader.name = "CentralPark"
	if not _hm_data.is_empty():
		loader.set_heightmap(_hm_data, _hm_width, _hm_depth, _hm_world_size)
	add_child(loader)
	# Grab lamppost material for day/night emission control
	if loader.lamppost_material:
		_lamp_mat = loader.lamppost_material


# ---------------------------------------------------------------------------
# Player
# ---------------------------------------------------------------------------
func _setup_player() -> CharacterBody3D:
	var p: CharacterBody3D = load("res://player.gd").new()
	p.name       = "Player"
	p.position.y = _hm_origin_height + 2.0
	add_child(p)
	return p


# ---------------------------------------------------------------------------
# HUD: semi-transparent panel, top-left corner
# ---------------------------------------------------------------------------
func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.0, 0.0, 0.0, 0.58)
	style.corner_radius_top_left     = 7
	style.corner_radius_top_right    = 7
	style.corner_radius_bottom_left  = 7
	style.corner_radius_bottom_right = 7
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_coord_label = Label.new()
	_coord_label.text = "X:       0.0      Z:       0.0"
	_coord_label.add_theme_font_size_override("font_size", 22)
	_coord_label.add_theme_color_override("font_color", Color(0.85, 1.00, 0.85))
	vbox.add_child(_coord_label)

	_heading_label = Label.new()
	_heading_label.text = "Heading:    0.0°  N"
	_heading_label.add_theme_font_size_override("font_size", 22)
	_heading_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.00))
	vbox.add_child(_heading_label)

	_latlon_label = Label.new()
	_latlon_label.text = "40.782900° N    73.965400° W"
	_latlon_label.add_theme_font_size_override("font_size", 22)
	_latlon_label.add_theme_color_override("font_color", Color(1.00, 0.95, 0.75))
	vbox.add_child(_latlon_label)

	_time_label = Label.new()
	_time_label.text = "6:00 AM  [1x]"
	_time_label.add_theme_font_size_override("font_size", 22)
	_time_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	vbox.add_child(_time_label)

	var hint := Label.new()
	hint.text = "Left stick: walk   Right stick: look   T: time speed   [/]: +/-1 hour"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(hint)
