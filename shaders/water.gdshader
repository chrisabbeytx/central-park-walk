shader_type spatial;
render_mode cull_disabled;

uniform sampler2D heightmap_tex : filter_nearest, repeat_disable;
uniform float hm_world_size = 5000.0;
uniform float hm_min_h      = 0.0;
uniform float hm_range      = 1.0;
uniform float hm_res        = 256.0;
uniform float water_y_offset = 0.03;
global uniform float rain_wetness;
global uniform vec3 sky_reflect_color;

varying vec3 world_pos;
varying float v_shore_dist;
varying float v_water_depth;

// Raindrop ripple rings — concentric circles from random impact points
float raindrop_ripple(vec2 p) {
	float t = TIME;
	float ripple = 0.0;
	for (int i = 0; i < 6; i++) {
		vec2 cell = floor(p * (1.5 + float(i) * 0.3)) + vec2(float(i) * 17.3, float(i) * 31.7);
		vec2 center = cell + vec2(fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453),
		                          fract(sin(dot(cell, vec2(269.5, 183.3))) * 43758.5453));
		float phase = fract(sin(dot(cell, vec2(113.5, 271.9))) * 43758.5453) * 3.0;
		float age = fract(t * 0.4 + phase);
		float dist = length(p * (1.5 + float(i) * 0.3) - center);
		float ring = sin((dist - age * 3.0) * 18.0) * exp(-dist * 2.5) * (1.0 - age);
		ripple += ring * 0.15;
	}
	return ripple;
}

#include "res://shaders/include/decode_terrain.gdshaderinc"

// Gradient noise (returns -1..1)
vec2 ghash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453) * 2.0 - 1.0;
}
float gnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(ghash(i),          f),
	               dot(ghash(i+vec2(1,0)), f-vec2(1,0)), u.x),
	           mix(dot(ghash(i+vec2(0,1)), f-vec2(0,1)),
	               dot(ghash(i+vec2(1,1)), f-vec2(1,1)), u.x), u.y);
}

// World-space wave normal from three overlapping noise layers
vec3 wave_normal(vec2 uv) {
	float t  = TIME;
	vec2 o1  = vec2( t * 0.08,  t * 0.05);   // slow drift
	vec2 o2  = vec2(-t * 0.12,  t * 0.09);   // medium ripples
	vec2 o3  = vec2( t * 0.18, -t * 0.14);   // fine detail
	float e  = 0.04;
	float h   = gnoise(uv * 0.7 + o1) * 0.4
	          + gnoise(uv * 1.8 + o2) * 0.35
	          + gnoise(uv * 4.5 + o3) * 0.25;
	float hx  = gnoise((uv + vec2(e, 0.0)) * 0.7 + o1) * 0.4
	          + gnoise((uv + vec2(e, 0.0)) * 1.8 + o2) * 0.35
	          + gnoise((uv + vec2(e, 0.0)) * 4.5 + o3) * 0.25;
	float hz  = gnoise((uv + vec2(0.0, e)) * 0.7 + o1) * 0.4
	          + gnoise((uv + vec2(0.0, e)) * 1.8 + o2) * 0.35
	          + gnoise((uv + vec2(0.0, e)) * 4.5 + o3) * 0.25;
	return normalize(vec3(-(hx - h) / e * 0.20, 1.0, -(hz - h) / e * 0.20));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Clamp water Y so it never pokes below the terrain surface
	float terrain_h = sample_terrain(w.xz) + water_y_offset;
	if (w.y < terrain_h) {
		vec3 snapped = (inverse(MODEL_MATRIX) * vec4(w.x, terrain_h, w.z, 1.0)).xyz;
		VERTEX.y = snapped.y;
		w.y = terrain_h;
	}
	world_pos = w;
	// Shore softening: sample terrain at 4 neighboring points
	float step_d = 3.0;
	float t_n = sample_terrain(w.xz + vec2(0.0, -step_d));
	float t_s = sample_terrain(w.xz + vec2(0.0,  step_d));
	float t_e = sample_terrain(w.xz + vec2( step_d, 0.0));
	float t_w = sample_terrain(w.xz + vec2(-step_d, 0.0));
	float max_neighbor = max(max(t_n, t_s), max(t_e, t_w));
	v_shore_dist = max(0.0, w.y - max_neighbor) * 3.0 + 0.5;
	if (max_neighbor > w.y) { v_shore_dist = max(0.0, w.y - max_neighbor + 0.5); }
	// Depth tinting
	float bed_h = sample_terrain(w.xz);
	v_water_depth = max(0.0, w.y - bed_h);
}

