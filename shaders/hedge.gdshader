shader_type spatial;

// Seasonal hedge foliage — green in summer, brown/bare in winter
global uniform float season_t;
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform vec2 wind_vec;

#include "res://shaders/include/hash_noise.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Wind sway: hedges rustle gently in wind, stiffer than grass
	float sway = max(VERTEX.y, 0.0);
	float wind_str = length(wind_vec);
	float flex = 0.15;  // much stiffer than grass (trimmed, dense)

	// Base rustle: continuous small oscillation
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float px = origin.x * 0.12 + origin.z * 0.18;
	VERTEX.x += sin(TIME * 1.2 + px) * 0.03 * sway * (0.2 + wind_str * 0.8) * flex;
	VERTEX.z += sin(TIME * 1.7 + origin.z * 0.15) * 0.02 * sway * (0.2 + wind_str * 0.8) * flex;

	// Wind push: constant lean in wind direction
	VERTEX.x += wind_vec.x * sway * 0.08 * flex;
	VERTEX.z += wind_vec.y * sway * 0.08 * flex;
}

void fragment() {
	// Per-bush variation from world position
	float var_h = hash2(floor(world_pos.xz * 0.3));

	// Base foliage color — dark boxwood green
	vec3 summer_col = vec3(0.14, 0.30, 0.10) * (0.85 + var_h * 0.30);
	// Spring: bright fresh green with yellow-green highlights
	vec3 spring_col = vec3(0.22, 0.40, 0.14) * (0.85 + var_h * 0.30);
	// Autumn: some hedges stay green, others bronze
	vec3 autumn_col = mix(
		vec3(0.18, 0.28, 0.10),   // still mostly green
		vec3(0.30, 0.22, 0.10),   // bronzed
		var_h * 0.5
	) * (0.85 + fract(var_h * 3.7) * 0.30);
	// Winter: bare brown twigs, dull gray-brown
	vec3 winter_col = vec3(0.22, 0.18, 0.12) * (0.80 + var_h * 0.30);

	// Seasonal blend (season_t: 0=spring, 1=summer, 2=autumn, 3=winter)
	float spring_f = smoothstep(1.0, 0.0, season_t) + smoothstep(3.5, 4.0, season_t);
	spring_f = clamp(spring_f, 0.0, 1.0);
	float summer_f = smoothstep(0.5, 1.5, season_t) * smoothstep(2.0, 1.0, season_t);
	float autumn_f = smoothstep(1.5, 2.5, season_t) * smoothstep(3.5, 2.5, season_t);
	float winter_f = smoothstep(2.5, 3.5, season_t);

	vec3 col = summer_col;
	col = mix(col, spring_col, spring_f);
	col = mix(col, autumn_col, autumn_f);
	col = mix(col, winter_col, winter_f);

	// Leaf texture noise — small-scale variation for foliage look
	float leaf_noise = vnoise(world_pos.xz * 8.0 + world_pos.yy * 4.0);
	col *= (0.88 + leaf_noise * 0.24);

	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.75, summer_f);  // glossier leaves in summer
	METALLIC = 0.0;

	// Rain: wet foliage darkens, gets glossy
	if (rain_wetness > 0.01) {
		float wet = rain_wetness;
		ALBEDO *= mix(1.0, 0.70, wet);
		ROUGHNESS = mix(ROUGHNESS, 0.25, wet);
		SPECULAR = mix(0.0, 0.35, wet);
	}

	// Snow on top surfaces
	if (snow_cover > 0.01) {
		vec3 world_n = mat3(INV_VIEW_MATRIX) * NORMAL;
		float upward = max(world_n.y, 0.0);
		if (upward > 0.5) {
			float sn = hash2(floor(world_pos.xz * 3.0)) * 0.2;
			float snow_amt = clamp((upward + sn - 0.3) * snow_cover, 0.0, 1.0);
			ALBEDO = mix(ALBEDO, vec3(0.90, 0.91, 0.94), snow_amt * 0.75);
			ROUGHNESS = mix(ROUGHNESS, 0.90, snow_amt);
		}
	}

	// Subsurface scattering: light passing through outer hedge leaves
	// Green glow visible when sun is behind the hedge
	float sss_strength = mix(0.10, 0.30, summer_f);  // stronger in summer (more leaves)
	sss_strength *= (1.0 - winter_f * 0.8);  // minimal in winter (bare)
	BACKLIGHT = col * sss_strength;

	// Subtle emission for visibility in shadow
	EMISSION = ALBEDO * 0.15;
}
