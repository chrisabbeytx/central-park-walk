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
var _hm_data:          PackedFloat32Array = PackedFloat32Array()
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
var _user_gamma: float = 1.0          # user brightness: , = darker, . = brighter
var _time_speed: float  = 0.001      # game-hours per real-second (~400 min full cycle)
var _time_speed_idx: int = 0
var _last_applied_tod: float = -999.0  # tracks last _apply_time_of_day() value
const TIME_SPEEDS: Array = [0.001, 0.01, 0.1, 0.0]
const TIME_SPEED_NAMES: Array = ["1x", "10x", "100x", "Paused"]

var _env: Environment
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _lamp_emission: float = 0.0  # cached for SpotLight3D pool
var _terrain_mat: ShaderMaterial
var _time_label: Label
var _speed_label: Label
var _location_label: Label

# Dynamic lamppost lighting — pool of SpotLight3D nodes that follow player
var _lamp_lights: Array = []  # Array of SpotLight3D
var _lamp_positions: PackedVector3Array = PackedVector3Array()

# Cinematic letterbox overlay
var _letterbox_canvas: CanvasLayer
var _hud_canvas: CanvasLayer
var _letterbox_top: ColorRect
var _letterbox_bot: ColorRect
var _letterbox_on: bool = false
var _lamp_light_timer: float = 0.0
var _lightning_timer: float = 0.0
var _lightning_flash: float = 0.0     # 0-1 current flash intensity (decays rapidly)
var _lightning_next: float = 5.0      # seconds until next flash
const LAMP_LIGHT_COUNT := 48
const LAMP_LIGHT_RANGE := 22.0
const LAMP_LIGHT_UPDATE_INTERVAL := 0.5  # seconds between position updates


# Weather particles
var _rain_particles: GPUParticles3D
var _snow_particles: GPUParticles3D
var _leaf_particles: GPUParticles3D  # autumn falling leaves
var _blossom_particles: GPUParticles3D  # spring cherry blossom petals
var _lens_canvas: CanvasLayer   # barrel distortion overlay

# 5 keyframes defining the full day/night cycle
# Night (21→5) wraps seamlessly; 8 hours of steady darkness.
var _keyframes: Array = []
const _KF_HOURS: Array = [5.0, 6.5, 12.0, 19.0, 21.0]


var _terrain_only := false
var _weather_mode := "clear"  # clear, rain, snow, fog, lens

# Wind system — layered crossing breezes
var _wind_vec := Vector2.ZERO   # current wind XZ direction+strength
var _wind_time := 0.0           # accumulated wind time (independent of game clock)
var _wind_override := -1.0      # <0 = auto, 0-1 = manual strength multiplier

# Snow accumulation
var _snow_cover := 0.0          # 0-1, ramps up during snow weather
# Rain wetness — ground darkens + specular increases
var _rain_wetness := 0.0        # 0-1, ramps up during rain

# Seasons — 0.0=spring equinox, 1.0=summer solstice, 2.0=autumn equinox, 3.0=winter solstice
var _season_t := 1.5            # default mid-summer (matches current look)
var _season_speed := 0.0        # season-units per real-second (0 = manual only)
const SEASON_PRESETS: Dictionary = {
	"spring": 0.5, "summer": 1.5, "autumn": 2.5, "fall": 2.5, "winter": 3.5,
}


# --time name-to-hour mapping
const TIME_PRESETS: Dictionary = {
	"dawn": 5.5, "morning": 8.0, "noon": 12.0,
	"golden_hour": 17.5, "dusk": 19.5, "night": 22.0,
}
const LANDUSE_TYPE_TO_ID: Dictionary = {
	"garden": 1, "grass": 2, "pitch": 3, "playground": 4,
	"nature_reserve": 5, "dog_park": 6, "sports": 7, "pool": 8, "track": 9,
	"wood": 10, "forest": 11,
}

var _cli_pos := Vector3.ZERO  # --pos x,z  or --pos x,z,yaw  or --pos x,z,yaw,height
var _cli_pos_set := false
var _cli_height := 1.8  # default eye height above terrain
var _cli_pitch := 0.0   # --pitch degrees (negative = look down)

