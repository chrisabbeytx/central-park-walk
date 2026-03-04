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
var _time_of_day: float = 16.0        # start at 4 PM
var _time_speed: float  = 0.001      # game-hours per real-second (~400 min full cycle)
var _time_speed_idx: int = 0
const TIME_SPEEDS: Array = [0.001, 0.01, 0.1, 0.0]
const TIME_SPEED_NAMES: Array = ["1x", "10x", "100x", "Paused"]

var _env: Environment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _lamp_mat: StandardMaterial3D
var _terrain_mat: ShaderMaterial
var _time_label: Label

# Dynamic lamppost lighting — pool of SpotLight3D nodes that follow player
var _lamp_lights: Array = []  # Array of SpotLight3D
var _lamp_positions: PackedVector3Array = PackedVector3Array()
var _lamp_light_timer: float = 0.0
const LAMP_LIGHT_COUNT := 32
const LAMP_LIGHT_RANGE := 18.0
const LAMP_LIGHT_UPDATE_INTERVAL := 0.5  # seconds between position updates

# Falling leaf particles
var _falling_leaves: GPUParticles3D

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
	if _park_loader and _park_loader.path_segs_texture:
		_apply_gpu_path_textures()
	if _park_loader and _park_loader.boundary_polygon.size() > 2:
		_apply_boundary_mask(_park_loader.boundary_polygon)
	_player = _setup_player()
	_setup_hud()
	_setup_color_grade()
	_setup_lamp_lights()
	_setup_falling_leaves()
	_setup_pigeons()
	_setup_audio()
	_apply_time_of_day()
	# Check for --tour CLI arg
	for arg in OS.get_cmdline_user_args():
		if arg == "--tour":
			_tour_mode = true
			_build_tour_shots()
			_tour_state = 0  # WAIT_LOAD
			_tour_timer = 0.0
			_tour_idx = 0
			DirAccess.make_dir_recursive_absolute("/tmp/tour")
			print("Tour mode: %d shots queued" % _tour_shots.size())
			break
var _screenshot_timer := 0.0
var _screenshot_done  := false

# ---------------------------------------------------------------------------
# Tour mode — automated screenshot capture across 10 locations × 3 angles × 3 times
# Activated via --tour CLI arg.  Non-tour mode is unchanged.
# ---------------------------------------------------------------------------
var _tour_mode := false
var _tour_state := 0  # 0=WAIT_LOAD, 1=SETTLE, 2=CAPTURE, 3=DONE
var _tour_timer := 0.0
var _tour_idx := 0  # index into _tour_shots array
var _tour_shots: Array = []  # populated in _build_tour_shots()

const TOUR_VIEWPOINTS: Array = [
	{"name": "bethesda_fountain", "x": -458.0, "z": 949.0, "yaw": 45.0},
	{"name": "literary_walk", "x": -600.0, "z": 1420.0, "yaw": 30.0},
	{"name": "great_lawn", "x": -200.0, "z": 0.0, "yaw": 0.0},
	{"name": "conservatory_water", "x": -152.0, "z": 958.0, "yaw": 270.0},
	{"name": "alice_wonderland", "x": -96.0, "z": 869.0, "yaw": 315.0},
	{"name": "balto_south", "x": -473.0, "z": 1430.0, "yaw": 60.0},
	{"name": "the_lake", "x": -522.0, "z": 694.0, "yaw": 0.0},
	{"name": "cherry_hill", "x": -616.0, "z": 907.0, "yaw": 90.0},
	{"name": "cleopatras_needle", "x": 0.0, "z": 360.0, "yaw": 180.0},
	{"name": "ramble", "x": -400.0, "z": 600.0, "yaw": 225.0},
]

const TOUR_ANGLES: Array = [
	{"suffix": "_0", "yaw_offset": 0.0, "pitch": 0.0},    # forward
	{"suffix": "_1", "yaw_offset": -90.0, "pitch": 0.0},   # left 90°
	{"suffix": "_2", "yaw_offset": 0.0, "pitch": -25.0},   # down
]

const TOUR_TIMES: Array = [7.0, 12.0, 17.0]

func _build_tour_shots() -> void:
	_tour_shots.clear()
	for vp in TOUR_VIEWPOINTS:
		for ti in range(TOUR_TIMES.size()):
			for ai in range(TOUR_ANGLES.size()):
				_tour_shots.append({
					"name": vp["name"],
					"x": float(vp["x"]),
					"z": float(vp["z"]),
					"yaw": float(vp["yaw"]) + float(TOUR_ANGLES[ai]["yaw_offset"]),
					"pitch": float(TOUR_ANGLES[ai]["pitch"]),
					"hour": TOUR_TIMES[ti],
					"filename": "%s_%dh%s" % [vp["name"], int(TOUR_TIMES[ti]), TOUR_ANGLES[ai]["suffix"]],
				})


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
	## Barycentric interpolation matching the terrain mesh's adaptive diagonal split.
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
	# Match mesh diagonal: checkerboard on flat, adaptive on slopes
	var d1 := absf(h00 - h11)
	var d2 := absf(h10 - h01)
	var use_alt: bool
	if absf(d1 - d2) < 0.02:
		use_alt = (xi0 + zi0) % 2 == 1
	else:
		use_alt = d2 < d1
	if not use_alt:
		# Split along 00→11
		if fz <= fx:
			return h00 + (h10 - h00) * fx + (h11 - h10) * fz
		else:
			return h00 + (h11 - h01) * fx + (h01 - h00) * fz
	else:
		# Split along 10→01
		if fx + fz <= 1.0:
			return h00 + (h10 - h00) * fx + (h01 - h00) * fz
		else:
			return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


# ---------------------------------------------------------------------------
# Per-frame update: time + HUD
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# --- Tour mode state machine ---
	if _tour_mode:
		_tour_timer += delta
		match _tour_state:
			0:  # WAIT_LOAD — let scene fully build
				if _tour_timer >= 50.0:
					_tour_state = 1
					_tour_timer = 0.0
					_tour_teleport(_tour_idx)
					print("Tour: load complete, starting captures")
			1:  # SETTLE — let SSAO/SSR/fog converge
				if _tour_timer >= 3.0:
					_tour_state = 2
					_tour_timer = 0.0
			2:  # CAPTURE
				var img := get_viewport().get_texture().get_image()
				if img:
					var shot: Dictionary = _tour_shots[_tour_idx]
					var path := "/tmp/tour/%s.png" % shot["filename"]
					img.save_png(path)
					print("Tour [%d/%d]: %s" % [_tour_idx + 1, _tour_shots.size(), shot["filename"]])
				_tour_idx += 1
				if _tour_idx >= _tour_shots.size():
					_tour_write_manifest()
					_tour_state = 3
					print("Tour complete: %d shots saved to /tmp/tour/" % _tour_shots.size())
					get_tree().quit()
				else:
					_tour_state = 1
					_tour_timer = 0.0
					_tour_teleport(_tour_idx)
			3:  # DONE
				pass
		_apply_time_of_day()
		return

	# Auto-screenshot for dev review (non-tour mode)
	if not _screenshot_done:
		_screenshot_timer += delta
		# Hold player frozen at aerial position every frame until screenshot
		var sx := -200.0; var sz := 100.0
		_player.set_physics_process(false)
		_player.velocity = Vector3.ZERO
		_player.global_position = Vector3(sx, _terrain_height(sx, sz) + 30.0, sz)
		_player.rotation_degrees.y = 90.0
		var head_node: Node3D = _player.get_node("Head")
		if head_node:
			head_node.rotation_degrees.x = -55.0
		_time_of_day = 12.0
		_time_speed = 0.0
		_apply_time_of_day()
		if _screenshot_timer >= 4.0:
			_screenshot_done = true
			var img := get_viewport().get_texture().get_image()
			if img:
				img.save_png("/tmp/godot_screenshot.png")
				print("Screenshot saved to /tmp/godot_screenshot.png")
	# Update lamp lights every 0.5s
	_lamp_light_timer += delta
	if _lamp_light_timer >= LAMP_LIGHT_UPDATE_INTERVAL:
		_lamp_light_timer = 0.0
		_update_lamp_lights()

	# Move falling leaves to follow player
	if _falling_leaves and _player:
		_falling_leaves.global_position = _player.global_position + Vector3(0, 10, 0)

	# Update audio
	_update_audio(delta)

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