void fragment() {
	vec2 uv      = world_pos.xz / 12.0;   // natural wave scale
	vec3 wave_nrm = wave_normal(uv);

	// Three noise layers at different scales for natural variation
	float t = TIME;
	float n_large = gnoise(uv * 0.4 + vec2(t * 0.06, t * 0.04));
	float n_med   = gnoise(uv * 1.2 + vec2(-t * 0.1, t * 0.08));
	float n_fine  = gnoise(uv * 3.5 + vec2(t * 0.15, -t * 0.12));
	float wave_h  = n_large * 0.4 + n_med * 0.35 + n_fine * 0.25;

	vec3 deep    = vec3(0.020, 0.038, 0.028);   // dark olive-green (Central Park lakes)
	vec3 shallow = vec3(0.050, 0.075, 0.045);   // slightly warmer shallow
	float extra_reflect = 0.0;

	// Per-water-body character based on world position
	// Conservatory Water (Model Boat Pond): shallow formal reflecting pool
	float d_conserv = length(world_pos.xz - vec2(-152.0, 958.0));
	if (d_conserv < 80.0) {
		deep    = vec3(0.035, 0.050, 0.045);   // lighter, blue-gray
		shallow = vec3(0.065, 0.085, 0.075);
		extra_reflect = 0.15;
	}
	// Turtle Pond: shallow, murky, dark green-brown
	float d_turtle = length(world_pos.xz - vec2(-213.0, 374.0));
	if (d_turtle < 120.0) {
		deep    = vec3(0.018, 0.030, 0.020);   // darker, murkier
		shallow = vec3(0.040, 0.055, 0.035);
	}
	// Reservoir: large, open, more reflective blue
	float d_reserv = length(world_pos.xz - vec2(282.0, -424.0));
	if (d_reserv < 500.0) {
		deep    = vec3(0.015, 0.030, 0.035);   // blue-tinted deep
		shallow = vec3(0.040, 0.065, 0.070);
		extra_reflect = 0.10;
	}
	// Harlem Meer: large, dark green-blue, reflective
	float d_meer = length(world_pos.xz - vec2(1132.0, -1494.0));
	if (d_meer < 250.0) {
		deep    = vec3(0.015, 0.032, 0.032);
		shallow = vec3(0.040, 0.060, 0.058);
		extra_reflect = 0.08;
	}
	// The Pool (North Woods): secluded, dark, tree-shadowed
	float d_pool = length(world_pos.xz - vec2(-400.0, -1100.0));
	if (d_pool < 80.0) {
		deep    = vec3(0.012, 0.025, 0.018);   // very dark, canopy-shadowed
		shallow = vec3(0.030, 0.048, 0.032);
	}
	// The Lake (main): classic Central Park, moderate reflectivity
	float d_lake = length(world_pos.xz - vec2(-420.0, 740.0));
	if (d_lake < 250.0) {
		deep    = vec3(0.018, 0.034, 0.028);   // natural dark green
		shallow = vec3(0.045, 0.065, 0.050);
		extra_reflect = 0.05;
	}

	// Subtle blend — mostly deep, shallow only at wave peaks
	vec3 base_col = mix(deep, shallow, smoothstep(-0.3, 0.6, wave_h));

	// Rain ripples — concentric ring disturbance when raining
	if (rain_wetness > 0.01) {
		float rr = raindrop_ripple(world_pos.xz / 6.0);
		float e = 0.02;
		float rr_dx = raindrop_ripple((world_pos.xz + vec2(e, 0.0)) / 6.0);
		float rr_dz = raindrop_ripple((world_pos.xz + vec2(0.0, e)) / 6.0);
		vec3 ripple_n = normalize(vec3(
			-(rr_dx - rr) / e * 0.3,
			1.0,
			-(rr_dz - rr) / e * 0.3
		));
		wave_nrm = normalize(mix(wave_nrm, ripple_n, rain_wetness * 0.6));
	}

	NORMAL    = normalize((VIEW_MATRIX * vec4(wave_nrm, 0.0)).xyz);

	// Fresnel — glancing angles reflect sky (color tracks time of day)
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);
	vec3 sky_col = sky_reflect_color;
	vec3 col = mix(base_col, sky_col, fresnel * (0.6 + extra_reflect));

	// Foam — white caps at wave peaks (subtle in ponds, more on reservoir)
	float foam = smoothstep(0.6, 0.85, wave_h);
	col = mix(col, vec3(0.85, 0.90, 0.92), foam * 0.7);

	ALBEDO    = col;
	ROUGHNESS = mix(0.12, 0.02, fresnel);
	METALLIC  = 0.05;
	SPECULAR  = 0.5;
	// Shore softening — fade alpha near edges
	ALPHA     = smoothstep(0.0, 1.5, v_shore_dist);
}
