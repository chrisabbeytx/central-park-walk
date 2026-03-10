shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/include/hash_noise.gdshaderinc"

global uniform vec2 wind_vec;
global uniform float season_t;
global uniform float snow_cover;
global uniform float rain_wetness;

varying float v_grass_type;
varying vec3 v_world_pos;

void vertex() {
	// INSTANCE_CUSTOM: R = grass_type (0=lawn, 1=woodland, 2=meadow)
	v_grass_type = INSTANCE_CUSTOM.r;

	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_world_pos = origin;

	// Height-based sway: model-space VERTEX.y (0 at base, tip varies by type)
	float sway = max(VERTEX.y, 0.0);
	float wind_str = length(wind_vec);

	// Wind response varies by type (0-9):
	// 0-4: lawn types — moderate sway
	// 5-6: woodland — minimal sway (sheltered under canopy)
	// 7: waterside — moderate
	// 8: wild meadow — strong dramatic flow
	// 9: open lawn — moderate
	float flex = 0.7;  // default
	if (v_grass_type > 7.5) {
		flex = 2.5;  // wild meadow: dramatic flow
	} else if (v_grass_type > 6.5) {
		flex = 0.8;  // waterside: moderate
	} else if (v_grass_type > 4.5) {
		flex = 0.35; // woodland: sheltered under canopy
	} else if (v_grass_type > 3.5) {
		flex = 0.5;  // sports turf: short, less sway
	}
	float rustle = (0.2 + wind_str * 0.8) * flex;

	// Base sway: continuous oscillation
	float px = origin.x * 0.15 + origin.z * 0.22;
	float pz = origin.z * 0.18 + origin.x * 0.12;
	VERTEX.x += sin(TIME * 1.8 + px) * 0.12 * sway * rustle;
	VERTEX.z += sin(TIME * 2.3 + pz) * 0.08 * sway * rustle;

	// Wind push: constant lean in wind direction
	VERTEX.x += wind_vec.x * sway * 0.4 * flex;
	VERTEX.z += wind_vec.y * sway * 0.4 * flex;

	// Traveling wind gusts
	float gust_phase = origin.x * 0.04 + origin.z * 0.05;
	float gust = sin(TIME * 0.5 + gust_phase) * 0.5 + 0.5;
	gust = gust * gust * gust;
	float gust_str = gust * wind_str * 0.5 * flex;
	VERTEX.x += wind_vec.x * sway * gust_str;
	VERTEX.z += wind_vec.y * sway * gust_str;

	// Blade flutter: high-frequency micro-movement
	float flutter = sin(TIME * 5.5 + VERTEX.x * 14.0 + VERTEX.z * 10.0) * 0.015 * rustle;
	flutter += sin(TIME * 8.0 + VERTEX.z * 18.0) * 0.008 * gust_str;
	VERTEX.y += flutter * sway;

	// Winter: lawn types go dormant (shorter). Woodland already sparse.
	float winter_t = smoothstep(3.0, 3.5, season_t);
	if (winter_t > 0.0 && (v_grass_type < 4.5 || v_grass_type > 8.5)) {
		VERTEX.y *= mix(1.0, 0.3, winter_t);
	}
}

void fragment() {
	// Vertex colors from Blender model provide base albedo
	vec3 col = COLOR.rgb;

	// --- Height-based shading: darker at base, brighter at tip ---
	// UV.y from Blender: 0.0 at base, 1.0 at tip (set in make_grass_patch.py)
	float blade_t = clamp(UV.y, 0.0, 1.0);
	// Ambient occlusion at blade base — creates depth in the grass carpet
	float ao = mix(0.55, 1.0, smoothstep(0.0, 0.4, blade_t));
	col *= ao;
	// Tip brightening: sun catches blade tips, not shaded bases
	col *= mix(1.0, 1.12, smoothstep(0.5, 1.0, blade_t));

	// --- Seasonal colour modulation ---
	float spring_t = 1.0 - smoothstep(0.0, 1.0, season_t);
	float autumn_t = smoothstep(2.0, 2.8, season_t) * (1.0 - smoothstep(3.2, 4.0, season_t));
	float winter_t = smoothstep(3.0, 3.5, season_t);

	col = mix(col, col * vec3(1.15, 1.20, 0.70), spring_t * 0.5);   // spring: bright yellow-green
	col = mix(col, col * vec3(1.30, 0.85, 0.45), autumn_t * 0.6);   // autumn: golden-brown
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 wint_col = mix(vec3(lum), col, 0.30) * vec3(0.85, 0.78, 0.55);
	col = mix(col, wint_col, winter_t * 0.75);                       // winter: dormant brown

	// Per-clump colour variation
	float clump_var = hash2(floor(v_world_pos.xz * 0.5));
	col *= 0.88 + clump_var * 0.24;

	ALBEDO    = col;
	ROUGHNESS = mix(0.85, 0.70, blade_t);  // tips smoother (catch specular)
	SPECULAR  = mix(0.05, 0.15, blade_t);  // tips more reflective
	METALLIC  = 0.0;

	// Rain: wet darkening + gloss
	if (rain_wetness > 0.01) {
		ALBEDO   *= mix(1.0, 0.65, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.25, rain_wetness);
		SPECULAR  = mix(SPECULAR,  0.35, rain_wetness);
	}

	// Snow on upper surfaces
	if (snow_cover > 0.01) {
		vec3 world_n = mat3(INV_VIEW_MATRIX) * NORMAL;
		float upward = max(world_n.y, 0.0);
		float snow_on = upward * snow_cover * mix(0.5, 1.0, v_grass_type);
		ALBEDO    = mix(ALBEDO,    vec3(0.92, 0.93, 0.96), snow_on * 0.65);
		ROUGHNESS = mix(ROUGHNESS, 0.90,                   snow_on * 0.5);
	}

	// Backlight / subsurface scattering — stronger at blade tips
	// Light passing through thin grass blade tips creates warm glow
	BACKLIGHT = col * mix(0.15, 0.50, blade_t);
}
