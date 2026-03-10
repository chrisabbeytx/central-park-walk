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
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform vec3 sky_reflect_color;
global uniform float season_t;
uniform sampler2D win_gradient : source_color, filter_linear_mipmap;

varying vec3 world_pos;

#include "res://shaders/include/hash_noise.gdshaderinc"

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
	// COLOR.a encodes real floor-to-floor height (COLOR.a * 6.0) when < 0.99
	// Default (COLOR.a == 1.0) uses material gap_y parameter
	float cell_h = COLOR.a < 0.99 ? COLOR.a * 6.0 : actual_win_h + gap_y;
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

		// Daytime sky reflections — NYC glass facades reflecting the sky
		// Especially dramatic at golden hour when windows glow orange/pink
		if (night_factor < 0.95 && !in_reveal) {
			float day_factor = 1.0 - night_factor;
			// Fresnel: more sky reflection at oblique angles
			vec3 view_dir = normalize(world_pos - INV_VIEW_MATRIX[3].xyz);
			vec3 face_n = mat3(INV_VIEW_MATRIX) * NORMAL;
			float fres = pow(1.0 - max(dot(-view_dir, face_n), 0.0), 3.0);
			// Tint reflection with sky color — golden hour windows are iconic
			vec3 sky_refl = sky_reflect_color * (0.3 + fres * 0.5);
			// Upper floors catch more sky, lower floors reflect ground/trees
			float height_fac = smoothstep(ground_h, ground_h + 30.0, UV.y);
			sky_refl *= mix(0.4, 1.0, height_fac);
			win_col = mix(win_col, sky_refl, day_factor * mix(0.35, 0.65, fres));
		}

		// Night window emission — NYC window light variety
		if (night_factor > 0.01 && !in_reveal) {
			// ~65% of windows lit (80% ground floor)
			bool is_lit = wrand < 0.65;
			if (gnd_win) { is_lit = wrand < 0.80; }
			if (is_lit) {
				float type_rand = fract(wrand * 13.7);
				float warmth = fract(wrand * 7.3);
				vec3 win_light;
				if (type_rand < 0.35) {
					// Warm incandescent (older apartments, classic NYC)
					win_light = mix(vec3(1.0, 0.68, 0.28), vec3(1.0, 0.76, 0.40), warmth);
				} else if (type_rand < 0.60) {
					// Cool white LED (modern offices, renovated apartments)
					win_light = mix(vec3(0.90, 0.92, 1.0), vec3(0.95, 0.95, 0.98), warmth);
				} else if (type_rand < 0.78) {
					// Warm white LED (3000K, newer residential)
					win_light = mix(vec3(1.0, 0.82, 0.55), vec3(1.0, 0.88, 0.62), warmth);
				} else if (type_rand < 0.92) {
					// TV/screen blue glow (apartments with screens on)
					win_light = vec3(0.35, 0.42, 0.62);
				} else {
					// Dim amber (nightlight, hallway, bathroom)
					win_light = vec3(0.85, 0.55, 0.18) * 0.6;
				}
				float em_strength = gnd_win ? 0.85 : 0.70;
				em_strength *= (0.65 + wrand * 0.45);
				// Some windows are dimmer (curtains, blinds partially drawn)
				float curtain = fract(wrand * 23.1);
				if (curtain < 0.25) em_strength *= 0.45;  // partially curtained
				vec2 win_uv = gnd_win
					? vec2(gnd_lx / 0.65, clamp((UV.y - 1.2) / (ground_h - 1.2), 0.0, 1.0))
					: vec2(lx / win_frac_x, ly / win_frac_y);
				vec3 grad = texture(win_gradient, vec2(win_uv.x, 1.0 - win_uv.y)).rgb;
				emission = win_light * grad * em_strength * night_factor;
				win_col = win_light * grad * 0.15;
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

		// Permanent weathering stains — decades of NYC grime
		// Dirt accumulates below ledges and cornices, vertical water stains
		float grime_base = hash2(floor(world_pos.xz * 0.08)) * 0.06;
		// Drip stains below window sills and ledges
		float drip = sin(world_pos.x * 4.2 + hash2(floor(world_pos.xz * 0.2)) * 15.0);
		drip = smoothstep(0.5, 0.85, drip);
		// Drips visible below ledge/cornice positions
		float below_ledge = fract(floor_pos + 0.05);
		drip *= smoothstep(0.0, 0.15, below_ledge) * smoothstep(0.35, 0.15, below_ledge);
		// Grime darkens lower floors more (pollution, splash, foot traffic)
		float low_grime = smoothstep(8.0, 0.0, UV.y) * 0.04;
		float total_grime = grime_base + drip * 0.05 + low_grime;
		wall_col *= (1.0 - total_grime);

		ALBEDO    = clamp(wall_col, 0.0, 1.0);
		ROUGHNESS = final_rough;
		METALLIC  = final_metal;
		SPECULAR  = 0.08;
		NORMAL_MAP = tex_nrm;
		NORMAL_MAP_DEPTH = 0.8;
		if (is_ledge) {
			NORMAL_MAP = vec3(tex_nrm.r, 0.7, tex_nrm.b);
			NORMAL_MAP_DEPTH = 1.2;
		}
		// Reduce wall emission at night — dark walls make lit windows pop
		float wall_em = mix(0.45, 0.06, night_factor);
		emission += wall_col * wall_em;
	}

	EMISSION = emission;

	// Rain wetness: wet walls darken, get reflective; rain streaks on walls
	if (rain_wetness > 0.01) {
		float wet = rain_wetness;
		if (!in_win) {
			// Wet masonry/brick darkens significantly
			ALBEDO *= mix(1.0, 0.60, wet);
			ROUGHNESS = mix(ROUGHNESS, max(ROUGHNESS * 0.3, 0.10), wet);
			SPECULAR = mix(0.0, 0.4, wet);
			// Rain streaks: vertical water trails running down walls
			// Multiple scales: wide rivulets + fine trickles
			float streak1 = sin(world_pos.x * 5.0 + hash2(floor(world_pos.xz * 0.3)) * 20.0);
			float streak2 = sin(world_pos.x * 13.0 + hash2(floor(world_pos.xz * 0.7)) * 30.0);
			float streak = max(smoothstep(0.6, 0.9, streak1), smoothstep(0.7, 0.95, streak2));
			// Streaks accumulate going down the building, fade near ground floor
			streak *= smoothstep(0.0, 4.0, UV.y) * wet;
			ROUGHNESS = mix(ROUGHNESS, 0.04, streak * 0.6);
			SPECULAR = mix(SPECULAR, 0.55, streak * 0.5);
		} else {
			// Rain on glass: slightly reduced transmission, higher specular
			ROUGHNESS = mix(ROUGHNESS, 0.05, wet * 0.4);
		}
	}

	// Snow on ledges and cornices
	if (snow_cover > 0.01 && !in_win) {
		vec3 world_n = mat3(INV_VIEW_MATRIX) * NORMAL;
		float upward = max(world_n.y, 0.0);
		if (upward > 0.7 && (is_ledge || is_cornice || is_awning)) {
			float snow_noise = hash2(floor(world_pos.xz * 2.0)) * 0.2;
			float snow_amt = clamp((upward + snow_noise - 0.5) * snow_cover, 0.0, 1.0);
			ALBEDO = mix(ALBEDO, vec3(0.92, 0.93, 0.96), snow_amt * 0.7);
			ROUGHNESS = mix(ROUGHNESS, 0.90, snow_amt);
		}
	}

	// Winter frost on windows — ice crystal patterns in corners
	float winter_f = smoothstep(2.8, 3.5, season_t);
	if (winter_f > 0.01 && in_win && !in_reveal && snow_cover > 0.05) {
		// Frost forms at window edges, spreading inward with colder temperatures
		vec2 win_uv_f = in_win && !gnd_win
			? vec2(lx / win_frac_x, ly / win_frac_y)
			: vec2(gnd_lx / 0.65, clamp((UV.y - 1.2) / (ground_h - 1.2), 0.0, 1.0));
		// Distance from window edge (0 at edge, 0.5 at center)
		float edge_dist = min(min(win_uv_f.x, 1.0 - win_uv_f.x),
		                      min(win_uv_f.y, 1.0 - win_uv_f.y));
		// Frost crystal noise
		float frost_noise = hash2(floor(world_pos.xz * 8.0 + world_pos.yy * 5.0));
		float frost = smoothstep(0.15, 0.0, edge_dist) * winter_f * snow_cover;
		frost *= (0.5 + frost_noise * 0.5);
		if (frost > 0.01) {
			ALBEDO = mix(ALBEDO, vec3(0.80, 0.85, 0.92), frost * 0.5);
			ROUGHNESS = mix(ROUGHNESS, 0.60, frost);
			SPECULAR = mix(SPECULAR, 0.15, frost * 0.5);
			EMISSION *= (1.0 - frost * 0.3);  // frost dims interior light
		}
	}

	// Atmospheric distance fade — buildings dissolve into haze
	// Haze color follows sky for time-of-day and seasonal accuracy
	float bldg_dist = length(world_pos.xyz - INV_VIEW_MATRIX[3].xyz);
	float atm_fade = smoothstep(120.0, 400.0, bldg_dist);
	float sky_lum = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
	// Day: blue-gray haze, Night: warm amber city glow, Golden: warm amber
	vec3 haze_col = mix(vec3(0.58, 0.56, 0.52), sky_reflect_color * 0.8 + vec3(0.20), 0.35);
	float night_t = smoothstep(0.15, 0.02, sky_lum);
	haze_col = mix(haze_col, vec3(0.14, 0.10, 0.06), night_t * 0.6);  // NYC amber at night
	// Autumn: warmer, golden haze
	float autumn_s = smoothstep(1.5, 2.5, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
	haze_col = mix(haze_col, haze_col * vec3(1.10, 1.00, 0.82), autumn_s * 0.4);
	// Winter: cooler, bluer haze
	float winter_s = smoothstep(2.5, 3.5, season_t);
	haze_col = mix(haze_col, haze_col * vec3(0.90, 0.95, 1.08), winter_s * 0.3);
	ALBEDO = mix(ALBEDO, haze_col, atm_fade * 0.45);
	ROUGHNESS = mix(ROUGHNESS, 0.95, atm_fade * 0.3);
	// At night, reduce haze dampening so distant lit windows stay visible in skyline
	float em_haze = mix(0.5, 0.25, night_t);
	EMISSION = mix(EMISSION, haze_col * 0.3, atm_fade * em_haze);
}
