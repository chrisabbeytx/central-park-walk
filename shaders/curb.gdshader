shader_type spatial;
render_mode cull_disabled;

// Terrain snapping (shared heightmap with path shader)
uniform sampler2D heightmap_tex : filter_nearest, repeat_disable;
uniform float hm_world_size = 5000.0;
uniform float hm_min_h      = 0.0;
uniform float hm_range       = 1.0;
uniform float hm_res         = 256.0;
uniform float curb_top_offset = 0.08;   // flush with path surface (matches path_y_offset)
uniform float curb_below_grade = 0.04;  // extend below terrain to prevent gaps
uniform float sample_offset = 0.30;     // how far inward/outward to sample terrain (metres)

global uniform float rain_wetness;
global uniform float snow_cover;
global uniform float season_t;

#include "res://shaders/include/decode_terrain.gdshaderinc"
#include "res://shaders/include/hash_noise.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_nrm;
varying float height_frac;  // 1.0 = top (path level), 0.0 = bottom (grass level)

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// COLOR.r encodes position in curb cross-section:
	//   1.0 = top vertex (path surface level)
	//   0.0 = bottom vertex (terrain/grass level)
	//
	// Both top and bottom vertices share the same XZ position (at the path edge),
	// producing a perfectly vertical face. To get the correct height for each:
	//   Top: sample terrain 30cm INWARD (toward path center) → path surface height
	//   Bottom: sample terrain 30cm OUTWARD (toward grass) → grass height
	// This captures the real grade change between path and grass from LiDAR.
	vec2 outward_xz = normalize(NORMAL.xz + vec2(0.0001));
	float sample_dir = mix(1.0, -1.0, COLOR.r);  // +1 outward (bottom), -1 inward (top)
	vec2 sample_xz = world.xz + outward_xz * sample_dir * sample_offset;
	float terrain_h = sample_terrain(sample_xz);

	float y_offset = mix(-curb_below_grade, curb_top_offset, COLOR.r);
	vec3 snapped = (inverse(MODEL_MATRIX) * vec4(world.x, terrain_h + y_offset, world.z, 1.0)).xyz;
	VERTEX.y = snapped.y;

	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	height_frac = COLOR.r;
}

void fragment() {
	// --- Cut granite curb ---
	// Central Park: machine-dressed granite blocks, ~90cm long, 15cm reveal,
	// light warm gray with feldspar pink, biotite mica sparkle, bush-hammered face

	// Per-block variation (~90cm blocks = 1.1/m)
	float block_id = hash2(floor(world_pos.xz * 1.1));
	vec3 base = vec3(0.70, 0.68, 0.66);
	base += vec3(0.03, -0.01, -0.02) * (block_id - 0.5);
	base *= 0.95 + block_id * 0.10;

	// Fine crystalline grain (~2-5mm crystals)
	float grain = hash2(floor(world_pos.xz * 200.0 + world_pos.yy * 200.0));
	base += (grain - 0.5) * 0.04;

	// Bush-hammer tooling marks on vertical face: fine horizontal grooves
	float face_vert = 1.0 - abs(world_nrm.y);
	if (face_vert > 0.3) {
		float tool_groove = sin(world_pos.y * 120.0 + hash2(floor(world_pos.xz * 3.0)) * 6.28);
		tool_groove = smoothstep(0.0, 0.5, tool_groove) * face_vert;
		base *= 1.0 - tool_groove * 0.06;
	}

	// Weathering: darker at base from splash staining and soil contact
	float dirt_grad = smoothstep(0.4, 0.0, height_frac);
	base *= 1.0 - dirt_grad * 0.15;
	// Dark runoff streaks
	float streak = vnoise(vec2(world_pos.x + world_pos.z, world_pos.y) * vec2(4.0, 0.5));
	streak = smoothstep(0.55, 0.75, streak) * 0.08 * face_vert;
	base *= 1.0 - streak;

	float rough = 0.72;

	// Mica sparkle
	float mica = hash2(floor(world_pos.xz * 25.0 + world_pos.yy * 20.0));
	float sparkle_spec = 0.0;
	if (mica > 0.94) {
		sparkle_spec = (mica - 0.94) * 16.0 * 0.3;
		base += vec3(0.02) * sparkle_spec;
	}

	// Moss at base in spring/summer
	float spring_summer = smoothstep(0.0, 1.0, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
	float moss_zone = smoothstep(0.3, 0.0, height_frac) * spring_summer;
	float moss_noise = vnoise(world_pos.xz * 3.0 + vec2(42.0));
	float moss = moss_zone * smoothstep(0.4, 0.65, moss_noise) * 0.35;
	if (moss > 0.01) {
		vec3 moss_col = mix(vec3(0.10, 0.18, 0.06), vec3(0.15, 0.24, 0.08), moss_noise);
		base = mix(base, moss_col, moss);
		rough = mix(rough, 0.90, moss);
	}

	// Rain
	if (rain_wetness > 0.01) {
		base *= mix(1.0, 0.62, rain_wetness);
		rough = mix(rough, 0.10, rain_wetness);
	}

	// Winter frost
	float winter_t = smoothstep(2.5, 3.5, season_t);
	if (winter_t > 0.01 && rain_wetness < 0.1) {
		float frost_n = hash2(floor(world_pos.xz * 8.0 + world_pos.yy * 6.0));
		float frost = step(0.55, frost_n) * winter_t * 0.25 * face_vert;
		base = mix(base, vec3(0.80, 0.83, 0.88), frost);
		rough = mix(rough, 0.12, frost * 0.5);
	}

	// Snow
	if (snow_cover > 0.01) {
		float upward = max(world_nrm.y, 0.0);
		float snow_amt = snow_cover * smoothstep(0.3, 0.8, upward);
		snow_amt += snow_cover * 0.15 * smoothstep(0.8, 1.0, height_frac) * face_vert;
		snow_amt = min(snow_amt, 1.0);
		base = mix(base, vec3(0.91, 0.92, 0.95), snow_amt * 0.8);
		rough = mix(rough, 0.80, snow_amt);
	}

	ALBEDO = base;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.08 + sparkle_spec;
	EMISSION = base * 0.06;
}
