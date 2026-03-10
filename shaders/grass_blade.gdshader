shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

#include "res://shaders/include/hash_noise.gdshaderinc"

global uniform vec2 wind_vec;
global uniform float season_t;
global uniform float snow_cover;
global uniform float rain_wetness;

varying float v_grass_type;
varying vec3 v_world_pos;

void vertex() {
	// INSTANCE_CUSTOM: R=grass_type (0=mowed, 1=meadow), G=seed, B=unused
	v_grass_type = INSTANCE_CUSTOM.r;

	// Clump world origin for wind spatial phasing
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_world_pos = origin;

	// --- Wind animation ---
	float sway = UV.y * UV.y;  // quadratic: base pinned, tip moves most
	float wind_str = length(wind_vec);
	// Meadow sways more (taller, more flexible stems)
	float flex = mix(0.7, 2.2, v_grass_type);
	float rustle = (0.2 + wind_str * 0.8) * flex;

	// Base sway: continuous oscillation (faster than trees — grass is lighter)
	float px = origin.x * 0.15 + origin.z * 0.22;
	float pz = origin.z * 0.18 + origin.x * 0.12;
	VERTEX.x += sin(TIME * 1.8 + px) * 0.04 * sway * rustle;
	VERTEX.z += sin(TIME * 2.3 + pz) * 0.03 * sway * rustle;

	// Wind push: constant lean in wind direction
	VERTEX.x += wind_vec.x * sway * 0.14 * flex;
	VERTEX.z += wind_vec.y * sway * 0.14 * flex;

	// Traveling wind gusts (wave across the field)
	float gust_phase = origin.x * 0.04 + origin.z * 0.05;
	float gust = sin(TIME * 0.5 + gust_phase) * 0.5 + 0.5;
	gust = gust * gust * gust;  // sharpen peaks: brief strong gusts
	float gust_str = gust * wind_str * 0.22 * flex;
	VERTEX.x += wind_vec.x * sway * gust_str;
	VERTEX.z += wind_vec.y * sway * gust_str;

	// Blade flutter: high-frequency micro-movement
	float flutter = sin(TIME * 5.5 + VERTEX.x * 14.0 + VERTEX.z * 10.0) * 0.006 * rustle;
	flutter += sin(TIME * 8.0 + VERTEX.z * 18.0) * 0.003 * gust_str;
	VERTEX.y += flutter * sway;

	// Winter: mowed grass retreats (goes dormant, shorter)
	float winter_t = smoothstep(3.0, 3.5, season_t);
	if (winter_t > 0.0 && v_grass_type < 0.5) {
		VERTEX.y *= mix(1.0, 0.3, winter_t);
	}
}

void fragment() {
	// --- Procedural blade shape ---
	// UV.x has per-quad offset (0.0, 0.333, 0.667) so each of the 3
	// cross-billboard quads shows a different blade arrangement.
	// 4 blades per quad; fract() handles the offset seamlessly.
	float bu = fract(UV.x * 4.0);            // local position within blade [0,1)
	float blade_id = floor(UV.x * 4.0);      // unique per blade across quads
	float blade_dist = abs(bu - 0.5);         // distance from blade centre

	// Per-blade height variation
	float h_rand = hash2(vec2(blade_id * 7.3 + 0.5,
	                          v_world_pos.x * 0.13 + v_world_pos.z * 0.17));
	float blade_h = 0.5 + h_rand * 0.5;      // 50-100% of full height

	// Blade shape: tapers from wide base to pointed tip
	float max_w = 0.45;
	float taper = max_w * max(1.0 - UV.y / max(blade_h, 0.01), 0.0);
	float alpha = smoothstep(taper + 0.04, taper - 0.02, blade_dist);

	if (alpha < 0.4) discard;

	// --- Grass colour ---
	vec3 mowed_green  = vec3(0.20, 0.42, 0.14);
	vec3 meadow_green = vec3(0.16, 0.34, 0.09);
	vec3 base_col = mix(mowed_green, meadow_green, v_grass_type);

	// Seasonal modulation (matching terrain.gdshader palette)
	float spring_t = 1.0 - smoothstep(0.0, 1.0, season_t);
	float autumn_t = smoothstep(2.0, 2.8, season_t) * (1.0 - smoothstep(3.2, 4.0, season_t));
	float winter_t = smoothstep(3.0, 3.5, season_t);

	vec3 col = base_col;
	col = mix(col, base_col * vec3(1.15, 1.20, 0.70), spring_t * 0.6);   // bright yellow-green
	col = mix(col, base_col * vec3(1.35, 0.85, 0.40), autumn_t * 0.75);  // golden-brown
	float lum = dot(base_col, vec3(0.299, 0.587, 0.114));
	vec3 wint_col = mix(vec3(lum), base_col, 0.25) * vec3(0.85, 0.78, 0.55);
	col = mix(col, wint_col, winter_t * 0.85);                            // dormant brown

	// Height gradient: darker at base, lighter at tips (subsurface-like)
	col *= 0.55 + UV.y * 0.55;

	// Per-clump colour variation (avoids uniform sea of identical green)
	float clump_var = hash2(floor(v_world_pos.xz * 0.5));
	col *= 0.88 + clump_var * 0.24;

	// Meadow: golden seed heads in late summer / autumn
	if (v_grass_type > 0.5 && UV.y > 0.7) {
		float golden = smoothstep(0.7, 0.95, UV.y) * smoothstep(1.0, 2.2, season_t);
		col = mix(col, col * vec3(1.35, 1.15, 0.65), golden * 0.5);
	}

	ALBEDO    = col;
	ROUGHNESS = 0.82;
	SPECULAR  = 0.08;
	METALLIC  = 0.0;

	// Rain: wet darkening + gloss
	if (rain_wetness > 0.01) {
		ALBEDO   *= mix(1.0, 0.65, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.25, rain_wetness);
		SPECULAR  = mix(SPECULAR,  0.35, rain_wetness);
	}

	// Snow on blade tips
	if (snow_cover > 0.01) {
		float snow_on = smoothstep(0.2, 0.7, UV.y) * snow_cover;
		snow_on *= mix(0.5, 1.0, v_grass_type);   // meadow catches more
		ALBEDO    = mix(ALBEDO,    vec3(0.92, 0.93, 0.96), snow_on * 0.65);
		ROUGHNESS = mix(ROUGHNESS, 0.90,                   snow_on * 0.5);
	}

	// Backlight / subsurface scattering
	BACKLIGHT = col * 0.35;
}
