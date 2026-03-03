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
var _time_of_day: float = 6.0        # start at 6 AM
var _time_speed: float  = 0.001      # game-hours per real-second (~400 min full cycle)
var _time_speed_idx: int = 0
const TIME_SPEEDS: Array = [0.001, 0.01, 0.1, 0.0]
const TIME_SPEED_NAMES: Array = ["1x", "10x", "100x", "Paused"]

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _lamp_mat: StandardMaterial3D
var _terrain_mat: ShaderMaterial
var _time_label: Label

# 5 keyframes defining the full day/night cycle
# Night (21→5) wraps seamlessly; 8 hours of steady darkness.
var _keyframes: Array = []
const _KF_HOURS: Array = [5.0, 6.5, 12.0, 19.0, 21.0]


func _ready() -> void:
	_build_keyframes()
	_load_heightmap()
	_setup_environment()
	_setup_park()
	_apply_tunnel_depressions()
	_setup_ground()
	if _park_loader and _park_loader.splat_texture:
		_apply_splat_map(_park_loader.splat_texture)
	if _park_loader and _park_loader.boundary_polygon.size() > 2:
		_apply_boundary_mask(_park_loader.boundary_polygon)
	_player = _setup_player()
	_setup_hud()
	_apply_time_of_day()
var _screenshot_timer := 0.0
var _screenshot_done  := false


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
	# Auto-screenshot for dev review
	if not _screenshot_done:
		_screenshot_timer += delta
		if _screenshot_timer >= 4.0:
			_screenshot_done = true
			var img := get_viewport().get_texture().get_image()
			if img:
				img.save_png("/tmp/godot_screenshot.png")
				print("Screenshot saved to /tmp/godot_screenshot.png")
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
	_env.ambient_light_source  = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 0.5
	_env.tonemap_mode          = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled          = true
	_env.glow_blend_mode       = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.ssao_enabled          = true
	_env.ssao_detail           = 0.5
	_env.ssil_enabled          = true
	_env.ssil_radius           = 5.0
	_env.ssil_sharpness        = 0.98
	_env.ssr_enabled           = true
	_env.ssr_max_steps         = 64
	_env.ssr_fade_in           = 0.15
	_env.ssr_fade_out          = 2.0
	_env.ssr_depth_tolerance   = 0.2
	_env.adjustment_enabled    = true
	_env.adjustment_brightness = 1.02
	_env.fog_enabled           = true

	# Volumetric fog — light shafts, depth haze, ground fog
	_env.volumetric_fog_enabled = false
	_env.volumetric_fog_density = 0.0008
	_env.volumetric_fog_albedo = Color(1.0, 1.0, 1.0)
	_env.volumetric_fog_emission = Color(0, 0, 0)
	_env.volumetric_fog_anisotropy = 0.3
	_env.volumetric_fog_length = 200.0
	_env.volumetric_fog_detail_spread = 2.0
	_env.volumetric_fog_ambient_inject = 0.5
	_env.volumetric_fog_gi_inject = 0.0
	_env.volumetric_fog_sky_affect = 0.15
	_env.volumetric_fog_temporal_reprojection_enabled = false

	# SDFGI — global illumination (green bounce under canopies, warm path reflections)
	_env.sdfgi_enabled = false
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_read_sky_light = true
	_env.sdfgi_bounce_feedback = 0.0
	_env.sdfgi_cascades = 4
	_env.sdfgi_min_cell_size = 0.2
	_env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	_env.sdfgi_energy = 0.6
	_env.sdfgi_normal_bias = 1.1
	_env.sdfgi_probe_bias = 1.1

	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_split_1      = 0.08
	_sun.directional_shadow_max_distance = 200.0
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
		"vol_fog_density":    0.0015,
		"vol_fog_anisotropy": 0.1,
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
		"ambient_color":  Color(0.45, 0.32, 0.18),
		"ambient_energy": 0.35,
		"exposure":       0.85,
		"white":          4.0,
		"glow_intensity": 0.7,
		"glow_bloom":     0.15,
		"glow_strength":  1.2,
		"glow_threshold": 0.8,
		"glow_cap":       5.0,
		"ssao_radius":    1.5,
		"ssao_intensity": 2.0,
		"ssao_power":     1.8,
		"ssil_intensity": 0.7,
		"saturation":     1.18,
		"contrast":       1.08,
		"brightness":     1.0,
		"fog_color":      Color(0.55, 0.38, 0.22),
		"fog_energy":     0.8,
		"fog_scatter":    0.35,
		"fog_density":    0.0015,
		"fog_aerial":     0.6,
		"fog_sky_affect": 0.5,
		"sun_energy":     2.2,
		"sun_color":      Color(1.0, 0.68, 0.32),
		"sun_pitch":      -15.0,
		"sun_yaw":        -95.0,
		"shadow_dist":    250.0,
		"lamp_emission":  0.0,
		"vol_fog_density":    0.0010,
		"vol_fog_anisotropy": 0.5,
	})

	# ---- 12.0  Noon ----
	_keyframes.append({
		"hour": 12.0,
		"sky_top":        Color(0.18, 0.38, 0.72),
		"sky_horizon":    Color(0.55, 0.58, 0.68),
		"gnd_bottom":     Color(0.10, 0.12, 0.08),
		"gnd_horizon":    Color(0.35, 0.38, 0.30),
		"sun_angle_max":  1.5,
		"sun_curve":      0.15,
		"ambient_color":  Color(0.42, 0.38, 0.28),
		"ambient_energy": 0.35,
		"exposure":       0.75,
		"white":          3.5,
		"glow_intensity": 0.6,
		"glow_bloom":     0.15,
		"glow_strength":  1.2,
		"glow_threshold": 0.8,
		"glow_cap":       8.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.0,
		"ssao_power":     1.8,
		"ssil_intensity": 0.8,
		"saturation":     1.18,
		"contrast":       1.05,
		"brightness":     1.0,
		"fog_color":      Color(0.48, 0.45, 0.38),
		"fog_energy":     1.0,
		"fog_scatter":    0.15,
		"fog_density":    0.0012,
		"fog_aerial":     0.5,
		"fog_sky_affect": 0.3,
		"sun_energy":     2.2,
		"sun_color":      Color(1.0, 0.94, 0.82),
		"sun_pitch":      -55.0,
		"sun_yaw":        -20.0,
		"shadow_dist":    300.0,
		"lamp_emission":  0.0,
		"vol_fog_density":    0.0005,
		"vol_fog_anisotropy": 0.3,
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
		"ambient_color":  Color(0.40, 0.28, 0.16),
		"ambient_energy": 0.32,
		"exposure":       0.90,
		"white":          4.0,
		"glow_intensity": 0.85,
		"glow_bloom":     0.22,
		"glow_strength":  1.5,
		"glow_threshold": 0.7,
		"glow_cap":       5.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.2,
		"ssao_power":     1.9,
		"ssil_intensity": 0.6,
		"saturation":     1.25,
		"contrast":       1.08,
		"brightness":     0.98,
		"fog_color":      Color(0.85, 0.82, 0.75),
		"fog_energy":     0.8,
		"fog_scatter":    0.40,
		"fog_density":    0.0016,
		"fog_aerial":     0.6,
		"fog_sky_affect": 0.5,
		"sun_energy":     2.0,
		"sun_color":      Color(1.0, 0.60, 0.25),
		"sun_pitch":      -12.0,
		"sun_yaw":        95.0,
		"shadow_dist":    220.0,
		"lamp_emission":  0.5,
		"vol_fog_density":    0.0012,
		"vol_fog_anisotropy": 0.6,
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
		"glow_bloom":     0.15,
		"glow_strength":  1.5,
		"glow_threshold": 0.5,
		"glow_cap":       3.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 3.0,
		"ssao_power":     2.0,
		"ssil_intensity": 0.6,
		"saturation":     0.60,
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
		"vol_fog_density":    0.0015,
		"vol_fog_anisotropy": 0.1,
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

	# Volumetric fog
	_env.volumetric_fog_density    = _lerp_kf("vol_fog_density", a, b, t)
	_env.volumetric_fog_anisotropy = _lerp_kf("vol_fog_anisotropy", a, b, t)

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
# Carve terrain at tunnel locations.
# Stairwells: {x, z, dx, dz, length, hw, max_depth} — linear ramp
# Tunnel bodies: {polyline, hw, max_depth, body:true} — distance to polyline
# ---------------------------------------------------------------------------
func _apply_tunnel_depressions() -> void:
	if _hm_data.is_empty() or _park_loader == null:
		return
	var depressions: Array = _park_loader.tunnel_depressions
	if depressions.is_empty():
		return
	var W := _hm_width
	var H := _hm_depth
	var half := _hm_world_size * 0.5
	var cell := _hm_world_size / float(W - 1)
	var margin := 2.0

	for dep in depressions:
		var is_body: bool = dep.get("body", false)
		var hw: float = dep["hw"]
		var max_d: float = dep["max_depth"]

		if is_body:
			# Polyline-based: depress all vertices within hw of the polyline
			var poly: Array = dep["polyline"]
			if poly.size() < 2:
				continue
			# Compute bounding box of polyline + hw
			var pmin_x := INF; var pmax_x := -INF
			var pmin_z := INF; var pmax_z := -INF
			for pt in poly:
				var px: float = pt[0]; var pz: float = pt[1]
				pmin_x = minf(pmin_x, px); pmax_x = maxf(pmax_x, px)
				pmin_z = minf(pmin_z, pz); pmax_z = maxf(pmax_z, pz)
			pmin_x -= hw; pmax_x += hw; pmin_z -= hw; pmax_z += hw
			var xi0 := maxi(0, int(floor((pmin_x + half) / cell)))
			var xi1 := mini(W - 1, int(ceil((pmax_x + half) / cell)))
			var zi0 := maxi(0, int(floor((pmin_z + half) / cell)))
			var zi1 := mini(H - 1, int(ceil((pmax_z + half) / cell)))

			for zi in range(zi0, zi1 + 1):
				for xi in range(xi0, xi1 + 1):
					var wx := -half + xi * cell
					var wz := -half + zi * cell
					# Find minimum distance to any segment of the polyline
					var min_dist := INF
					for si in range(poly.size() - 1):
						var ax: float = poly[si][0]; var az: float = poly[si][1]
						var bx: float = poly[si+1][0]; var bz: float = poly[si+1][1]
						var dx := bx - ax; var dz := bz - az
						var len_sq := dx * dx + dz * dz
						if len_sq < 0.0001:
							continue
						var t := clampf(((wx - ax) * dx + (wz - az) * dz) / len_sq, 0.0, 1.0)
						var cx := ax + t * dx; var cz := az + t * dz
						var dist := sqrt((wx - cx) * (wx - cx) + (wz - cz) * (wz - cz))
						if dist < min_dist:
							min_dist = dist
					if min_dist <= hw:
						var idx := zi * W + xi
						_hm_data[idx] = _hm_data[idx] - max_d
		else:
			# Stairwell: linear ramp depression
			var ox: float = dep["x"]; var oz: float = dep["z"]
			var dx: float = dep["dx"]; var dz: float = dep["dz"]
			var seg_len: float = dep["length"]
			var nx := -dz; var nz := dx
			var ext := hw + margin
			var bmin_x := minf(ox, ox + dx * seg_len) - ext
			var bmax_x := maxf(ox, ox + dx * seg_len) + ext
			var bmin_z := minf(oz, oz + dz * seg_len) - ext
			var bmax_z := maxf(oz, oz + dz * seg_len) + ext
			var xi0 := maxi(0, int(floor((bmin_x + half) / cell)))
			var xi1 := mini(W - 1, int(ceil((bmax_x + half) / cell)))
			var zi0 := maxi(0, int(floor((bmin_z + half) / cell)))
			var zi1 := mini(H - 1, int(ceil((bmax_z + half) / cell)))

			for zi in range(zi0, zi1 + 1):
				for xi in range(xi0, xi1 + 1):
					var wx := -half + xi * cell
					var wz := -half + zi * cell
					var rx := wx - ox; var rz := wz - oz
					var along := rx * dx + rz * dz
					var across := absf(rx * nx + rz * nz)
					if along < 0.0 or along > seg_len:
						continue
					if across > ext:
						continue
					var t_along := clampf(along / seg_len, 0.0, 1.0)
					# Deepest at tunnel entrance (t=0), surface at far end (t=1)
					var depth := max_d * (1.0 - t_along)
					if across > hw:
						depth *= 1.0 - clampf((across - hw) / margin, 0.0, 1.0)
					if depth > 0.01:
						var idx := zi * W + xi
						_hm_data[idx] = _hm_data[idx] - depth

	print("Terrain: applied ", depressions.size(), " tunnel depressions")


# ---------------------------------------------------------------------------
# Terrain ground – height-mapped mesh + HeightMapShape3D collision
# Falls back to a flat plane when heightmap.json is absent.
# ---------------------------------------------------------------------------
func _setup_ground() -> void:
	var tex_alb := _load_img_tex("res://textures/grass_albedo.jpg")
	var tex_nrm := _load_img_tex("res://textures/grass_normal.jpg")
	var tex_rgh := _load_img_tex("res://textures/grass_rough.jpg")
	var shader  := Shader.new()
	shader.code  = _terrain_shader_textured() if tex_alb != null else _terrain_shader_code()
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = shader
	if tex_alb != null:
		_terrain_mat.set_shader_parameter("grass_albedo", tex_alb)
		_terrain_mat.set_shader_parameter("grass_normal", tex_nrm)
		_terrain_mat.set_shader_parameter("grass_rough",  tex_rgh)
		_terrain_mat.set_shader_parameter("tile_m",       5.0)
		# Meadow/wild grass blend
		var m_alb := _load_img_tex("res://textures/Ground037_2K-JPG_Color.jpg")
		var m_nrm := _load_img_tex("res://textures/Ground037_2K-JPG_NormalGL.jpg")
		var m_rgh := _load_img_tex("res://textures/Ground037_2K-JPG_Roughness.jpg")
		if m_alb:
			_terrain_mat.set_shader_parameter("meadow_albedo", m_alb)
			_terrain_mat.set_shader_parameter("meadow_normal", m_nrm)
			_terrain_mat.set_shader_parameter("meadow_rough",  m_rgh)
			_terrain_mat.set_shader_parameter("meadow_tile_m", 4.0)
		print("Ground: textured grass shader + meadow blend")

	if _hm_data.is_empty():
		# Flat fallback
		var plane            := PlaneMesh.new()
		plane.size            = Vector2(5000.0, 5000.0)
		plane.subdivide_width  = 1
		plane.subdivide_depth  = 1
		var mi                := MeshInstance3D.new()
		mi.mesh                = plane
		mi.material_override   = _terrain_mat
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
	mesh.surface_set_material(0, _terrain_mat)

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

// Grass textures
uniform sampler2D grass_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 5.0;

// Meadow/wild grass blend
uniform sampler2D meadow_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float meadow_tile_m = 4.0;

// Splat map + path texture arrays
uniform sampler2D splat_map : filter_nearest, repeat_disable;
uniform sampler2DArray path_alb_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray path_nrm_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray path_rgh_arr : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float world_size = 5000.0;
uniform float path_tile_m = 2.5;

// Park boundary mask: white = inside park, black = outside
uniform sampler2D park_mask : filter_linear, repeat_disable;

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

// Returns vec4(tex_set_index, tint_r, tint_g, tint_b) for material indices 1-30
vec4 mat_lookup(int idx) {
	// tex_set: 0=Asphalt, 1=Concrete, 2=PavingStones, 3=Gravel, 4=Wood
	if (idx == 1)  return vec4(0.0, 0.32, 0.30, 0.26);   // asphalt
	if (idx == 2)  return vec4(1.0, 0.72, 0.68, 0.60);   // concrete
	if (idx == 3)  return vec4(1.0, 0.65, 0.65, 0.63);   // concrete:plates
	if (idx == 4)  return vec4(2.0, 0.80, 0.74, 0.62);   // paving_stones
	if (idx == 5)  return vec4(2.0, 0.54, 0.52, 0.48);   // sett
	if (idx == 6)  return vec4(2.0, 0.52, 0.50, 0.44);   // unhewn_cobblestone
	if (idx == 7)  return vec4(3.0, 0.60, 0.57, 0.50);   // pebblestone
	if (idx == 8)  return vec4(2.0, 0.60, 0.58, 0.54);   // stone
	if (idx == 9)  return vec4(2.0, 0.56, 0.54, 0.50);   // rock
	if (idx == 10) return vec4(2.0, 0.68, 0.38, 0.26);   // brick
	if (idx == 11) return vec4(1.0, 0.62, 0.63, 0.66);   // metal
	if (idx == 12) return vec4(4.0, 0.50, 0.34, 0.16);   // wood
	if (idx == 13) return vec4(1.0, 0.64, 0.60, 0.52);   // paved
	if (idx == 14) return vec4(3.0, 0.52, 0.42, 0.28);   // compacted
	if (idx == 15) return vec4(3.0, 0.64, 0.57, 0.44);   // fine_gravel
	if (idx == 16) return vec4(3.0, 0.60, 0.53, 0.40);   // gravel
	if (idx == 17) return vec4(3.0, 0.54, 0.43, 0.28);   // unpaved
	if (idx == 18) return vec4(3.0, 0.50, 0.38, 0.22);   // dirt
	if (idx == 19) return vec4(3.0, 0.46, 0.38, 0.26);   // ground
	if (idx == 20) return vec4(3.0, 0.28, 0.52, 0.18);   // grass
	if (idx == 21) return vec4(3.0, 0.46, 0.32, 0.14);   // woodchips
	if (idx == 22) return vec4(3.0, 0.40, 0.28, 0.12);   // mulch
	if (idx == 23) return vec4(3.0, 0.76, 0.70, 0.52);   // sand
	if (idx == 24) return vec4(2.0, 0.74, 0.66, 0.50);   // hw:footway
	if (idx == 25) return vec4(0.0, 0.30, 0.30, 0.32);   // hw:cycleway
	if (idx == 26) return vec4(2.0, 0.80, 0.74, 0.62);   // hw:pedestrian
	if (idx == 27) return vec4(3.0, 0.54, 0.44, 0.30);   // hw:path
	if (idx == 28) return vec4(1.0, 0.64, 0.58, 0.48);   // hw:steps
	if (idx == 29) return vec4(3.0, 0.48, 0.40, 0.26);   // hw:track
	return vec4(3.0, 0.65, 0.60, 0.48);                   // catchall (30)
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// --- Park boundary mask: outside = dark pavement ---
	vec2 mask_uv = (world_pos.xz + world_size * 0.5) / world_size;
	float park_inside = texture(park_mask, mask_uv).r;
	if (park_inside < 0.1) {
		// Outside park — city sidewalk / street
		float street_noise = hash2(floor(world_pos.xz * 0.3)) * 0.06;
		ALBEDO    = vec3(0.25 + street_noise, 0.23 + street_noise, 0.21 + street_noise);
		ROUGHNESS = 0.92;
		SPECULAR  = 0.0;
		METALLIC  = 0.0;
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	} else {

	// --- Splat map sampling (RG8: R=material index, G=coverage alpha) ---
	vec2 splat_uv = (world_pos.xz + world_size * 0.5) / world_size;

	// Sample 4 nearest texels for bilinear coverage interpolation
	float splat_res = float(textureSize(splat_map, 0).x);
	vec2 splat_texel = splat_uv * splat_res - 0.5;
	vec2 splat_frac = fract(splat_texel);
	vec2 splat_base = (floor(splat_texel) + 0.5) / splat_res;
	float splat_step = 1.0 / splat_res;

	vec2 s00 = texture(splat_map, splat_base).rg;
	vec2 s10 = texture(splat_map, splat_base + vec2(splat_step, 0.0)).rg;
	vec2 s01 = texture(splat_map, splat_base + vec2(0.0, splat_step)).rg;
	vec2 s11 = texture(splat_map, splat_base + vec2(splat_step, splat_step)).rg;

	// Bilinear blend of G (coverage) channel — already smooth from rasterizer
	float path_weight = mix(
		mix(s00.g, s10.g, splat_frac.x),
		mix(s01.g, s11.g, splat_frac.x),
		splat_frac.y
	);

	// Material index from nearest texel
	int mat_idx = int(texture(splat_map, splat_uv).r * 255.0 + 0.5);
	// If center is grass but there's path coverage nearby, use nearest path material
	if (mat_idx == 0 && path_weight > 0.01) {
		float best = s00.g;
		mat_idx = int(s00.r * 255.0 + 0.5);
		if (s10.g > best) { best = s10.g; mat_idx = int(s10.r * 255.0 + 0.5); }
		if (s01.g > best) { best = s01.g; mat_idx = int(s01.r * 255.0 + 0.5); }
		if (s11.g > best) { best = s11.g; mat_idx = int(s11.r * 255.0 + 0.5); }
	}

	// --- Grass shading ---
	vec2 uv  = world_pos.xz / tile_m;
	vec2 uv2 = world_pos.xz / (tile_m * 4.0) + vec2(0.37, 0.61);
	vec3 grass_alb = texture(grass_albedo, uv).rgb;
	vec3 grass_n1 = texture(grass_normal, uv).rgb;
	vec3 grass_n2 = texture(grass_normal, uv2).rgb;
	vec3 grass_nrm = normalize(grass_n1 * 0.65 + grass_n2 * 0.35);
	float grass_rgh = clamp(texture(grass_rough, uv).r * 0.15 + 0.72, 0.0, 1.0);
	float f = clamp(fbm(world_pos.xz * 0.004, 4) * 0.45
	              + fbm(world_pos.xz * 0.025, 3) * 0.35 + 0.30, 0.48, 1.1);
	vec3 dirt = vec3(0.28, 0.20, 0.10);
	float wear = smoothstep(0.60, 0.50, f);
	grass_alb = mix(grass_alb * f, dirt, wear * 0.7);

	// Meadow/wild grass blend — large-scale FBM patches
	vec2 muv = world_pos.xz / meadow_tile_m;
	vec3 m_alb = texture(meadow_albedo, muv).rgb;
	vec3 m_nrm = texture(meadow_normal, muv).rgb;
	float m_rgh = clamp(texture(meadow_rough, muv).r * 0.15 + 0.72, 0.0, 1.0);
	float meadow_noise = fbm(world_pos.xz * 0.003, 3) * 0.6
	                    + fbm(world_pos.xz * 0.018, 2) * 0.4;
	float meadow_blend = smoothstep(0.42, 0.58, meadow_noise);
	grass_alb = mix(grass_alb, m_alb * f, meadow_blend);
	grass_nrm = mix(grass_nrm, m_nrm, meadow_blend);
	grass_rgh = mix(grass_rgh, m_rgh, meadow_blend);

	// Mud puddles where wear patches exist
	float mud = smoothstep(0.25, 0.45, wear);
	grass_alb = mix(grass_alb, vec3(0.15, 0.10, 0.06), mud * 0.5);
	grass_rgh = mix(grass_rgh, 0.30, mud * 0.6);

	// Micro-normal bumps — uneven ground feel
	float bump_a = vnoise(world_pos.xz * 0.8) * 0.5 + vnoise(world_pos.xz * 2.5) * 0.3;
	float bump_dx = (vnoise(vec2(world_pos.x + 0.1, world_pos.z) * 0.8) - vnoise(vec2(world_pos.x - 0.1, world_pos.z) * 0.8)) * 2.5;
	float bump_dz = (vnoise(vec2(world_pos.x, world_pos.z + 0.1) * 0.8) - vnoise(vec2(world_pos.x, world_pos.z - 0.1) * 0.8)) * 2.5;
	grass_nrm.rg += vec2(bump_dx, bump_dz) * 0.15;
	grass_nrm = normalize(grass_nrm);

	// Warm green push — richer green, subtle
	grass_alb.r *= 1.02;
	grass_alb.g *= 1.06;
	grass_alb.b *= 0.88;

	// Flower carpet — per-pixel flower dots for bluebell carpet illusion
	// Large-scale patch mask matches CPU wildflower placement noise
	float flower_n = fbm(world_pos.xz * 0.007, 3);
	float carpet_mask = smoothstep(0.25, 0.50, flower_n);
	carpet_mask *= (1.0 - wear * 0.8);
	float canopy_shade = 1.0 - smoothstep(0.35, 0.65, fbm(world_pos.xz * 0.15, 3));
	carpet_mask *= mix(0.15, 1.0, canopy_shade);
	// High-frequency flower dots — multi-scale for organic pattern
	float dot_n1 = vnoise(world_pos.xz * 10.0);
	float dot_n2 = vnoise(world_pos.xz * 22.0 + vec2(33.7, 17.1));
	float dot_combined = dot_n1 * 0.65 + dot_n2 * 0.35;
	float dot_mask = smoothstep(0.38, 0.56, dot_combined);
	// Color variation between individual dots
	float hue_var = vnoise(world_pos.xz * 4.0);
	vec3 flower_col = mix(vec3(0.14, 0.12, 0.45), vec3(0.22, 0.16, 0.52), hue_var);
	// Darken grass between flower dots for depth
	vec3 carpet_ground = mix(grass_alb * 0.70, flower_col, dot_mask);
	grass_alb = mix(grass_alb, carpet_ground, carpet_mask * 0.55);

	// Dappled sunlight — simulates light filtering through tree canopy
	float dapple = fbm(world_pos.xz * 0.15, 3) * 0.5
	             + fbm(world_pos.xz * 0.4, 2) * 0.3
	             + fbm(world_pos.xz * 1.2, 2) * 0.2;
	float sun_patch = smoothstep(0.38, 0.62, dapple);
	vec3 sun_tint = vec3(1.12, 1.06, 0.85); // warm golden highlight
	grass_alb *= mix(vec3(1.0), sun_tint, sun_patch * 0.45);

	if (mat_idx > 0 && path_weight > 0.001) {
		// --- Path shading ---
		vec4 ml = mat_lookup(mat_idx);
		float tex_set = ml.x;
		vec3 tint = ml.yzw;
		vec2 path_uv = world_pos.xz / path_tile_m;
		vec3 p_alb = texture(path_alb_arr, vec3(path_uv, tex_set)).rgb * tint;
		vec3 p_nrm = texture(path_nrm_arr, vec3(path_uv, tex_set)).rgb;
		float p_rgh = clamp(texture(path_rgh_arr, vec3(path_uv, tex_set)).r + 0.10, 0.0, 1.0);

		ALBEDO          = mix(grass_alb, p_alb, path_weight);
		NORMAL_MAP      = mix(grass_nrm, p_nrm, path_weight);
		NORMAL_MAP_DEPTH = mix(1.6, 1.0, path_weight);
		ROUGHNESS       = mix(grass_rgh, p_rgh, path_weight);
		SPECULAR        = mix(0.15, 0.0, path_weight);
		METALLIC        = 0.0;
	} else {
		ALBEDO          = grass_alb;
		NORMAL_MAP      = grass_nrm;
		NORMAL_MAP_DEPTH = 1.6;
		ROUGHNESS       = grass_rgh;
		SPECULAR        = 0.15;
		METALLIC        = 0.0;
	}

	} // end park_inside else
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
var _park_loader = null  # reference for tunnel depressions + splat map data

func _setup_park() -> void:
	var loader = load("res://park_loader.gd").new()
	loader.name = "CentralPark"
	if not _hm_data.is_empty():
		loader.set_heightmap(_hm_data, _hm_width, _hm_depth, _hm_world_size)
	add_child(loader)
	_park_loader = loader
	# Grab lamppost material for day/night emission control
	if loader.lamppost_material:
		_lamp_mat = loader.lamppost_material


func _apply_splat_map(splat_tex: ImageTexture) -> void:
	## Load 5 CC0 path texture sets into Texture2DArrays and wire them into
	## the terrain shader along with the splat map.
	var prefixes: Array = [
		"res://textures/Asphalt012_2K-JPG",       # index 0
		"res://textures/Concrete034_2K-JPG",       # index 1
		"res://textures/PavingStones130_2K-JPG",   # index 2
		"res://textures/Gravel021_2K-JPG",         # index 3
		"res://textures/WoodFloor041_2K-JPG",      # index 4
	]
	var suffixes: Array = ["_Color.jpg", "_NormalGL.jpg", "_Roughness.jpg"]
	var arr_tex: Array = []  # [alb_arr, nrm_arr, rgh_arr]

	for si in range(3):
		var images: Array[Image] = []
		for pi in range(prefixes.size()):
			var path: String = prefixes[pi] + suffixes[si]
			var img := Image.load_from_file(path)
			if not img:
				push_warning("Splat: missing texture " + path)
				img = Image.create(64, 64, false, Image.FORMAT_RGB8)
			# Ensure all layers have matching size and format
			if pi == 0:
				# First image sets the target size — use its natural size
				pass
			else:
				var target_size := images[0].get_size()
				if img.get_size() != target_size:
					img.resize(target_size.x, target_size.y)
			if img.get_format() != images[0].get_format() if pi > 0 else false:
				img.convert(images[0].get_format())
			img.generate_mipmaps()
			images.append(img)
		var tex2d_arr := Texture2DArray.new()
		tex2d_arr.create_from_images(images)
		arr_tex.append(tex2d_arr)

	_terrain_mat.set_shader_parameter("splat_map",    splat_tex)
	_terrain_mat.set_shader_parameter("path_alb_arr", arr_tex[0])
	_terrain_mat.set_shader_parameter("path_nrm_arr", arr_tex[1])
	_terrain_mat.set_shader_parameter("path_rgh_arr", arr_tex[2])
	_terrain_mat.set_shader_parameter("world_size",   _hm_world_size)
	_terrain_mat.set_shader_parameter("path_tile_m",  2.5)
	print("Terrain: splat map + path texture arrays applied")


func _apply_boundary_mask(poly: PackedVector2Array) -> void:
	## Rasterize a park-interior mask so terrain outside renders as dark pavement.
	var sz := 1024
	var img := Image.create(sz, sz, false, Image.FORMAT_R8)
	img.fill(Color(0, 0, 0))  # black = outside park
	var half := _hm_world_size * 0.5
	var n := poly.size()

	# Scanline fill: for each image row, find polygon edge crossings
	for y in range(sz):
		var wz := (float(y) / float(sz) - 0.5) * _hm_world_size
		var crossings := PackedFloat32Array()
		for i in range(n):
			var j := (i + 1) % n
			var zi := poly[i].y
			var zj := poly[j].y
			if (zi > wz) != (zj > wz):
				var t := (wz - zi) / (zj - zi)
				crossings.append(poly[i].x + t * (poly[j].x - poly[i].x))
		# Sort crossings
		var arr: Array = Array(crossings)
		arr.sort()
		# Fill between pairs (inside polygon)
		for k in range(0, arr.size() - 1, 2):
			var px0 := int(clampf((float(arr[k]) + half) / _hm_world_size * float(sz), 0.0, float(sz - 1)))
			var px1 := int(clampf((float(arr[k + 1]) + half) / _hm_world_size * float(sz), 0.0, float(sz - 1)))
			for px in range(px0, px1 + 1):
				img.set_pixel(px, y, Color(1, 1, 1))

	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_terrain_mat.set_shader_parameter("park_mask", tex)
	print("Terrain: boundary mask applied (%dx%d)" % [sz, sz])


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
