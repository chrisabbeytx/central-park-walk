shader_type spatial;
render_mode cull_disabled;

// Weathered wood — rain darkening, snow accumulation
uniform vec3 wood_color = vec3(0.38, 0.32, 0.25);
uniform float base_roughness = 0.88;
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform float season_t;
global uniform vec3 sky_reflect_color;

#include "res://shaders/include/hash_noise.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Per-plank variation from world position
	float var_h = hash2(floor(world_pos.xz * 2.0 + world_pos.yy * 1.5));

	// Grain pattern: elongated noise along primary axis
	// Wood grain runs roughly horizontal on bridge rails, vertical on posts
	float grain_u = world_pos.x * 6.0 + world_pos.z * 6.0;
	float grain_v = world_pos.y * 1.5;
	float grain = vnoise(vec2(grain_u, grain_v));
	float fine_grain = vnoise(vec2(grain_u * 3.0, grain_v * 2.5));
	// Annual ring pattern: concentric curves visible on end grain
	float ring = sin(grain_u * 2.0 + grain * 4.0) * 0.5 + 0.5;
	ring = smoothstep(0.3, 0.7, ring);

	vec3 col = wood_color * (0.85 + var_h * 0.30);
	col *= (0.88 + grain * 0.18 + fine_grain * 0.06);
	// Ring pattern: subtle earlywood/latewood variation
	col *= mix(0.95, 1.05, ring);

	// --- Silver-gray UV weathering ---
	// Outdoor wood exposed to sun/rain turns silver-gray over years
	// More weathered on upward-facing and sun-exposed surfaces
	float upward_face = max(world_nrm.y, 0.0);
	float weather_expo = 0.3 + upward_face * 0.4;
	// Weathering noise: patchy silver in areas where UV has bleached the surface
	float weather_noise = vnoise(world_pos.xz * 1.5 + world_pos.yy * 0.8);
	float silver_mask = smoothstep(0.2, 0.6, weather_noise) * weather_expo;
	vec3 silver_gray = vec3(0.52, 0.50, 0.46);
	col = mix(col, silver_gray, silver_mask * 0.35);

	// --- Checking/splitting: hairline cracks from drying ---
	// Visible on weathered wood as thin dark lines along the grain
	float check = sin(grain_u * 25.0 + vnoise(vec2(grain_u * 2.0, grain_v * 3.0)) * 5.0);
	float check_mask = smoothstep(0.85, 0.95, check) * silver_mask;
	col *= (1.0 - check_mask * 0.15);

	// --- Nail/bolt rust staining: dark rust streaks below fastener points ---
	float nail_hash = hash2(floor(world_pos.xz * 3.5 + world_pos.yy * 2.0));
	if (nail_hash > 0.88) {
		// Rust streak running downward from fastener
		float streak_mask = smoothstep(0.88, 0.92, nail_hash);
		float streak_run = smoothstep(0.0, 0.1, fract(world_pos.y * 3.0));
		float rust = streak_mask * streak_run * 0.15;
		col = mix(col, vec3(0.30, 0.16, 0.08), rust);
	}

	float rough = base_roughness + silver_mask * 0.04;  // weathered wood is rougher

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.04;

	// Rain: wet wood darkens significantly, becomes slightly reflective
	if (rain_wetness > 0.01) {
		float wet = rain_wetness;
		ALBEDO *= mix(1.0, 0.55, wet);
		ROUGHNESS = mix(ROUGHNESS, 0.40, wet);
		SPECULAR = mix(SPECULAR, 0.25, wet);
	}

	// Snow on upward-facing surfaces
	if (snow_cover > 0.01) {
		if (upward_face > 0.4) {
			float sn = hash2(floor(world_pos.xz * 4.0)) * 0.2;
			float snow_amt = clamp((upward_face + sn - 0.2) * snow_cover, 0.0, 1.0);
			ALBEDO = mix(ALBEDO, vec3(0.90, 0.91, 0.94), snow_amt * 0.7);
			ROUGHNESS = mix(ROUGHNESS, 0.90, snow_amt);
		}
	}

	// Green algae staining on north-facing and shaded surfaces
	float spring_summer = smoothstep(0.0, 1.0, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
	float algae_facing = max(0.0, -world_nrm.z) * 0.4 + (1.0 - upward_face) * 0.3;
	float algae_noise = vnoise(world_pos.xz * 2.5 + world_pos.yy * 1.8);
	float algae = algae_facing * smoothstep(0.4, 0.7, algae_noise) * spring_summer;
	if (algae > 0.01) {
		ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.75, 1.15, 0.65), algae * 0.25);
		ROUGHNESS = mix(ROUGHNESS, 0.95, algae * 0.2);
	}

	// Aerial perspective
	float wood_dist = length(world_pos - INV_VIEW_MATRIX[3].xyz);
	float wood_aerial = smoothstep(80.0, 300.0, wood_dist);
	if (wood_aerial > 0.01) {
		float wl = dot(ALBEDO, vec3(0.2126, 0.7152, 0.0722));
		ALBEDO = mix(ALBEDO, vec3(wl), wood_aerial * 0.25);
		float sky_l = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
		vec3 haze = mix(vec3(0.58, 0.56, 0.52), sky_reflect_color * 0.8 + vec3(0.20), 0.35);
		float night_f = smoothstep(0.15, 0.02, sky_l);
		haze = mix(haze, vec3(0.14, 0.10, 0.06), night_f * 0.6);
		ALBEDO = mix(ALBEDO, haze, wood_aerial * 0.25);
	}
}