func _ready() -> void:
	# Check for CLI args early
	var cli_time := ""
	for i in OS.get_cmdline_user_args().size():
		var arg: String = OS.get_cmdline_user_args()[i]
		if arg == "--terrain-only":
			_terrain_only = true
		elif arg == "--time" and i + 1 < OS.get_cmdline_user_args().size():
			cli_time = OS.get_cmdline_user_args()[i + 1]
		elif arg == "--weather" and i + 1 < OS.get_cmdline_user_args().size():
			_weather_mode = OS.get_cmdline_user_args()[i + 1]
		elif arg == "--pos" and i + 1 < OS.get_cmdline_user_args().size():
			var parts := OS.get_cmdline_user_args()[i + 1].split(",")
			if parts.size() >= 2:
				_cli_pos.x = float(parts[0])
				_cli_pos.z = float(parts[1])
				if parts.size() >= 3:
					_cli_pos.y = float(parts[2])  # yaw
				if parts.size() >= 4:
					_cli_height = float(parts[3])  # height above terrain
				_cli_pos_set = true
		elif arg == "--pitch" and i + 1 < OS.get_cmdline_user_args().size():
			_cli_pitch = float(OS.get_cmdline_user_args()[i + 1])
		elif arg == "--season" and i + 1 < OS.get_cmdline_user_args().size():
			var s_val: String = OS.get_cmdline_user_args()[i + 1]
			if SEASON_PRESETS.has(s_val):
				_season_t = SEASON_PRESETS[s_val]
				print("Season: %s (%.1f)" % [s_val, _season_t])
			elif s_val.is_valid_float():
				_season_t = clampf(float(s_val), 0.0, 4.0)
				print("Season: %.1f" % _season_t)
			else:
				print("Unknown --season '%s'. Options: spring summer autumn fall winter (or 0.0-4.0)" % s_val)
	# Auto-screenshot only in headless capture mode (--quit-after)
	for earg in OS.get_cmdline_args():
		if earg.begins_with("--quit-after"):
			_auto_screenshot = true
			break
	if cli_time != "":
		if TIME_PRESETS.has(cli_time):
			_time_of_day = TIME_PRESETS[cli_time]
			_time_speed = 0.0  # freeze clock
			_time_speed_idx = 3  # "Paused"
			print("Time locked: %s (%.1fh)" % [cli_time, _time_of_day])
		elif cli_time.is_valid_float():
			_time_of_day = clampf(float(cli_time), 0.0, 23.99)
			_time_speed = 0.0
			_time_speed_idx = 3
			print("Time locked: %.1fh" % _time_of_day)
		else:
			print("Unknown --time '%s'. Options: dawn morning noon golden_hour dusk night (or 0-24)" % cli_time)
	if _weather_mode != "clear":
		print("Weather: %s" % _weather_mode)
	var _mt := Time.get_ticks_msec()
	_build_keyframes()
	_load_heightmap()
	print("main: heightmap: %d ms" % (Time.get_ticks_msec() - _mt)); _mt = Time.get_ticks_msec()
	_setup_environment()
	# Register global shader parameters BEFORE park_loader creates materials
	RenderingServer.global_shader_parameter_add("wind_vec", RenderingServer.GLOBAL_VAR_TYPE_VEC2, Vector2.ZERO)
	RenderingServer.global_shader_parameter_add("snow_cover", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add("rain_wetness", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add("sky_reflect_color", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.32, 0.38, 0.45))
	RenderingServer.global_shader_parameter_add("season_t", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, _season_t)
	RenderingServer.global_shader_parameter_add("lightning_flash", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	print("main: environment: %d ms" % (Time.get_ticks_msec() - _mt)); _mt = Time.get_ticks_msec()
	if not _terrain_only:
		_setup_park()
		print("main: park_loader: %d ms" % (Time.get_ticks_msec() - _mt)); _mt = Time.get_ticks_msec()
	_setup_ground()
	print("main: ground mesh: %d ms" % (Time.get_ticks_msec() - _mt)); _mt = Time.get_ticks_msec()
	if not _terrain_only:
		_apply_structure_textures()
		if _park_loader and _park_loader.boundary_polygon.size() > 2:
			_apply_boundary_mask(_park_loader.boundary_polygon)
		print("main: boundary mask: %d ms" % (Time.get_ticks_msec() - _mt)); _mt = Time.get_ticks_msec()
		if _park_loader and not _park_loader.landuse_zones.is_empty():
			_apply_landuse_map(_park_loader.landuse_zones, _park_loader.water_bodies)
		print("main: landuse map: %d ms" % (Time.get_ticks_msec() - _mt)); _mt = Time.get_ticks_msec()
		_apply_structure_mask()
		print("main: structure mask: %d ms" % (Time.get_ticks_msec() - _mt)); _mt = Time.get_ticks_msec()
		# Surface atlas GPU texture no longer needed — vertex colors in terrain mesh
		# provide smooth surface blending. CPU-side atlas still used by builders.
		# _apply_surface_atlas()
		print("main: vertex colors replace surface atlas GPU texture")
	_player = _setup_player()
	if _park_loader and _park_loader.boundary_polygon.size() > 2:
		_player.boundary_polygon = _park_loader.boundary_polygon
	_setup_hud()
	#_setup_color_grade()  # POST-FX BASELINE TEST — disabled
	_setup_letterbox()
	if not _terrain_only:
		_setup_lamp_lights()
	print("main: total _ready: %d ms" % (Time.get_ticks_msec() - _mt + (Time.get_ticks_msec() - _mt)))
	_apply_time_of_day()
	_setup_weather()
	# Check for --tour / --tour-showcase / --readme-shots CLI arg
	for arg in OS.get_cmdline_user_args():
		if arg in ["--tour", "--tour-showcase", "--readme-shots"]:
			_tour_mode = true
			_build_tour_shots()
			_tour_state = 0  # WAIT_LOAD
			_tour_timer = 0.0
			_tour_idx = 0
			DirAccess.make_dir_recursive_absolute(_tour_save_dir)
			if arg == "--tour-showcase":
				_tour_settle_time = 60.0  # 60s per location for interactive exploration
				_player.tour_freeze = false  # let user fly around between transports
				print("Tour showcase (interactive): %d shots, %ds per location → %s/" % [
					_tour_shots.size(), int(_tour_settle_time), _tour_save_dir])
			else:
				_tour_settle_time = 3.0
				_player.tour_freeze = true  # freeze for automated captures
				print("Tour mode: %d shots queued → %s/" % [_tour_shots.size(), _tour_save_dir])
			break
var _screenshot_timer := 0.0
var _screenshot_done  := false
var _labels_hidden_for_screenshot := false
var _screenshot_counter := 0  # incrementing counter for F12 screenshots
var _auto_screenshot := false  # only auto-capture when --quit-after is used

# ---------------------------------------------------------------------------
# Tour mode — automated screenshot capture across 10 locations × 3 angles × 3 times
# Activated via --tour CLI arg.  Non-tour mode is unchanged.
# ---------------------------------------------------------------------------
var _tour_mode := false
var _tour_state := 0  # 0=WAIT_LOAD, 1=SETTLE, 2=CAPTURE, 3=DONE
var _tour_timer := 0.0
var _tour_idx := 0  # index into _tour_shots array
var _tour_shots: Array = []  # populated in _build_tour_shots()
var _tour_save_dir := "/tmp/tour"  # overridden by --readme-shots
var _tour_settle_time := 3.0  # seconds to wait at each location (60 for showcase)

const TOUR_VIEWPOINTS: Array = [
	{"name": "bethesda_fountain", "x": -480.0, "z": 1020.0, "yaw": 180.0},
	{"name": "literary_walk", "x": -600.0, "z": 1420.0, "yaw": 30.0},
	{"name": "great_lawn", "x": -200.0, "z": 0.0, "yaw": 0.0},
	{"name": "conservatory_water", "x": -152.0, "z": 958.0, "yaw": 270.0},
	{"name": "alice_wonderland", "x": -96.0, "z": 869.0, "yaw": 315.0},
	{"name": "balto_south", "x": -473.0, "z": 1430.0, "yaw": 60.0},
	{"name": "the_lake", "x": -560.0, "z": 780.0, "yaw": 60.0},
	{"name": "cherry_hill", "x": -630.0, "z": 880.0, "yaw": 90.0},
	{"name": "cleopatras_needle", "x": 40.0, "z": 360.0, "yaw": 250.0},
	{"name": "ramble", "x": -400.0, "z": 600.0, "yaw": 225.0},
	{"name": "cpw_skyline", "x": -600.0, "z": 1420.0, "yaw": 90.0},
	{"name": "fifth_ave_skyline", "x": 100.0, "z": 200.0, "yaw": 270.0},
	{"name": "north_woods", "x": 600.0, "z": -1315.0, "yaw": 180.0},
	{"name": "reservoir_south", "x": -200.0, "z": -300.0, "yaw": 0.0},
	{"name": "bow_bridge", "x": -540.0, "z": 740.0, "yaw": 310.0},
	{"name": "soccer_fields", "x": 390.0, "z": -1070.0, "yaw": 30.0},
	{"name": "sheep_meadow", "x": -700.0, "z": 1600.0, "yaw": 270.0},
]

const TOUR_ANGLES: Array = [
	{"suffix": "_0", "yaw_offset": 0.0, "pitch": 0.0},    # forward
	{"suffix": "_1", "yaw_offset": -90.0, "pitch": 0.0},   # left 90°
	{"suffix": "_2", "yaw_offset": 0.0, "pitch": -25.0},   # down
	{"suffix": "_aerial30", "yaw_offset": 0.0, "pitch": -55.0, "height": 30.0},   # 30m aerial
	{"suffix": "_aerial80", "yaw_offset": 0.0, "pitch": -75.0, "height": 80.0},   # 80m aerial overview
]

const TOUR_TIMES: Array = [7.0, 12.0, 17.0, 22.0]

func _build_tour_shots() -> void:
	_tour_shots.clear()
	for arg in OS.get_cmdline_user_args():
		if arg == "--readme-shots":
			_build_readme_shots()
			return
	# Check for --tour-showcase: focused set with weather/season variety
	for arg in OS.get_cmdline_user_args():
		if arg == "--tour-showcase":
			_build_showcase_shots()
			return
	for vp in TOUR_VIEWPOINTS:
		for ti in range(TOUR_TIMES.size()):
			for ai in range(TOUR_ANGLES.size()):
				var shot_data: Dictionary = {
					"name": vp["name"],
					"x": float(vp["x"]),
					"z": float(vp["z"]),
					"yaw": float(vp["yaw"]) + float(TOUR_ANGLES[ai]["yaw_offset"]),
					"pitch": float(TOUR_ANGLES[ai]["pitch"]),
					"hour": TOUR_TIMES[ti],
					"filename": "%s_%dh%s" % [vp["name"], int(TOUR_TIMES[ti]), TOUR_ANGLES[ai]["suffix"]],
				}
				if TOUR_ANGLES[ai].has("height"):
					shot_data["height"] = float(TOUR_ANGLES[ai]["height"])
				_tour_shots.append(shot_data)


# Showcase tour — curated shots demonstrating time, weather, and season variety
const SHOWCASE_SHOTS: Array = [
	# Summer golden hour — flagship shot
	{"name": "literary_walk_summer_golden", "x": -600.0, "z": 1420.0, "yaw": 30.0, "pitch": 0.0, "hour": 17.5, "season": 1.5, "weather": "clear"},
	# Autumn morning at Bethesda
	{"name": "bethesda_autumn_morning", "x": -480.0, "z": 1020.0, "yaw": 180.0, "pitch": 0.0, "hour": 8.0, "season": 2.5, "weather": "clear"},
	# Winter snow at the Lake — Bow Bridge area
	{"name": "bow_bridge_winter_snow", "x": -540.0, "z": 740.0, "yaw": 310.0, "pitch": 0.0, "hour": 12.0, "season": 3.5, "weather": "snow"},
	# Spring dawn at the Ramble
	{"name": "ramble_spring_dawn", "x": -400.0, "z": 600.0, "yaw": 225.0, "pitch": 0.0, "hour": 6.0, "season": 0.5, "weather": "clear"},
	# Rain at Conservatory Water
	{"name": "conservatory_rain_afternoon", "x": -152.0, "z": 958.0, "yaw": 270.0, "pitch": 0.0, "hour": 15.0, "season": 2.0, "weather": "rain"},
	# Night at Literary Walk — sodium vapor lamps
	{"name": "literary_walk_night", "x": -600.0, "z": 1420.0, "yaw": 30.0, "pitch": 0.0, "hour": 22.0, "season": 1.5, "weather": "clear"},
	# Winter fog at Great Lawn
	{"name": "great_lawn_winter_fog", "x": -200.0, "z": 0.0, "yaw": 0.0, "pitch": 0.0, "hour": 7.0, "season": 3.2, "weather": "fog"},
	# Autumn golden hour at Cherry Hill
	{"name": "cherry_hill_autumn_golden", "x": -630.0, "z": 880.0, "yaw": 90.0, "pitch": 0.0, "hour": 17.5, "season": 2.6, "weather": "clear"},
	# Summer noon skyline from Fifth Ave side
	{"name": "fifth_ave_summer_noon", "x": 100.0, "z": 200.0, "yaw": 270.0, "pitch": 0.0, "hour": 12.0, "season": 1.5, "weather": "clear"},
	# Snow at North Woods
	{"name": "north_woods_snow_morning", "x": 600.0, "z": -1315.0, "yaw": 180.0, "pitch": 0.0, "hour": 9.0, "season": 3.5, "weather": "snow"},
	# Spring rain at the Mall
	{"name": "the_mall_spring_rain", "x": -550.0, "z": 1300.0, "yaw": 180.0, "pitch": 0.0, "hour": 14.0, "season": 0.6, "weather": "rain"},
	# Autumn dusk at CPW skyline
	{"name": "cpw_skyline_autumn_dusk", "x": -600.0, "z": 1420.0, "yaw": 90.0, "pitch": 0.0, "hour": 19.0, "season": 2.5, "weather": "clear"},
	# Summer dawn at Reservoir
	{"name": "reservoir_summer_dawn", "x": -200.0, "z": -300.0, "yaw": 0.0, "pitch": -5.0, "hour": 5.5, "season": 1.5, "weather": "clear"},
	# Summer golden hour at Sheep Meadow — mowing stripes visible on green grass
	{"name": "sheep_meadow_summer_golden", "x": -700.0, "z": 1600.0, "yaw": 270.0, "pitch": -3.0, "hour": 18.0, "season": 1.5, "weather": "clear"},
	# Autumn at the Lake
	{"name": "the_lake_autumn_afternoon", "x": -560.0, "z": 780.0, "yaw": 60.0, "pitch": 0.0, "hour": 15.0, "season": 2.7, "weather": "clear"},
	# Spring morning at soccer fields
	{"name": "soccer_fields_spring_morning", "x": 390.0, "z": -1070.0, "yaw": 30.0, "pitch": 0.0, "hour": 9.0, "season": 0.5, "weather": "clear"},
	# Aerial views — looking down from various heights
	# Bethesda Terrace + fountain from 40m — summer noon
	{"name": "bethesda_aerial_40m", "x": -480.0, "z": 1020.0, "yaw": 180.0, "pitch": -70.0, "hour": 12.0, "season": 1.5, "weather": "clear", "height": 40.0},
	# The Lake + Bow Bridge from 80m — autumn afternoon
	{"name": "lake_aerial_80m_autumn", "x": -540.0, "z": 740.0, "yaw": 0.0, "pitch": -80.0, "hour": 15.0, "season": 2.5, "weather": "clear", "height": 80.0},
	# Great Lawn from 100m — summer golden hour
	{"name": "great_lawn_aerial_100m", "x": -100.0, "z": 100.0, "yaw": 0.0, "pitch": -85.0, "hour": 17.5, "season": 1.5, "weather": "clear", "height": 100.0},
	# Conservatory Water from 30m — rainy day
	{"name": "conservatory_aerial_30m_rain", "x": -152.0, "z": 958.0, "yaw": 90.0, "pitch": -60.0, "hour": 14.0, "season": 2.0, "weather": "rain", "height": 30.0},
	# North Woods from 60m — winter snow
	{"name": "north_woods_aerial_60m_snow", "x": 600.0, "z": -1315.0, "yaw": 180.0, "pitch": -75.0, "hour": 10.0, "season": 3.5, "weather": "snow", "height": 60.0},
	# Reservoir from 120m — dawn overview
	{"name": "reservoir_aerial_120m_dawn", "x": -200.0, "z": -400.0, "yaw": 0.0, "pitch": -80.0, "hour": 6.0, "season": 1.5, "weather": "clear", "height": 120.0},
]


func _build_showcase_shots() -> void:
	for shot in SHOWCASE_SHOTS:
		_tour_shots.append(shot.duplicate())
		_tour_shots.back()["filename"] = shot["name"]


# README shots — exactly the 4 images referenced in README.md
# Saves to screenshots/ (not /tmp/tour/) so they land in the repo directly.
const README_SHOTS: Array = [
	# Autumn dusk on Literary Walk looking west toward CPW skyline
	{"name": "cpw_skyline_autumn_dusk", "x": -600.0, "z": 1420.0, "yaw": 90.0, "pitch": 0.0, "hour": 19.0, "season": 2.5, "weather": "clear"},
	# Rain at Conservatory Water — atmosphere + weather showcase
	{"name": "conservatory_rain_afternoon", "x": -152.0, "z": 958.0, "yaw": 270.0, "pitch": 0.0, "hour": 15.0, "season": 2.0, "weather": "rain"},
	# Winter snow at Sheep Meadow
	{"name": "sheep_meadow_winter_noon", "x": -700.0, "z": 1600.0, "yaw": 270.0, "pitch": 0.0, "hour": 12.0, "season": 3.5, "weather": "snow"},
	# North Woods winter morning — snow + woodland
	{"name": "north_woods_snow_morning", "x": 600.0, "z": -1315.0, "yaw": 180.0, "pitch": 0.0, "hour": 9.0, "season": 3.5, "weather": "snow"},
]

func _build_readme_shots() -> void:
	_tour_save_dir = "screenshots"
	for shot in README_SHOTS:
		_tour_shots.append(shot.duplicate())
		_tour_shots.back()["filename"] = shot["name"]


# ---------------------------------------------------------------------------
# Heightmap helpers
# ---------------------------------------------------------------------------
func _load_heightmap() -> void:
	# Try binary format first, then fall back to JSON
	if FileAccess.file_exists("res://heightmap.bin"):
		var fa := FileAccess.open("res://heightmap.bin", FileAccess.READ)
		_hm_width         = fa.get_32()
		_hm_depth         = fa.get_32()
		_hm_world_size    = fa.get_float()
		_hm_origin_height = fa.get_float()
		var byte_count := _hm_width * _hm_depth * 4
		var buf := fa.get_buffer(byte_count)
		fa.close()
		_hm_data = buf.to_float32_array()
		print("Heightmap loaded (bin): %d×%d  origin_y=%.1f m" % [
			_hm_width, _hm_depth, _hm_origin_height])
		return
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
	var raw_data: Array = hm["data"]
	_hm_data.resize(raw_data.size())
	for i in range(raw_data.size()):
		_hm_data[i] = float(raw_data[i])
	print("Heightmap loaded (json): %d×%d  origin_y=%.1f m" % [_hm_width, _hm_depth, _hm_origin_height])


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
		if _hud_canvas and _hud_canvas.visible:
			_hud_canvas.visible = false  # hide HUD for clean screenshots
			_set_labels_visible(false)
		_tour_timer += delta
		match _tour_state:
			0:  # WAIT_LOAD — let scene fully build
				if _tour_timer >= 8.0:
					_tour_state = 1
					_tour_timer = 0.0
					_tour_teleport(_tour_idx)
					print("Tour: load complete, starting captures")
			1:  # SETTLE — let SSAO/SSR/fog converge + explore time
				if _tour_timer >= _tour_settle_time:
					_tour_state = 2
					_tour_timer = 0.0
			2:  # CAPTURE
				var img := get_viewport().get_texture().get_image()
				if img:
					var shot: Dictionary = _tour_shots[_tour_idx]
					var path := "%s/%s.png" % [_tour_save_dir, shot["filename"]]
					img.save_png(path)
					print("Tour [%d/%d]: %s" % [_tour_idx + 1, _tour_shots.size(), shot["filename"]])
				_tour_idx += 1
				if _tour_idx >= _tour_shots.size():
					_tour_write_manifest()
					_tour_state = 3
					print("Tour complete: %d shots saved to %s/" % [_tour_shots.size(), _tour_save_dir])
					get_tree().quit()
				else:
					_tour_state = 1
					_tour_timer = 0.0
					_tour_teleport(_tour_idx)
			3:  # DONE
				pass
		_apply_time_of_day()
		_update_hud()
		return

	# Auto-screenshot for headless capture (only with --quit-after)
	if not _screenshot_done and _auto_screenshot:
		_screenshot_timer += delta
		if _screenshot_timer <= delta and _player:
			_player.set_physics_process(false)
			_player.velocity = Vector3.ZERO
		if _screenshot_timer >= 6.0 and _hud_canvas and _hud_canvas.visible:
			_hud_canvas.visible = false  # hide HUD before capture
		if _screenshot_timer >= 6.0 and not _labels_hidden_for_screenshot:
			_labels_hidden_for_screenshot = true
			_set_labels_visible(false)   # hide Label3D (building names, etc.)
		if _screenshot_timer >= 8.0:
			_screenshot_done = true
			var img := get_viewport().get_texture().get_image()
			if img:
				img.save_png("/tmp/godot_screenshot.png")
				print("Screenshot saved to /tmp/godot_screenshot.png")
			if _player:
				_player.set_physics_process(true)
			if _hud_canvas:
				_hud_canvas.visible = true  # restore HUD after capture
				_set_labels_visible(true)
	# Update lamp lights every 0.5s
	_lamp_light_timer += delta
	if _lamp_light_timer >= LAMP_LIGHT_UPDATE_INTERVAL:
		_lamp_light_timer = 0.0
		_update_lamp_lights()

	# Wind
	_update_wind(delta)

	# Snow accumulation — ramps up during snow, melts otherwise
	var prev_snow := _snow_cover
	if _weather_mode == "snow":
		_snow_cover = minf(_snow_cover + delta * 0.02, 1.0)  # ~50s to full cover
	else:
		_snow_cover = maxf(_snow_cover - delta * 0.05, 0.0)  # ~20s to melt
	if _snow_cover != prev_snow:
		RenderingServer.global_shader_parameter_set("snow_cover", _snow_cover)

	# Rain wetness — ground darkens, gets glossy
	var prev_wet := _rain_wetness
	if _weather_mode == "rain" or _weather_mode == "thunderstorm":
		_rain_wetness = minf(_rain_wetness + delta * 0.04, 1.0)  # ~25s to full wet
	else:
		_rain_wetness = maxf(_rain_wetness - delta * 0.015, 0.0)  # ~67s to dry
	if _rain_wetness != prev_wet:
		RenderingServer.global_shader_parameter_set("rain_wetness", _rain_wetness)

	# Season advance
	if _season_speed > 0.0:
		_season_t = fmod(_season_t + _season_speed * delta, 4.0)
		RenderingServer.global_shader_parameter_set("season_t", _season_t)

	# Particles follow player — wind deflects rain/snow
	if _rain_particles and _player:
		_rain_particles.global_position = _player.global_position + Vector3(0, 14, 0)
		var rpm: ParticleProcessMaterial = _rain_particles.process_material
		rpm.gravity = Vector3(_wind_vec.x * 5.0, -1.5, _wind_vec.y * 5.0)
	if _snow_particles and _player:
		_snow_particles.global_position = _player.global_position + Vector3(0, 15, 0)
		var spm: ParticleProcessMaterial = _snow_particles.process_material
		spm.gravity = Vector3(_wind_vec.x * 3.0, -1.5, _wind_vec.y * 3.0)

	# Autumn falling leaves — activate during fall season (2.0-3.2)
	var autumn_strength := smoothstep(1.8, 2.3, _season_t) * (1.0 - smoothstep(2.8, 3.2, _season_t))
	if autumn_strength > 0.05 and not _leaf_particles:
		_setup_leaf_particles()
	elif autumn_strength < 0.02 and _leaf_particles:
		_leaf_particles.queue_free()
		_leaf_particles = null
	if _leaf_particles and _player:
		_leaf_particles.global_position = _player.global_position + Vector3(0, 12, 0)
		var lpm: ParticleProcessMaterial = _leaf_particles.process_material
		# Wind pushes leaves strongly — they drift on the breeze
		lpm.gravity = Vector3(_wind_vec.x * 4.0, -0.3, _wind_vec.y * 4.0)
		# Vary amount by autumn intensity (sparse early/late, dense at peak)
		_leaf_particles.amount = int(lerpf(200.0, 2000.0, autumn_strength))

	# Spring cherry blossom petals — activate during bloom season (0.2-1.0)
	# Peak bloom around season_t 0.5 (mid-spring), tapering off into summer
	var bloom_strength := smoothstep(0.1, 0.4, _season_t) * (1.0 - smoothstep(0.7, 1.1, _season_t))
	# Also catch late-winter to spring wrap (season_t near 4.0→0)
	if _season_t > 3.8:
		bloom_strength = maxf(bloom_strength, smoothstep(3.8, 3.95, _season_t) * 0.5)
	if bloom_strength > 0.05 and not _blossom_particles:
		_setup_blossom_particles()
	elif bloom_strength < 0.02 and _blossom_particles:
		_blossom_particles.queue_free()
		_blossom_particles = null
	if _blossom_particles and _player:
		_blossom_particles.global_position = _player.global_position + Vector3(0, 10, 0)
		var bpm: ParticleProcessMaterial = _blossom_particles.process_material
		# Petals drift gently on the breeze — lighter than autumn leaves
		bpm.gravity = Vector3(_wind_vec.x * 3.0, -0.15, _wind_vec.y * 3.0)
		_blossom_particles.amount = int(lerpf(100.0, 1200.0, bloom_strength))

	# Lightning flashes during thunderstorm
	if _weather_mode == "thunderstorm":
		_lightning_flash = maxf(_lightning_flash - delta * 4.0, 0.0)  # rapid decay (~0.25s)
		_lightning_timer += delta
		if _lightning_timer >= _lightning_next:
			_lightning_timer = 0.0
			_lightning_flash = randf_range(0.6, 1.0)
			# Double flash 20% of the time
			if randf() < 0.2:
				_lightning_flash = 1.0
			_lightning_next = randf_range(3.0, 12.0)
	elif _lightning_flash > 0.01:
		_lightning_flash = maxf(_lightning_flash - delta * 4.0, 0.0)
	RenderingServer.global_shader_parameter_set("lightning_flash", _lightning_flash)

	# Advance clock
	_time_of_day += _time_speed * delta
	if _time_of_day >= 24.0:
		_time_of_day -= 24.0
	elif _time_of_day < 0.0:
		_time_of_day += 24.0
	# Only update sky/env/lighting when time actually changes (~0.01h threshold)
	if absf(_time_of_day - _last_applied_tod) > 0.01 or _last_applied_tod < 0.0:
		_apply_time_of_day()

	# ===== POST-FX BASELINE TEST — glow height fade disabled =====
	# if _env and _player:
	# 	var cam_y: float = _player.global_position.y
	# 	var terr_y: float = _terrain_height(_player.global_position.x, _player.global_position.z)
	# 	var hag: float = maxf(cam_y - terr_y, 0.0)
	# 	var gfade: float = 1.0 - clampf((hag - 20.0) / 60.0, 0.0, 1.0)
	# 	_env.glow_enabled = gfade > 0.01
	# 	if _env.glow_enabled:
	# 		_env.glow_intensity *= gfade
	# 		_env.glow_bloom    *= gfade
	# 		_env.glow_strength *= gfade
	# ===== END POST-FX BASELINE TEST =====

	# Letterbox bar sizing (adapts to viewport resize)
	if _letterbox_on and _letterbox_top:
		var vp := get_viewport().get_visible_rect().size
		var bar_h := maxf((vp.y - vp.x / 2.35) * 0.5, 0.0)
		_letterbox_top.offset_bottom = bar_h
		_letterbox_bot.offset_top = -bar_h

	_update_hud()


func _update_hud() -> void:
	if not _player or not _coord_label:
		return
	var pos := _player.position
	_coord_label.text = "X: %7.1f      Z: %7.1f" % [pos.x, pos.z]
	var bearing := fmod(fmod(-_player.rotation_degrees.y, 360.0) + 360.0, 360.0)
	_heading_label.text = "Heading: %5.1f°  %s" % [bearing, _compass_label(bearing)]
	var lat :=  REF_LAT + (-pos.z / METRES_PER_DEG_LAT)
	var lon :=  REF_LON + ( pos.x / METRES_PER_DEG_LON)
	_latlon_label.text  = "%.6f° N    %.6f° W" % [lat, absf(lon)]
	if _time_label:
		var h12: int = int(_time_of_day) % 12
		if h12 == 0:
			h12 = 12
		var mins: int = int(fmod(_time_of_day, 1.0) * 60.0)
		var ampm: String = "AM" if _time_of_day < 12.0 else "PM"
		_time_label.text = "%d:%02d %s  [%s]  %s" % [h12, mins, ampm, TIME_SPEED_NAMES[_time_speed_idx], _season_name(_season_t)]
	if _speed_label and _player:
		_speed_label.text = "%s (%.1f m/s)" % [_player.SPEED_NAMES[_player._speed_idx], _player.walk_speed]
	if _location_label:
		var area := _nearest_area(pos.x, pos.z)
		_location_label.text = area if area else ""
		_location_label.visible = not area.is_empty()


func _set_labels_visible(vis: bool) -> void:
	for n: Node in find_children("*", "Label3D", true, false):
		n.visible = vis


func _tour_teleport(idx: int) -> void:
	var shot: Dictionary = _tour_shots[idx]
	var x: float = shot["x"]
	var z: float = shot["z"]
	var yaw: float = shot["yaw"]
	var pitch: float = shot["pitch"]
	var hour: float = shot["hour"]
	var cam_height: float = shot.get("height", 1.3)
	_player.global_position = Vector3(x, _terrain_height(x, z) + cam_height, z)
	_player.velocity = Vector3.ZERO
	_player.rotation_degrees.y = yaw
	var head: Node3D = _player.get_node("Head")
	if head:
		head.rotation_degrees.x = pitch
	_time_of_day = hour
	_time_speed = 0.0
	# Apply weather if specified
	if shot.has("weather"):
		_set_weather(shot["weather"])
	# Apply season if specified
	if shot.has("season"):
		_season_t = float(shot["season"])
		RenderingServer.global_shader_parameter_set("season_t", _season_t)
	_last_applied_tod = -999.0  # force full lighting update
	_apply_time_of_day()


func _set_weather(mode: String) -> void:
	## Set weather mode, tearing down previous particles and pre-accumulating cover.
	if _rain_particles:
		_rain_particles.queue_free()
		_rain_particles = null
	if _snow_particles:
		_snow_particles.queue_free()
		_snow_particles = null
	_weather_mode = mode
	_setup_weather()
	# Pre-accumulate snow/rain so screenshots don't need to wait
	if mode == "snow":
		_snow_cover = 1.0
		_rain_wetness = 0.0
	elif mode == "rain" or mode == "thunderstorm":
		_rain_wetness = 1.0
		_snow_cover = 0.0
	else:
		_snow_cover = 0.0
		_rain_wetness = 0.0
	RenderingServer.global_shader_parameter_set("snow_cover", _snow_cover)
	RenderingServer.global_shader_parameter_set("rain_wetness", _rain_wetness)


func _tour_write_manifest() -> void:
	var manifest: Dictionary = {"shots": [], "viewpoints": TOUR_VIEWPOINTS.size(), "angles": TOUR_ANGLES.size(), "times": TOUR_TIMES.size()}
	for shot in _tour_shots:
		manifest["shots"].append({"filename": shot["filename"] + ".png", "name": shot["name"], "hour": shot["hour"], "x": shot["x"], "z": shot["z"]})
	var fa := FileAccess.open("%s/manifest.json" % _tour_save_dir, FileAccess.WRITE)
	fa.store_string(JSON.stringify(manifest, "\t"))
	fa.close()
	print("Tour: manifest.json written")


func _compass_label(deg: float) -> String:
	var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return labels[int(fmod(deg + 22.5, 360.0) / 45.0) % 8]


# Central Park named areas — [x_min, x_max, z_min, z_max, name]
const PARK_AREAS: Array = [
	# ── Landmarks and major areas ──
	[-700, -400, 1300, 1500, "Literary Walk"],
	[-550, -380, 1050, 1300, "The Mall"],
	[-530, -390, 900, 1050, "Bethesda Terrace"],
	[-650, -420, 700, 900, "The Lake"],
	[-550, -200, 400, 700, "The Ramble"],
	[-700, -550, 800, 1000, "Cherry Hill"],
	[-200, 200, -200, 400, "Great Lawn"],
	[-900, -600, 1500, 2100, "Sheep Meadow"],
	[-300, 200, -800, -400, "Reservoir"],
	[-200, 100, 800, 1050, "Conservatory Water"],
	[200, 800, -1800, -1200, "North Meadow"],
	[400, 900, -1600, -1000, "North Woods"],
	[-100, 500, -200, 200, "Turtle Pond"],
	[600, 1200, -2200, -1700, "Harlem Meer"],
	[-100, 200, 600, 900, "Belvedere Castle"],
	[-350, 0, 200, 500, "Delacorte Theater"],
	[0, 300, 300, 500, "Cleopatra's Needle"],
	[-700, -500, 1450, 1550, "Naumburg Bandshell"],
	[-250, 0, -600, -300, "Reservoir Running Track"],
	[100, 500, -900, -600, "Tennis Center"],
	[-200, 200, -1200, -800, "Conservatory Garden"],
	[-600, -350, 600, 750, "Bow Bridge"],
	[-900, -650, 1100, 1350, "Strawberry Fields"],
	[-700, -400, 1900, 2100, "The Pond"],
	[-800, -500, 2050, 2200, "Wollman Rink"],
	[700, 1100, -2100, -1800, "Lasker Pool"],
	[-300, 0, 500, 700, "Shakespeare Garden"],
	[300, 700, -1100, -700, "The Pool"],
	[400, 800, -1400, -1100, "The Loch"],
	[-200, 200, -400, -200, "The Obelisk"],
	[-1100, -800, 1400, 1800, "Tavern on the Green"],
	# ── Additional areas from Conservancy maps ──
	[-500, -200, -1950, -1700, "The Ravine"],
	[-300, 100, -350, -100, "Summit Rock"],
	[-700, -500, 450, 650, "Ladies Pavilion"],
	[100, 400, 150, 400, "Cedar Hill"],
	[-650, -350, 1100, 1250, "The Dene"],
	[-400, -100, 1600, 1800, "Heckscher Ballfields"],
	[200, 600, -1050, -750, "East Meadow"],
	[-100, 200, -1800, -1500, "Great Hill"],
	[300, 600, -1600, -1350, "Conservatory Garden East"],
	[-800, -500, 1050, 1250, "Mineral Springs"],
	[-500, -200, 750, 950, "Wagner Cove"],
	[-300, 0, 50, 300, "Arthur Ross Pinetum"],
	# ── Playgrounds (from Conservancy Playground Map) ──
	[-700, -550, -1850, -1750, "Yoseoff Playground"],
	[-700, -500, -1100, -1000, "Tarr Family Playground"],
	[-750, -600, -800, -700, "Rudin Family Playground"],
	[-750, -600, -575, -475, "Wild West Playground"],
	[-750, -600, -425, -325, "Safari Playground"],
	[-750, -600, 25, 125, "West 85th St Playground"],
	[-700, -550, 100, 200, "Toll Family Playground"],
	[-750, -600, 325, 425, "Diana Ross Playground"],
	[-750, -600, 1300, 1400, "Tarr-Coyne Tots Playground"],
	[-750, -600, 1375, 1475, "Adventure Playground"],
	[-500, -300, 1675, 1800, "Heckscher Playground"],
	[250, 450, -1850, -1750, "East 110th St Playground"],
	[250, 450, -1700, -1600, "Bernard Family Playground"],
	[250, 450, -1100, -1000, "Bendheim Playground"],
	[250, 450, -800, -700, "Kempner Playground"],
	[200, 400, 25, 125, "Ancient Playground"],
	[200, 400, 475, 575, "Smadbeck Playground"],
	[200, 400, 625, 725, "Levin Playground"],
	[200, 400, 1000, 1100, "East 72nd St Playground"],
	[200, 400, 1375, 1475, "Billy Johnson Playground"],
	# ── Facilities ──
	[300, 500, -1850, -1750, "Dana Discovery Center"],
	[-600, -400, 1375, 1475, "Dairy Visitor Center"],
	[-550, -400, 1450, 1550, "Chess & Checkers House"],
	[100, 350, 1525, 1625, "Central Park Zoo"],
	[-400, -200, 1150, 1250, "SummerStage"],
	[-300, -100, 550, 700, "Swedish Cottage"],
]

func _nearest_area(x: float, z: float) -> String:
	for area in PARK_AREAS:
		if x >= float(area[0]) and x <= float(area[1]) and z >= float(area[2]) and z <= float(area[3]):
			return area[4]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_T:
		_time_speed_idx = (_time_speed_idx + 1) % TIME_SPEEDS.size()
		_time_speed = TIME_SPEEDS[_time_speed_idx]
		print("Time speed: ", TIME_SPEED_NAMES[_time_speed_idx])
	elif event.keycode == KEY_BRACKETLEFT:
		_time_of_day = fmod(_time_of_day - 1.0 + 24.0, 24.0)
		_apply_time_of_day()
		print("Time: %.1f h" % _time_of_day)
	elif event.keycode == KEY_BRACKETRIGHT:
		_time_of_day = fmod(_time_of_day + 1.0, 24.0)
		_apply_time_of_day()
		print("Time: %.1f h" % _time_of_day)
	elif event.keycode == KEY_L:
		_letterbox_on = not _letterbox_on
		_letterbox_canvas.visible = _letterbox_on
		print("Letterbox: ", "ON" if _letterbox_on else "OFF")
	elif event.keycode == KEY_P:
		_cycle_weather()
	elif event.keycode == KEY_G:
		if _park_loader and _park_loader._gap_builder:
			var gb = _park_loader._gap_builder
			var vis: bool = not (gb._root and gb._root.visible)
			gb.set_visible(vis)
			print("Data gaps: %s" % ("ON" if vis else "OFF"))
	elif event.keycode == KEY_H:
		if _hud_canvas:
			_hud_canvas.visible = not _hud_canvas.visible
	elif event.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif event.keycode == KEY_COMMA:
		_user_gamma = clampf(_user_gamma - 0.05, 0.5, 2.0)
		print("Gamma: %.2f" % _user_gamma)
	elif event.keycode == KEY_PERIOD:
		_user_gamma = clampf(_user_gamma + 0.05, 0.5, 2.0)
		print("Gamma: %.2f" % _user_gamma)
	# +/- reserved for movement speed (player.gd)
	elif event.keycode == KEY_9:
		if _wind_override < 0.0:
			_wind_override = 1.0
		_wind_override = clampf(_wind_override - 0.1, 0.0, 3.0)
		print("Wind: %.0f%%" % (_wind_override * 100.0))
	elif event.keycode == KEY_0:
		if _wind_override < 0.0:
			_wind_override = 1.0
		_wind_override = clampf(_wind_override + 0.1, 0.0, 3.0)
		print("Wind: %.0f%%" % (_wind_override * 100.0))
	elif event.keycode == KEY_N:
		if event.shift_pressed:
			# Shift+N: cycle season backward
			_season_t = fmod(float(int(_season_t - 1.0 + 4.0)), 4.0)
		else:
			# N: cycle season forward
			_season_t = fmod(float(int(_season_t + 1.0)), 4.0)
		RenderingServer.global_shader_parameter_set("season_t", _season_t)
		var season_name := _season_name(_season_t)
		print("Season: %s (%.1f)" % [season_name, _season_t])
	elif event.keycode == KEY_F12:
		_take_screenshot()


func _season_name(t: float) -> String:
	if t < 1.0: return "Spring"
	if t < 2.0: return "Summer"
	if t < 3.0: return "Autumn"
	return "Winter"


func _take_screenshot() -> void:
	var dir_path := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var img := get_viewport().get_texture().get_image()
	if not img:
		print("Screenshot: failed to capture")
		return
	var path := "%s/cpw_%03d.png" % [dir_path, _screenshot_counter]
	img.save_png(path)
	_screenshot_counter += 1
	print("Screenshot saved: %s" % path)


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
	var sky_shader: Shader = load("res://shaders/cloud_sky.gdshader")
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
	# ===== POST-FX BASELINE TEST — all post-processing OFF =====
	# Re-enable one at a time to find the artifact source.
	_env.tonemap_mode          = Environment.TONE_MAPPER_FILMIC  # TEST 1: filmic tonemap
	_env.tonemap_white         = 6.0
	_env.glow_enabled          = false   # OFF
	_env.ssao_enabled          = false   # OFF
	_env.ssil_enabled          = false   # OFF
	_env.ssr_enabled           = false   # OFF
	_env.adjustment_enabled    = false   # OFF
	_env.fog_enabled           = false   # OFF
	_env.volumetric_fog_enabled = false  # OFF
	_env.sdfgi_enabled         = false   # OFF
	# ===== END POST-FX BASELINE TEST =====

	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.light_angular_distance = 1.5  # soft penumbra — velvety shadows
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
	# NYC light pollution: horizon never fully dark, ambient glow from city
	_keyframes.append({
		"hour": 5.0,
		"sky_top":        Color(0.03, 0.04, 0.12),
		"sky_horizon":    Color(0.14, 0.11, 0.20),  # light pollution glow
		"gnd_bottom":     Color(0.02, 0.02, 0.035),
		"gnd_horizon":    Color(0.10, 0.07, 0.12),
		"ambient_color":  Color(0.16, 0.14, 0.22),
		"ambient_energy": 0.40,   # NYC ambient from light pollution
		"exposure":       0.85,
		"white":          6.0,
		"glow_intensity": 0.6,
		"glow_bloom":     0.08,
		"glow_strength":  0.7,
		"glow_threshold": 0.55,
		"glow_cap":       5.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.2,
		"ssao_power":     1.8,
		"ssil_intensity": 0.5,
		"saturation":     0.75,
		"contrast":       1.06,
		"brightness":     0.88,
		"fog_color":      Color(0.12, 0.10, 0.14),
		"fog_energy":     0.20,
		"fog_scatter":    0.05,
		"fog_density":    0.0005,
		"fog_aerial":     0.20,
		"fog_sky_affect": 0.6,
		"sun_energy":     0.05,
		"sun_color":      Color(0.65, 0.72, 0.95),
		"sun_pitch":      -10.0,
		"sun_yaw":        -100.0,
		"shadow_dist":    180.0,
		"lamp_emission":  5.0,  # pre-dawn: lamps still at full brightness
		"vol_fog_density":    0.0004,
		"vol_fog_anisotropy": 0.45,
		"cloud_coverage":     0.50,
		"cloud_density":      0.60,
		"cloud_color_top":    Color(0.42, 0.40, 0.44),
		"cloud_color_bottom": Color(0.16, 0.14, 0.18),
		"cloud_speed":        0.003,
	})

	# ---- 6.5  Sunrise / Golden hour ----
	# Morning light from the east bathes the Fifth Avenue buildings in gold,
	# long shadows stretch westward across the lawns, mist rises from the ponds.
	_keyframes.append({
		"hour": 6.5,
		"sky_top":        Color(0.28, 0.42, 0.68),
		"sky_horizon":    Color(0.75, 0.52, 0.35),    # richer sunrise glow
		"gnd_bottom":     Color(0.10, 0.08, 0.06),
		"gnd_horizon":    Color(0.46, 0.34, 0.22),
		"ambient_color":  Color(0.48, 0.38, 0.26),
		"ambient_energy": 0.65,
		"exposure":       0.72,
		"white":          5.5,
		"glow_intensity": 0.2,    # restrained morning bloom — warmth is directional, not global
		"glow_bloom":     0.03,
		"glow_strength":  0.4,
		"glow_threshold": 0.85,
		"glow_cap":       6.0,
		"ssao_radius":    1.5,
		"ssao_intensity": 2.5,
		"ssao_power":     1.8,
		"ssil_intensity": 0.7,
		"saturation":     1.05,
		"contrast":       1.08,
		"brightness":     0.92,
		"fog_color":      Color(0.50, 0.42, 0.34),   # subtle warm haze, not amber wash
		"fog_energy":     0.45,
		"fog_scatter":    0.18,
		"fog_density":    0.0005,   # golden hour haze — buildings fade into warm atmosphere
		"fog_aerial":     0.22,     # atmospheric depth
		"fog_sky_affect": 0.30,
		"sun_energy":     0.90,
		"sun_color":      Color(1.0, 0.75, 0.50),    # warm but not deep amber
		"sun_pitch":      -12.0,
		"sun_yaw":        -95.0,
		"shadow_dist":    250.0,
		"lamp_emission":  0.0,
		"vol_fog_density":    0.0003,  # subtle sunrise haze
		"vol_fog_anisotropy": 0.80,    # moderate forward scatter
		"cloud_coverage":     0.50,
		"cloud_density":      0.55,
		"cloud_color_top":    Color(0.95, 0.85, 0.72),   # gold-lit cloud tops
		"cloud_color_bottom": Color(0.52, 0.42, 0.32),
		"cloud_speed":        0.004,
	})

	# ---- 12.0  Noon (clear, bright daylight) ----
	_keyframes.append({
		"hour": 12.0,
		"sky_top":        Color(0.22, 0.42, 0.75),
		"sky_horizon":    Color(0.55, 0.60, 0.68),
		"gnd_bottom":     Color(0.12, 0.12, 0.10),
		"gnd_horizon":    Color(0.38, 0.36, 0.32),
		"ambient_color":  Color(0.50, 0.46, 0.38),
		"ambient_energy": 0.85,
		"exposure":       0.68,
		"white":          6.0,
		"glow_intensity": 0.0,
		"glow_bloom":     0.0,
		"glow_strength":  0.0,
		"glow_threshold": 2.0,
		"glow_cap":       12.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.0,
		"ssao_power":     1.6,
		"ssil_intensity": 1.0,
		"saturation":     1.05,
		"contrast":       1.06,
		"brightness":     0.90,
		"fog_color":      Color(0.62, 0.60, 0.56),  # warmer haze — NYC summer atmosphere
		"fog_energy":     0.5,
		"fog_scatter":    0.06,
		"fog_density":    0.0004,   # NYC has noticeable daytime haze — buildings fade at distance
		"fog_aerial":     0.25,     # atmospheric scattering: blue haze on distant objects
		"fog_sky_affect": 0.30,
		"sun_energy":     0.95,
		"sun_color":      Color(0.95, 0.92, 0.85),
		"sun_pitch":      -55.0,
		"sun_yaw":        -20.0,
		"shadow_dist":    300.0,
		"lamp_emission":  0.0,
		"vol_fog_density":    0.0001,  # very subtle volumetric — just enough for depth
		"vol_fog_anisotropy": 0.45,
		"cloud_coverage":     0.60,
		"cloud_density":      0.55,
		"cloud_color_top":    Color(0.95, 0.95, 0.93),
		"cloud_color_bottom": Color(0.68, 0.68, 0.66),
		"cloud_speed":        0.005,
	})

	# ---- 19.0  Sunset / Golden hour ----
	# The most photogenic time in Central Park — warm light raking across meadows,
	# long shadows, golden tree canopy, NYC skyline silhouettes catching fire.
	_keyframes.append({
		"hour": 19.0,
		"sky_top":        Color(0.28, 0.22, 0.42),   # deeper purple above
		"sky_horizon":    Color(0.82, 0.50, 0.28),    # richer orange at horizon
		"gnd_bottom":     Color(0.10, 0.07, 0.04),
		"gnd_horizon":    Color(0.48, 0.35, 0.20),    # warm ground reflection
		"ambient_color":  Color(0.48, 0.42, 0.32),    # warm ambient but not saturated amber
		"ambient_energy": 0.80,
		"exposure":       0.72,
		"white":          5.5,
		"glow_intensity": 0.15,  # minimal bloom — golden hour warmth is directional, not global
		"glow_bloom":     0.03,
		"glow_strength":  0.4,
		"glow_threshold": 0.90,  # only sun-facing surfaces bloom
		"glow_cap":       6.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 1.8,
		"ssao_power":     1.9,
		"ssil_intensity": 0.8,
		"saturation":     1.05,   # natural — saturation boost makes everything amber
		"contrast":       1.08,   # long shadows
		"brightness":     0.93,
		"fog_color":      Color(0.55, 0.45, 0.35),    # neutral warm haze, not amber blanket
		"fog_energy":     0.45,
		"fog_scatter":    0.18,
		"fog_density":    0.0005,   # golden hour atmospheric haze
		"fog_aerial":     0.22,     # atmospheric depth
		"fog_sky_affect": 0.30,
		"sun_energy":     0.95,    # strong low sun but not overblown
		"sun_color":      Color(1.0, 0.72, 0.45),     # warm golden, not deep amber
		"sun_pitch":      -12.0,   # lower sun angle for longer shadows
		"sun_yaw":        95.0,
		"shadow_dist":    250.0,
		"lamp_emission":  0.0,  # lamps off until after sunset (ramp 19h→21h)
		"vol_fog_density":    0.0003,  # subtle haze — clarity over drama
		"vol_fog_anisotropy": 0.80,    # moderate forward scatter
		"cloud_coverage":     0.60,
		"cloud_density":      0.55,
		"cloud_color_top":    Color(0.85, 0.55, 0.38),  # golden-lit cloud tops
		"cloud_color_bottom": Color(0.55, 0.30, 0.18),  # warm undersides
		"cloud_speed":        0.004,
	})

	# ---- 21.0  Night ----
	# NYC light pollution: never truly dark. Central Park is surrounded by 6,557 lit buildings.
	# Real nighttime in CP: you can see paths, grass, trees clearly. The city bathes everything in warm glow.
	_keyframes.append({
		"hour": 21.0,
		"sky_top":        Color(0.03, 0.02, 0.02),  # dark warm brown — NYC Bortle 9
		"sky_horizon":    Color(0.14, 0.10, 0.06),  # warm amber light pollution glow
		"gnd_bottom":     Color(0.02, 0.015, 0.01),
		"gnd_horizon":    Color(0.08, 0.06, 0.04),  # warm ground glow from city
		"ambient_color":  Color(0.85, 0.65, 0.40),  # warm amber city glow — NYC sodium vapor spill
		"ambient_energy": 0.10,   # darker ambient — lets lamppost pools stand out more
		"exposure":       0.92,   # darker overall — night IS dark even in NYC
		"white":          6.0,
		"glow_intensity": 0.45,
		"glow_bloom":     0.06,
		"glow_strength":  0.6,
		"glow_threshold": 0.65,
		"glow_cap":       5.0,
		"ssao_radius":    2.0,
		"ssao_intensity": 2.2,
		"ssao_power":     1.8,
		"ssil_intensity": 0.6,
		"saturation":     0.50,   # colors are very muted at night — olive/brown, not green
		"contrast":       1.04,
		"brightness":     1.0,
		"fog_color":      Color(0.12, 0.09, 0.07),  # warm amber night haze — city light scatter
		"fog_energy":     0.20,
		"fog_scatter":    0.06,
		"fog_density":    0.0003,
		"fog_aerial":     0.15,
		"fog_sky_affect": 0.4,
		"sun_energy":     0.05,
		"sun_color":      Color(0.70, 0.78, 1.00),
		"sun_pitch":      -65.0,
		"sun_yaw":        40.0,
		"shadow_dist":    200.0,
		"lamp_emission":  5.0,  # stronger glow — Kent Bloomer luminaires are quite bright
		"vol_fog_density":    0.0005,  # slight night haze catches lamplight scatter
		"vol_fog_anisotropy": 0.35,
		"cloud_coverage":     0.45,
		"cloud_density":      0.55,
		"cloud_color_top":    Color(0.14, 0.12, 0.18),
		"cloud_color_bottom": Color(0.06, 0.05, 0.08),
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

	# ===== POST-FX BASELINE TEST — skip all post-processing updates =====
	# Glow, SSAO, SSIL, adjustment, fog, volumetric fog all disabled.
	# Only ambient + tonemapping exposure still update (needed for basic lighting).
	# _env.glow_intensity         = _lerp_kf("glow_intensity", a, b, t)
	# _env.glow_bloom             = _lerp_kf("glow_bloom", a, b, t)
	# _env.glow_strength          = _lerp_kf("glow_strength", a, b, t)
	# _env.glow_hdr_threshold     = _lerp_kf("glow_threshold", a, b, t)
	# _env.glow_hdr_luminance_cap = _lerp_kf("glow_cap", a, b, t)
	# _env.ssao_radius    = _lerp_kf("ssao_radius", a, b, t)
	# _env.ssao_intensity = _lerp_kf("ssao_intensity", a, b, t)
	# _env.ssao_power     = _lerp_kf("ssao_power", a, b, t)
	# _env.ssil_intensity = _lerp_kf("ssil_intensity", a, b, t)
	# _env.adjustment_saturation = _lerp_kf("saturation", a, b, t)
	# _env.adjustment_contrast   = _lerp_kf("contrast", a, b, t)
	# _env.adjustment_brightness = _lerp_kf("brightness", a, b, t) * _user_gamma
	# if _lightning_flash > 0.01:
	# 	_env.adjustment_brightness *= (1.0 + _lightning_flash * 3.0)
	# _env.fog_light_color       = _lerp_kf("fog_color", a, b, t)
	# _env.fog_light_energy      = _lerp_kf("fog_energy", a, b, t)
	# _env.fog_sun_scatter       = _lerp_kf("fog_scatter", a, b, t)
	# _env.fog_density           = _lerp_kf("fog_density", a, b, t)
	# _env.fog_aerial_perspective = _lerp_kf("fog_aerial", a, b, t)
	# _env.fog_sky_affect        = _lerp_kf("fog_sky_affect", a, b, t)
	# _env.volumetric_fog_density    = _lerp_kf("vol_fog_density", a, b, t)
	# _env.volumetric_fog_anisotropy = _lerp_kf("vol_fog_anisotropy", a, b, t)
	# ===== END POST-FX BASELINE TEST =====

	# Weather overrides — use absolute values for fog/clouds so the effect
	# is clearly visible regardless of time-of-day keyframe base values.
	if _weather_mode == "fog":
		_env.fog_density = 0.035  # heavy fade: ~50% at 20m, ~90% at 65m
		_env.fog_light_energy = 0.6
		_env.fog_light_color = Color(0.78, 0.80, 0.82)
		_env.fog_sun_scatter = 0.05
		if _env.volumetric_fog_enabled:
			_env.volumetric_fog_density = 0.015
		_env.adjustment_saturation = 0.45
		_env.adjustment_brightness = 0.90
		_sky_mat.set_shader_parameter("cloud_coverage", 0.99)
		_sky_mat.set_shader_parameter("cloud_density", 0.95)
	elif _weather_mode == "rain":
		_env.fog_density = 0.012
		_env.fog_light_energy *= 0.7
		if _env.volumetric_fog_enabled:
			_env.volumetric_fog_density = 0.006
		_env.adjustment_saturation *= 0.7
		_sky_mat.set_shader_parameter("cloud_coverage", 0.95)
		_sky_mat.set_shader_parameter("cloud_density", 0.85)
	elif _weather_mode == "thunderstorm":
		_env.fog_density = 0.018
		_env.fog_light_energy *= 0.5
		if _env.volumetric_fog_enabled:
			_env.volumetric_fog_density = 0.010
		_env.adjustment_saturation *= 0.55
		_env.adjustment_brightness *= 0.85
		_sky_mat.set_shader_parameter("cloud_coverage", 0.98)
		_sky_mat.set_shader_parameter("cloud_density", 0.92)
	elif _weather_mode == "snow":
		_env.fog_density = 0.008
		_env.adjustment_saturation *= 0.75
		_sky_mat.set_shader_parameter("cloud_coverage", 0.92)
		_sky_mat.set_shader_parameter("cloud_density", 0.80)

	# Wind reduces fog density slightly (wind disperses mist)
	var wind_str: float = _wind_vec.length()
	if wind_str > 0.1 and _env.fog_density > 0.001:
		_env.fog_density *= lerpf(1.0, 0.82, clampf(wind_str * 0.3, 0.0, 1.0))

	# Thunderstorm glow boost — lightning briefly illuminates clouds/scene
	if _lightning_flash > 0.01:
		_env.glow_bloom = maxf(_env.glow_bloom, _lightning_flash * 0.25)
		_env.glow_intensity *= (1.0 + _lightning_flash * 0.8)

	# Sky reflection color for water surfaces — tracks time-of-day sky tone
	var sky_r: Color = _lerp_kf("fog_color", a, b, t)
	var sun_c: Color = _lerp_kf("sun_color", a, b, t)
	# Blend fog color (ambient sky) with sun color for water reflection
	var reflect := sky_r.lerp(sun_c, 0.3)
	# Boost luminance slightly for specular reflection
	reflect = reflect * 1.2
	RenderingServer.global_shader_parameter_set("sky_reflect_color",
		Vector3(reflect.r, reflect.g, reflect.b))

	# Morning dew — specular on grass surfaces at dawn (4:30-8:30 AM)
	var dew := 0.0
	if _time_of_day >= 4.5 and _time_of_day <= 8.5:
		if _time_of_day <= 6.0:
			dew = smoothstep(4.5, 6.0, _time_of_day)
		else:
			dew = 1.0 - smoothstep(6.0, 8.5, _time_of_day)
	if _weather_mode != "clear":
		dew = 0.0  # no visible dew in rain/snow
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("dew_amount", dew)

	# Dawn mist — natural morning fog that lifts with sunrise (5-7:30 AM)
	# Common phenomenon in Central Park near water bodies and in wooded areas
	if _weather_mode == "clear":
		var dawn_mist := 0.0
		if _time_of_day >= 4.5 and _time_of_day <= 7.5:
			# Peak at 5:30, fading by 7:30
			if _time_of_day <= 5.5:
				dawn_mist = smoothstep(4.5, 5.5, _time_of_day)
			else:
				dawn_mist = 1.0 - smoothstep(5.5, 7.5, _time_of_day)
			_env.fog_density += dawn_mist * 0.008  # subtle ground fog
			if _env.volumetric_fog_enabled:
				_env.volumetric_fog_density += dawn_mist * 0.003
			_env.adjustment_saturation *= (1.0 - dawn_mist * 0.15)  # slightly desaturated mist

	# Seasonal fog and atmosphere modulation
	# Autumn: warmer golden haze, slightly denser
	# Winter: cooler blue-gray haze, denser, more desaturated
	# Spring: fresh, clear, slightly green-tinted
	var s_autumn := smoothstep(1.5, 2.5, _season_t) * (1.0 - smoothstep(2.5, 3.5, _season_t))
	var s_winter := smoothstep(2.5, 3.5, _season_t)
	if s_autumn > 0.01:
		# Warm golden haze from humidity + pollen/leaf particles
		var fog_c: Color = _env.fog_light_color
		_env.fog_light_color = fog_c.lerp(Color(0.82, 0.72, 0.55), s_autumn * 0.25)
		_env.fog_density *= (1.0 + s_autumn * 0.15)
	if s_winter > 0.01:
		# Cold, blue-gray winter atmosphere — shorter days, lower sun angle
		var fog_c: Color = _env.fog_light_color
		_env.fog_light_color = fog_c.lerp(Color(0.72, 0.75, 0.82), s_winter * 0.3)
		_env.fog_density *= (1.0 + s_winter * 0.2)
		_env.adjustment_saturation *= (1.0 - s_winter * 0.2)
		# Winter overcast: increase cloud coverage
		var cc: float = _sky_mat.get_shader_parameter("cloud_coverage")
		_sky_mat.set_shader_parameter("cloud_coverage", minf(cc + s_winter * 0.15, 0.95))

	# Sun / moon directional light
	_sun.light_energy    = _lerp_kf("sun_energy", a, b, t)
	_sun.light_color     = _lerp_kf("sun_color", a, b, t)
	var pitch: float     = _lerp_kf("sun_pitch", a, b, t)
	var yaw: float       = _lerp_kf("sun_yaw", a, b, t)
	_sun.rotation_degrees = Vector3(pitch, yaw, 0.0)
	_sun.directional_shadow_max_distance = _lerp_kf("shadow_dist", a, b, t)

	# Lamp emission level — drives SpotLight3D pool energy (globe mesh removed)
	_lamp_emission = _lerp_kf("lamp_emission", a, b, t)

	# Building window emission — smooth night_factor curve
	# 0.0 during day (7h-18h), ramps to 1.0 at night (21h-5h)
	var nf: float = 0.0
	if _time_of_day >= 18.0 and _time_of_day < 21.0:
		nf = (_time_of_day - 18.0) / 3.0  # sunset ramp
	elif _time_of_day >= 21.0 or _time_of_day < 5.0:
		nf = 1.0  # full night
	elif _time_of_day >= 5.0 and _time_of_day < 7.0:
		nf = 1.0 - (_time_of_day - 5.0) / 2.0  # dawn ramp
	if _park_loader:
		for fm in _park_loader.facade_materials:
			if fm is ShaderMaterial:
				fm.set_shader_parameter("night_factor", nf)

	_last_applied_tod = _time_of_day


# ---------------------------------------------------------------------------
# Terrain ground – height-mapped mesh + HeightMapShape3D collision
# Falls back to a flat plane when heightmap.json is absent.
# ---------------------------------------------------------------------------
func _setup_ground() -> void:
	# grass_albedo is dense green turf; lawn_grass is sparse brown/dead — use green
	var tex_alb := _load_img_tex("res://textures/grass_albedo.jpg")
	if tex_alb == null:
		tex_alb = _load_img_tex("res://textures/lawn_grass_Color.jpg")
	var tex_nrm := _load_img_tex("res://textures/grass_normal.jpg")
	if tex_nrm == null:
		tex_nrm = _load_img_tex("res://textures/lawn_grass_NormalGL.jpg")
	var tex_rgh := _load_img_tex("res://textures/grass_rough.jpg")
	if tex_rgh == null:
		tex_rgh = _load_img_tex("res://textures/lawn_grass_Roughness.jpg")
	var shader: Shader = load("res://shaders/terrain.gdshader")
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = shader
	if tex_alb != null:
		_terrain_mat.set_shader_parameter("grass_albedo", tex_alb)
		_terrain_mat.set_shader_parameter("grass_normal", tex_nrm)
		_terrain_mat.set_shader_parameter("grass_rough",  tex_rgh)
		_terrain_mat.set_shader_parameter("tile_m",       6.0)
		# Anti-tiling noise texture
		var noise_tex := _load_img_tex("res://textures/tile_noise.png")
		if noise_tex:
			_terrain_mat.set_shader_parameter("tile_noise", noise_tex)
		# Meadow/wild grass blend
		var m_alb := _load_img_tex("res://textures/leaf_litter_Color.jpg")
		if m_alb == null:
			m_alb = _load_img_tex("res://textures/forrest_ground_01_Color.jpg")
		var m_nrm := _load_img_tex("res://textures/leaf_litter_NormalGL.jpg")
		if m_nrm == null:
			m_nrm = _load_img_tex("res://textures/forrest_ground_01_NormalGL.jpg")
		var m_rgh := _load_img_tex("res://textures/leaf_litter_Roughness.jpg")
		if m_rgh == null:
			m_rgh = _load_img_tex("res://textures/forrest_ground_01_Roughness.jpg")
		if m_alb:
			_terrain_mat.set_shader_parameter("meadow_albedo", m_alb)
			_terrain_mat.set_shader_parameter("meadow_normal", m_nrm)
			_terrain_mat.set_shader_parameter("meadow_rough",  m_rgh)
			_terrain_mat.set_shader_parameter("meadow_tile_m", 4.0)
		# Rock texture for steep slopes
		var r_alb := _load_img_tex("res://textures/schist_rock_Color.jpg")
		if r_alb == null:
			r_alb = _load_img_tex("res://textures/rock_wall_diff.jpg")
		var r_nrm := _load_img_tex("res://textures/schist_rock_NormalGL.jpg")
		if r_nrm == null:
			r_nrm = _load_img_tex("res://textures/rock_wall_nrm.jpg")
		var r_rgh := _load_img_tex("res://textures/schist_rock_Roughness.jpg")
		if r_rgh == null:
			r_rgh = _load_img_tex("res://textures/rock_wall_rgh.jpg")
		if r_alb:
			_terrain_mat.set_shader_parameter("rock_albedo", r_alb)
			_terrain_mat.set_shader_parameter("rock_normal", r_nrm)
			_terrain_mat.set_shader_parameter("rock_rough",  r_rgh)
			_terrain_mat.set_shader_parameter("rock_tile_m", 3.0)
		# Dirt texture for playgrounds, dog parks, tracks
		var d_alb := _load_img_tex("res://textures/park_dirt_Color.jpg")
		var d_nrm := _load_img_tex("res://textures/park_dirt_NormalGL.jpg")
		var d_rgh := _load_img_tex("res://textures/park_dirt_Roughness.jpg")
		if d_alb:
			_terrain_mat.set_shader_parameter("dirt_albedo", d_alb)
			_terrain_mat.set_shader_parameter("dirt_normal", d_nrm)
			_terrain_mat.set_shader_parameter("dirt_rough",  d_rgh)
			_terrain_mat.set_shader_parameter("dirt_tile_m", 2.0)
		# Shore/mud texture for water edges
		var s_alb := _load_img_tex("res://textures/shore_mud_Color.jpg")
		var s_nrm := _load_img_tex("res://textures/shore_mud_NormalGL.jpg")
		var s_rgh := _load_img_tex("res://textures/shore_mud_Roughness.jpg")
		if s_alb:
			_terrain_mat.set_shader_parameter("shore_albedo", s_alb)
			_terrain_mat.set_shader_parameter("shore_normal", s_nrm)
			_terrain_mat.set_shader_parameter("shore_rough",  s_rgh)
			_terrain_mat.set_shader_parameter("shore_tile_m", 3.0)
		print("Ground: textured grass shader + meadow blend + rock slopes + dirt zones + shore")

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

	# ---- Load pre-baked terrain mesh (8K, built by convert_to_godot.py) ----
	# At 8192×8192 (0.61m cells), LiDAR detail is preserved: bridge decks,
	# parapets, steps, retaining walls, rock outcrops — all in the geometry.
	# Shader heightmap texture provides per-pixel normals for sub-cell shading.
	# V2 format: vertex colors encode smoothed surface blend weights — GPU
	# interpolation creates smooth transitions, eliminating the splat map grid.
	var mesh_path := "res://terrain_mesh.bin"
	if not FileAccess.file_exists(mesh_path):
		print("ERROR: terrain_mesh.bin not found — run convert_to_godot.py")
		return
	var mf := FileAccess.open(mesh_path, FileAccess.READ)
	var n_verts := mf.get_32()
	var n_indices := mf.get_32()
	var world_sz := mf.get_float()
	# Check for v2 format (has vertex colors)
	var mesh_version := mf.get_32()  # v2 = vertex colors present
	# Read positions: n_verts × 3 floats (x, y, z interleaved)
	var pos_buf := mf.get_buffer(n_verts * 12)
	var pos_f32 := pos_buf.to_float32_array()
	var verts := PackedVector3Array(); verts.resize(n_verts)
	var uvs := PackedVector2Array(); uvs.resize(n_verts)
	var half := world_sz * 0.5
	var inv_ws := 1.0 / world_sz
	for i in n_verts:
		var px := pos_f32[i * 3]
		var pz := pos_f32[i * 3 + 2]
		verts[i] = Vector3(px, pos_f32[i * 3 + 1], pz)
		uvs[i] = Vector2((px + half) * inv_ws, (pz + half) * inv_ws)
	# Read vertex colors if v2 format: n_verts × 4 bytes (RGBA8)
	# R=paved path blend, G=unpaved blend, B=rock blend, A=building blend
	var vert_colors := PackedColorArray()
	if mesh_version >= 2:
		var col_buf := mf.get_buffer(n_verts * 4)
		vert_colors.resize(n_verts)
		for i in n_verts:
			vert_colors[i] = Color(
				col_buf[i * 4] / 255.0,
				col_buf[i * 4 + 1] / 255.0,
				col_buf[i * 4 + 2] / 255.0,
				col_buf[i * 4 + 3] / 255.0)
		print("Terrain: vertex colors loaded (v2 — smooth surface blending)")
	# Read indices: n_indices × uint32
	var idx_buf := mf.get_buffer(n_indices * 4)
	var indices := idx_buf.to_int32_array()
	mf.close()
	print("Terrain mesh loaded: %d verts, %d tris (%.1f MB file)" % [
		n_verts, n_indices / 3, FileAccess.open(mesh_path, FileAccess.READ).get_length() / 1e6])

	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]  = verts
	arrays[Mesh.ARRAY_TEX_UV]  = uvs
	if not vert_colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = vert_colors
	arrays[Mesh.ARRAY_INDEX]   = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_mat)

	var mi       := MeshInstance3D.new()
	mi.mesh       = mesh
	mi.name       = "Terrain"
	add_child(mi)

	# ---- HeightMapShape3D collision (4096 = ~1.2m cells, matching atlas res) ----
	var COL_RES := 4096
	var col_cell := _hm_world_size / float(COL_RES - 1)
	var col_step_x := float(_hm_width - 1) / float(COL_RES - 1)
	var col_step_z := float(_hm_depth - 1) / float(COL_RES - 1)
	var hm_shape          := HeightMapShape3D.new()
	hm_shape.map_width     = COL_RES
	hm_shape.map_depth     = COL_RES
	var pf                := PackedFloat32Array(); pf.resize(COL_RES * COL_RES)
	for czi in COL_RES:
		var src_row := mini(int(czi * col_step_z + 0.5), _hm_depth - 1) * _hm_width
		for cxi in COL_RES:
			pf[czi * COL_RES + cxi] = _hm_data[src_row + mini(int(cxi * col_step_x + 0.5), _hm_width - 1)]
	hm_shape.map_data      = pf

	# Heightmap texture for per-pixel fragment normals — full-res data
	var hm_img := Image.create(_hm_width, _hm_depth, false, Image.FORMAT_RF)
	hm_img.set_data(_hm_width, _hm_depth, false, Image.FORMAT_RF, _hm_data.to_byte_array())
	var hm_tex := ImageTexture.create_from_image(hm_img)
	_terrain_mat.set_shader_parameter("heightmap_tex", hm_tex)

	var col               := CollisionShape3D.new()
	col.shape              = hm_shape
	col.scale              = Vector3(col_cell, 1.0, col_cell)

	var body              := StaticBody3D.new()
	body.name              = "TerrainBody"
	body.add_child(col)
	add_child(body)


# ---------------------------------------------------------------------------
# Central Park geometry (paths + boundary walls from park_data.json)
# ---------------------------------------------------------------------------
var _park_loader = null  # reference for splat map data

func _setup_park() -> void:
	var loader = load("res://park_loader.gd").new()
	loader.name = "CentralPark"
	if not _hm_data.is_empty():
		loader.set_heightmap(_hm_data, _hm_width, _hm_depth, _hm_world_size)
	add_child(loader)
	_park_loader = loader


func _apply_structure_textures() -> void:
	## Load material texture arrays (asphalt, concrete, stone, gravel, wood)
	## used by the terrain shader's structure mask system.
	_terrain_mat.set_shader_parameter("world_size", _hm_world_size)
	_terrain_mat.set_shader_parameter("path_tile_m", 2.5)
	var prefixes: Array = [
		"res://textures/Asphalt012_2K-JPG",
		"res://textures/Concrete034_2K-JPG",
		"res://textures/PavingStones130_2K-JPG",
		"res://textures/Gravel021_2K-JPG",
		"res://textures/WoodFloor041_2K-JPG",
	]
	var suffixes: Array = ["_Color.jpg", "_NormalGL.jpg", "_Roughness.jpg"]
	for si in range(3):
		var images: Array[Image] = []
		for pi in range(prefixes.size()):
			var path: String = prefixes[pi] + suffixes[si]
			var img := Image.load_from_file(path)
			if not img:
				push_warning("Structure texture missing: " + path)
				img = Image.create(64, 64, false, Image.FORMAT_RGB8)
			if pi > 0:
				var target_size := images[0].get_size()
				if img.get_size() != target_size:
					img.resize(target_size.x, target_size.y)
				if img.get_format() != images[0].get_format():
					img.convert(images[0].get_format())
			img.generate_mipmaps()
			images.append(img)
		var tex2d_arr := Texture2DArray.new()
		tex2d_arr.create_from_images(images)
		var param_name: String = ["path_alb_arr", "path_nrm_arr", "path_rgh_arr"][si]
		_terrain_mat.set_shader_parameter(param_name, tex2d_arr)
	print("Terrain: structure material textures loaded")


func _apply_boundary_mask(poly: PackedVector2Array) -> void:
	## Load pre-baked boundary mask or rasterize at runtime.
	## White = inside park, black = outside.
	var img: Image = null

	# Try pre-baked PNG first (generated by convert_to_godot.py at 8192×8192)
	for path in ["res://boundary_mask.png"]:
		var global_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
		elif FileAccess.file_exists(global_path):
			img = Image.load_from_file(global_path)
		if img:
			if img.get_format() != Image.FORMAT_R8:
				img.convert(Image.FORMAT_R8)
			print("Terrain: loaded pre-baked boundary mask %dx%d" % [img.get_width(), img.get_height()])
			break

	# Fallback: runtime scanline rasterization at 1024×1024
	if not img:
		print("Terrain: boundary_mask.png not found — rasterizing at runtime")
		var sz := 1024
		img = Image.create(sz, sz, false, Image.FORMAT_R8)
		img.fill(Color(0, 0, 0))
		var half := _hm_world_size * 0.5
		var n := poly.size()
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
			var arr: Array = Array(crossings)
			arr.sort()
			for k in range(0, arr.size() - 1, 2):
				var px0 := int(clampf((float(arr[k]) + half) / _hm_world_size * float(sz), 0.0, float(sz - 1)))
				var px1 := int(clampf((float(arr[k + 1]) + half) / _hm_world_size * float(sz), 0.0, float(sz - 1)))
				for px in range(px0, px1 + 1):
					img.set_pixel(px, y, Color(1, 1, 1))

	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_terrain_mat.set_shader_parameter("park_mask", tex)
	print("Terrain: boundary mask applied (%dx%d)" % [img.get_width(), img.get_height()])


func _apply_landuse_map(zones: Array, water: Array = []) -> void:
	## Load pre-baked landuse map (8192×8192) from landuse_map.png, or fall back
	## to runtime rasterization at 1024×1024 if the pre-baked file is missing.
	## Zone encoding: 0=unzoned (woodland/meadow), 1=garden, 2=grass, 3=pitch,
	## 4=playground, 5=nature_reserve, 6=dog_park, 7=sports, 8=pool, 9=track,
	## 10=wood, 11=forest, 12=water, 13=shore
	var img: Image = null

	# Try pre-baked PNG first (generated by convert_to_godot.py at 8192×8192)
	for path in ["res://landuse_map.png"]:
		var global_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			img = Image.load_from_file(path)
		elif FileAccess.file_exists(global_path):
			img = Image.load_from_file(global_path)
		if img:
			# Ensure R8 format for zone ID lookup
			if img.get_format() != Image.FORMAT_R8:
				img.convert(Image.FORMAT_R8)
			print("Terrain: loaded pre-baked landuse map %dx%d" % [img.get_width(), img.get_height()])
			break

	# Fallback: runtime rasterization at 1024×1024
	if not img:
		print("Terrain: landuse_map.png not found — rasterizing at runtime (run convert_to_godot.py to pre-bake)")
		img = _rasterize_landuse_runtime(zones, water)

	var tex := ImageTexture.create_from_image(img)
	_terrain_mat.set_shader_parameter("landuse_map", tex)

	# Load pre-baked shore distance field for smooth water-to-land transitions
	var shore_path := "res://shore_distance.png"
	var shore_global := ProjectSettings.globalize_path(shore_path)
	var shore_img: Image = null
	if FileAccess.file_exists(shore_path):
		shore_img = Image.load_from_file(shore_path)
	elif FileAccess.file_exists(shore_global):
		shore_img = Image.load_from_file(shore_global)
	if shore_img:
		var shore_tex := ImageTexture.create_from_image(shore_img)
		_terrain_mat.set_shader_parameter("shore_distance", shore_tex)
		print("Terrain: loaded shore distance field %dx%d" % [shore_img.get_width(), shore_img.get_height()])


func _rasterize_landuse_runtime(zones: Array, water: Array) -> Image:
	## Runtime fallback: scanline-fill landuse zones at 1024×1024.
	var sz := 1024
	var img := Image.create(sz, sz, false, Image.FORMAT_R8)
	img.fill(Color(0, 0, 0))
	var half := _hm_world_size * 0.5

	var _scanline_fill := func(pts: Array, zone_id: int) -> void:
		var min_row := sz
		var max_row := 0
		var poly_x := PackedFloat64Array()
		var poly_z := PackedFloat64Array()
		for pt in pts:
			poly_x.append(float(pt[0]))
			poly_z.append(float(pt[1]))
			var row := int((float(pt[1]) + half) / _hm_world_size * float(sz))
			min_row = min(min_row, row)
			max_row = max(max_row, row)
		min_row = clampi(min_row - 1, 0, sz - 1)
		max_row = clampi(max_row + 1, 0, sz - 1)
		var n := poly_x.size()
		var zone_color := Color(float(zone_id) / 255.0, 0, 0)
		for y in range(min_row, max_row + 1):
			var wz := (float(y) / float(sz)) * _hm_world_size - half
			var crossings := PackedFloat64Array()
			for i in range(n):
				var j := (i + 1) % n
				var zi := poly_z[i]
				var zj := poly_z[j]
				if (zi > wz) != (zj > wz):
					var t := (wz - zi) / (zj - zi)
					crossings.append(poly_x[i] + t * (poly_x[j] - poly_x[i]))
			var arr: Array = Array(crossings)
			arr.sort()
			for k in range(0, arr.size() - 1, 2):
				var px0 := int(clampf((float(arr[k]) + half) / _hm_world_size * float(sz), 0.0, float(sz - 1)))
				var px1 := int(clampf((float(arr[k + 1]) + half) / _hm_world_size * float(sz), 0.0, float(sz - 1)))
				for px in range(px0, px1 + 1):
					img.set_pixel(px, y, zone_color)

	var filled := 0
	for zone in zones:
		var zone_type: String = zone.get("type", "")
		var zone_id: int = LANDUSE_TYPE_TO_ID.get(zone_type, 0)
		if zone_id == 0:
			continue
		var pts: Array = zone.get("points", [])
		if pts.size() < 3:
			continue
		_scanline_fill.call(pts, zone_id)
		filled += 1

	var water_count := 0
	for body in water:
		var pts: Array = body.get("points", [])
		if pts.size() < 3:
			continue
		_scanline_fill.call(pts, 12)
		water_count += 1

	if water_count > 0:
		var shore_pixels := PackedVector2Array()
		var SHORE_R := 3
		for y in range(sz):
			for x in range(sz):
				var v := int(img.get_pixel(x, y).r * 255.0 + 0.5)
				if v == 12:
					for dy in range(-SHORE_R, SHORE_R + 1):
						for dx in range(-SHORE_R, SHORE_R + 1):
							if dx * dx + dy * dy > SHORE_R * SHORE_R:
								continue
							var nx := x + dx
							var ny := y + dy
							if nx < 0 or nx >= sz or ny < 0 or ny >= sz:
								continue
							var nv := int(img.get_pixel(nx, ny).r * 255.0 + 0.5)
							if nv != 12 and nv != 13:
								shore_pixels.append(Vector2(nx, ny))
		var shore_color := Color(13.0 / 255.0, 0, 0)
		for sp in shore_pixels:
			img.set_pixel(int(sp.x), int(sp.y), shore_color)

	print("Terrain: runtime landuse %dx%d (%d zones, %d water)" % [sz, sz, filled, water_count])
	return img


func _apply_structure_mask() -> void:
	## Load the LiDAR structure mask (HH-BE difference) and apply it to the terrain shader.
	## Structure pixels get stone/concrete textures instead of grass.
	var mask_path := "res://lidar_data/structure_mask.png"
	var global_path := ProjectSettings.globalize_path(mask_path)
	if not FileAccess.file_exists(mask_path) and not FileAccess.file_exists(global_path):
		print("Terrain: no structure mask found at %s" % mask_path)
		return
	var img := Image.load_from_file(mask_path)
	if not img:
		img = Image.load_from_file(global_path)
	if not img:
		print("Terrain: failed to load structure mask")
		return
	var tex := ImageTexture.create_from_image(img)
	_terrain_mat.set_shader_parameter("structure_mask", tex)
	print("Terrain: structure mask applied (%dx%d)" % [img.get_width(), img.get_height()])


func _apply_surface_atlas() -> void:
	## Upload world_atlas.bin as an RG8 GPU texture for the terrain shader.
	## R channel = surface type (0=outside, 1=grass, 2=paved, 3=unpaved, 4=water,
	## 5=building, 6=bridge, 7=rock). Shader samples .r to render distinct path surfaces.
	if not _park_loader or _park_loader._atlas_data.is_empty():
		return
	var res: int = _park_loader._atlas_res
	# Upload full RG8 data directly — no per-pixel extraction loop needed.
	# Shader reads .r for surface type (ignoring .g occupancy channel).
	var img := Image.create_from_data(res, res, false, Image.FORMAT_RG8, _park_loader._atlas_data)
	var atlas_tex := ImageTexture.create_from_image(img)
	_terrain_mat.set_shader_parameter("surface_atlas", atlas_tex)
	print("Terrain: surface atlas %dx%d uploaded (RG8, %d KB)" % [
		res, res, _park_loader._atlas_data.size() / 1024])


# ---------------------------------------------------------------------------
# Player
# ---------------------------------------------------------------------------
func _setup_player() -> CharacterBody3D:
	var p: CharacterBody3D = load("res://player.gd").new()
	p.name       = "Player"
	if _terrain_only:
		p.position = Vector3(-300.0, _terrain_height(-300.0, 200.0) + 200.0, 200.0)
		p.rotation_degrees.y = 0.0
		p.set_physics_process(false)
	elif _cli_pos_set:
		p.position = Vector3(_cli_pos.x, _terrain_height(_cli_pos.x, _cli_pos.z) + _cli_height, _cli_pos.z)
		p.rotation_degrees.y = _cli_pos.y if _cli_pos.y != 0.0 else 30.0
		if _cli_height > 5.0:
			p.set_physics_process(false)  # disable gravity for elevated shots
	else:
		p.position = Vector3(-400.0, _terrain_height(-400.0, 600.0) + 1.8, 600.0)
	if not _cli_pos_set:
		p.rotation_degrees.y = 30.0
	p.terrain_height_fn = Callable(self, "_terrain_height")
	add_child(p)
	if _terrain_only and p.head:
		p.head.rotation_degrees.x = -55.0  # look down at terrain
	elif _cli_pitch != 0.0 and p.head:
		p.head.rotation_degrees.x = _cli_pitch
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
		if not child.name.begins_with("Lampposts"):
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
		light.light_color = Color(1.0, 0.62, 0.22)  # warm sodium vapor — Kent Bloomer luminaire
		light.light_energy = 0.0  # off until positioned
		light.spot_range = 45.0   # wide pool — CP lampposts illuminate ~12m radius from 3.5m height
		light.spot_angle = 75.0   # ~150° cone — directed downward from shade
		light.spot_attenuation = 0.65  # soft quadratic-ish falloff for warm pool edges
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
	var pool_size: int = _lamp_lights.size()
	for i in _lamp_positions.size():
		var d := player_pos.distance_squared_to(_lamp_positions[i])
		if d < 2500.0:  # within 50m
			dists.append([d, i])
	# Only sort if we have more candidates than light slots
	if dists.size() > pool_size:
		dists.sort_custom(func(a, b): return a[0] < b[0])

	# Get current lamp emission energy from day/night cycle
	var night_energy: float = _lamp_emission

	for li in _lamp_lights.size():
		if li < dists.size() and night_energy > 0.1:
			var idx: int = dists[li][1]
			_lamp_lights[li].global_position = _lamp_positions[idx]
			_lamp_lights[li].light_energy = night_energy * 22.0
		else:
			_lamp_lights[li].light_energy = 0.0


# ---------------------------------------------------------------------------
# HUD: semi-transparent panel, top-left corner
# ---------------------------------------------------------------------------
func _setup_color_grade() -> void:
	## Fullscreen color grade — glowing in the dark: deep darks, luminous color
	var grade_shader: Shader = load("res://shaders/color_grade.gdshader")
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


# ---------------------------------------------------------------------------
# Wind — layered crossing breezes that vary with time of day and weather
# ---------------------------------------------------------------------------

func _update_wind(delta: float) -> void:
	_wind_time += delta
	var t := _wind_time

	# Time-of-day strength: calm 17-22h so fireflies aren't blown away
	var tod_mult := 1.0
	if _time_of_day >= 17.0 and _time_of_day < 18.0:
		tod_mult = lerpf(1.0, 0.12, (_time_of_day - 17.0))
	elif _time_of_day >= 18.0 and _time_of_day < 21.0:
		tod_mult = 0.12
	elif _time_of_day >= 21.0 and _time_of_day < 22.0:
		tod_mult = lerpf(0.12, 1.0, (_time_of_day - 21.0))

	# Weather multiplier
	var wx := 1.0
	if _weather_mode == "rain":
		wx = 1.8
	elif _weather_mode == "thunderstorm":
		wx = 2.8
	elif _weather_mode == "snow":
		wx = 0.5
	elif _weather_mode == "fog":
		wx = 0.3

	# Layer 1: slow broad wind — base direction rotates over ~3.5 min
	var a1 := t * 0.03
	var s1 := sin(t * 0.21) * 0.25 + 0.30
	var w1 := Vector2(cos(a1), sin(a1)) * s1

	# Layer 2: crossing gust from a different angle (~18s period)
	var a2 := t * 0.03 + 2.1 + sin(t * 0.07) * 0.8
	var s2 := sin(t * 0.35 + 1.7) * 0.20
	var w2 := Vector2(cos(a2), sin(a2)) * s2

	# Layer 3: quick turbulence (~4s puffs, smaller amplitude)
	var s3 := sin(t * 1.3 + 3.1) * 0.10
	var w3 := Vector2(sin(t * 1.7 + 0.5), cos(t * 2.1 + 1.3)) * s3

	_wind_vec = (w1 + w2 + w3) * tod_mult * wx

	# Manual override (- / = keys)
	if _wind_override >= 0.0:
		_wind_vec = (w1 + w2 + w3).normalized() * _wind_override * 0.55

	# Push to global shader uniform
	RenderingServer.global_shader_parameter_set("wind_vec", _wind_vec)


const WEATHER_MODES: Array = ["clear", "rain", "thunderstorm", "snow", "fog"]

func _cycle_weather() -> void:
	# Tear down current weather effects
	if _rain_particles:
		_rain_particles.queue_free()
		_rain_particles = null
	if _snow_particles:
		_snow_particles.queue_free()
		_snow_particles = null
	# Advance to next mode
	var idx := WEATHER_MODES.find(_weather_mode)
	if idx < 0:
		idx = 0
	_weather_mode = WEATHER_MODES[(idx + 1) % WEATHER_MODES.size()]
	_setup_weather()
	# Force re-apply time-of-day so keyframe values override stale weather fog/clouds
	_last_applied_tod = -999.0
	_apply_time_of_day()
	print("Weather: %s" % _weather_mode)


func _setup_weather() -> void:
	if _weather_mode == "rain":
		_setup_rain()
	elif _weather_mode == "thunderstorm":
		_setup_thunderstorm()
	elif _weather_mode == "snow":
		_setup_snow()
	elif _weather_mode == "fog":
		_setup_fog_weather()
	elif _weather_mode == "lens":
		_setup_lens_distortion()


func _setup_rain() -> void:
	# Gentle rain — soft, slow, soothing
	_rain_particles = GPUParticles3D.new()
	_rain_particles.amount = 6000
	_rain_particles.lifetime = 4.0
	_rain_particles.visibility_aabb = AABB(Vector3(-25, -15, -25), Vector3(50, 30, 50))

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -1.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(25.0, 0.5, 25.0)
	_rain_particles.process_material = pm

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.006, 0.10)
	_rain_particles.draw_pass_1 = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.75, 0.85, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.45, 0.55)
	mat.emission_energy_multiplier = 0.2
	_rain_particles.material_override = mat

	add_child(_rain_particles)
	print("Rain: 6000 gentle particles")


