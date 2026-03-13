shader_type spatial;

uniform vec3 bark_color = vec3(0.48, 0.38, 0.28);
// 0=deep furrows (oak/elm), 1=smooth+lenticels (birch/cherry),
// 2=exfoliating patches (london plane), 3=scaled plates (pine), 4=smooth (magnolia)
uniform int bark_style = 0;
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform float season_t;
global uniform vec3 sky_reflect_color;

varying vec3 world_pos;
varying vec3 world_nrm;

#include "res://shaders/include/hash_noise.gdshaderinc"

// Variable-octave FBM for bark texture detail
float fbm(vec2 p, int oct) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < oct; i++) { v += a*vnoise(p); p *= 2.17; a *= 0.49; }
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Per-tree variation seed from model origin
	vec3 tree_base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float tree_var = hash2(floor(tree_base.xz * 0.5));
	vec3 col = bark_color * (0.90 + tree_var * 0.20);

	// UV approximation: vertical = world_pos.y, horizontal = angular position
	float local_h = world_pos.y - tree_base.y;
	float bark_y = local_h * 4.0;
	float bark_u = world_pos.x * 3.5 + world_pos.z * 2.8;
	float furrow = 0.5;  // shared variable for lichen/moss/snow to use
	float rough = 0.88;
	float micro = 0.0;

	if (bark_style == 0) {
		// --- Style 0: Deep vertical furrows (oak, elm, maple, ginkgo, etc.) ---
		float furrow_wave = sin(bark_u * 6.0 + vnoise(vec2(bark_u * 0.8, bark_y * 0.3)) * 2.5);
		furrow = smoothstep(0.15, 0.55, furrow_wave);
		col *= mix(0.78, 1.08, furrow);
		micro = fbm(vec2(bark_u * 12.0, bark_y * 8.0), 3);
		col *= (0.92 + micro * 0.16);
		rough = mix(0.82, 0.95, furrow) + micro * 0.05;
	} else if (bark_style == 1) {
		// --- Style 1: Smooth bark with horizontal lenticels (birch, cherry) ---
		// Birch: white/cream with dark horizontal lines; cherry: reddish-brown shiny
		// Smooth base with subtle horizontal banding
		float h_band = sin(bark_y * 18.0 + vnoise(vec2(bark_u * 0.4, bark_y * 0.6)) * 1.5);
		furrow = smoothstep(0.3, 0.6, h_band);
		// Lenticels: short dark horizontal dashes scattered across smooth bark
		float lenticel_h = sin(bark_y * 35.0 + bark_u * 0.5);
		float lenticel_u = sin(bark_u * 8.0 + bark_y * 2.0);
		float lenticel = smoothstep(0.75, 0.90, lenticel_h) * smoothstep(0.4, 0.8, lenticel_u);
		col *= mix(1.0, 0.65, lenticel * 0.7);  // dark lenticel marks
		// Subtle horizontal shimmer (smooth bark catches light)
		col *= (0.96 + furrow * 0.08);
		micro = vnoise(vec2(bark_u * 15.0, bark_y * 10.0)) * 0.06;
		col *= (0.97 + micro);
		rough = 0.55 + lenticel * 0.20;  // smooth bark, rougher at lenticels
		// Peeling papery bark for birch (lighter patches revealing inner bark)
		float peel = smoothstep(0.60, 0.75, fbm(vec2(bark_u * 1.2, bark_y * 0.8), 2));
		peel *= smoothstep(2.0, 4.0, local_h) * smoothstep(8.0, 5.0, local_h);  // mid-height
		col = mix(col, col * 1.15, peel * 0.3);
	} else if (bark_style == 2) {
		// --- Style 2: Exfoliating mottled patches (london plane / sycamore) ---
		// Jigsaw-like pattern of cream, olive, and gray patches where bark peels
		float patch_n = fbm(vec2(bark_u * 1.5, bark_y * 1.0), 3);
		float patch2 = vnoise(vec2(bark_u * 2.8 + 17.0, bark_y * 2.2));
		// Three-tone mottling: fresh inner bark (cream), medium (olive), old (gray)
		vec3 cream_bark = col * vec3(1.30, 1.25, 1.10);  // fresh exposed inner bark
		vec3 olive_bark = col * vec3(0.82, 0.88, 0.75);  // mossy green-gray
		vec3 gray_bark  = col * vec3(0.90, 0.88, 0.85);  // weathered old bark
		float zone1 = smoothstep(0.3, 0.5, patch_n);
		float zone2 = smoothstep(0.5, 0.7, patch2);
		col = mix(gray_bark, cream_bark, zone1);
		col = mix(col, olive_bark, zone2 * 0.6);
		// Patch boundary edges: slightly raised ridges where bark meets
		float edge = abs(fract(patch_n * 3.0) - 0.5) * 2.0;
		edge = 1.0 - smoothstep(0.0, 0.15, edge);
		col *= (1.0 - edge * 0.12);
		furrow = 1.0 - edge;  // "furrows" at patch borders
		micro = vnoise(vec2(bark_u * 10.0, bark_y * 8.0)) * 0.08;
		col *= (0.96 + micro);
		rough = mix(0.65, 0.80, zone1);  // fresh patches are smoother
	} else if (bark_style == 3) {
		// --- Style 3: Thick scaled plates (pine / conifer) ---
		// Overlapping rectangular plates with deep fissures between
		float plate_y = floor(bark_y * 2.5 + vnoise(vec2(bark_u * 0.5, bark_y * 0.3)) * 0.8);
		float plate_u = floor(bark_u * 1.8 + vnoise(vec2(bark_y * 0.4, bark_u * 0.2)) * 0.6);
		float plate_fy = fract(bark_y * 2.5 + vnoise(vec2(bark_u * 0.5, bark_y * 0.3)) * 0.8);
		float plate_fu = fract(bark_u * 1.8 + vnoise(vec2(bark_y * 0.4, bark_u * 0.2)) * 0.6);
		// Deep fissures at plate boundaries
		float fissure_y = smoothstep(0.0, 0.08, plate_fy) * smoothstep(1.0, 0.92, plate_fy);
		float fissure_u = smoothstep(0.0, 0.10, plate_fu) * smoothstep(1.0, 0.90, plate_fu);
		furrow = fissure_y * fissure_u;
		// Reddish-warm variation within plates
		float plate_var = hash2(vec2(plate_y, plate_u));
		col *= mix(0.85, 1.15, plate_var);
		col *= mix(0.72, 1.0, furrow);  // dark fissures
		// Flaky surface texture within plates
		micro = fbm(vec2(bark_u * 8.0, bark_y * 6.0), 2);
		col *= (0.94 + micro * 0.12);
		rough = mix(0.85, 0.95, 1.0 - furrow) + micro * 0.04;
	} else {
		// --- Style 4: Smooth gray (magnolia, callery pear) ---
		// Very smooth with subtle vertical streaking, almost no furrows
		float streak = vnoise(vec2(bark_u * 2.0, bark_y * 6.0));
		furrow = smoothstep(0.3, 0.7, streak);
		col *= (0.94 + furrow * 0.12);
		micro = vnoise(vec2(bark_u * 10.0, bark_y * 8.0)) * 0.04;
		col *= (0.98 + micro);
		rough = 0.58 + furrow * 0.12;  // quite smooth
		// Subtle bumpy texture like beech bark
		float bump = fbm(vec2(bark_u * 5.0, bark_y * 3.0), 2);
		col *= (0.96 + bump * 0.08);
	}

	// --- Height-based bark variation (all styles) ---
	float height_factor = smoothstep(0.0, 6.0, local_h);
	col *= mix(0.88, 1.0, height_factor);
	rough = mix(rough + 0.03, rough, height_factor);
	float upper = smoothstep(4.0, 10.0, local_h);
	col = mix(col, col * 1.12, upper * 0.3);  // lighter higher up

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.04;

	// --- Lichen patches: gray-green crusty patches common on NYC park trees ---
	float lichen_season = smoothstep(0.0, 0.8, season_t) * (1.0 - smoothstep(3.0, 3.8, season_t));
	if (lichen_season > 0.01) {
		float lich_noise = fbm(vec2(bark_u * 2.0, bark_y * 1.5) + tree_var * 10.0, 2);
		float lich_mask = smoothstep(0.55, 0.72, lich_noise) * lichen_season;
		// Only on bark ridges (not in deep furrows) and mid-height
		lich_mask *= furrow * smoothstep(1.0, 3.0, local_h) * smoothstep(8.0, 5.0, local_h);
		if (lich_mask > 0.01) {
			// Gray-green crustose lichen
			vec3 lichen_col = mix(vec3(0.35, 0.42, 0.30), vec3(0.45, 0.48, 0.38), lich_noise);
			ALBEDO = mix(ALBEDO, lichen_col, lich_mask * 0.45);
			ROUGHNESS = mix(ROUGHNESS, 0.92, lich_mask * 0.3);
		}
	}

	// --- Moss at trunk base: more in spring/summer, north-facing ---
	float spring_summer = smoothstep(0.0, 1.0, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
	float moss_height = smoothstep(3.0, 0.0, local_h);  // bottom 3m of trunk
	float moss_facing = max(0.0, -world_nrm.z) * 0.5 + max(0.0, -world_nrm.x) * 0.3 + 0.2;
	float moss_noise = fbm(vec2(bark_u * 3.0, bark_y * 2.0), 2);
	float moss = moss_height * moss_facing * smoothstep(0.35, 0.6, moss_noise) * spring_summer;
	if (moss > 0.01) {
		vec3 moss_col = mix(vec3(0.10, 0.20, 0.06), vec3(0.16, 0.26, 0.08), moss_noise);
		ALBEDO = mix(ALBEDO, moss_col, moss * 0.45);
		ROUGHNESS = mix(ROUGHNESS, 0.95, moss * 0.3);
	}

	// --- Rain: wet bark darkens, gets glossy ---
	if (rain_wetness > 0.01) {
		ALBEDO *= mix(1.0, 0.62, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.35, rain_wetness);
		SPECULAR = mix(SPECULAR, 0.28, rain_wetness);
		// Water streaks in furrows — darker wet lines running down bark
		float wet_streak = smoothstep(0.45, 0.20, furrow) * rain_wetness;
		ALBEDO *= mix(1.0, 0.82, wet_streak * 0.6);
		ROUGHNESS = mix(ROUGHNESS, 0.12, wet_streak * 0.4);
		// Wet moss becomes vivid green
		if (moss > 0.01) {
			ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.82, 1.25, 0.78), moss * rain_wetness * 0.4);
		}
	}

	// --- Snow on upward-facing bark and branch crotches ---
	if (snow_cover > 0.01) {
		float upward = max(world_nrm.y, 0.0);
		float snow_noise = hash2(floor(world_pos.xz * 5.0 + world_pos.yy * 3.0));
		float snow_amt = snow_cover * smoothstep(0.3, 0.7, upward + snow_noise * 0.3);
		// Snow collects more in bark furrows (concavities)
		snow_amt += snow_cover * (1.0 - furrow) * upward * 0.15;
		snow_amt = min(snow_amt, 1.0);
		ALBEDO = mix(ALBEDO, vec3(0.90, 0.91, 0.94), snow_amt * 0.7);
		ROUGHNESS = mix(ROUGHNESS, 0.85, snow_amt);
	}

	// --- Sap runs and resin: dark wet streaks on deciduous trees ---
	// Especially visible in spring when sap flows
	float sap_season = smoothstep(0.0, 0.5, season_t) * (1.0 - smoothstep(1.5, 2.5, season_t));
	if (sap_season > 0.01) {
		float sap_hash = hash2(floor(vec2(bark_u * 2.0, bark_y * 0.5)) + tree_var * 20.0);
		// Only ~8% of positions show sap runs
		if (sap_hash > 0.92) {
			// Dark glossy streak running downward
			float sap_run = smoothstep(0.92, 0.96, sap_hash) * sap_season;
			ALBEDO *= mix(1.0, 0.72, sap_run * 0.6);
			ROUGHNESS = mix(ROUGHNESS, 0.25, sap_run * 0.4);
			SPECULAR = mix(SPECULAR, 0.30, sap_run * 0.3);
		}
	}

	// Aerial perspective: desaturate + cool shift + haze blend at distance.
	float bark_dist = length(tree_base - INV_VIEW_MATRIX[3].xyz);
	float bark_aerial = smoothstep(60.0, 300.0, bark_dist);
	if (bark_aerial > 0.01) {
		float bl = dot(ALBEDO, vec3(0.2126, 0.7152, 0.0722));
		ALBEDO = mix(ALBEDO, vec3(bl), bark_aerial * 0.30);
		ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.94, 0.96, 1.04), bark_aerial);
		float sky_l = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
		vec3 haze = mix(vec3(0.58, 0.56, 0.52), sky_reflect_color * 0.8 + vec3(0.20), 0.35);
		float night_f = smoothstep(0.15, 0.02, sky_l);
		haze = mix(haze, vec3(0.14, 0.10, 0.06), night_f * 0.6);
		ALBEDO = mix(ALBEDO, haze, bark_aerial * 0.30);
	}
}
