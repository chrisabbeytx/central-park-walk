shader_type spatial;
render_mode cull_disabled;

// Building roof surfaces — flat tar roofs, copper, slate, stone
// Vertex color carries per-building roof tint
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform float season_t;

varying vec3 world_pos;

#include "res://shaders/include/hash_noise.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	float rough = 0.92;

	// Per-building variation: slight tint and roughness shift
	float bld_hash = hash2(floor(world_pos.xz * 0.015));
	col *= (0.92 + bld_hash * 0.16);
	rough += (bld_hash - 0.5) * 0.06;

	// Surface texture: tar paper seams, gravel aggregate
	float tex_noise = vnoise(world_pos.xz * 3.0);
	col *= (0.94 + tex_noise * 0.12);
	// Tar seam lines running roughly east-west
	float seam = smoothstep(0.42, 0.48, fract(world_pos.z * 0.25 + bld_hash * 5.0));
	col *= mix(1.0, 0.85, seam * 0.3);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.06;

	// Rain: wet roofs darken significantly, become reflective
	if (rain_wetness > 0.01) {
		ALBEDO *= mix(1.0, 0.55, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.04, rain_wetness);
		SPECULAR = mix(SPECULAR, 0.50, rain_wetness);
		// Standing water puddles on flat roofs
		if (rain_wetness > 0.4) {
			float puddle = vnoise(world_pos.xz * 0.2);
			puddle = smoothstep(0.3, 0.5, puddle) * smoothstep(0.4, 0.8, rain_wetness);
			ROUGHNESS = mix(ROUGHNESS, 0.01, puddle);
			SPECULAR = mix(SPECULAR, 0.65, puddle);
			ALBEDO = mix(ALBEDO, ALBEDO * 0.5, puddle);
		}
	}

	// Snow accumulation — roofs are flat, so snow accumulates readily
	if (snow_cover > 0.01) {
		float snow_noise = vnoise(world_pos.xz * 0.15) * 0.2;
		float snow_amt = clamp(snow_cover + snow_noise, 0.0, 1.0);
		// Snow is uneven: some areas swept by wind, others piled
		float wind_clear = vnoise(world_pos.xz * 0.06);
		snow_amt *= smoothstep(0.2, 0.5, wind_clear);
		ALBEDO = mix(ALBEDO, vec3(0.92, 0.93, 0.96), snow_amt * 0.85);
		ROUGHNESS = mix(ROUGHNESS, 0.80, snow_amt);
		SPECULAR = mix(SPECULAR, 0.15, snow_amt);
	}
}