func _setup_thunderstorm() -> void:
	# Heavy downpour — dense, fast, thick drops
	_rain_particles = GPUParticles3D.new()
	_rain_particles.amount = 30000
	_rain_particles.lifetime = 2.5
	_rain_particles.visibility_aabb = AABB(Vector3(-25, -15, -25), Vector3(50, 30, 50))

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 7.5
	pm.gravity = Vector3(0, -3.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(25.0, 0.5, 25.0)
	_rain_particles.process_material = pm

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.012, 0.22)
	_rain_particles.draw_pass_1 = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.65, 0.75, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.40, 0.50)
	mat.emission_energy_multiplier = 0.25
	_rain_particles.material_override = mat

	add_child(_rain_particles)
	print("Thunderstorm: 30000 heavy rain")


func _setup_snow() -> void:
	_snow_particles = GPUParticles3D.new()
	_snow_particles.amount = 3000
	_snow_particles.lifetime = 4.0
	_snow_particles.visibility_aabb = AABB(Vector3(-25, -20, -25), Vector3(50, 40, 50))

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, -1.5, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(25.0, 0.5, 25.0)
	# Gentle drift
	pm.orbit_velocity_min = 0.1
	pm.orbit_velocity_max = 0.3
	_snow_particles.process_material = pm

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.04, 0.04)
	_snow_particles.draw_pass_1 = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.95, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snow_particles.material_override = mat

	add_child(_snow_particles)

	print("Snow: 3000 particles")



