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
	// Gravel aggregate: fine-scale stippling on flat tar roofs
	float gravel = hash2(floor(world_pos.xz * 15.0));
	col *= (0.95 + gravel * 0.10);
	rough += gravel * 0.04;
	// Tar seam lines running roughly east-west
	float seam = smoothstep(0.42, 0.48, fract(world_pos.z * 0.25 + bld_hash * 5.0));
	col *= mix(1.0, 0.85, seam * 0.3);

	// HVAC equipment shadows: rectangular darker patches (roof machinery footprints)
	// ~50% of buildings have visible rooftop equipment
	float equip_hash = fract(bld_hash * 11.3);
	if (equip_hash < 0.50) {
		// Equipment positioned at hash-determined location on roof
		vec2 equip_center = vec2(fract(bld_hash * 5.7), fract(bld_hash * 8.9)) * 0.6 + 0.2;
		vec2 local_uv = fract(world_pos.xz * 0.04 + bld_hash * 10.0);
		vec2 d = abs(local_uv - equip_center);
		float equip_size = 0.06 + equip_hash * 0.08;
		float equip_mask = step(d.x, equip_size) * step(d.y, equip_size * 0.7);
		// Equipment is slightly lighter (silver/gray metal units)
		col = mix(col, col * 1.15 + vec3(0.02), equip_mask * 0.4);
		rough = mix(rough, 0.70, equip_mask * 0.3);
	}

	// Roof edge staining: drainage lines darken the perimeter
	// Water runs toward edges and stains the tar darker over years
	float edge_noise = vnoise(world_pos.xz * 0.8);
	float edge_dark = smoothstep(0.4, 0.2, edge_noise) * 0.06;
	col *= (1.0 - edge_dark);

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
