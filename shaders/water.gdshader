shader_type spatial;
render_mode cull_disabled;

uniform sampler2D heightmap_tex : filter_nearest, repeat_disable;
uniform float hm_world_size = 5000.0;
uniform float hm_min_h      = 0.0;
uniform float hm_range      = 1.0;
uniform float hm_res        = 256.0;
uniform float water_y_offset = 0.03;
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform vec3 sky_reflect_color;
global uniform float season_t;
global uniform vec2 wind_vec;

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
// Wind biases wave direction and increases amplitude
vec3 wave_normal(vec2 uv) {
	float t  = TIME;
	float wind_str = length(wind_vec);
	// Wind pushes wave drift direction
	vec2 wind_dir = wind_str > 0.01 ? normalize(wind_vec) : vec2(0.0);
	vec2 wind_push = wind_dir * wind_str * 0.06;
	vec2 o1  = vec2( t * 0.08,  t * 0.05)  + wind_push * 1.2;   // slow drift
	vec2 o2  = vec2(-t * 0.12,  t * 0.09)  + wind_push * 0.8;   // medium ripples
	vec2 o3  = vec2( t * 0.18, -t * 0.14)  + wind_push * 0.4;   // fine detail
	float e  = 0.04;
	// Wind increases wave amplitude (calm = 0.20, strong = 0.40 normal strength)
	float amp = 0.20 + wind_str * 0.10;
	float h   = gnoise(uv * 0.7 + o1) * 0.4
	          + gnoise(uv * 1.8 + o2) * 0.35
	          + gnoise(uv * 4.5 + o3) * 0.25;
	float hx  = gnoise((uv + vec2(e, 0.0)) * 0.7 + o1) * 0.4
	          + gnoise((uv + vec2(e, 0.0)) * 1.8 + o2) * 0.35
	          + gnoise((uv + vec2(e, 0.0)) * 4.5 + o3) * 0.25;
	float hz  = gnoise((uv + vec2(0.0, e)) * 0.7 + o1) * 0.4
	          + gnoise((uv + vec2(0.0, e)) * 1.8 + o2) * 0.35
	          + gnoise((uv + vec2(0.0, e)) * 4.5 + o3) * 0.25;
	return normalize(vec3(-(hx - h) / e * amp, 1.0, -(hz - h) / e * amp));
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
	// Shore softening: fade water alpha where terrain is close to or above water level.
	// Sample terrain at this vertex and at 4 neighbors. Use the maximum terrain height
	// to detect shore proximity — if any nearby terrain rises to water level, we're
	// near the shore and should start fading.
	float bed_h = sample_terrain(w.xz);
	float step_d = 2.0;
	float t_n = sample_terrain(w.xz + vec2(0.0, -step_d));
	float t_s = sample_terrain(w.xz + vec2(0.0,  step_d));
	float t_e = sample_terrain(w.xz + vec2( step_d, 0.0));
	float t_w = sample_terrain(w.xz + vec2(-step_d, 0.0));
	float max_neighbor = max(max(t_n, t_s), max(t_e, t_w));
	// How far below the water surface is the terrain here?
	// depth > 0 = water is deep, depth ≈ 0 = shore edge
	float depth_here = w.y - bed_h;
	float depth_neighbor = w.y - max_neighbor;
	// Shore dist: blend of local depth and neighbor depth.
	// Use the shallower of the two — if ANY measurement says "shore", fade.
	v_shore_dist = min(depth_here, depth_neighbor);
	// Depth tinting
	v_water_depth = max(0.0, depth_here);
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
	float d_pool = length(world_pos.xz - vec2(394.0, -1311.0));
	if (d_pool < 100.0) {
		deep    = vec3(0.012, 0.025, 0.018);   // very dark, canopy-shadowed
		shallow = vec3(0.030, 0.048, 0.032);
	}
	// The Lake (main): classic Central Park, moderate reflectivity
	float d_lake = length(world_pos.xz - vec2(-522.0, 694.0));
	if (d_lake < 300.0) {
		deep    = vec3(0.018, 0.034, 0.028);   // natural dark green
		shallow = vec3(0.045, 0.065, 0.050);
		extra_reflect = 0.05;
	}
	// The Pond (59th St): formal, shallow, clear, near Columbus Circle
	float d_pond = length(world_pos.xz - vec2(-764.0, 1829.0));
	if (d_pond < 100.0) {
		deep    = vec3(0.025, 0.040, 0.035);   // clearer than most
		shallow = vec3(0.050, 0.070, 0.060);
		extra_reflect = 0.10;  // reflecting nearby skyscrapers
	}
	// Azalea Pond (Ramble): small, secluded, tree-shadowed
	float d_azalea = length(world_pos.xz - vec2(-358.0, 645.0));
	if (d_azalea < 50.0) {
		deep    = vec3(0.012, 0.025, 0.018);   // very dark, canopy-filtered
		shallow = vec3(0.028, 0.042, 0.030);
	}

	// Seasonal water color shifts
	// Spring (0): clear, slightly green from algae bloom
	// Summer (1): base colors (tuned above)
	// Autumn (2): brown-amber tint from leaf tannins
	// Winter (3): lighter, grayer, less saturated
	float autumn_t = smoothstep(1.5, 2.5, season_t) * smoothstep(3.5, 2.5, season_t);
	float winter_t = smoothstep(2.5, 3.5, season_t);
	float spring_t = smoothstep(1.0, 0.0, season_t) + smoothstep(3.5, 4.0, season_t);
	spring_t = clamp(spring_t, 0.0, 1.0);
	if (autumn_t > 0.01) {
		// Fallen leaves leach tannins: amber-brown tint
		deep    = mix(deep,    deep    * vec3(1.15, 0.95, 0.70), autumn_t * 0.4);
		shallow = mix(shallow, shallow * vec3(1.20, 0.95, 0.65), autumn_t * 0.4);
	}
	if (winter_t > 0.01) {
		// Cold water: desaturated, slightly lighter, gray shift
		float d_lum = dot(deep, vec3(0.33));
		float s_lum = dot(shallow, vec3(0.33));
		deep    = mix(deep,    vec3(d_lum) * 1.15, winter_t * 0.3);
		shallow = mix(shallow, vec3(s_lum) * 1.15, winter_t * 0.3);
	}
	if (spring_t > 0.01) {
		// Spring algae bloom: green boost, more visible in shallow warm areas
		deep    = mix(deep,    deep    * vec3(0.85, 1.18, 0.78), spring_t * 0.30);
		shallow = mix(shallow, shallow * vec3(0.82, 1.22, 0.75), spring_t * 0.35);
	}
	// Summer peak algae: July-August warmth drives chlorophyll
	float summer_t = smoothstep(0.5, 1.2, season_t) * smoothstep(2.0, 1.2, season_t);
	if (summer_t > 0.01) {
		// Warm stagnant water gets greener, especially shallow edges
		deep    = mix(deep,    deep    * vec3(0.88, 1.12, 0.82), summer_t * 0.20);
		shallow = mix(shallow, shallow * vec3(0.80, 1.25, 0.72), summer_t * 0.30);
	}

	// Depth tinting: deeper water is darker and more saturated
	float depth_t = smoothstep(0.0, 2.5, v_water_depth);
	deep    = mix(shallow, deep, depth_t);

	// Subtle blend — mostly deep, shallow only at wave peaks
	vec3 base_col = mix(deep, shallow, smoothstep(-0.3, 0.6, wave_h));

	// Rain ripples — concentric ring disturbance when raining
	// Intensity scales with rain: gentle drizzle → heavy downpour
	if (rain_wetness > 0.01) {
		float ripple_scale = mix(0.3, 1.0, rain_wetness);  // gentle at low rain, full at heavy
		float rr = raindrop_ripple(world_pos.xz / 6.0) * ripple_scale;
		float e = 0.02;
		float rr_dx = raindrop_ripple((world_pos.xz + vec2(e, 0.0)) / 6.0) * ripple_scale;
		float rr_dz = raindrop_ripple((world_pos.xz + vec2(0.0, e)) / 6.0) * ripple_scale;
		vec3 ripple_n = normalize(vec3(
			-(rr_dx - rr) / e * 0.3,
			1.0,
			-(rr_dz - rr) / e * 0.3
		));
		wave_nrm = normalize(mix(wave_nrm, ripple_n, rain_wetness * 0.6));
	}

	NORMAL    = normalize((VIEW_MATRIX * vec4(wave_nrm, 0.0)).xyz);

	// Fresnel — glancing angles reflect sky (color tracks time of day)
	// Power 3.0 (not 4.0) for gentler ramp — water has visible reflection even at moderate angles
	// Minimum floor 0.04: real water reflects ~2-4% at normal incidence (Schlick)
	float fresnel = max(pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0), 0.04);
	vec3 sky_col = sky_reflect_color;

	// Night city reflection: when sky is very dark, water reflects city light pollution
	// NYC skyline reflecting in Central Park water is iconic
	float sky_lum = dot(sky_col, vec3(0.2126, 0.7152, 0.0722));
	float night_boost = smoothstep(0.15, 0.02, sky_lum);  // 1.0 at night
	if (night_boost > 0.01) {
		// Warm amber city glow reflected in water — brighter, more vivid
		vec3 city_reflect = vec3(0.16, 0.10, 0.05);
		// Directional: west side (CPW) is residential high-rises, warm yellow windows
		// East side (5th Ave) is commercial, cooler white-blue
		float west_bias = smoothstep(0.0, -600.0, world_pos.x);  // west edge of park
		float east_bias = smoothstep(0.0, 600.0, world_pos.x);    // east edge
		city_reflect += vec3(0.04, 0.03, 0.01) * west_bias;       // warmer west
		city_reflect += vec3(0.02, 0.02, 0.03) * east_bias;       // cooler east
		// Distance from park edges increases reflected light
		float edge_factor = abs(world_pos.x) / 1000.0;
		city_reflect *= (1.0 + clamp(edge_factor, 0.0, 1.0) * 0.6);
		sky_col += city_reflect * night_boost;
		// Window sparkle: bright warm points dancing on wave crests
		float sparkle = gnoise(world_pos.xz * 0.3 + vec2(TIME * 0.02, 0.0));
		sparkle = smoothstep(0.6, 0.9, sparkle) * night_boost * 0.10;
		sky_col += vec3(1.0, 0.72, 0.32) * sparkle;
		// Occasional cool-white sparkle (modern buildings)
		float sparkle2 = gnoise(world_pos.xz * 0.45 + vec2(-TIME * 0.015, TIME * 0.01));
		sparkle2 = smoothstep(0.7, 0.95, sparkle2) * night_boost * 0.05;
		sky_col += vec3(0.70, 0.80, 1.0) * sparkle2;
	}

	// Golden hour water: warm orange-gold reflection during sunset/sunrise
	// Detect golden hour from sky_reflect_color warmth (warm R > cool B)
	float sky_warmth = sky_reflect_color.r - sky_reflect_color.b;
	float golden_w = smoothstep(0.05, 0.20, sky_warmth) * smoothstep(0.02, 0.10, sky_lum);
	if (golden_w > 0.01) {
		// Warm amber-gold amplified by fresnel at glancing angles
		vec3 golden_reflect = sky_reflect_color * vec3(1.10, 0.85, 0.65);
		float golden_path = fresnel * golden_w * 0.20;
		sky_col += golden_reflect * golden_path;
	}

	vec3 col = mix(base_col, sky_col, fresnel * (0.6 + extra_reflect));

	// Caustics: light dappling in shallow clear water during daytime
	// Sunlight refracting through wave surface creates bright dancing patterns on bed
	float caustic = 0.0;
	float daytime = 1.0 - night_boost;
	if (daytime > 0.1 && v_water_depth < 1.5) {
		float shallow_factor = 1.0 - smoothstep(0.0, 1.5, v_water_depth);
		// Two overlapping caustic layers at different scales/speeds
		float c1 = gnoise(world_pos.xz * 1.8 + vec2(t * 0.12, t * 0.08));
		float c2 = gnoise(world_pos.xz * 2.5 + vec2(-t * 0.15, t * 0.11));
		caustic = (c1 + c2) * 0.5;
		caustic = smoothstep(0.1, 0.5, caustic) * shallow_factor * daytime * 0.12;
		// Rain disrupts caustics (turbid water)
		caustic *= (1.0 - rain_wetness * 0.7);
		col += vec3(caustic * 1.1, caustic, caustic * 0.8);
	}

	// Foam — white caps at wave peaks (subtle in ponds, more on reservoir)
	// Wind increases foam: lower threshold, more visible caps
	float wind_str = length(wind_vec);
	float foam_thresh = mix(0.6, 0.35, clamp(wind_str, 0.0, 2.0) * 0.5);
	float foam = smoothstep(foam_thresh, foam_thresh + 0.25, wave_h);
	float foam_vis = night_boost > 0.5 ? 0.3 : 0.7;  // less visible foam at night
	foam_vis *= (1.0 + wind_str * 0.3);  // wind makes foam more prominent
	col = mix(col, vec3(0.85, 0.90, 0.92), foam * min(foam_vis, 1.0));

	ALBEDO    = col;
	ROUGHNESS = mix(0.12, 0.02, fresnel);
	METALLIC  = 0.15;   // enough for SSR to pick up building/tree reflections
	SPECULAR  = 0.5 + night_boost * 0.2;

	// Winter ice — shallow edges freeze first, center stays open longer
	// Central Park water bodies partially freeze in deep winter
	if (winter_t > 0.3 && snow_cover > 0.1) {
		// Ice forms from shores inward: shallow areas freeze first
		float freeze = smoothstep(0.3, 0.8, winter_t) * smoothstep(0.1, 0.6, snow_cover);
		// Shallow edges freeze before deep center
		float depth_resist = smoothstep(0.0, 1.5, v_water_depth);
		float ice_mask = freeze * (1.0 - depth_resist * 0.6);
		// Noise breaks up ice edge naturally
		float ice_noise = gnoise(world_pos.xz * 0.15) * 0.3;
		ice_mask = smoothstep(0.2, 0.6, ice_mask + ice_noise);
		if (ice_mask > 0.01) {
			// Ice color: pale blue-white with slight translucency
			vec3 ice_col = mix(vec3(0.72, 0.78, 0.84), vec3(0.82, 0.86, 0.90), gnoise(world_pos.xz * 0.4) * 0.5 + 0.5);
			// Snow dusting on top of ice
			if (snow_cover > 0.4) {
				float snow_noise = gnoise(world_pos.xz * 0.25 + vec2(17.3)) * 0.5 + 0.5;
				float snow_on_ice = smoothstep(0.3, 0.7, snow_noise) * smoothstep(0.4, 0.8, snow_cover);
				ice_col = mix(ice_col, vec3(0.90, 0.91, 0.94), snow_on_ice * 0.6);
			}
			ALBEDO = mix(ALBEDO, ice_col, ice_mask);
			ROUGHNESS = mix(ROUGHNESS, 0.35, ice_mask);  // ice is somewhat smooth
			SPECULAR = mix(SPECULAR, 0.25, ice_mask);
			// Flatten normal on ice (no waves)
			vec3 flat_n = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
			NORMAL = mix(NORMAL, flat_n, ice_mask * 0.85);
		}
	}

	// Shore softening — fade alpha where water is shallow near shore.
	// v_shore_dist = depth below water surface at this vertex (metres).
	// Fade quickly: min 0.3 opacity prevents terrain checkerboard in shallow ponds
	// (Conservatory Water, Turtle Pond). Only fully transparent right at the shore edge.
	float shore_alpha = smoothstep(-0.05, 0.25, v_shore_dist);
	ALPHA = max(shore_alpha, smoothstep(-0.15, -0.05, v_shore_dist) * 0.5);
}