func _setup_leaf_particles() -> void:
	## Autumn falling leaves — warm-colored quads drifting down through canopy.
	## Active only during autumn season (season_t 2.0-3.2). Amount varies
	## with season intensity: sparse at start/end, dense at peak color.
	_leaf_particles = GPUParticles3D.new()
	_leaf_particles.amount = 800  # adjusted dynamically in _process
	_leaf_particles.lifetime = 8.0  # slow drift down
	_leaf_particles.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 45.0  # wide spread — leaves tumble in all directions
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, -0.3, 0)  # very slow fall (wind does most of the work)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 2.0, 30.0)
	# Orbit for tumbling/spinning as leaves fall
	pm.orbit_velocity_min = 0.15
	pm.orbit_velocity_max = 0.45
	# Angular velocity for spinning
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	# Scale variation — different leaf sizes
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	# Randomize color: fall palette from warm yellow to deep red
	pm.color = Color(0.85, 0.55, 0.20, 0.85)
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.90, 0.80, 0.25, 0.90))  # golden yellow
	grad.add_point(0.3, Color(0.85, 0.50, 0.15, 0.85))  # orange
	grad.add_point(0.6, Color(0.75, 0.25, 0.10, 0.80))  # red-brown
	grad.set_color(1, Color(0.50, 0.30, 0.15, 0.70))  # dark brown (old leaves)
	color_ramp.gradient = grad
	pm.color_initial_ramp = color_ramp
	_leaf_particles.process_material = pm

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.035, 0.025)  # small leaf shape — wider than tall
	_leaf_particles.draw_pass_1 = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.55, 0.20, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_leaf_particles.material_override = mat

	add_child(_leaf_particles)
	print("Autumn leaves: drifting fall particles")


