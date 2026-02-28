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

# HUD label references kept for per-frame updates
var _player:        CharacterBody3D
var _coord_label:   Label
var _heading_label: Label
var _latlon_label:  Label


func _ready() -> void:
	_setup_environment()
	_setup_ground()
	_setup_park()
	_player = _setup_player()
	_setup_hud()


# ---------------------------------------------------------------------------
# Per-frame HUD update
# ---------------------------------------------------------------------------
func _process(_delta: float) -> void:
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


func _compass_label(deg: float) -> String:
	var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return labels[int(fmod(deg + 22.5, 360.0) / 45.0) % 8]


# ---------------------------------------------------------------------------
# Sky + lighting
# ---------------------------------------------------------------------------
func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color     = Color(0.13, 0.40, 0.82)
	sky_mat.sky_horizon_color = Color(0.58, 0.78, 0.96)
	sky_mat.ground_bottom_color  = Color(0.06, 0.14, 0.04)
	sky_mat.ground_horizon_color = Color(0.24, 0.42, 0.14)
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve     = 0.06

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode      = Environment.BG_SKY
	env.sky                  = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode         = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled         = true
	env.glow_intensity       = 0.4
	env.glow_bloom           = 0.05

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy     = 2.2
	sun.light_color      = Color(1.00, 0.95, 0.85)
	sun.shadow_enabled   = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 150.0, 0.0)
	fill.light_energy     = 0.35
	fill.light_color      = Color(0.75, 0.85, 1.00)
	fill.shadow_enabled   = false
	add_child(fill)


# ---------------------------------------------------------------------------
# Ground plane with procedural grid shader
# (5 km × 5 km to cover all of Central Park's ~4 km length)
# ---------------------------------------------------------------------------
func _setup_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size            = Vector2(5000.0, 5000.0)
	plane.subdivide_width  = 1
	plane.subdivide_depth  = 1

	var shader := Shader.new()
	shader.code = _grid_shader_code()

	var mat := ShaderMaterial.new()
	mat.shader = shader

	var mi := MeshInstance3D.new()
	mi.mesh              = plane
	mi.material_override = mat
	add_child(mi)

	# Infinite flat collision floor
	var body := StaticBody3D.new()
	var col  := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()
	body.add_child(col)
	add_child(body)


func _grid_shader_code() -> String:
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
	add_child(loader)


# ---------------------------------------------------------------------------
# Player
# ---------------------------------------------------------------------------
func _setup_player() -> CharacterBody3D:
	var p: CharacterBody3D = load("res://player.gd").new()
	p.name = "Player"
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

	var hint := Label.new()
	hint.text = "Left stick: walk   Right stick: look"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	vbox.add_child(hint)
