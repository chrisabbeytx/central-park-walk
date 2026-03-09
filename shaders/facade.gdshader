shader_type spatial;
render_mode cull_disabled;

// Wall surface — two modes controlled by use_brick:
//   use_brick=0: procedural wall with tint + facade texture blend
//   use_brick=1: direct brick/stone texture mapping
uniform float use_brick = 0.0;

// Shared textures (albedo, normal, roughness)
uniform sampler2D wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.5;

// Procedural mode uniforms
uniform vec3 wall_tint = vec3(0.78, 0.72, 0.62);
uniform float wall_rough = 0.88;
uniform float wall_metal = 0.0;

// Window parameters
uniform vec3 glass_a = vec3(0.10, 0.13, 0.16);
uniform vec3 glass_b = vec3(0.35, 0.48, 0.58);
uniform float glass_rough = 0.12;
uniform float glass_metal = 0.15;
uniform float win_w = 1.5;
uniform float win_h = 2.0;
uniform float gap_x = 0.6;
uniform float gap_y = 0.8;
uniform float ground_h = 3.5;
uniform float night_factor = 0.0;
uniform sampler2D win_gradient : source_color, filter_linear_mipmap;

varying vec3 world_pos;

float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Per-building hash for window size jitter + UV offset
	vec2 bld = floor(world_pos.xz * 0.03);
	float bld_hash = hash2(bld * 0.7);
	float actual_win_w = win_w * (0.8 + bld_hash * 0.4);
	float actual_gap_x = gap_x * (0.8 + fract(bld_hash * 7.3) * 0.4);
	float actual_win_h = win_h * (0.85 + fract(bld_hash * 3.1) * 0.3);

	// Per-building UV.x offset so adjacent buildings don't align
	float uv_offset = fract(bld_hash * 5.7) * (actual_win_w + actual_gap_x);

	float cell_w = actual_win_w + actual_gap_x;
	float cell_h = actual_win_h + gap_y;
	float shifted_u = UV.x + uv_offset;
	float lx = fract(shifted_u / cell_w);
	float ly = fract((UV.y - ground_h) / cell_h);

	// Window reveal border (fraction of cell for 0.08m dark inset on each side)
	float reveal_frac = 0.08 / cell_w;
	float reveal_frac_y = 0.08 / cell_h;
	float win_frac_x = actual_win_w / cell_w;
	float win_frac_y = actual_win_h / cell_h;

	// Ground floor: wider, darker storefront openings
	bool is_ground = UV.y < ground_h && UV.y > 0.5;
	float gnd_lx = fract(shifted_u / (cell_w * 1.5));
	bool gnd_win = is_ground && (gnd_lx < 0.65) && (UV.y > 1.2);

	bool in_win = ((lx < win_frac_x) && (ly < win_frac_y) && (UV.y > ground_h)) || gnd_win;

	// Window reveal depth — dark shadow border on window edges
	bool in_reveal = false;
	if (in_win && !gnd_win) {
		bool near_edge_x = (lx < reveal_frac) || (lx > win_frac_x - reveal_frac);
		bool near_edge_y = (ly < reveal_frac_y) || (ly > win_frac_y - reveal_frac_y);
		in_reveal = near_edge_x || near_edge_y;
	}

	// Per-floor ledge lines — thin horizontal band at each floor level
	float floor_pos = (UV.y - ground_h) / cell_h;
	float floor_frac = fract(floor_pos);
	bool is_ledge = (UV.y > ground_h) && (floor_frac < 0.03 || floor_frac > 0.97);

	// Cornice bands every 4 floors
	float floor_num = floor_pos;
	bool is_cornice = (UV.y > ground_h) && (fract(floor_num / 4.0) < 0.08);

	// Ground floor awning shadow — 40% of buildings (hash-based)
	bool has_awning = fract(bld_hash * 3.3) < 0.40;
	bool is_awning = has_awning && UV.y > (ground_h - 0.3) && UV.y < ground_h;

	vec2 cell_idx = vec2(floor(shifted_u / cell_w), floor((UV.y - ground_h) / cell_h));
	float wrand = hash2(bld * 0.5 + cell_idx * 0.13);

	vec3 emission = vec3(0.0);

	if (in_win) {
		vec3 win_col;
		if (gnd_win) {
			win_col = mix(glass_a * 0.7, glass_b * 0.6, wrand * 0.4);
		} else {
			win_col = mix(glass_a, glass_b, wrand * 0.6);
		}
		ROUGHNESS = glass_rough;
		METALLIC  = glass_metal;
		if (in_reveal) {
			win_col *= 0.35;
			ROUGHNESS = 0.6;
			METALLIC = 0.0;
		}
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
		NORMAL_MAP_DEPTH = 0.0;

		// Night window emission
		if (night_factor > 0.01 && !in_reveal) {
			// ~65% of windows lit, warm interior tones
			bool is_lit = wrand < 0.65;
			if (gnd_win) { is_lit = wrand < 0.80; }
			if (is_lit) {
				float warmth = fract(wrand * 7.3);
				vec3 warm_light = mix(vec3(1.0, 0.68, 0.28), vec3(1.0, 0.76, 0.40), warmth);
				if (fract(wrand * 13.7) < 0.10) {
					warm_light = vec3(0.35, 0.42, 0.58);
				}
				float em_strength = gnd_win ? 0.60 : 0.50;
				em_strength *= (0.6 + wrand * 0.5);
				vec2 win_uv = gnd_win
					? vec2(gnd_lx / 0.65, clamp((UV.y - 1.2) / (ground_h - 1.2), 0.0, 1.0))
					: vec2(lx / win_frac_x, ly / win_frac_y);
				vec3 grad = texture(win_gradient, vec2(win_uv.x, 1.0 - win_uv.y)).rgb;
				emission = warm_light * grad * em_strength * night_factor;
				win_col = warm_light * grad * 0.15;
				ROUGHNESS = 0.9;
				METALLIC = 0.0;
			}
		}
		ALBEDO = win_col;
	} else {
		vec2 tex_uv = UV * tex_scale;
		vec3 tex_col = texture(wall_albedo, tex_uv).rgb;
		vec3 tex_nrm = texture(wall_normal, tex_uv).rgb;
		float tex_rgh = texture(wall_roughness, tex_uv).r;

		vec3 wall_col;
		float final_rough;
		float final_metal;
		if (use_brick > 0.5) {
			// Brick/stone mode: direct texture * vertex color
			wall_col = tex_col * COLOR.rgb;
			final_rough = tex_rgh;
			final_metal = 0.0;
		} else {
			// Procedural mode: tint blended with facade texture
			float var_ = hash2(world_pos.xz * 0.15) * 0.08;
			vec3 base_wall = wall_tint * COLOR.rgb * (0.92 + var_);
			wall_col = mix(base_wall, tex_col * base_wall * 2.0, 0.35);
			final_rough = mix(wall_rough, tex_rgh, 0.4);
			final_metal = wall_metal;
		}

		if (is_cornice) { wall_col *= 0.78; }
		if (is_ledge)   { wall_col *= 1.12; }
		if (is_awning)  { wall_col *= 0.55; }
		ALBEDO    = clamp(wall_col, 0.0, 1.0);
		ROUGHNESS = final_rough;
		METALLIC  = final_metal;
		NORMAL_MAP = tex_nrm;
		NORMAL_MAP_DEPTH = 0.8;
		if (is_ledge) {
			NORMAL_MAP = vec3(tex_nrm.r, 0.7, tex_nrm.b);
			NORMAL_MAP_DEPTH = 1.2;
		}
		emission += wall_col * 0.45;
	}

	EMISSION = emission;

	// Atmospheric distance fade — buildings dissolve into haze
	float bldg_dist = length(world_pos.xyz - INV_VIEW_MATRIX[3].xyz);
	float atm_fade = smoothstep(120.0, 400.0, bldg_dist);
	vec3 haze_col = vec3(0.58, 0.56, 0.52);
	ALBEDO = mix(ALBEDO, haze_col, atm_fade * 0.45);
	ROUGHNESS = mix(ROUGHNESS, 0.95, atm_fade * 0.3);
	EMISSION = mix(EMISSION, haze_col * 0.3, atm_fade * 0.5);
}