func _setup_blossom_particles() -> void:
	## Spring cherry blossom petals — pale pink quads floating down like snow.
	## Active during spring bloom (season_t 0.2-1.0). Yoshino cherry, callery pear,
	## and magnolia all shed petals in Central Park's April bloom.
	_blossom_particles = GPUParticles3D.new()
	_blossom_particles.amount = 600  # adjusted dynamically in _process
	_blossom_particles.lifetime = 12.0  # very slow drift — petals are light
	_blossom_particles.visibility_aabb = AABB(Vector3(-35, -15, -35), Vector3(70, 30, 70))

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 60.0  # wide spread — petals flutter in all directions
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, -0.15, 0)  # extremely slow fall (petals are featherlight)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35.0, 3.0, 35.0)
	# Gentle orbit for graceful fluttering descent
	pm.orbit_velocity_min = 0.08
	pm.orbit_velocity_max = 0.25
	# Slow spin — petals rotate gracefully, not chaotically
	pm.angular_velocity_min = -45.0
	pm.angular_velocity_max = 45.0
	# Scale variation — small petals
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	# Color: cherry blossom pink palette
	pm.color = Color(0.95, 0.82, 0.85, 0.90)
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.92, 0.94, 0.95))    # almost white (fresh petal)
	grad.add_point(0.25, Color(0.98, 0.82, 0.86, 0.92)) # pale pink (Yoshino cherry)
	grad.add_point(0.5, Color(0.95, 0.72, 0.78, 0.88))  # medium pink
	grad.add_point(0.75, Color(0.92, 0.65, 0.72, 0.80)) # deeper pink (aging petal)
	grad.set_color(1, Color(0.88, 0.60, 0.65, 0.50))    # browning edge (ground)
	color_ramp.gradient = grad
	pm.color_initial_ramp = color_ramp
	# Damping so petals slow down as they drift
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	_blossom_particles.process_material = pm

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.018, 0.016)  # tiny petal shape — slightly wider than tall

	_blossom_particles.draw_pass_1 = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.85, 0.88, 0.90)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Slight emission for that ethereal glow of sunlit petals
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.80, 0.82)
	mat.emission_energy_multiplier = 0.15
	_blossom_particles.material_override = mat

	add_child(_blossom_particles)
	print("Cherry blossoms: spring petal drift particles")


