shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/include/hash_noise.gdshaderinc"

global uniform vec2 wind_vec;
global uniform float season_t;
global uniform float snow_cover;
global uniform float rain_wetness;
global uniform float dew_amount;
global uniform vec3 sky_reflect_color;

// Canopy coverage map: grayscale, 2K resolution. Bright = under tree canopy.
uniform sampler2D canopy_map : filter_linear, repeat_disable;
uniform float hm_world_size = 5000.0;

varying float v_grass_type;
varying vec3 v_world_pos;
varying float v_mow_stripe;  // -1 to +1: mowing stripe lean direction (mowed lawns only)
varying float v_path_prox;   // 0-1: proximity to nearest path (for edge wear)
varying float v_edge_fade;   // 0-1: soft fade at tile edge (0=center, 1=perimeter)

void vertex() {
	// INSTANCE_CUSTOM: R = grass_type, G = random, B = path_proximity
	v_grass_type = INSTANCE_CUSTOM.r;
	v_path_prox = INSTANCE_CUSTOM.b;

	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_world_pos = origin;

	// Soft edge fade: compute how close this blade is to the tile perimeter.
	// Tile models are circular with radius ~0.95-1.0m in model space.
	// Blades near the edge get faded out (dithered discard in fragment),
	// creating soft overlapping boundaries that hide the grid pattern.
	float blade_r = length(VERTEX.xz);  // model-space distance from tile center
	float tile_radius = 1.0;  // approximate tile model radius
	v_edge_fade = smoothstep(0.5, 1.0, blade_r / tile_radius);  // 0 at center, 1 at edge

	// Height-based sway: model-space VERTEX.y (0 at base, tip varies by type)
	float sway = max(VERTEX.y, 0.0);
	float wind_str = length(wind_vec);

	// Wind response varies by type (0-9):
	// 0-4: lawn types — moderate sway
	// 5-6: woodland — minimal sway (sheltered under canopy)
	// 7: waterside — moderate
	// 8: wild meadow — strong dramatic flow
	// 9: open lawn — moderate
	float flex = 0.7;  // default
	if (v_grass_type > 7.5) {
		flex = 2.5;  // wild meadow: dramatic flow
	} else if (v_grass_type > 6.5) {
		flex = 0.8;  // waterside: moderate
	} else if (v_grass_type > 4.5) {
		flex = 0.35; // woodland: sheltered under canopy
	} else if (v_grass_type > 3.5) {
		flex = 0.5;  // sports turf: short, less sway
	}
	float rustle = (0.2 + wind_str * 0.8) * flex;

	// --- Mowing stripes on formal lawns (types 0-4, 9) ---
	// Central Park Conservancy mows with riding mowers creating ~1.5m alternating
	// stripe passes. Blades lean in opposite directions in adjacent stripes.
	// The stripe direction rotates slightly per area (hash on coarse grid).
	v_mow_stripe = 0.0;
	bool is_mowed = v_grass_type < 4.5 || (v_grass_type > 8.5 && v_grass_type < 9.5);
	if (is_mowed) {
		// Per-area mow angle: rotates stripe direction by field so they don't all align
		float area_hash = hash2(floor(origin.xz * 0.005));
		float mow_angle = area_hash * 3.14159;  // 0 to PI rotation per meadow
		// Project world position onto the mow direction perpendicular
		float stripe_pos = origin.x * cos(mow_angle) + origin.z * sin(mow_angle);
		// 1.5m stripe width (riding mower deck)
		float stripe_phase = sin(stripe_pos * (3.14159 * 2.0 / 1.5));
		v_mow_stripe = stripe_phase;
		// Lean blade tips in stripe direction (subtle, ~0.015m offset at tip)
		float lean = stripe_phase * sway * 0.015;
		VERTEX.x += lean * cos(mow_angle);
		VERTEX.z += lean * sin(mow_angle);
	}

	// Base sway: continuous oscillation
	float px = origin.x * 0.15 + origin.z * 0.22;
	float pz = origin.z * 0.18 + origin.x * 0.12;
	VERTEX.x += sin(TIME * 1.8 + px) * 0.12 * sway * rustle;
	VERTEX.z += sin(TIME * 2.3 + pz) * 0.08 * sway * rustle;

	// Wind push: constant lean in wind direction
	VERTEX.x += wind_vec.x * sway * 0.4 * flex;
	VERTEX.z += wind_vec.y * sway * 0.4 * flex;

	// Traveling wind gusts
	float gust_phase = origin.x * 0.04 + origin.z * 0.05;
	float gust = sin(TIME * 0.5 + gust_phase) * 0.5 + 0.5;
	gust = gust * gust * gust;
	float gust_str = gust * wind_str * 0.5 * flex;
	VERTEX.x += wind_vec.x * sway * gust_str;
	VERTEX.z += wind_vec.y * sway * gust_str;

	// Blade flutter: high-frequency micro-movement
	float flutter = sin(TIME * 5.5 + VERTEX.x * 14.0 + VERTEX.z * 10.0) * 0.015 * rustle;
	flutter += sin(TIME * 8.0 + VERTEX.z * 18.0) * 0.008 * gust_str;
	VERTEX.y += flutter * sway;

	// Winter: lawn types go dormant — shrink nearly flat to avoid grid pattern
	// on brown terrain. Terrain shader handles winter ground color.
	float winter_t = smoothstep(3.0, 3.5, season_t);
	if (winter_t > 0.0 && (v_grass_type < 4.5 || v_grass_type > 8.5)) {
		VERTEX.y *= mix(1.0, 0.08, winter_t);  // nearly flat — 8% of summer height
	}
	// Woodland grass also shrinks but less (some evergreen understory)
	if (winter_t > 0.0 && v_grass_type > 4.5 && v_grass_type < 8.5) {
		VERTEX.y *= mix(1.0, 0.25, winter_t);
	}
}

