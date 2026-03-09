shader_type spatial;

uniform vec3 bark_color = vec3(0.48, 0.38, 0.28);
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform float season_t;

varying vec3 world_pos;
varying vec3 world_nrm;

#include "res://shaders/include/hash_noise.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Base bark color with per-tree variation from world position
	vec3 tree_base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float tree_var = hash2(floor(tree_base.xz * 0.5));
	vec3 col = bark_color * (0.90 + tree_var * 0.20);

	// Vertical bark texture streaks
	float streak = hash2(vec2(world_pos.x * 3.0 + world_pos.z * 2.0, world_pos.y * 8.0));
	col *= (0.90 + streak * 0.20);

	ALBEDO = col;
	ROUGHNESS = 0.90;
	METALLIC = 0.0;
	SPECULAR = 0.04;

	// Moss at trunk base — more in spring/summer, north-facing
	float spring_summer = smoothstep(0.0, 1.0, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
	float local_h = world_pos.y - tree_base.y;
	float moss_height = smoothstep(3.0, 0.0, local_h);  // bottom 3m of trunk
	float moss_facing = max(0.0, -world_nrm.z) * 0.5 + max(0.0, -world_nrm.x) * 0.3 + 0.2;
	float moss_noise = hash2(floor(world_pos.xz * 4.0 + world_pos.yy * 2.0));
	float moss = moss_height * moss_facing * step(0.4, moss_noise) * spring_summer;
	if (moss > 0.01) {
		vec3 moss_col = mix(vec3(0.10, 0.20, 0.06), vec3(0.16, 0.26, 0.08), moss_noise);
		ALBEDO = mix(ALBEDO, moss_col, moss * 0.35);
		ROUGHNESS = mix(ROUGHNESS, 0.95, moss * 0.3);
	}

	// Rain: wet bark darkens, gets slightly glossy
	if (rain_wetness > 0.01) {
		ALBEDO *= mix(1.0, 0.65, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.40, rain_wetness);
		SPECULAR = mix(SPECULAR, 0.25, rain_wetness);
		// Wet moss becomes vivid
		if (moss > 0.01) {
			ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.85, 1.20, 0.80), moss * rain_wetness * 0.3);
		}
	}

	// Snow on upward-facing bark and branch crotches
	if (snow_cover > 0.01) {
		float upward = max(world_nrm.y, 0.0);
		float snow_noise = hash2(floor(world_pos.xz * 5.0 + world_pos.yy * 3.0));
		float snow_amt = snow_cover * smoothstep(0.3, 0.7, upward + snow_noise * 0.3);
		ALBEDO = mix(ALBEDO, vec3(0.90, 0.91, 0.94), snow_amt * 0.7);
		ROUGHNESS = mix(ROUGHNESS, 0.85, snow_amt);
	}
}