func _setup_fog_weather() -> void:
	# Fog multipliers are applied per-frame in the day/night cycle update
	print("Fog: heavy atmospheric fog")


func _setup_lens_distortion() -> void:
	# Barrel distortion + chromatic aberration
	_lens_canvas = CanvasLayer.new()
	_lens_canvas.layer = 98  # below color grade
	var lens_rect := ColorRect.new()
	lens_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	lens_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lens_shader: Shader = load("res://shaders/lens_distortion.gdshader")
	var lens_mat := ShaderMaterial.new()
	lens_mat.shader = lens_shader
	lens_rect.material = lens_mat
	_lens_canvas.add_child(lens_rect)
	add_child(_lens_canvas)
	print("Lens: barrel distortion + chromatic aberration")


func _setup_letterbox() -> void:
	# Cinematic 2.35:1 letterbox — black bars top and bottom, toggled with L key.
	# Bar height = (viewport_h - viewport_w / 2.35) / 2
	_letterbox_canvas = CanvasLayer.new()
	_letterbox_canvas.name = "Letterbox"
	_letterbox_canvas.layer = 101  # above color grade
	_letterbox_canvas.visible = false

	_letterbox_top = ColorRect.new()
	_letterbox_top.color = Color.BLACK
	_letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letterbox_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_letterbox_top.anchor_bottom = 0.0
	_letterbox_top.offset_bottom = 1.0  # will be resized in _process
	_letterbox_canvas.add_child(_letterbox_top)

	_letterbox_bot = ColorRect.new()
	_letterbox_bot.color = Color.BLACK
	_letterbox_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letterbox_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_letterbox_bot.anchor_top = 1.0
	_letterbox_bot.offset_top = -1.0  # will be resized in _process
	_letterbox_canvas.add_child(_letterbox_bot)

	add_child(_letterbox_canvas)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	_hud_canvas = canvas
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

	_speed_label = Label.new()
	_speed_label.text = "Stroll (0.4 m/s)"
	_speed_label.add_theme_font_size_override("font_size", 22)
	_speed_label.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	vbox.add_child(_speed_label)

	_location_label = Label.new()
	_location_label.text = ""
	_location_label.add_theme_font_size_override("font_size", 26)
	_location_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_location_label.visible = false
	vbox.add_child(_location_label)

	var hint := Label.new()
	hint.text = "WASD: move   Mouse+RMB: look   Scroll/+/-: speed   9/0: wind   T: time   [/]: ±1h   P: weather   H: HUD"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(hint)