void fragment() {
	// In deep winter, discard lawn grass entirely — the tiny 8% stubs create
	// a visible grid pattern in fog/snow. Terrain shader handles winter ground.
	float winter_discard = smoothstep(3.2, 3.8, season_t);
	if (winter_discard > 0.95 && v_grass_type < 4.5) discard;  // lawn types only

	// Soft tile edge: stochastically discard blades near tile perimeter.
	// Uses world-space hash (not FRAGCOORD) so pattern is stable as camera moves.
	if (v_edge_fade > 0.01) {
		float edge_dither = hash2(v_world_pos.xz * 3.7 + vec2(VERTEX.x * 11.0, VERTEX.z * 13.0));
		if (edge_dither < v_edge_fade * 0.85) discard;
	}

	// Aerial height-based fade — from above, individual grass blades would be
	// sub-pixel, but the tile grid pattern becomes visible as colored blocks.
	// World-space hash for stable discard pattern (no per-frame sparkle).
	float cam_h = INV_VIEW_MATRIX[3].y - v_world_pos.y;
	if (cam_h > 12.0) {
		float aerial_discard = smoothstep(12.0, 35.0, cam_h);
		float ad = hash2(v_world_pos.xz * 1.3 + vec2(41.2, 63.9));
		if (ad < aerial_discard) discard;
	}

	// Vertex colors from Blender model provide base albedo
	vec3 col = COLOR.rgb;

	// --- Base color toning: match terrain shader for seamless blending ---
	// CP Conservancy Class A lawns are lush green, not olive. Keep more saturation
	// and push green-dominant to match the richer terrain grass color.
	float base_lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(base_lum), col, 0.72);  // 28% desaturation (was 40%) — preserve green character
	// Darken to PBR range but keep green dominant over red (no olive shift)
	col *= vec3(0.58, 0.68, 0.48);  // green channel preserved, red reduced → distinctly green

	// --- Height-based shading: darker at base, brighter at tip ---
	// UV.y from Blender: 0.0 at base, 1.0 at tip (set in make_grass_patch.py)
	float blade_t = clamp(UV.y, 0.0, 1.0);
	// Ambient occlusion at blade base — creates depth in the grass carpet
	float ao = mix(0.55, 1.0, smoothstep(0.0, 0.4, blade_t));
	col *= ao;
	// Tip brightening: sun catches blade tips, not shaded bases
	col *= mix(1.0, 1.12, smoothstep(0.5, 1.0, blade_t));

	// --- Seasonal colour modulation ---
	// Seasonal ramps MUST match terrain.gdshader exactly to prevent grass tile grid
	// being visible from seasonal color mismatch between blades and terrain
	float spring_t = 1.0 - smoothstep(0.0, 1.0, season_t);
	float autumn_t = smoothstep(2.0, 2.6, season_t) * (1.0 - smoothstep(2.8, 3.5, season_t));
	float winter_t = smoothstep(2.7, 3.1, season_t);  // match terrain's dormancy start

	col = mix(col, col * vec3(1.1, 1.15, 0.75), spring_t * 0.6);    // spring: match terrain
	// Autumn: flat target color (matching terrain) prevents noise amplification
	vec3 autumn_blade = vec3(0.16, 0.12, 0.04);  // match terrain's autumn_target
	col = mix(col, autumn_blade, autumn_t * 0.7);                     // autumn: uniform golden
	// Winter dormancy: match terrain's flat dormant brown color
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 dormant_brown = vec3(0.12, 0.10, 0.06);  // match terrain shader's winter_grass target
	col = mix(col, dormant_brown, winter_t);                          // winter: dormant brown

	// --- Multi-scale colour variation — MUST match terrain.gdshader exactly ---
	// Using identical noise scales and seed offsets as terrain shader ensures that
	// grass blades and the terrain underneath get the same color modulation.
	// Any mismatch makes the tile grid visible as colored blocks.

	// Scale 1: field condition (333m) — matches terrain field_tone
	float field_cond = vnoise(v_world_pos.xz * 0.003 + vec2(50.0, 23.0));
	// Terrain blends toward lush/olive targets; we apply equivalent brightness shift
	col *= mix(1.02, 0.96, field_cond);  // subtle — terrain does 25% blend

	// Scale 2: large patches (166m) — matches terrain lawn_large
	float lawn_large = fbm3(v_world_pos.xz * 0.006);
	col *= 0.88 + lawn_large * 0.24;  // match terrain's gentler 0.85 + 0.30

	// Scale 3: medium patches (40m) — matches terrain lawn_med
	float lawn_med = fbm3(v_world_pos.xz * 0.025 + 37.0);
	float stress = smoothstep(0.55, 0.80, lawn_med);
	col = mix(col, col * vec3(1.04, 0.96, 0.80), stress * 0.08);  // subtler stress
	col *= 0.94 + lawn_med * 0.12;  // match terrain's 0.94 + 0.12

	// Scale 4: warm/cool hue (100m) — matches terrain temp_shift (reduced amplitude)
	float temp_shift = fbm3(v_world_pos.xz * 0.01 + 91.0) - 0.5;
	col *= vec3(1.0 + temp_shift * 0.10, 1.0, 1.0 - temp_shift * 0.08);  // subtler

	// Scale 5: per-clump variation (2m) — sub-tile, doesn't need to match terrain
	// Kept small to preserve close-up visual interest without affecting aerial pattern
	float clump_var = hash2(floor(v_world_pos.xz * 0.5));
	col *= 0.94 + clump_var * 0.12;  // reduced from 0.88+0.24 to minimize grid contrast

	// --- Path-edge wear: grass near paths is stressed and browner ---
	// Foot traffic compacts soil, wears grass. Trampled edges are a universal park feature.
	if (v_path_prox > 0.05) {
		// Brown/yellow shift — compacted, stressed, partly bare
		vec3 worn_col = col * vec3(1.10, 0.88, 0.60);  // warm brown tint
		col = mix(col, worn_col, v_path_prox * 0.55);
		// Wear reduces saturation too (exposed soil)
		float wear_desat = v_path_prox * 0.25;
		float wear_lum = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(wear_lum), wear_desat);
	}

	// --- Mowing stripes: view-dependent brightness on formal lawns ---
	// Blades bent toward viewer appear lighter (reflect sky), away appear darker
	// This creates the classic striped lawn pattern visible from any angle
	if (abs(v_mow_stripe) > 0.01) {
		// View-dependent: stripe brightness varies with camera angle
		// Stripe phase is -1 to +1; positive lean toward camera = brighter
		float stripe_bright = v_mow_stripe * 0.06;  // subtle ±6% brightness
		col *= 1.0 + stripe_bright;
	}

	// --- Wildflower coloring (spring/summer) ---
	// Meadow zones (7,8): dense wildflowers (~15%)
	// Mowed lawns (0-4,9): sparse weeds (~4%) — dandelions and clover survive mowing
	float flower_season = smoothstep(0.0, 0.8, season_t) * (1.0 - smoothstep(2.2, 3.0, season_t));
	bool is_meadow_zone = v_grass_type > 6.5;
	bool is_lawn_zone = v_grass_type < 4.5 || (v_grass_type > 8.5 && v_grass_type < 9.5);
	if (flower_season > 0.01 && blade_t > 0.7 && (is_meadow_zone || is_lawn_zone)) {
		float flower_hash = hash2(floor(v_world_pos.xz * 2.0));
		// Meadow: 15% flowers. Lawn: 4% weeds (dandelions, clover — they always come back)
		float flower_thresh = is_meadow_zone ? 0.85 : 0.96;
		if (flower_hash > flower_thresh) {
			float flower_type = fract(flower_hash * 7.3);
			vec3 flower_col;
			if (is_lawn_zone) {
				// Mowed lawns: only dandelions and clover survive regular mowing
				if (flower_type < 0.55) {
					flower_col = vec3(0.95, 0.85, 0.20);  // dandelion yellow
				} else {
					flower_col = vec3(0.90, 0.90, 0.85);  // white clover
				}
			} else {
				// Meadow: full wildflower diversity
				if (flower_type < 0.30) {
					flower_col = vec3(0.95, 0.85, 0.20);  // dandelion yellow
				} else if (flower_type < 0.50) {
					flower_col = vec3(0.90, 0.90, 0.85);  // white clover
				} else if (flower_type < 0.70) {
					flower_col = vec3(0.55, 0.30, 0.65);  // violet/purple
				} else if (flower_type < 0.85) {
					flower_col = vec3(0.90, 0.65, 0.15);  // black-eyed susan
				} else {
					flower_col = vec3(0.85, 0.40, 0.50);  // pink clover
				}
			}
			float tip_blend = smoothstep(0.7, 0.95, blade_t) * flower_season;
			col = mix(col, flower_col, tip_blend * 0.8);
		}
	}

	// --- Dappled canopy shade — grass under trees receives filtered light ---
	// Matches terrain.gdshader and path.gdshader canopy shade algorithm exactly.
	{
		vec2 canopy_uv = (v_world_pos.xz + hm_world_size * 0.5) / hm_world_size;
		float canopy = texture(canopy_map, canopy_uv).r;
		if (canopy > 0.01) {
			float deciduous_loss = smoothstep(2.5, 3.2, season_t);
			float winter_bare = smoothstep(3.0, 3.5, season_t);
			float spring_fill = smoothstep(0.0, 0.4, season_t);
			float sc = canopy * mix(1.0, 0.3, deciduous_loss) * mix(1.0, 0.15, winter_bare) * mix(0.5, 1.0, spring_fill);
			vec2 dapple_uv = v_world_pos.xz * 0.35 + wind_vec * TIME * 0.08;
			float dapple = vnoise(dapple_uv);
			float dapple_fine = vnoise(v_world_pos.xz * 1.2 + wind_vec * TIME * 0.15);
			float light_gap = smoothstep(0.35, 0.65, dapple) * 0.6 + smoothstep(0.55, 0.75, dapple_fine) * 0.4;
			float sky_lum = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
			float sun_factor = smoothstep(0.02, 0.20, sky_lum);
			float shade = sc * sun_factor;
			col *= (1.0 - shade * (1.0 - light_gap) * 0.35);
			// Warm sun spots through canopy gaps
			float warm_spots = light_gap * shade * 0.08;
			col *= vec3(1.0 + warm_spots, 1.0 + warm_spots * 0.5, 1.0 - warm_spots * 0.3);
		}
	}

	// Distance-based darkening (match terrain shader: blade highlights average out at distance)
	float blade_dist = length(v_world_pos - INV_VIEW_MATRIX[3].xyz);
	float dist_darken = smoothstep(30.0, 150.0, blade_dist) * 0.25;
	col *= (1.0 - dist_darken);
	// Aerial perspective: desaturate + cool shift at distance (match terrain)
	float blade_aerial = smoothstep(60.0, 300.0, blade_dist);
	float col_lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(col_lum), blade_aerial * 0.25);
	col = mix(col, col * vec3(0.94, 0.96, 1.04), blade_aerial);

	ALBEDO    = col;
	// Real grass is one of the most Lambertian surfaces in nature — almost no specular.
	// Any specular on 3D blades makes them pop brighter than the flat terrain underneath,
	// creating a visible grid pattern from tile placement.
	ROUGHNESS = 0.95;
	SPECULAR  = 0.0;
	METALLIC  = 0.0;

	// Rain: wet darkening + gloss
	if (rain_wetness > 0.01) {
		ALBEDO   *= mix(1.0, 0.65, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.25, rain_wetness);
		SPECULAR  = mix(SPECULAR,  0.35, rain_wetness);
	}

	// Snow on upper surfaces
	if (snow_cover > 0.01) {
		vec3 world_n = mat3(INV_VIEW_MATRIX) * NORMAL;
		float upward = max(world_n.y, 0.0);
		float snow_on = upward * snow_cover * mix(0.5, 1.0, v_grass_type);
		ALBEDO    = mix(ALBEDO,    vec3(0.92, 0.93, 0.96), snow_on * 0.65);
		ROUGHNESS = mix(ROUGHNESS, 0.90,                   snow_on * 0.5);
	}

	// Frost sparkle: ice crystals on blade surfaces in winter
	// Each crystal is a tiny mirror — creates bright specular pinpoints
	if (winter_t > 0.1 && snow_cover < 0.6) {
		// Frost forms preferentially on blade tips (exposed, cools fastest)
		float frost_mask = winter_t * smoothstep(0.2, 0.8, blade_t);
		// Ice crystal facets: high-frequency hash gives random sparkle per blade position
		float crystal = hash2(floor(v_world_pos.xz * 12.0 + vec2(blade_t * 5.0)));
		// Only ~20% of positions sparkle (discrete crystal facets)
		float sparkle = step(0.80, crystal) * frost_mask;
		// Frost coating: thin rime ice makes surface smoother and more reflective
		ALBEDO    = mix(ALBEDO, ALBEDO * vec3(1.10, 1.12, 1.18), frost_mask * 0.4);
		ROUGHNESS = mix(ROUGHNESS, 0.10, sparkle * 0.8);
		SPECULAR  = mix(SPECULAR,  0.60, sparkle * 0.9);
		// Broad frost reduces roughness subtly even without sparkle
		ROUGHNESS = mix(ROUGHNESS, 0.40, frost_mask * 0.3);
	}

	// Morning dew — time-limited to dawn/morning via dew_amount global uniform.
	// Broad surface moisture + discrete droplet sparkle on blade tips.
	if (dew_amount > 0.01 && blade_t > 0.5) {
		float dew = dew_amount * smoothstep(0.5, 0.85, blade_t);
		ROUGHNESS = mix(ROUGHNESS, 0.20, dew * 0.4);
		SPECULAR  = mix(SPECULAR,  0.30, dew * 0.3);
		// Vividity boost — wet grass catches more light, looks greener
		ALBEDO *= mix(1.0, 1.06, dew * 0.3);
	}

	// Backlight / subsurface scattering — subtle, only at blade tips.
	// Reduced to prevent grass tiles appearing brighter than terrain underneath.
	BACKLIGHT = col * mix(0.05, 0.20, blade_t);

}
