shader_type spatial;
render_mode cull_disabled;

uniform sampler2D tex_alb : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_nrm : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D heightmap_tex : filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float hm_world_size = 5000.0;
uniform float hm_min_h      = 0.0;
uniform float hm_range      = 1.0;
uniform float hm_res        = 256.0;
uniform float path_y_offset = 0.08;
uniform float snap_to_terrain = 1.0;  // 0.0 for bridge decks (pre-elevated)
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform float season_t;
global uniform vec3 sky_reflect_color;

#include "res://shaders/include/decode_terrain.gdshaderinc"

varying flat float depth_jitter;
varying vec3 world_pos;

#include "res://shaders/include/hash_noise.gdshaderinc"

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (snap_to_terrain > 0.5) {
		float terrain_h = sample_terrain(world.xz);
		vec3 snapped = (inverse(MODEL_MATRIX) * vec4(world.x, terrain_h + path_y_offset, world.z, 1.0)).xyz;
		VERTEX.y = snapped.y;
	}
	world_pos = world;
	// Per-triangle depth jitter to break z-fighting at same-type intersections
	depth_jitter = hash2(floor(world.xz * 0.5)) * 0.0003;
}

void fragment() {
	vec3  alb   = texture(tex_alb, UV).rgb;
	float rough = texture(tex_rgh, UV).r;
	ALBEDO     = alb * tint.rgb * COLOR.rgb;
	NORMAL_MAP = texture(tex_nrm, UV).rgb;
	ROUGHNESS  = clamp(rough + 0.10, 0.0, 1.0);
	METALLIC   = 0.0;
	SPECULAR   = 0.06;  // matte paving default

	// Seasonal path appearance
	// Autumn: scattered leaf litter on paths, warmer tint
	float autumn_t = smoothstep(2.0, 2.6, season_t) * (1.0 - smoothstep(3.3, 3.8, season_t));
	if (autumn_t > 0.01) {
		// Leaf debris: small brown/amber patches on pavement
		float leaf_noise = hash2(floor(UV * 40.0));
		float leaf_mask = step(0.85, leaf_noise) * autumn_t;
		vec3 leaf_col = mix(vec3(0.45, 0.28, 0.10), vec3(0.58, 0.32, 0.12), leaf_noise);
		ALBEDO = mix(ALBEDO, leaf_col, leaf_mask * 0.5);
		// Overall warmer tint from tannin staining
		ALBEDO *= mix(vec3(1.0), vec3(1.04, 0.98, 0.90), autumn_t * 0.3);
	}
	// Winter: paths look grayer, salt stains, slightly lighter
	float winter_t = smoothstep(2.8, 3.5, season_t);
	if (winter_t > 0.01) {
		// Road salt residue: lighter streaks on pavement
		float salt_noise = hash2(floor(UV * 20.0));
		float salt_mask = step(0.8, salt_noise) * winter_t;
		ALBEDO = mix(ALBEDO, ALBEDO * 1.25 + vec3(0.06), salt_mask * 0.3);
		// Overall cooler, grayer
		float path_lum = dot(ALBEDO, vec3(0.33));
		ALBEDO = mix(ALBEDO, vec3(path_lum) * 1.05, winter_t * 0.2);
	}

	// Rain: wet pavement darkens, gets glossy, puddles form in low spots
	if (rain_wetness > 0.01) {
		ALBEDO   *= mix(1.0, 0.60, rain_wetness);   // 40% darker when wet
		ROUGHNESS = mix(ROUGHNESS, 0.08, rain_wetness);
		SPECULAR  = mix(SPECULAR, 0.45, rain_wetness);
		// Puddles: collect in low-frequency noise depressions
		// Visible at moderate-to-heavy rain, mirror-like reflection of sky
		if (rain_wetness > 0.3) {
			float puddle_noise = vnoise(world_pos.xz * 0.12);
			puddle_noise += vnoise(world_pos.xz * 0.35) * 0.4;
			float puddle = smoothstep(0.35, 0.55, puddle_noise) * smoothstep(0.3, 0.7, rain_wetness);
			if (puddle > 0.01) {
				// Puddle surface: near-mirror reflecting sky color
				vec3 puddle_col = sky_reflect_color * 0.4 + ALBEDO * 0.15;
				// Night: puddles reflect warm city light instead
				float sky_lum = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
				float night_t = smoothstep(0.15, 0.02, sky_lum);
				puddle_col = mix(puddle_col, vec3(0.10, 0.07, 0.04) + ALBEDO * 0.08, night_t);
				ALBEDO    = mix(ALBEDO, puddle_col, puddle);
				ROUGHNESS = mix(ROUGHNESS, 0.02, puddle);  // mirror-smooth
				SPECULAR  = mix(SPECULAR, 0.60, puddle);
				METALLIC  = mix(METALLIC, 0.10, puddle);
			}
		}
	}

	// Snow accumulation on paths
	if (snow_cover > 0.01) {
		vec3 world_n = mat3(INV_VIEW_MATRIX) * NORMAL;
		float upward = max(world_n.y, 0.0);
		float snow_amt = snow_cover * smoothstep(0.3, 0.8, upward);
		ALBEDO    = mix(ALBEDO, vec3(0.90, 0.91, 0.94), snow_amt * 0.85);
		ROUGHNESS = mix(ROUGHNESS, 0.70, snow_amt);
		SPECULAR  = mix(SPECULAR, 0.15, snow_amt);
		// Snow sparkle on paths
		if (snow_amt > 0.3) {
			float sparkle = hash2(floor(world_pos.xz * 25.0));
			if (sparkle > 0.96) {
				float si = (sparkle - 0.96) * 25.0;
				SPECULAR = mix(SPECULAR, 0.90, si * snow_amt);
				ROUGHNESS = mix(ROUGHNESS, 0.05, si * snow_amt * 0.4);
			}
		}
	}

	DEPTH = FRAGCOORD.z - depth_jitter;
}
