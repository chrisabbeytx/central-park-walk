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


func _ready() -> void:
	_load_heightmap()
	_setup_environment()
	_setup_ground()
	_setup_park()
	_player = _setup_player()
	_setup_hud()


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
	return h00*(1.0-fx)*(1.0-fz) + h10*fx*(1.0-fz) + h01*(1.0-fx)*fz + h11*fx*fz


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
func _load_img_tex(path: String) -> ImageTexture:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if not img:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _load_sky_material() -> Material:
	var path := "res://textures/sky.hdr"
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			img.generate_mipmaps()
			var tex := ImageTexture.create_from_image(img)
			var pan := PanoramaSkyMaterial.new()
			pan.panorama = tex
			print("Sky: loaded HDR panorama")
			return pan
	print("Sky: procedural fallback")
	var proc := ProceduralSkyMaterial.new()
	proc.sky_top_color        = Color(0.13, 0.40, 0.82)
	proc.sky_horizon_color    = Color(0.58, 0.78, 0.96)
	proc.ground_bottom_color  = Color(0.06, 0.14, 0.04)
	proc.ground_horizon_color = Color(0.24, 0.42, 0.14)
	proc.sun_angle_max        = 30.0
	proc.sun_curve            = 0.06
	return proc


func _setup_environment() -> void:
	var sky_mat: Material = _load_sky_material()

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode      = Environment.BG_SKY
	env.sky                  = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode         = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled         = true
	env.glow_intensity       = 0.12
	env.glow_bloom           = 0.02

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy     = 1.3
	sun.light_color      = Color(1.00, 0.95, 0.85)
	sun.shadow_enabled   = true
	add_child(sun)



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
	vec2 uv     = world_pos.xz / tile_m;
	vec3  alb   = texture(grass_albedo, uv).rgb;
	float rough = texture(grass_rough,  uv).r;

	// Large-scale tint breaks up tiling repetition
	float f = clamp(fbm(world_pos.xz * 0.004, 4) * 0.45
	              + fbm(world_pos.xz * 0.025, 3) * 0.35 + 0.30, 0.55, 1.1);

	ALBEDO     = alb * f;
	NORMAL_MAP = texture(grass_normal, uv).rgb;
	ROUGHNESS  = clamp(rough * 0.85 + 0.1, 0.0, 1.0);
	METALLIC   = 0.0;
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
	add_child(loader)


# ---------------------------------------------------------------------------
# Player
# ---------------------------------------------------------------------------
func _setup_player() -> CharacterBody3D:
	var p: CharacterBody3D = load("res://player.gd").new()
	p.name       = "Player"
	p.position.y = _hm_origin_height + 2.0   # spawn above terrain; physics settles
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
