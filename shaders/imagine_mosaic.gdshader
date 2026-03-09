shader_type spatial;
render_mode cull_disabled;

global uniform float rain_wetness;
global uniform float snow_cover;

#include "res://shaders/include/hash_noise.gdshaderinc"

void fragment() {
	// UV 0..1, center at 0.5
	vec2 c = UV - 0.5;
	float r = length(c);
	float angle = atan(c.y, c.x);

	// The real Imagine mosaic: black & white Roman tesserae
	// Design: central "IMAGINE" text area, surrounded by radiating
	// teardrop/acanthus-leaf pattern in concentric zones

	// Individual tesserae (small mosaic tiles ~2cm)
	vec2 tile_uv = UV * 160.0;  // ~160 tiles across diameter
	vec2 tile_id = floor(tile_uv);
	vec2 tile_f = fract(tile_uv) - 0.5;
	float tile_var = hash2(tile_id);
	// Grout lines between tesserae
	float grout = smoothstep(0.38, 0.42, max(abs(tile_f.x), abs(tile_f.y)));
	float grout_mask = 1.0 - (1.0 - grout) * 0.3;

	// Zone 1: Central medallion (r < 0.09) — warm white, "IMAGINE" text
	// Zone 2: Inner ring (0.09-0.15) — black border ring
	// Zone 3: Radiating acanthus pattern (0.15-0.42)
	// Zone 4: Outer border ring (0.42-0.48)
	// Zone 5: Black surround (0.48-0.50)

	vec3 white_stone = vec3(0.91, 0.88, 0.82);   // Carrara marble white
	vec3 cream_stone = vec3(0.86, 0.82, 0.72);   // aged Roman travertine
	vec3 black_stone = vec3(0.12, 0.11, 0.10);   // Belgian black marble
	vec3 gray_stone  = vec3(0.42, 0.40, 0.38);   // surrounding path

	// Each tile gets slight color variation (real tesserae aren't uniform)
	white_stone += (tile_var - 0.5) * 0.06;
	black_stone += (tile_var - 0.5) * 0.04;

	vec3 col;

	if (r < 0.09) {
		// Central medallion: warm white/cream for IMAGINE text area
		col = mix(white_stone, cream_stone, tile_var * 0.3);
	} else if (r < 0.14) {
		// Inner border: black ring
		col = black_stone;
	} else if (r < 0.42) {
		// Acanthus/teardrop radiating pattern — the iconic design
		// Alternating pointed leaves radiating outward
		float zone_r = (r - 0.14) / (0.42 - 0.14);  // 0-1 within pattern zone
		// 8 large leaves + 8 small leaves alternating
		float leaf_angle = angle + 3.14159;  // offset
		float sector = mod(leaf_angle / (3.14159 * 2.0) * 16.0, 2.0);

		// Large leaves (even sectors): teardrop shape expanding outward
		float leaf_width_large = 0.8 * smoothstep(0.0, 0.3, zone_r) * smoothstep(1.0, 0.5, zone_r);
		// Small leaves (odd sectors): thinner, shorter
		float leaf_width_small = 0.6 * smoothstep(0.1, 0.4, zone_r) * smoothstep(0.8, 0.4, zone_r);

		float leaf_shape;
		float sector_frac = fract(sector);
		float dist_from_center = abs(sector_frac - 0.5) * 2.0;  // 0 at center, 1 at edge

		if (sector < 1.0) {
			// Large leaf
			leaf_shape = smoothstep(leaf_width_large, leaf_width_large - 0.15, dist_from_center);
		} else {
			// Small leaf
			leaf_shape = smoothstep(leaf_width_small, leaf_width_small - 0.12, dist_from_center);
		}

		// Inner triangular points between leaves near center
		float inner_points = smoothstep(0.15, 0.0, zone_r) * smoothstep(0.5, 0.35, dist_from_center);

		float is_white = max(leaf_shape, inner_points);

		// Concentric ring accents within the pattern zone
		float ring1 = smoothstep(0.28, 0.30, zone_r) * smoothstep(0.34, 0.32, zone_r);
		float ring2 = smoothstep(0.58, 0.60, zone_r) * smoothstep(0.64, 0.62, zone_r);
		is_white = max(is_white, max(ring1, ring2) * 0.8);

		col = mix(black_stone, white_stone, is_white);
	} else if (r < 0.48) {
		// Outer border: thick black ring with thin white accent
		float accent = smoothstep(0.44, 0.445, r) * smoothstep(0.455, 0.45, r);
		col = mix(black_stone, white_stone, accent);
	} else if (r < 0.50) {
		// Transition to surrounding path
		col = mix(black_stone, gray_stone, smoothstep(0.48, 0.50, r));
	} else {
		col = gray_stone;
	}

	// Apply grout between tesserae (within the mosaic circle)
	if (r < 0.48) {
		vec3 grout_col = vec3(0.35, 0.33, 0.28);  // dark mortar
		col = mix(grout_col, col, grout_mask);
	}

	// Subtle stone grain noise
	float grain = fract(sin(dot(UV * 200.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (grain - 0.5) * 0.025;

	// Wear and foot traffic: center area slightly more polished
	float center_polish = smoothstep(0.20, 0.0, r);
	float polish_factor = center_polish * 0.2;

	ALBEDO = col;
	ROUGHNESS = mix(0.72, 0.55, polish_factor);  // center more polished from foot traffic
	METALLIC = 0.0;
	SPECULAR = mix(0.18, 0.30, polish_factor);

	// Rain: wet stone gets very reflective
	if (rain_wetness > 0.01) {
		ALBEDO *= mix(1.0, 0.70, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.06, rain_wetness);
		SPECULAR = mix(SPECULAR, 0.50, rain_wetness);
	}

	// Snow: light dusting
	if (snow_cover > 0.01) {
		float snow_noise = hash2(tile_id + vec2(99.0));
		// Snow collects in grout lines and lower spots
		float snow_in_grout = (1.0 - grout) * 0.4;
		float snow_amt = snow_cover * (0.6 + snow_in_grout + snow_noise * 0.2);
		ALBEDO = mix(ALBEDO, vec3(0.92, 0.93, 0.96), snow_amt * 0.7);
		ROUGHNESS = mix(ROUGHNESS, 0.85, snow_amt);
	}
}
