shader_type spatial;
render_mode cull_disabled;

// Generic ground surface — sports fields, playgrounds, pools, etc.
// Weather-responsive: rain darkening, snow cover, puddle pooling
// Surface type inferred from base color: green=sport turf, red/brown=clay/rubber,
// blue=court, gray=concrete/asphalt
uniform vec3 surface_color = vec3(0.5, 0.4, 0.3);
uniform float base_roughness = 0.90;
uniform float surface_specular = 0.10;
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform float season_t;
global uniform vec3 sky_reflect_color;

#include "res://shaders/include/hash_noise.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Per-patch variation
	float var_h = hash2(floor(world_pos.xz * 0.5));
	vec3 col = surface_color * (0.90 + var_h * 0.20);

	// --- Surface texture: material-dependent detail ---
	// Detect surface type from color for appropriate texturing
	float green_amt = surface_color.g - max(surface_color.r, surface_color.b);
	float red_amt = surface_color.r - max(surface_color.g, surface_color.b);
	float blue_amt = surface_color.b - max(surface_color.r, surface_color.g);
	float is_gray = 1.0 - 3.0 * max(max(abs(surface_color.r - surface_color.g),
	                                      abs(surface_color.g - surface_color.b)),
	                                  abs(surface_color.r - surface_color.b));
	is_gray = clamp(is_gray, 0.0, 1.0);

	float rough = base_roughness;

	if (green_amt > 0.05) {
		// Synthetic turf or sport grass: fine-grained with mowing pattern
		float turf_grain = vnoise(world_pos.xz * 25.0);
		float mow_stripe = sin(world_pos.x * 3.0 + world_pos.z * 0.5) * 0.5 + 0.5;
		mow_stripe = smoothstep(0.3, 0.7, mow_stripe);
		col *= (0.94 + turf_grain * 0.08);
		col *= mix(0.97, 1.03, mow_stripe);  // subtle mowing stripes
		// Worn center areas: slightly lighter from foot traffic
		float wear_noise = vnoise(world_pos.xz * 0.15);
		col *= (0.95 + wear_noise * 0.10);
		rough = mix(rough, 0.82, 0.3);
	} else if (red_amt > 0.03) {
		// Clay court or rubber playground surface
		// Granular texture: visible aggregate
		float grain = vnoise(world_pos.xz * 12.0);
		float fine = vnoise(world_pos.xz * 35.0);
		col *= (0.92 + grain * 0.12 + fine * 0.04);
		// Foot traffic wear: lighter patches
		float wear = vnoise(world_pos.xz * 0.08);
		float wear_mask = smoothstep(0.4, 0.7, wear);
		col = mix(col, col * 1.12, wear_mask * 0.2);
		rough = mix(rough, 0.88, 0.3);
	} else if (blue_amt > 0.03) {
		// Painted sport court (handball, basketball)
		// Smooth acrylic surface with slight orange-peel texture
		float peel = vnoise(world_pos.xz * 40.0);
		col *= (0.97 + peel * 0.04);
		// Paint wear: slight fading in high-traffic areas
		float fade = vnoise(world_pos.xz * 0.12);
		col = mix(col, col * 1.08, smoothstep(0.5, 0.8, fade) * 0.15);
		rough = mix(rough, 0.55, 0.5);  // acrylic is smoother
	} else {
		// Concrete/asphalt or general hard surface
		float tex_noise = vnoise(world_pos.xz * 8.0);
		float fine = vnoise(world_pos.xz * 20.0);
		col *= (0.93 + tex_noise * 0.10 + fine * 0.04);
		// Crack network: fine dark lines
		float crack = vnoise(world_pos.xz * 2.5);
		float crack_line = smoothstep(0.72, 0.78, crack);
		col *= (1.0 - crack_line * 0.12);
		// Stain patches: oil/dirt accumulation
		float stain = hash2(floor(world_pos.xz * 0.8));
		if (stain > 0.85) {
			col *= mix(1.0, 0.88, (stain - 0.85) * 6.0);
		}
	}

	// Edge wear: surfaces are more worn at boundaries
	float edge_noise = vnoise(world_pos.xz * 0.5);
	float edge_wear = smoothstep(0.6, 0.8, edge_noise) * 0.08;
	col = mix(col, col * vec3(1.06, 1.04, 1.00), edge_wear);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = surface_specular;

	// Seasonal aging
	float winter_t = smoothstep(2.8, 3.5, season_t);
	if (winter_t > 0.01) {
		// Winter: salt residue on hard surfaces, faded colors
		float salt = hash2(floor(world_pos.xz * 3.0));
		float salt_mask = step(0.75, salt) * winter_t;
		ALBEDO = mix(ALBEDO, ALBEDO * 1.15 + vec3(0.04), salt_mask * 0.25);
		// Colors fade in winter UV
		float lum = dot(ALBEDO, vec3(0.33));
		ALBEDO = mix(ALBEDO, vec3(lum) * 1.05, winter_t * 0.15);
	}

	// Rain: darkens surface, increases specularity
	if (rain_wetness > 0.01) {
		float wet = rain_wetness;
		ALBEDO *= mix(1.0, 0.60, wet);
		ROUGHNESS = mix(ROUGHNESS, max(ROUGHNESS * 0.3, 0.08), wet);
		SPECULAR = mix(SPECULAR, 0.45, wet);

		// Puddle formation on flat surfaces
		if (wet > 0.4) {
			float puddle_noise = vnoise(world_pos.xz * 0.1);
			puddle_noise += vnoise(world_pos.xz * 0.3) * 0.4;
			float puddle = smoothstep(0.4, 0.6, puddle_noise) * smoothstep(0.4, 0.8, wet);
			if (puddle > 0.01) {
				float sky_lum = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
				float night_t = smoothstep(0.15, 0.02, sky_lum);
				vec3 puddle_col = sky_reflect_color * 0.35 + ALBEDO * 0.12;
				puddle_col = mix(puddle_col, vec3(0.08, 0.06, 0.03) + ALBEDO * 0.06, night_t);
				ALBEDO = mix(ALBEDO, puddle_col, puddle);
				ROUGHNESS = mix(ROUGHNESS, 0.02, puddle);
				SPECULAR = mix(SPECULAR, 0.65, puddle);
			}
		}
	}

	// Snow accumulation
	if (snow_cover > 0.01) {
		float sn = hash2(floor(world_pos.xz * 2.0)) * 0.2;
		float snow_amt = clamp(snow_cover * (0.7 + sn), 0.0, 1.0);
		ALBEDO = mix(ALBEDO, vec3(0.90, 0.91, 0.94), snow_amt * 0.75);
		ROUGHNESS = mix(ROUGHNESS, 0.88, snow_amt);
		// Snow sparkle
		if (snow_amt > 0.3) {
			float sparkle = hash2(floor(world_pos.xz * 20.0));
			if (sparkle > 0.96) {
				float si = (sparkle - 0.96) * 25.0;
				SPECULAR = mix(SPECULAR, 0.85, si * snow_amt);
				ROUGHNESS = mix(ROUGHNESS, 0.05, si * snow_amt * 0.3);
			}
		}
	}

	// Ambient emission for shadow fill
	EMISSION = ALBEDO * 0.10;
}