func _tour_teleport(idx: int) -> void:
	var shot: Dictionary = _tour_shots[idx]
	var x: float = shot["x"]
	var z: float = shot["z"]
	var yaw: float = shot["yaw"]
	var pitch: float = shot["pitch"]
	var hour: float = shot["hour"]
	_player.position = Vector3(x, _terrain_height(x, z) + 1.8, z)
	_player.rotation_degrees.y = yaw
	var head: Node3D = _player.get_node("Head")
	if head:
		head.rotation_degrees.x = pitch
	_time_of_day = hour
	_time_speed = 0.0
	_apply_time_of_day()


func _tour_write_manifest() -> void:
	var manifest: Dictionary = {"shots": [], "viewpoints": TOUR_VIEWPOINTS.size(), "angles": TOUR_ANGLES.size(), "times": TOUR_TIMES.size()}
	for shot in _tour_shots:
		manifest["shots"].append({"filename": shot["filename"] + ".png", "name": shot["name"], "hour": shot["hour"], "x": shot["x"], "z": shot["z"]})
	var fa := FileAccess.open("/tmp/tour/manifest.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(manifest, "\t"))
	fa.close()
	print("Tour: manifest.json written")


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


func _cloud_sky_shader_code() -> String:
	return """shader_type sky;

uniform vec3 sky_top_color = vec3(0.18, 0.38, 0.72);
uniform vec3 sky_horizon_color = vec3(0.55, 0.58, 0.68);
uniform vec3 ground_bottom_color = vec3(0.10, 0.12, 0.08);
uniform vec3 ground_horizon_color = vec3(0.35, 0.38, 0.30);

uniform float cloud_coverage = 0.65;
uniform float cloud_density = 0.50;
uniform float cloud_speed = 0.004;
uniform vec3 cloud_color_top = vec3(0.90, 0.90, 0.92);
uniform vec3 cloud_color_bottom = vec3(0.45, 0.45, 0.50);

float sky_hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}
float sky_vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(sky_hash(i), sky_hash(i + vec2(1.0, 0.0)), u.x),
	           mix(sky_hash(i + vec2(0.0, 1.0)), sky_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float sky_fbm(vec2 p, int oct) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * sky_vnoise(p);
		p *= 2.13;
		a *= 0.47;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float elev = dir.y;

	// --- Sky gradient ---
	vec3 sky_col;
	if (elev >= 0.0) {
		float t = clamp(elev * 2.5, 0.0, 1.0);
		sky_col = mix(sky_horizon_color, sky_top_color, t);
	} else {
		float t = clamp(-elev * 4.0, 0.0, 1.0);
		sky_col = mix(ground_horizon_color, ground_bottom_color, t);
	}

	// --- Sun disc ---
	float sun_dot = dot(dir, LIGHT0_DIRECTION);
	float sun_disc = smoothstep(0.9992, 0.9998, sun_dot);
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY * 2.0;
	// Sun glow halo
	float sun_glow = pow(max(sun_dot, 0.0), 64.0) * 0.3;
	sky_col += sun_col * (sun_disc + sun_glow);

	// --- Stars ---
	if (elev > 0.0) {
		float star_fade = smoothstep(0.15, 0.0, LIGHT0_ENERGY);
		if (star_fade > 0.0) {
			vec2 star_uv = dir.xz / (elev + 0.001) * 80.0;
			vec2 star_cell = floor(star_uv);
			float star_rand = sky_hash(star_cell);
			float star_mask = step(0.97, star_rand);
			float star_bright = sky_hash(star_cell + vec2(13.7, 29.3));
			star_bright = star_bright * star_bright * 1.5;
			float twinkle = 0.8 + 0.2 * sin(TIME * 2.0 + star_rand * 100.0);
			vec2 star_frac = fract(star_uv) - 0.5;
			float star_point = smoothstep(0.12, 0.02, length(star_frac));
			sky_col += vec3(star_bright * star_mask * star_point * star_fade * twinkle);
		}
	}

	// --- FBM cloud layer ---
	if (elev > -0.05) {
		// Project onto cloud dome — higher elevation = closer to zenith
		float cloud_y = max(elev, 0.01);
		vec2 cloud_uv = dir.xz / (cloud_y + 0.1) * 0.8;
		cloud_uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.7);

		float n = sky_fbm(cloud_uv * 3.0, 5);
		// Coverage threshold — higher coverage = more clouds
		float cloud_mask = smoothstep(1.0 - cloud_coverage - 0.1, 1.0 - cloud_coverage + 0.2, n);
		cloud_mask *= cloud_density;

		// Cloud shading: top lit by sun, bottom darker
		float sun_illum = max(dot(LIGHT0_DIRECTION, vec3(0.0, 1.0, 0.0)), 0.0);
		float edge_lit = pow(max(sun_dot, 0.0), 4.0) * 0.4;
		vec3 cloud_col = mix(cloud_color_bottom, cloud_color_top, sun_illum * 0.4 + 0.25);
		// Sun-facing edges get warm highlight
		cloud_col += LIGHT0_COLOR * edge_lit * 0.5;

		// Fade clouds near horizon to blend with haze
		float horizon_fade = smoothstep(0.0, 0.12, elev);
		cloud_mask *= horizon_fade;

		sky_col = mix(sky_col, cloud_col, cloud_mask);
	}

	COLOR = sky_col;
}
"""


func _setup_environment() -> void:
	var sky_shader := Shader.new()
	sky_shader.code = _cloud_sky_shader_code()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sky_shader

	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	_env = Environment.new()
	_env.background_mode       = Environment.BG_SKY
	_env.sky                   = sky
	_env.ambient_light_source  = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 0.3
	_env.tonemap_mode          = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white         = 6.0
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

	# Volumetric fog — light shafts (god rays at sunrise/sunset via high anisotropy)
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_density = 0.0008
	_env.volumetric_fog_albedo = Color(1.0, 1.0, 1.0)
	_env.volumetric_fog_emission = Color(0.8, 0.85, 0.9)
	_env.volumetric_fog_emission_energy = 0.12
	_env.volumetric_fog_anisotropy = 0.3
	_env.volumetric_fog_length = 150.0
	_env.volumetric_fog_detail_spread = 2.0
	_env.volumetric_fog_ambient_inject = 0.8
	_env.volumetric_fog_gi_inject = 0.0
	_env.volumetric_fog_sky_affect = 0.30
	_env.volumetric_fog_temporal_reprojection_enabled = true

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
		"sky_top":        Color(0.03, 0.04, 0.12),
		"sky_horizon":    Color(0.10, 0.10, 0.18),
		"gnd_bottom":     Color(0.01, 0.01, 0.02),
		"gnd_horizon":    Color(0.08, 0.06, 0.10),
		"sun_angle_max":  3.0,
		"sun_curve":      0.01,
		"ambient_color":  Color(0.10, 0.10, 0.18),
		"ambient_energy": 0.15,
		"exposure":       0.75,
		"white":          5.0,
		"glow_intensity": 0.7,
		"glow_bloom":     0.20,
		"glow_strength":  2.5,
		"glow_threshold": 0.10,
		"glow_cap":       3.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.8,
		"ssao_power":     2.0,
		"ssil_intensity": 0.5,
		"saturation":     0.55,
		"contrast":       1.08,
		"brightness":     0.85,
		"fog_color":      Color(0.12, 0.10, 0.14),
		"fog_energy":     0.15,
		"fog_scatter":    0.05,
		"fog_density":    0.0020,
		"fog_aerial":     0.50,
		"fog_sky_affect": 0.6,
		"sun_energy":     0.05,
		"sun_color":      Color(0.65, 0.72, 0.95),
		"sun_pitch":      -10.0,
		"sun_yaw":        -100.0,
		"shadow_dist":    180.0,
		"lamp_emission":  2.0,
		"vol_fog_density":    0.0010,
		"vol_fog_anisotropy": 0.15,
		"cloud_coverage":     0.30,
		"cloud_density":      0.55,
		"cloud_color_top":    Color(0.42, 0.40, 0.44),
		"cloud_color_bottom": Color(0.16, 0.14, 0.18),
		"cloud_speed":        0.003,
	})

	# ---- 6.5  Sunrise / Golden hour ----
	_keyframes.append({
		"hour": 6.5,
		"sky_top":        Color(0.25, 0.38, 0.62),
		"sky_horizon":    Color(0.68, 0.50, 0.38),
		"gnd_bottom":     Color(0.10, 0.08, 0.06),
		"gnd_horizon":    Color(0.42, 0.32, 0.22),
		"sun_angle_max":  5.0,
		"sun_curve":      0.08,
		"ambient_color":  Color(0.45, 0.35, 0.25),
		"ambient_energy": 0.60,
		"exposure":       0.80,
		"white":          5.0,
		"glow_intensity": 0.75,
		"glow_bloom":     0.20,
		"glow_strength":  1.0,
		"glow_threshold": 0.55,
		"glow_cap":       5.0,
		"ssao_radius":    1.5,
		"ssao_intensity": 2.5,
		"ssao_power":     1.8,
		"ssil_intensity": 0.7,
		"saturation":     0.94,
		"contrast":       1.06,
		"brightness":     1.0,
		"fog_color":      Color(0.55, 0.42, 0.34),
		"fog_energy":     0.6,
		"fog_scatter":    0.20,
		"fog_density":    0.0012,
		"fog_aerial":     0.40,
		"fog_sky_affect": 0.3,
		"sun_energy":     0.85,
		"sun_color":      Color(1.0, 0.72, 0.38),
		"sun_pitch":      -15.0,
		"sun_yaw":        -95.0,
		"shadow_dist":    250.0,
		"lamp_emission":  0.0,
		"vol_fog_density":    0.0006,
		"vol_fog_anisotropy": 0.75,
		"cloud_coverage":     0.40,
		"cloud_density":      0.55,
		"cloud_color_top":    Color(0.92, 0.88, 0.78),
		"cloud_color_bottom": Color(0.48, 0.40, 0.32),
		"cloud_speed":        0.004,
	})

	# ---- 12.0  Noon (clear, punchy daylight) ----
	_keyframes.append({
		"hour": 12.0,
		"sky_top":        Color(0.22, 0.42, 0.75),
		"sky_horizon":    Color(0.55, 0.60, 0.68),
		"gnd_bottom":     Color(0.12, 0.12, 0.10),
		"gnd_horizon":    Color(0.38, 0.36, 0.32),
		"sun_angle_max":  1.5,
		"sun_curve":      0.15,
		"ambient_color":  Color(0.50, 0.46, 0.38),
		"ambient_energy": 0.75,
		"exposure":       0.80,
		"white":          6.0,
		"glow_intensity": 0.50,
		"glow_bloom":     0.15,
		"glow_strength":  0.70,
		"glow_threshold": 0.60,
		"glow_cap":       8.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.5,
		"ssao_power":     2.0,
		"ssil_intensity": 1.0,
		"saturation":     0.95,
		"contrast":       1.06,
		"brightness":     1.00,
		"fog_color":      Color(0.55, 0.52, 0.48),
		"fog_energy":     0.6,
		"fog_scatter":    0.05,
		"fog_density":    0.0008,
		"fog_aerial":     0.35,
		"fog_sky_affect": 0.30,
		"sun_energy":     0.75,
		"sun_color":      Color(0.95, 0.92, 0.85),
		"sun_pitch":      -55.0,
		"sun_yaw":        -20.0,
		"shadow_dist":    300.0,
		"lamp_emission":  0.0,
		"vol_fog_density":    0.0004,
		"vol_fog_anisotropy": 0.18,
		"cloud_coverage":     0.35,
		"cloud_density":      0.50,
		"cloud_color_top":    Color(0.95, 0.95, 0.93),
		"cloud_color_bottom": Color(0.68, 0.68, 0.66),
		"cloud_speed":        0.005,
	})

	# ---- 19.0  Sunset / Golden hour ----
	_keyframes.append({
		"hour": 19.0,
		"sky_top":        Color(0.25, 0.22, 0.38),
		"sky_horizon":    Color(0.72, 0.46, 0.30),
		"gnd_bottom":     Color(0.08, 0.06, 0.04),
		"gnd_horizon":    Color(0.42, 0.32, 0.20),
		"sun_angle_max":  5.0,
		"sun_curve":      0.08,
		"ambient_color":  Color(0.42, 0.32, 0.22),
		"ambient_energy": 0.55,
		"exposure":       0.80,
		"white":          5.0,
		"glow_intensity": 0.85,
		"glow_bloom":     0.25,
		"glow_strength":  1.2,
		"glow_threshold": 0.48,
		"glow_cap":       5.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.5,
		"ssao_power":     1.9,
		"ssil_intensity": 0.6,
		"saturation":     0.94,
		"contrast":       1.05,
		"brightness":     1.0,
		"fog_color":      Color(0.68, 0.52, 0.38),
		"fog_energy":     0.6,
		"fog_scatter":    0.25,
		"fog_density":    0.0014,
		"fog_aerial":     0.40,
		"fog_sky_affect": 0.3,
		"sun_energy":     0.80,
		"sun_color":      Color(1.0, 0.65, 0.30),
		"sun_pitch":      -12.0,
		"sun_yaw":        95.0,
		"shadow_dist":    220.0,
		"lamp_emission":  0.5,
		"vol_fog_density":    0.0008,
		"vol_fog_anisotropy": 0.78,
		"cloud_coverage":     0.45,
		"cloud_density":      0.55,
		"cloud_color_top":    Color(0.78, 0.55, 0.42),
		"cloud_color_bottom": Color(0.50, 0.28, 0.18),
		"cloud_speed":        0.004,
	})

	# ---- 21.0  Night ----
	_keyframes.append({
		"hour": 21.0,
		"sky_top":        Color(0.02, 0.03, 0.08),
		"sky_horizon":    Color(0.04, 0.05, 0.12),
		"gnd_bottom":     Color(0.005, 0.008, 0.012),
		"gnd_horizon":    Color(0.02, 0.03, 0.06),
		"sun_angle_max":  3.0,
		"sun_curve":      0.01,
		"ambient_color":  Color(0.10, 0.10, 0.18),
		"ambient_energy": 0.15,
		"exposure":       0.75,
		"white":          5.0,
		"glow_intensity": 0.7,
		"glow_bloom":     0.25,
		"glow_strength":  2.5,
		"glow_threshold": 0.10,
		"glow_cap":       3.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 3.0,
		"ssao_power":     2.0,
		"ssil_intensity": 0.6,
		"saturation":     0.55,
		"contrast":       1.08,
		"brightness":     0.85,
		"fog_color":      Color(0.08, 0.08, 0.12),
		"fog_energy":     0.15,
		"fog_scatter":    0.05,
		"fog_density":    0.0020,
		"fog_aerial":     0.50,
		"fog_sky_affect": 0.6,
		"sun_energy":     0.05,
		"sun_color":      Color(0.70, 0.78, 1.00),
		"sun_pitch":      -65.0,
		"sun_yaw":        40.0,
		"shadow_dist":    200.0,
		"lamp_emission":  2.0,
		"vol_fog_density":    0.0010,
		"vol_fog_anisotropy": 0.10,
		"cloud_coverage":     0.25,
		"cloud_density":      0.50,
		"cloud_color_top":    Color(0.12, 0.12, 0.18),
		"cloud_color_bottom": Color(0.05, 0.05, 0.08),
		"cloud_speed":        0.003,
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

	# Sky shader material
	var sky_top: Color = _lerp_kf("sky_top", a, b, t)
	var sky_hor: Color = _lerp_kf("sky_horizon", a, b, t)
	var gnd_bot: Color = _lerp_kf("gnd_bottom", a, b, t)
	var gnd_hor: Color = _lerp_kf("gnd_horizon", a, b, t)
	_sky_mat.set_shader_parameter("sky_top_color", Vector3(sky_top.r, sky_top.g, sky_top.b))
	_sky_mat.set_shader_parameter("sky_horizon_color", Vector3(sky_hor.r, sky_hor.g, sky_hor.b))
	_sky_mat.set_shader_parameter("ground_bottom_color", Vector3(gnd_bot.r, gnd_bot.g, gnd_bot.b))
	_sky_mat.set_shader_parameter("ground_horizon_color", Vector3(gnd_hor.r, gnd_hor.g, gnd_hor.b))
	# Cloud properties
	_sky_mat.set_shader_parameter("cloud_coverage", _lerp_kf("cloud_coverage", a, b, t))
	_sky_mat.set_shader_parameter("cloud_density", _lerp_kf("cloud_density", a, b, t))
	var cc_top: Color = _lerp_kf("cloud_color_top", a, b, t)
	var cc_bot: Color = _lerp_kf("cloud_color_bottom", a, b, t)
	_sky_mat.set_shader_parameter("cloud_color_top", Vector3(cc_top.r, cc_top.g, cc_top.b))
	_sky_mat.set_shader_parameter("cloud_color_bottom", Vector3(cc_bot.r, cc_bot.g, cc_bot.b))
	_sky_mat.set_shader_parameter("cloud_speed", _lerp_kf("cloud_speed", a, b, t))

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
			_lamp_mat.emission = Color(1.0, 0.45, 0.08) * em

	# Day/night audio modulation
	if _audio_birds and _audio_birds.stream:
		# Birds: loud dawn/day, quiet night
		var bird_energy := 1.0
		if _time_of_day < 5.0 or _time_of_day > 21.0:
			bird_energy = 0.1  # night — near silence
		elif _time_of_day < 7.0:
			bird_energy = lerpf(0.1, 1.2, (_time_of_day - 5.0) / 2.0)  # dawn chorus
		elif _time_of_day > 19.0:
			bird_energy = lerpf(1.0, 0.1, (_time_of_day - 19.0) / 2.0)
		_audio_birds.volume_db = lerpf(-25.0, -6.0, bird_energy)
	if _audio_wind and _audio_wind.stream:
		# Wind: slightly stronger at dawn/dusk
		var wind_vol := -14.0
		if _time_of_day > 18.0 or _time_of_day < 6.0:
			wind_vol = -10.0
		_audio_wind.volume_db = wind_vol


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


func _perturb_heightmap() -> void:
	## Add ±2cm micro-randomization to the heightmap for subtle terrain undulation.
	if _hm_data.is_empty():
		return
	for zi in _hm_depth:
		for xi in _hm_width:
			var idx := zi * _hm_width + xi
			var h := fmod(abs(float(xi) * 127.1 + float(zi) * 311.7), 1000.0) / 1000.0
			_hm_data[idx] = _hm_data[idx] + (h - 0.5) * 0.04  # ±2cm
	print("Terrain: micro-randomization applied (±2cm)")


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
		# Anti-tiling noise texture
		var noise_tex := _load_img_tex("res://textures/tile_noise.png")
		if noise_tex:
			_terrain_mat.set_shader_parameter("tile_noise", noise_tex)
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
			# Adaptive diagonal on slopes, checkerboard on flat — eliminates plowed-row artifacts
			var h00_v := float(_hm_data[i00])
			var h11_v := float(_hm_data[i11])
			var h10_v := float(_hm_data[i10])
			var h01_v := float(_hm_data[i01])
			var d1 := absf(h00_v - h11_v)
			var d2 := absf(h10_v - h01_v)
			var use_alt: bool
			if absf(d1 - d2) < 0.02:
				# Nearly flat — checkerboard breaks visible diagonal pattern
				use_alt = (xi + zi) % 2 == 1
			else:
				# Sloped — pick flatter diagonal
				use_alt = d2 < d1
			if not use_alt:
				indices[t]     = i00; indices[t + 1] = i10; indices[t + 2] = i11
				indices[t + 3] = i00; indices[t + 4] = i11; indices[t + 5] = i01
			else:
				indices[t]     = i00; indices[t + 1] = i10; indices[t + 2] = i01
				indices[t + 3] = i10; indices[t + 4] = i11; indices[t + 5] = i01
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

	# Heightmap texture for per-pixel fragment normals (decouples lighting from mesh topology)
	var hm_img := Image.create_from_data(W, H, false, Image.FORMAT_RF, pf.to_byte_array())
	var hm_tex := ImageTexture.create_from_image(hm_img)
	_terrain_mat.set_shader_parameter("heightmap_tex", hm_tex)

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
uniform float tile_m = 3.0;

// Meadow/wild grass blend
uniform sampler2D meadow_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float meadow_tile_m = 2.5;

// Anti-tiling noise texture (256x256 white noise)
uniform sampler2D tile_noise : filter_linear_mipmap, repeat_enable;

// Heightmap for per-pixel terrain normals (eliminates mesh topology artifacts)
uniform sampler2D heightmap_tex : filter_linear, repeat_disable;

// Splat map + path texture arrays
uniform sampler2D splat_map : filter_linear_mipmap, repeat_disable;
uniform sampler2DArray path_alb_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray path_nrm_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray path_rgh_arr : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float world_size = 5000.0;
uniform float path_tile_m = 2.5;

// Analytical GPU path textures
uniform sampler2D path_segs : filter_nearest, repeat_disable;
uniform sampler2D path_grid : filter_nearest, repeat_disable;
uniform sampler2D path_list : filter_nearest, repeat_disable;
uniform float grid_cell_size = 16.0;
uniform int grid_w = 313;
uniform int seg_tex_w = 256;
uniform int list_tex_w = 512;

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

// Inigo Quilez textureNoTile — kills tiling at all distances with 2 extra samples
vec3 textureNoTile_c(sampler2D tex, vec2 uv) {
	float k = texture(tile_noise, uv * 0.0085).x;
	vec2 duvdx = dFdx(uv); vec2 duvdy = dFdy(uv);
	float l = k * 12.0;
	float f = fract(l);
	vec2 offa = sin(vec2(3.0, 7.0) * floor(l));
	vec2 offb = sin(vec2(3.0, 7.0) * ceil(l));
	vec3 cola = textureGrad(tex, uv + offa, duvdx, duvdy).rgb;
	vec3 colb = textureGrad(tex, uv + offb, duvdx, duvdy).rgb;
	return mix(cola, colb, smoothstep(0.15, 0.85, f - 0.1 * dot(cola - colb, vec3(1.0))));
}

vec3 textureNoTile_n(sampler2D tex, vec2 uv) {
	float k = texture(tile_noise, uv * 0.0085).x;
	vec2 duvdx = dFdx(uv); vec2 duvdy = dFdy(uv);
	float l = k * 12.0;
	float f = fract(l);
	vec2 offa = sin(vec2(3.0, 7.0) * floor(l));
	vec2 offb = sin(vec2(3.0, 7.0) * ceil(l));
	vec3 na = textureGrad(tex, uv + offa, duvdx, duvdy).rgb;
	vec3 nb = textureGrad(tex, uv + offb, duvdx, duvdy).rgb;
	return mix(na, nb, smoothstep(0.15, 0.85, f));
}

float textureNoTile_r(sampler2D tex, vec2 uv) {
	float k = texture(tile_noise, uv * 0.0085).x;
	vec2 duvdx = dFdx(uv); vec2 duvdy = dFdy(uv);
	float l = k * 12.0;
	float f = fract(l);
	vec2 offa = sin(vec2(3.0, 7.0) * floor(l));
	vec2 offb = sin(vec2(3.0, 7.0) * ceil(l));
	float ra = textureGrad(tex, uv + offa, duvdx, duvdy).r;
	float rb = textureGrad(tex, uv + offb, duvdx, duvdy).r;
	return mix(ra, rb, smoothstep(0.15, 0.85, f));
}

float point_segment_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	return length(p - (a + t * ab));
}

// Returns vec4(tex_set_index, tint_r, tint_g, tint_b) for material indices 1-30
vec4 mat_lookup(int idx) {
	// tex_set: 0=Asphalt, 1=Concrete, 2=PavingStones, 3=Gravel, 4=Wood
	if (idx == 1)  return vec4(0.0, 0.32, 0.30, 0.26);   // asphalt
	if (idx == 2)  return vec4(1.0, 0.85, 0.80, 0.72);   // concrete
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
	if (idx == 24) return vec4(1.0, 0.90, 0.86, 0.80);   // hw:footway → concrete sidewalk
	if (idx == 25) return vec4(0.0, 0.30, 0.30, 0.32);   // hw:cycleway
	if (idx == 26) return vec4(1.0, 0.92, 0.88, 0.82);   // hw:pedestrian → concrete plaza
	if (idx == 27) return vec4(3.0, 0.54, 0.44, 0.30);   // hw:path
	if (idx == 28) return vec4(1.0, 0.78, 0.72, 0.62);   // hw:steps
	if (idx == 29) return vec4(3.0, 0.48, 0.40, 0.26);   // hw:track
	return vec4(3.0, 0.65, 0.60, 0.48);                   // catchall (30)
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float half_ws = world_size * 0.5;
	float cell = world_size / float(textureSize(heightmap_tex, 0).x - 1);
	vec2 grid_pos = (world_pos.xz + half_ws) / cell;
	vec2 frac_pos = fract(grid_pos);
	float envelope = sin(frac_pos.x * 3.14159) * sin(frac_pos.y * 3.14159);
	float n = vnoise(world_pos.xz * 0.8 + vec2(17.3, 41.7)) * 0.65
	        + vnoise(world_pos.xz * 2.3 + vec2(93.1, 27.5)) * 0.35;
	vec2 splat_uv_v = (world_pos.xz + half_ws) / world_size;
	float path_mask = texture(splat_map, splat_uv_v).g;
	float suppress = 1.0 - smoothstep(0.0, 0.15, path_mask);
	float disp = (n - 0.3) * envelope * 0.18 * suppress;
	VERTEX.y += max(disp, 0.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Per-pixel terrain normal from heightmap — eliminates mesh triangle artifacts
	vec2 hm_uv = (world_pos.xz + world_size * 0.5) / world_size;
	float htexel = 1.0 / float(textureSize(heightmap_tex, 0).x);
	float cell_m = world_size / float(textureSize(heightmap_tex, 0).x - 1);
	float tL = texture(heightmap_tex, hm_uv + vec2(-htexel, 0.0)).r;
	float tR = texture(heightmap_tex, hm_uv + vec2( htexel, 0.0)).r;
	float tU = texture(heightmap_tex, hm_uv + vec2(0.0, -htexel)).r;
	float tD = texture(heightmap_tex, hm_uv + vec2(0.0,  htexel)).r;
	vec3 terrain_n = normalize(vec3(tL - tR, 2.0 * cell_m, tU - tD));
	// TBN aligned to grass UV (U=+X, V=+Z) on the terrain surface
	vec3 terr_T = normalize(vec3(2.0 * cell_m, tR - tL, 0.0));
	vec3 terr_B = normalize(cross(terr_T, terrain_n));

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
		NORMAL = normalize((VIEW_MATRIX * vec4(terrain_n, 0.0)).xyz);
	} else {

	// --- Analytical GPU path distance + raster fallback ---
	vec2 splat_uv = (world_pos.xz + world_size * 0.5) / world_size;
	float feather = 1.2;  // matches SPLAT_FEATHER

	// Analytical distance-to-segment for open polyline paths
	float half_ws = world_size * 0.5;
	ivec2 cell = ivec2((world_pos.xz + half_ws) / grid_cell_size);
	cell = clamp(cell, ivec2(0), ivec2(grid_w - 1));

	vec2 gd = texelFetch(path_grid, cell, 0).rg;
	int gstart = int(gd.r);
	int gcount = min(int(gd.g), 48);

	float best_cov = 0.0;
	int best_mat = 0;

	for (int gi = 0; gi < gcount; gi++) {
		int li = gstart + gi;
		float si = texelFetch(path_list, ivec2(li % list_tex_w, li / list_tex_w), 0).r;
		int seg = int(si);

		int seg_col = seg % seg_tex_w;
		int seg_row = (seg / seg_tex_w) * 2;
		vec4 ep = texelFetch(path_segs, ivec2(seg_col, seg_row), 0);
		vec4 pr = texelFetch(path_segs, ivec2(seg_col, seg_row + 1), 0);

		float d = point_segment_dist(world_pos.xz, ep.xy, ep.zw);
		float hw = pr.x;
		float cov = 1.0 - smoothstep(hw - feather * 0.3, hw + feather, d);

		if (cov > best_cov) {
			best_cov = cov;
			best_mat = int(pr.y);
		}
	}

	// Raster fallback for closed polygons + dense areas exceeding loop cap
	float raster_cov = texture(splat_map, splat_uv).g;
	int raster_mat = int(texture(splat_map, splat_uv).r * 255.0 + 0.5);

	// Combine: analytical wins where it has coverage, raster fills polygons
	float path_weight = max(best_cov, raster_cov);
	int mat_idx = best_cov > raster_cov ? best_mat : raster_mat;

	// --- Grass shading (textureNoTile — Inigo Quilez anti-tiling) ---
	vec2 uv  = world_pos.xz / tile_m;
	vec3 grass_alb = textureNoTile_c(grass_albedo, uv);
	vec3 grass_nrm = textureNoTile_n(grass_normal, uv);
	float grass_rgh = clamp(textureNoTile_r(grass_rough, uv) * 0.15 + 0.72, 0.0, 1.0);
	// Roughness micro-variation — wet/dry patches at ~8m scale
	float rgh_var = vnoise(world_pos.xz * 0.125) * 0.16 - 0.08;
	grass_rgh = clamp(grass_rgh + rgh_var, 0.0, 1.0);
	float f = clamp(fbm(world_pos.xz * 0.004, 4) * 0.45
	              + fbm(world_pos.xz * 0.025, 3) * 0.35 + 0.30, 0.48, 1.1);
	vec3 dirt = vec3(0.22, 0.16, 0.08);
	float wear = smoothstep(0.60, 0.50, f);
	grass_alb = mix(grass_alb * f, dirt, wear * 0.6);
	// Macro color variation — warm vs cool patches at ~20m scale
	float color_var = vnoise(world_pos.xz * 0.05 + vec2(17.3, 41.7));
	vec3 warm_tint = grass_alb * vec3(1.10, 0.95, 0.75);  // golden
	vec3 cool_tint = grass_alb * vec3(0.92, 0.95, 0.80);  // olive
	grass_alb = mix(cool_tint, warm_tint, color_var);

	// Meadow/wild grass blend — large-scale FBM patches
	vec2 muv = world_pos.xz / meadow_tile_m;
	// Rotate meadow UV 60° to break alignment with grass striations
	float s60 = 0.866; float c60 = 0.5;
	vec2 muv_rot = vec2(muv.x * c60 + muv.y * s60, -muv.x * s60 + muv.y * c60);
	vec3 m_alb = texture(meadow_albedo, muv_rot).rgb;
	vec3 m_nrm_raw = texture(meadow_normal, muv_rot).rgb;
	// Un-rotate normal back to world alignment
	vec3 m_nrm = vec3(
		(m_nrm_raw.r - 0.5) * c60 + (m_nrm_raw.g - 0.5) * s60 + 0.5,
		-(m_nrm_raw.r - 0.5) * s60 + (m_nrm_raw.g - 0.5) * c60 + 0.5,
		m_nrm_raw.b);
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

	// Autumn lawn push — warm but still alive (not dead brown)
	grass_alb.r *= 1.04;
	grass_alb.g *= 0.92;
	grass_alb.b *= 0.75;
	// (Removed: vnoise at 50.0 freq aliased with mesh grid → plowed-row artifacts)

	// Canopy shadow pools — subtle dark patches under/between trees
	// Suppress near paths to avoid spotted bleed-through at edges
	float near_path_fade = 1.0 - smoothstep(0.0, 0.10, path_weight);
	float shade_noise = fbm(world_pos.xz * 0.05, 4);
	float canopy_dark = smoothstep(0.35, 0.70, shade_noise);
	grass_alb *= mix(0.72, 1.0, mix(1.0, canopy_dark, near_path_fade));

	// Flower carpet — per-pixel flower dots for bluebell carpet illusion
	// Large-scale patch mask matches CPU wildflower placement noise
	float flower_n = fbm(world_pos.xz * 0.007, 3);
	float carpet_mask = smoothstep(0.25, 0.50, flower_n);
	carpet_mask *= (1.0 - wear * 0.8);
	float canopy_shade = 1.0 - smoothstep(0.35, 0.65, fbm(world_pos.xz * 0.15, 3));
	carpet_mask *= mix(0.15, 1.0, canopy_shade);
	// Domain-warped flower dots — breaks lattice grid artifacts
	vec2 warp = vec2(vnoise(world_pos.xz * 2.3 + vec2(41.0, 73.0)),
	                 vnoise(world_pos.xz * 2.7 + vec2(91.0, 37.0))) * 0.4;
	vec2 warped = world_pos.xz + warp;
	float dot_n1 = vnoise(warped * 7.3);
	float dot_n2 = vnoise(warped * 31.7 + vec2(33.7, 17.1));
	float dot_combined = dot_n1 * 0.65 + dot_n2 * 0.35;
	// Dot size varies with secondary noise — some tight, some diffuse
	float size_var = vnoise(warped * 5.1 + vec2(7.1, 19.3));
	float dot_lo = 0.40 + size_var * 0.06;  // 0.40–0.46
	float dot_hi = dot_lo + 0.10;
	float dot_mask = smoothstep(dot_lo, dot_hi, dot_combined);
	// 3 autumn color bands: russet/brown (70%), goldenrod (20%), cream aster (10%)
	float hue_var = vnoise(warped * 4.0);
	float band_sel = vnoise(warped * 7.5 + vec2(42.0, 13.0));
	vec3 flower_col;
	if (band_sel > 0.90) {
		// Cream aster (10%)
		flower_col = mix(vec3(0.68, 0.62, 0.50), vec3(0.72, 0.66, 0.55), hue_var);
	} else if (band_sel > 0.70) {
		// Goldenrod (20%)
		flower_col = mix(vec3(0.65, 0.55, 0.12), vec3(0.72, 0.60, 0.15), hue_var);
	} else {
		// Russet/brown (dominant)
		flower_col = mix(vec3(0.40, 0.25, 0.10), vec3(0.50, 0.32, 0.14), hue_var);
	}
	// Vary density: denser near canopy shade → more saturated
	float density_boost = canopy_shade * 0.3;
	// Darken grass between flower dots for depth
	vec3 carpet_ground = mix(grass_alb * 0.70, flower_col, dot_mask + density_boost * dot_mask);
	grass_alb = mix(grass_alb, carpet_ground, carpet_mask * 0.15);

	// Dappled sunlight — simulates light filtering through tree canopy
	// Suppress near paths to avoid spotted bleed-through at edges
	float dapple = fbm(world_pos.xz * 0.15, 3) * 0.5
	             + fbm(world_pos.xz * 0.4, 2) * 0.3
	             + fbm(world_pos.xz * 1.2, 2) * 0.2;
	float sun_patch = smoothstep(0.38, 0.62, dapple);
	vec3 sun_tint = vec3(1.15, 1.02, 0.75); // warmer amber highlight
	grass_alb *= mix(vec3(1.0), sun_tint, sun_patch * 0.32 * near_path_fade);

	if (mat_idx > 0 && path_weight > 0.001) {
		// --- Path shading ---
		vec4 ml = mat_lookup(mat_idx);
		float tex_set = ml.x;
		vec3 tint = ml.yzw;
		vec2 path_uv = world_pos.xz / path_tile_m;
		vec3 p_alb = texture(path_alb_arr, vec3(path_uv, tex_set)).rgb * tint;
		vec3 p_nrm = texture(path_nrm_arr, vec3(path_uv, tex_set)).rgb;
		float p_rgh = clamp(texture(path_rgh_arr, vec3(path_uv, tex_set)).r + 0.10, 0.0, 1.0);

		// Smooth path-grass transition — tight crisp edge
		float soft_weight = smoothstep(0.05, 0.65, path_weight);

		ALBEDO          = mix(grass_alb, p_alb, soft_weight);
		vec3 _cn = mix(grass_nrm, p_nrm, soft_weight) * 2.0 - 1.0;
		_cn.xy *= mix(0.8, 0.3, soft_weight);
		vec3 _cfn = normalize(terr_T * _cn.x + terr_B * _cn.y + terrain_n * _cn.z);
		NORMAL = normalize((VIEW_MATRIX * vec4(_cfn, 0.0)).xyz);
		ROUGHNESS       = mix(grass_rgh, p_rgh, soft_weight);
		SPECULAR        = 0.0;
		METALLIC        = 0.0;
	} else {
		ALBEDO          = grass_alb;
		vec3 _gn = grass_nrm * 2.0 - 1.0;
		_gn.xy *= 0.8;
		vec3 _gfn = normalize(terr_T * _gn.x + terr_B * _gn.y + terrain_n * _gn.z);
		NORMAL = normalize((VIEW_MATRIX * vec4(_gfn, 0.0)).xyz);
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


func _apply_gpu_path_textures() -> void:
	## Wire analytical GPU path textures into the terrain shader.
	_terrain_mat.set_shader_parameter("path_segs", _park_loader.path_segs_texture)
	_terrain_mat.set_shader_parameter("path_grid", _park_loader.path_grid_texture)
	_terrain_mat.set_shader_parameter("path_list", _park_loader.path_list_texture)
	_terrain_mat.set_shader_parameter("grid_cell_size", _park_loader.gpu_path_grid_cell)
	_terrain_mat.set_shader_parameter("grid_w", _park_loader.gpu_path_grid_w)
	_terrain_mat.set_shader_parameter("seg_tex_w", _park_loader.gpu_path_seg_tex_w)
	_terrain_mat.set_shader_parameter("list_tex_w", _park_loader.gpu_path_list_tex_w)
	print("Terrain: analytical GPU path textures applied")


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
	p.position = Vector3(-600.0, _terrain_height(-600.0, 1420.0) + 2.0, 1420.0)  # Literary Walk
	p.rotation_degrees.y = 30.0
	add_child(p)
	return p


# ---------------------------------------------------------------------------
# Dynamic lamppost lighting — pool of OmniLight3D follows player
# ---------------------------------------------------------------------------
func _setup_lamp_lights() -> void:
	# Extract all lamppost world positions from MultiMesh instances
	_lamp_positions = PackedVector3Array()
	for child in _park_loader.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		if not child.name.begins_with("Lampposts_"):
			continue
		var mmi: MultiMeshInstance3D = child as MultiMeshInstance3D
		var mm: MultiMesh = mmi.multimesh
		for i in mm.instance_count:
			var xf: Transform3D = mm.get_instance_transform(i)
			# Lantern sits at ~3.5m above base
			_lamp_positions.append(xf.origin + Vector3(0, 3.5, 0))
	print("Lamp lights: %d lamppost positions extracted, pool of %d lights" % [
		_lamp_positions.size(), LAMP_LIGHT_COUNT])

	# Create light pool — SpotLight3D pointing downward (lamppost shade)
	for i in LAMP_LIGHT_COUNT:
		var light := SpotLight3D.new()
		light.light_color = Color(1.0, 0.45, 0.08)  # deep sodium vapor
		light.light_energy = 0.0  # off until positioned
		light.spot_range = 18.0
		light.spot_angle = 70.0  # ~140° cone — wide pool below
		light.spot_attenuation = 0.8
		light.shadow_enabled = false  # too expensive for 24 lights
		light.light_bake_mode = Light3D.BAKE_DISABLED
		light.rotation_degrees = Vector3(-90, 0, 0)  # point straight down
		light.name = "LampLight_%d" % i
		add_child(light)
		_lamp_lights.append(light)


func _update_lamp_lights() -> void:
	if _lamp_positions.is_empty() or _lamp_lights.is_empty() or not _player:
		return
	var player_pos := _player.global_position
	# Find closest lamps within 30m
	var dists: Array = []
	for i in _lamp_positions.size():
		var d := player_pos.distance_squared_to(_lamp_positions[i])
		if d < 900.0:  # within 30m
			dists.append([d, i])
	dists.sort_custom(func(a, b): return a[0] < b[0])

	# Get current lamp emission energy from day/night cycle
	var night_energy: float = 0.0
	if _lamp_mat:
		night_energy = _lamp_mat.emission_energy_multiplier

	for li in _lamp_lights.size():
		if li < dists.size() and night_energy > 0.1:
			var idx: int = dists[li][1]
			_lamp_lights[li].global_position = _lamp_positions[idx]
			_lamp_lights[li].light_energy = night_energy * 8.0
		else:
			_lamp_lights[li].light_energy = 0.0


# ---------------------------------------------------------------------------
# HUD: semi-transparent panel, top-left corner
# ---------------------------------------------------------------------------
func _setup_color_grade() -> void:
	## Fullscreen post-process color grading — autumn tones, lifted blacks, warm highlights
	var grade_shader := Shader.new()
	grade_shader.code = """shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

void fragment() {
	vec3 c = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;

	// Lift blacks slightly (prevents crushing, adds atmosphere)
	c = max(c, vec3(0.012, 0.010, 0.015));

	// Split-tone: warm highlights, cool shadows
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 shadow_tint = vec3(0.92, 0.95, 1.05);   // cool blue-ish shadows
	vec3 highlight_tint = vec3(1.06, 1.02, 0.92); // warm golden highlights
	float shadow_blend = 1.0 - smoothstep(0.0, 0.35, lum);
	float highlight_blend = smoothstep(0.5, 0.85, lum);
	c *= mix(vec3(1.0), shadow_tint, shadow_blend * 0.3);
	c *= mix(vec3(1.0), highlight_tint, highlight_blend * 0.25);

	// Subtle S-curve for contrast without crushing
	c = c / (c + 0.15) * 1.15;

	// Very slight vignette — darken edges
	vec2 vig_uv = SCREEN_UV * 2.0 - 1.0;
	float vig = 1.0 - dot(vig_uv, vig_uv) * 0.12;
	c *= vig;

	COLOR = vec4(c, 1.0);
}
"""
	var grade_mat := ShaderMaterial.new()
	grade_mat.shader = grade_shader
	var grade_canvas := CanvasLayer.new()
	grade_canvas.name = "ColorGrade"
	grade_canvas.layer = 100  # on top of everything
	var rect := ColorRect.new()
	rect.material = grade_mat
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade_canvas.add_child(rect)
	add_child(grade_canvas)
	print("Post-process: color grade shader applied")


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


func _setup_falling_leaves() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 200
	particles.lifetime = 8.0
	particles.preprocess = 4.0  # pre-fill so leaves are already falling at start
	particles.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))

	# Particle material
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(30, 0.5, 30)
	mat.gravity = Vector3(0, -0.4, 0)
	mat.initial_velocity_min = 0.1
	mat.initial_velocity_max = 0.3
	mat.direction = Vector3(0.3, -1, 0.2)
	mat.spread = 30.0
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.damping_min = 0.3
	mat.damping_max = 0.6
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	particles.process_material = mat

	# Draw pass — small leaf quad
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.55, 0.35, 0.12, 0.8)
	leaf_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	leaf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	leaf_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = leaf_mat
	particles.draw_pass_1 = quad

	particles.name = "FallingLeaves"
	add_child(particles)
	_falling_leaves = particles


func _setup_pigeons() -> void:
	## 3 pigeon flocks at key gathering spots as GPUParticles3D.
	var locations := [
		{"name": "Bethesda", "x": -458.0, "z": 949.0},
		{"name": "LiteraryWalk", "x": -600.0, "z": 1420.0},
		{"name": "ConservatoryWater", "x": -152.0, "z": 958.0},
	]
	for loc in locations:
		var px: float = loc["x"]
		var pz: float = loc["z"]
		var py := _terrain_height(px, pz) + 0.1
		var particles := GPUParticles3D.new()
		particles.amount = 40
		particles.lifetime = 8.0
		particles.preprocess = 4.0
		particles.visibility_aabb = AABB(Vector3(-10, -1, -10), Vector3(20, 3, 20))
		particles.position = Vector3(px, py, pz)

		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(8, 0.2, 8)
		mat.gravity = Vector3(0, 0, 0)
		mat.initial_velocity_min = 0.0
		mat.initial_velocity_max = 0.5
		mat.direction = Vector3(0.1, 0, 0.1)
		mat.spread = 180.0
		mat.damping_min = 2.0
		mat.damping_max = 4.0
		mat.scale_min = 0.8
		mat.scale_max = 1.2
		mat.color = Color(0.45, 0.42, 0.48)
		particles.process_material = mat

		var quad := QuadMesh.new()
		quad.size = Vector2(0.15, 0.12)
		var pigeon_mat := StandardMaterial3D.new()
		pigeon_mat.albedo_color = Color(0.10, 0.09, 0.11)
		pigeon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		pigeon_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		pigeon_mat.roughness = 0.90
		pigeon_mat.specular = 0.0
		quad.material = pigeon_mat
		particles.draw_pass_1 = quad

		particles.name = "Pigeons_%s" % loc["name"]
		add_child(particles)
	print("Pigeons: 3 flocks placed")


# ---------------------------------------------------------------------------
# Ambient Soundscape
# ---------------------------------------------------------------------------
var _audio_birds: AudioStreamPlayer
var _audio_wind: AudioStreamPlayer
var _audio_city: AudioStreamPlayer
var _audio_water: AudioStreamPlayer3D
var _audio_footstep_grass: AudioStreamPlayer
var _audio_footstep_stone: AudioStreamPlayer
var _footstep_timer: float = 0.0
var _footstep_interval: float = 0.65  # seconds per step at walk speed

func _setup_audio() -> void:
	## Initialize layered ambient soundscape.
	# Background layers (non-spatial)
	_audio_birds = _make_audio_player("res://sounds/birds_daytime.ogg", -8.0)
	_audio_wind = _make_audio_player("res://sounds/wind_trees.ogg", -14.0)
	_audio_city = _make_audio_player("res://sounds/city_distant.ogg", -18.0)
	# Spatial water
	_audio_water = AudioStreamPlayer3D.new()
	_audio_water.name = "AudioWater"
	if ResourceLoader.exists("res://sounds/water_lake.ogg"):
		var wstream = ResourceLoader.load("res://sounds/water_lake.ogg")
		if wstream is AudioStream:
			_audio_water.stream = wstream
			_audio_water.volume_db = -10.0
			_audio_water.max_distance = 60.0
			_audio_water.autoplay = true
			add_child(_audio_water)
	# Footsteps
	_audio_footstep_grass = _make_audio_player("res://sounds/footstep_grass.ogg", -6.0, false)
	_audio_footstep_stone = _make_audio_player("res://sounds/footstep_stone.ogg", -6.0, false)

func _make_audio_player(path: String, vol_db: float, autoplay: bool = true) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = path.get_file().get_basename()
	if ResourceLoader.exists(path):
		var stream = ResourceLoader.load(path)
		if stream is AudioStream:
			player.stream = stream
			player.volume_db = vol_db
			player.autoplay = autoplay
			add_child(player)
	return player

func _update_audio(delta: float) -> void:
	if not _player:
		return
	var ppos := _player.global_position

	# City hum louder near boundary
	if _audio_city and _audio_city.stream:
		var min_dist := 999999.0
		if _park_loader and _park_loader.boundary_polygon.size() > 2:
			for pt in _park_loader.boundary_polygon:
				var d := Vector2(ppos.x - pt.x, ppos.z - pt.y).length()
				if d < min_dist:
					min_dist = d
		var city_vol := lerpf(-12.0, -22.0, clampf(min_dist / 200.0, 0.0, 1.0))
		_audio_city.volume_db = city_vol

	# Birds louder in dense tree areas (use tree density heuristic)
	if _audio_birds and _audio_birds.stream:
		var bird_vol := -10.0  # base volume
		# Louder in The Ramble area (dense trees)
		if ppos.x > -550 and ppos.x < -250 and ppos.z > 400 and ppos.z < 800:
			bird_vol = -5.0
		_audio_birds.volume_db = bird_vol

	# Water proximity
	if _audio_water and _audio_water.stream and _park_loader:
		# Move water audio to nearest water zone
		var wgk := Vector2i(int(floor(ppos.x / 4.0)), int(floor(ppos.z / 4.0)))
		if _park_loader._water_grid.has(wgk):
			_audio_water.position = ppos + Vector3(0, -1, 0)
		else:
			# Find nearest water (crude: just place far away to mute)
			_audio_water.position = ppos + Vector3(0, -1, 80)

	# Footsteps
	if _player.velocity.length() > 0.5:
		_footstep_timer += delta
		if _footstep_timer >= _footstep_interval:
			_footstep_timer = 0.0
			# Check if on path
			var on_path := false
			if _park_loader:
				on_path = _park_loader._is_on_path(ppos.x, ppos.z)
			var player_to_use: AudioStreamPlayer
			if on_path and _audio_footstep_stone and _audio_footstep_stone.stream:
				player_to_use = _audio_footstep_stone
			elif _audio_footstep_grass and _audio_footstep_grass.stream:
				player_to_use = _audio_footstep_grass
			if player_to_use:
				# Pitch variation
				player_to_use.pitch_scale = randf_range(0.9, 1.1)
				player_to_use.play()
	else:
		_footstep_timer = 0.0
