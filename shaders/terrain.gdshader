shader_type spatial;
render_mode cull_disabled;

// Grass textures
uniform sampler2D grass_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 3.0;

// Meadow/wild grass blend
uniform sampler2D meadow_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float meadow_tile_m = 2.5;

// Rock texture for steep slopes (Manhattan schist outcrops)
uniform sampler2D rock_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_tile_m = 3.0;

// Dirt texture for playgrounds, dog parks, tracks
uniform sampler2D dirt_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float dirt_tile_m = 2.0;

// Shore/mud texture for water body edges
uniform sampler2D shore_albedo : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_normal : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_rough  : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float shore_tile_m = 3.0;

// Anti-tiling noise texture (256x256 white noise)
uniform sampler2D tile_noise : filter_linear_mipmap, repeat_enable;

// Heightmap for per-pixel terrain normals (eliminates mesh topology artifacts)
uniform sampler2D heightmap_tex : filter_linear, repeat_disable;

uniform float world_size = 5000.0;

// Structure material texture arrays (stone, concrete, asphalt, etc.)
uniform sampler2DArray path_alb_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray path_nrm_arr : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray path_rgh_arr : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float path_tile_m = 2.5;

// Park boundary mask: white = inside park, black = outside
uniform sampler2D park_mask : filter_linear, repeat_disable;

// Weather & season (global uniforms — set by main.gd via RenderingServer)
global uniform float snow_cover;
global uniform float rain_wetness;
global uniform float season_t;
global uniform vec3 sky_reflect_color;
global uniform vec2 wind_vec;

// Landuse zone map: encodes zone type per pixel
// 0=unzoned (default mowed lawn), 1=garden, 2=grass, 3=pitch, 4=playground,
// 5=nature_reserve, 6=dog_park, 7=sports, 8=pool, 9=track, 10=wood, 11=forest
uniform sampler2D landuse_map : filter_nearest, repeat_disable;

// Shore distance field: R=distance from water (0-30m→0-255), A=depth into water (0-30m→0-255)
// filter_linear gives smooth interpolation — no aliased edges at zone boundaries
uniform sampler2D shore_distance : filter_linear, repeat_disable;

// Structure mask from LiDAR (HH - BE difference): 0=ground, 1-254=height in half-feet
uniform sampler2D structure_mask : filter_linear, repeat_disable;

// Vertex colors encode smoothed surface blend weights (from convert_to_godot.py):
// R = paved path/bridge blend (0-1, Gaussian smoothed)
// G = unpaved trail blend (0-1, Gaussian smoothed)
// B = rock blend (0-1, slope + atlas smoothed)
// A = building area blend (0-1)
// GPU hardware interpolation across triangle faces creates smooth transitions —
// no more 0.61m grid artifacts from the old splat map atlas.

varying vec3 world_pos;
varying vec4 vert_color;

#include "res://shaders/include/hash_noise.gdshaderinc"

// Variable-octave FBM (terrain needs more than 3 octaves in places)
float fbm(vec2 p, int oct) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < oct; i++) { v += a*vnoise(p); p *= 2.13; a *= 0.47; }
	return v;
}

// Inigo Quilez textureNoTile — kills tiling at all distances with 2 extra samples
vec3 textureNoTile_c(sampler2D tex, vec2 uv) {
	float k = texture(tile_noise, uv * 0.0085).x;
	vec2 duvdx = dFdx(uv); vec2 duvdy = dFdy(uv);
	float l = k * 12.0;
	float f = fract(l);
	vec2 offa = sin(vec2(3.0, 7.0) * floor(l));
	vec2 offb = sin(vec2(3.0, 7.0) * ceil(l));
	vec3 cola = textureGrad(tex, uv + offa, duvdx, duvdy).rgb;
	vec3 colb = textureGrad(tex, uv + offb, duvdx, duvdy).rgb;
	return mix(cola, colb, smoothstep(0.15, 0.85, f - 0.1 * dot(cola - colb, vec3(1.0))));
}

vec3 textureNoTile_n(sampler2D tex, vec2 uv) {
	float k = texture(tile_noise, uv * 0.0085).x;
	vec2 duvdx = dFdx(uv); vec2 duvdy = dFdy(uv);
	float l = k * 12.0;
	float f = fract(l);
	vec2 offa = sin(vec2(3.0, 7.0) * floor(l));
	vec2 offb = sin(vec2(3.0, 7.0) * ceil(l));
	vec3 na = textureGrad(tex, uv + offa, duvdx, duvdy).rgb;
	vec3 nb = textureGrad(tex, uv + offb, duvdx, duvdy).rgb;
	return mix(na, nb, smoothstep(0.15, 0.85, f));
}

float textureNoTile_r(sampler2D tex, vec2 uv) {
	float k = texture(tile_noise, uv * 0.0085).x;
	vec2 duvdx = dFdx(uv); vec2 duvdy = dFdy(uv);
	float l = k * 12.0;
	float f = fract(l);
	vec2 offa = sin(vec2(3.0, 7.0) * floor(l));
	vec2 offb = sin(vec2(3.0, 7.0) * ceil(l));
	float ra = textureGrad(tex, uv + offa, duvdx, duvdy).r;
	float rb = textureGrad(tex, uv + offb, duvdx, duvdy).r;
	return mix(ra, rb, smoothstep(0.15, 0.85, f));
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vert_color = COLOR;  // GPU interpolates across triangle face → smooth transitions
}

void fragment() {
	// Per-pixel terrain normal from heightmap — eliminates mesh triangle artifacts
	vec2 hm_uv = (world_pos.xz + world_size * 0.5) / world_size;
	float htexel = 1.0 / float(textureSize(heightmap_tex, 0).x);
	float cell_m = world_size / float(textureSize(heightmap_tex, 0).x - 1);
	float tL = texture(heightmap_tex, hm_uv + vec2(-htexel, 0.0)).r;
	float tR = texture(heightmap_tex, hm_uv + vec2( htexel, 0.0)).r;
	float tU = texture(heightmap_tex, hm_uv + vec2(0.0, -htexel)).r;
	float tD = texture(heightmap_tex, hm_uv + vec2(0.0,  htexel)).r;
	vec3 terrain_n = normalize(vec3(tL - tR, 2.0 * cell_m, tU - tD));

	// --- Park boundary mask: outside = NYC sidewalk ---
	vec2 mask_uv = (world_pos.xz + world_size * 0.5) / world_size;
	float park_inside = texture(park_mask, mask_uv).r;

	// TBN aligned to grass UV (U=+X, V=+Z) on the terrain surface
	vec3 terr_T = normalize(vec3(2.0 * cell_m, tR - tL, 0.0));
	vec3 terr_B = normalize(cross(terr_T, terrain_n));

	// Atlas UV for landuse, boundary, shore distance lookups
	vec2 splat_uv = (world_pos.xz + world_size * 0.5) / world_size;

	// --- Grass shading (textureNoTile — Inigo Quilez anti-tiling) ---
	vec2 uv  = world_pos.xz / tile_m;
	float cam_dist = length(world_pos - INV_VIEW_MATRIX[3].xyz);
	vec3 grass_alb = textureNoTile_c(grass_albedo, uv);
	// Aerial texture fade — at distance, the 3m texture tile creates visible
	// anti-tiling cell boundaries from above. Use camera height to detect aerial
	// views (looking down) vs ground views (looking across). From ground level
	// texture stays sharp even at distance; from aerial, flatten aggressively.
	float cam_height = INV_VIEW_MATRIX[3].y - world_pos.y;
	float tex_fade = max(
		smoothstep(15.0, 50.0, cam_height),          // aerial: aggressive fade from height
		smoothstep(100.0, 250.0, cam_dist)            // ground: gentle fade at extreme distance
	);
	{
		float avg_g = dot(grass_alb, vec3(0.299, 0.587, 0.114));
		grass_alb = mix(grass_alb, vec3(avg_g), tex_fade);
	}
	// Summer lawn: strong green — terrain IS the grass carpet, 3D blades add depth.
	// The Great Lawn looks correct; push all grass surfaces to match.
	float grass_lum = dot(grass_alb, vec3(0.299, 0.587, 0.114));
	grass_alb = mix(vec3(grass_lum), grass_alb, 0.75);  // 25% desaturation — grass isn't neon in linear PBR
	grass_alb *= 0.82;  // real grass albedo is quite dark in linear space (~0.04-0.10 green channel)
	grass_alb.r *= 0.94;  // reduce red for cooler green, not warm yellow-green
	grass_alb.b *= 0.85;  // reduce blue for earthy green, not teal

	// Multi-scale grass color variation — real lawns are never uniform.
	// Aerial imagery of Central Park shows a patchwork of greens, olives, browns.

	// Define grass color targets (linear space values — these blend with PBR texture)
	// Brightened to better match 3D grass blade shader output — prevents visible grid
	vec3 lush_green    = vec3(0.07, 0.12, 0.04);  // deep rich green — recently watered
	vec3 olive_green   = vec3(0.10, 0.10, 0.04);  // olive — normal healthy grass
	vec3 yellow_stress = vec3(0.14, 0.12, 0.04);  // yellow-green — drought stress
	vec3 brown_dirt    = vec3(0.10, 0.07, 0.04);  // exposed soil/thatch

	// Scale 1: very large (100-200m) — whole-field condition (visible from aerial)
	float field_cond = vnoise(world_pos.xz * 0.003 + vec2(50.0, 23.0));
	// Mix between lush and olive at field scale — visible from 100m but subtle
	// enough that grass blade clumps don't create a grid pattern
	vec3 field_tone = mix(lush_green, olive_green, field_cond);
	grass_alb = mix(grass_alb, field_tone, 0.25);

	// Scale 2: large patches (25-40m) — drainage, irrigation, sun/shade
	float lawn_large = fbm(world_pos.xz * 0.006, 3);
	grass_alb *= 0.75 + lawn_large * 0.50;  // wider brightness range for aerial visibility

	// Scale 3: medium patches (8-15m) — mowing age, species dominance
	float lawn_med = fbm(world_pos.xz * 0.025 + 37.0, 2);
	// Yellow stress patches where grass is thin
	float stress_mask = smoothstep(0.55, 0.80, lawn_med);
	grass_alb = mix(grass_alb, yellow_stress, stress_mask * 0.25);
	grass_alb *= 0.88 + lawn_med * 0.24;

	// Scale 4: warm/cool hue patches — Kentucky bluegrass vs perennial ryegrass
	float temp_shift = fbm(world_pos.xz * 0.01 + 91.0, 2) - 0.5;
	grass_alb *= vec3(1.0 + temp_shift * 0.28, 1.0, 1.0 - temp_shift * 0.22);

	// Scale 5: small-scale thinning (2-4m) — bare spots, compaction, foot traffic
	// Reduced from 0.30 to 0.15 to prevent dark spots that contrast with 3D grass blades
	float thin_noise = vnoise(world_pos.xz * 0.15);
	float thin_patch = smoothstep(0.50, 0.70, thin_noise);
	grass_alb = mix(grass_alb, brown_dirt, thin_patch * 0.15);

	// Distance-based darkening + aerial perspective.
	// Far grass darkens (blade highlights average out, self-shadowing).
	// Also desaturate + shift slightly blue to simulate atmospheric scattering.
	// cam_dist computed above (before texture sample)
	float dist_darken = smoothstep(30.0, 150.0, cam_dist) * 0.25;
	grass_alb *= (1.0 - dist_darken);
	// Aerial perspective: desaturate + cool shift at distance
	float aerial_t = smoothstep(60.0, 300.0, cam_dist);
	float g_lum = dot(grass_alb, vec3(0.2126, 0.7152, 0.0722));
	grass_alb = mix(grass_alb, vec3(g_lum), aerial_t * 0.25);  // 25% desaturation at 300m
	grass_alb = mix(grass_alb, grass_alb * vec3(0.94, 0.96, 1.04), aerial_t);  // subtle blue shift

	// --- Seasonal grass color modulation ---
	// Spring (0-1): fresh bright green, Summer (1-2): rich green (baseline),
	// Autumn (2-3): golden-brown, Winter (3-4): dormant brown
	{
		float spring_t = 1.0 - smoothstep(0.0, 1.0, season_t);
		float autumn_t = smoothstep(2.0, 2.6, season_t) * (1.0 - smoothstep(2.8, 3.5, season_t));
		float winter_t = smoothstep(2.7, 3.1, season_t);  // dormancy starts in late autumn
		// Spring: brighter, more yellow-green
		vec3 spring_grass = grass_alb * vec3(1.1, 1.15, 0.75);
		// Autumn: golden-amber — use flat target color to prevent texture noise
		// amplification that creates visible squares from aerial views.
		// Real autumn lawns are uniformly golden with only gentle large-scale variation.
		vec3 autumn_target = vec3(0.16, 0.12, 0.04);  // golden-brown autumn lawn
		float autumn_var = vnoise(world_pos.xz * 0.008) * 0.04;  // large-scale variation only
		vec3 autumn_grass = autumn_target + autumn_var;
		// Winter: dormant brown — nearly flat color to eliminate tiling artifacts.
		// Real dormant grass is uniformly straw-brown, very little texture contrast.
		float g_lum = dot(grass_alb, vec3(0.299, 0.587, 0.114));
		// Flat dormant brown with only slight noise variation (not from texture)
		vec3 dormant_brown = vec3(0.12, 0.10, 0.06);
		float w_noise = vnoise(world_pos.xz * 0.04) * 0.03;
		vec3 winter_grass = dormant_brown + w_noise;
		grass_alb = mix(grass_alb, spring_grass, spring_t * 0.6);
		grass_alb = mix(grass_alb, autumn_grass, autumn_t * 0.7);
		grass_alb = mix(grass_alb, winter_grass, winter_t);
	}

	vec3 grass_nrm = textureNoTile_n(grass_normal, uv);
	// Flatten normal detail at distance — anti-tiling creates lighting cell artifacts
	grass_nrm = mix(grass_nrm, vec3(0.5, 0.5, 1.0), tex_fade);
	float grass_rgh = clamp(textureNoTile_r(grass_rough, uv) * 0.20 + 0.65, 0.0, 1.0);
	// Winter: completely flatten normal map and force roughness — dormant grass is
	// a flat mat of straw with no texture detail. Fully flattened normals eliminate
	// anti-tiling cell boundaries that become visible as checkerboard in winter fog.
	{
		float w_t = smoothstep(2.7, 3.1, season_t);
		grass_nrm = mix(grass_nrm, vec3(0.5, 0.5, 1.0), w_t);  // 100% flat in full winter
		grass_rgh = mix(grass_rgh, 0.95, w_t);  // fully rough
	}

	// Meadow/wild grass blend — driven by landuse zones from OSM
	// Unzoned areas (0) = woodland/meadow, zoned (garden/grass/pitch) = mowed lawn
	vec2 muv = world_pos.xz / meadow_tile_m;
	float s60 = 0.866; float c60 = 0.5;
	vec2 muv_rot = vec2(muv.x * c60 + muv.y * s60, -muv.x * s60 + muv.y * c60);
	vec3 m_alb = texture(meadow_albedo, muv_rot).rgb;
	// Distance fade for meadow texture too — prevents tiling from aerial views
	{
		float m_lum = dot(m_alb, vec3(0.299, 0.587, 0.114));
		m_alb = mix(m_alb, vec3(m_lum), tex_fade);
	}
	vec3 m_nrm_raw = texture(meadow_normal, muv_rot).rgb;
	vec3 m_nrm = vec3(
		(m_nrm_raw.r - 0.5) * c60 + (m_nrm_raw.g - 0.5) * s60 + 0.5,
		-(m_nrm_raw.r - 0.5) * s60 + (m_nrm_raw.g - 0.5) * c60 + 0.5,
		m_nrm_raw.b);
	m_nrm = mix(m_nrm, vec3(0.5, 0.5, 1.0), tex_fade);  // flatten at distance
	float m_rgh = clamp(texture(meadow_rough, muv).r * 0.20 + 0.65, 0.0, 1.0);

	// Landuse lookup: woodland zones get meadow texture, everything else is mowed lawn
	// Most of Central Park is maintained lawn — only marked woodland areas get wild texture
	float zone_val = texture(landuse_map, splat_uv).r * 255.0;
	int zone_id = int(zone_val + 0.5);
	// Woodland zones: nature_reserve(5), wood(10), forest(11) → meadow texture
	bool is_woodland = (zone_id == 5 || zone_id == 10 || zone_id == 11);
	float meadow_base = is_woodland ? 1.0 : 0.0;
	// Add FBM edge softening so zone boundaries don't look razor-sharp
	float edge_noise = fbm(world_pos.xz * 0.012, 2) * 0.15;
	float meadow_blend = clamp(meadow_base + edge_noise - 0.07, 0.0, 1.0);
	grass_alb = mix(grass_alb, m_alb, meadow_blend);
	grass_nrm = mix(grass_nrm, m_nrm, meadow_blend);
	grass_rgh = mix(grass_rgh, m_rgh, meadow_blend);

	// --- Olmsted Landscape Modes: subtle color modulation by design intent ---
	// Pastoral (open meadows): warm golden-green, brighter — "soothe and restore"
	// Picturesque (Ramble, North Woods): cool blue-green, deeper shade — "sense of mystery"
	// Formal (Mall, Bethesda, Conservatory Garden): crisp, slightly desaturated
	if (is_woodland) {
		// Picturesque: cooler, deeper, more mysterious
		grass_alb.r *= 0.88;
		grass_alb.g *= 1.04;
		grass_alb.b *= 1.10;
		grass_alb *= 0.88;  // deeper shade under canopy
	} else if (zone_id == 1) {
		// Garden zones → Formal: crisp, slightly desaturated manicured look
		float sat = dot(grass_alb, vec3(0.299, 0.587, 0.114));
		grass_alb = mix(vec3(sat), grass_alb, 0.85);  // 15% desaturation
		grass_alb *= 1.05;  // slightly brighter, well-maintained
		// Mowing stripes: alternating lighter/darker bands from reel mower passes
		// Visible on formal lawns and gardens — Conservatory Garden, Great Lawn
		float stripe = sin(world_pos.z * 0.85);  // ~3.7m stripe width (realistic)
		grass_alb *= 1.0 + stripe * 0.04;  // very subtle ±4% stripe
	} else if (zone_id == 2 || zone_id == 3) {
		// Maintained grass/pitch: mowing stripes more prominent on sports turf
		float stripe = sin(world_pos.z * 1.1);  // ~2.9m stripe width
		grass_alb *= 1.0 + stripe * 0.06;  // ±6% stripe on maintained turf
	} else if (zone_id == 8) {
		// Grass/pitch → Pastoral: warm, golden Kentucky bluegrass
		grass_alb.r *= 1.06;
		grass_alb.g *= 1.02;
		grass_alb.b *= 0.90;
	}

	// Dirt/mulch for playgrounds(4), dog_parks(6)
	bool is_dirt = (zone_id == 4 || zone_id == 6);
	if (is_dirt) {
		vec2 duv = world_pos.xz / dirt_tile_m;
		vec3 d_alb = textureNoTile_c(dirt_albedo, duv);
		vec3 d_nrm = textureNoTile_n(dirt_normal, duv);
		float d_rgh = clamp(textureNoTile_r(dirt_rough, duv) * 0.15 + 0.80, 0.0, 1.0);
		float dirt_blend = clamp(0.85 + edge_noise, 0.0, 1.0);
		grass_alb = mix(grass_alb, d_alb, dirt_blend);
		grass_nrm = mix(grass_nrm, d_nrm, dirt_blend);
		grass_rgh = mix(grass_rgh, d_rgh, dirt_blend);
	}

	// --- Surface blend weights from vertex colors (replaces splat map atlas) ---
	// Vertex colors are Gaussian-smoothed in Python → GPU hardware interpolation
	// creates natural ~2m transitions at surface boundaries. No grid artifacts.
	float paved_w = vert_color.r;    // paved path / bridge deck blend
	float unpaved_w = vert_color.g;  // unpaved trail blend
	float rock_w = vert_color.b;     // rock blend (slope + atlas combined)
	float bldg_w = vert_color.a;     // building area suppression
	float path_proximity = max(paved_w, unpaved_w);  // near any path type
	float slope = 1.0 - terrain_n.y;  // 0=flat, 1=vertical

	// --- Path-edge wear: grass thins out near paths ---
	// Vertex color interpolation gives smooth proximity — no neighbor sampling needed
	if (path_proximity > 0.02 && path_proximity < 0.6 && slope < 0.15) {
		// Transition zone: vertex color is between 0 (pure grass) and 1 (pure path)
		// This IS the worn grass-to-path edge, naturally smooth
		float wear = path_proximity * 0.50;
		float wear_noise = vnoise(world_pos.xz * 0.3) * 0.25;
		wear = clamp(wear + wear_noise - 0.05, 0.0, 0.55);
		vec3 worn_grass = grass_alb * vec3(1.18, 0.95, 0.62);  // brown, trampled dirt
		grass_alb = mix(grass_alb, worn_grass, wear);
		float worn_lum = dot(grass_alb, vec3(0.299, 0.587, 0.114));
		grass_alb = mix(grass_alb, vec3(worn_lum) * vec3(1.04, 1.0, 0.92), wear * 0.3);
		grass_rgh = mix(grass_rgh, grass_rgh + 0.12, wear);
	}

	// --- Paths: paved and unpaved surfaces (vertex color blended) ---
	// Vertex colors provide smooth blend weights — no neighbor sampling needed.
	// paved_w smoothly transitions from 0 (grass) through edge zone to 1 (path center).
	if (paved_w > 0.02 && slope < 0.20) {
		// Asphalt paving — dark gray, slightly rough
		vec2 puv = world_pos.xz / path_tile_m;
		vec3 p_alb = texture(path_alb_arr, vec3(puv, 0.0)).rgb;  // layer 0 = Asphalt
		vec3 p_nrm = texture(path_nrm_arr, vec3(puv, 0.0)).rgb;
		float p_rgh = clamp(texture(path_rgh_arr, vec3(puv, 0.0)).r + 0.05, 0.0, 1.0);
		// NYC Parks asphalt: neutral medium gray, slightly weathered
		float p_lum = dot(p_alb, vec3(0.2126, 0.7152, 0.0722));
		p_alb = mix(p_alb, vec3(p_lum), 0.5);  // 50% desaturation
		p_alb *= vec3(2.5, 2.5, 2.45);
		// Asphalt patch repairs — distinctive NYC Parks mosaic
		float patch_hash = hash2(floor(world_pos.xz * 0.25));  // 4m patch grid
		float is_patch = step(0.72, patch_hash);  // ~28% repaired
		float patch_age = fract(patch_hash * 7.3);
		p_alb *= mix(1.0, mix(0.72, 0.92, patch_age), is_patch);
		// Fine hairline cracks
		float crack_n = vnoise(world_pos.xz * 2.5);
		float crack = smoothstep(0.48, 0.50, crack_n) * smoothstep(0.52, 0.50, crack_n);
		p_alb *= mix(1.0, 0.70, crack * 0.5);
		// Patchy wear
		float wear = fbm(world_pos.xz * 0.05, 2);
		p_alb *= (0.90 + wear * 0.20);
		// Smooth blend from vertex color — natural grass-to-asphalt transition
		grass_alb = mix(grass_alb, p_alb, paved_w);
		grass_nrm = mix(grass_nrm, p_nrm, paved_w);
		grass_rgh = mix(grass_rgh, p_rgh, paved_w);
	}
	if (unpaved_w > 0.02 && slope < 0.20) {
		// Unpaved trail: compacted gravel/dirt — brown-gray
		vec2 puv = world_pos.xz / path_tile_m;
		vec3 p_alb = texture(path_alb_arr, vec3(puv, 3.0)).rgb;  // layer 3 = Gravel
		vec3 p_nrm = texture(path_nrm_arr, vec3(puv, 3.0)).rgb;
		float p_rgh = clamp(texture(path_rgh_arr, vec3(puv, 3.0)).r + 0.08, 0.0, 1.0);
		// Compacted earth tone: warm tan-gray decomposed granite
		p_alb *= vec3(2.2, 1.9, 1.6);
		// Exposed pebbles and stones
		float pebble = hash2(floor(world_pos.xz * 4.0));
		if (pebble > 0.85) {
			p_alb *= mix(1.0, 1.25, fract(pebble * 7.1));
		}
		// Ruts and puddle-prone depressions
		float rut = vnoise(world_pos.xz * 0.12);
		p_alb *= mix(0.85, 1.05, smoothstep(0.3, 0.7, rut));
		// Foot traffic variation
		float wear = fbm(world_pos.xz * 0.04, 2);
		p_alb *= (0.88 + wear * 0.24);
		// Smooth blend from vertex color — natural grass-to-gravel transition
		grass_alb = mix(grass_alb, p_alb, unpaved_w);
		grass_nrm = mix(grass_nrm, p_nrm, unpaved_w);
		grass_rgh = mix(grass_rgh, p_rgh, unpaved_w);
	}

	// Running track zones(9): distinctive reddish-brown cinder surface
	// The Reservoir track is NYC's most iconic running loop
	if (zone_id == 9) {
		vec2 duv = world_pos.xz / dirt_tile_m;
		vec3 d_alb = textureNoTile_c(dirt_albedo, duv);
		vec3 d_nrm = textureNoTile_n(dirt_normal, duv);
		float d_rgh = clamp(textureNoTile_r(dirt_rough, duv) * 0.15 + 0.72, 0.0, 1.0);
		// Cinder track: reddish-brown, compacted, slightly smoother than raw dirt
		vec3 cinder_tint = vec3(0.52, 0.32, 0.22);  // warm reddish cinder
		d_alb = mix(d_alb, d_alb * cinder_tint * 2.5, 0.6);
		float dirt_blend = clamp(0.90 + edge_noise, 0.0, 1.0);
		grass_alb = mix(grass_alb, d_alb, dirt_blend);
		grass_nrm = mix(grass_nrm, d_nrm, dirt_blend);
		grass_rgh = mix(grass_rgh, d_rgh, dirt_blend);
	}

	// Shore transition — smooth distance-based blending from shore_distance texture
	// R channel = distance from water (0-30m encoded as 0-255), filter_linear for smooth edges
	vec2 shore_sample = texture(shore_distance, splat_uv).ra;
	float shore_dist_m = shore_sample.r * 30.0;  // 0-30m range
	if (shore_dist_m < 15.0) {
		vec2 suv = world_pos.xz / shore_tile_m;
		vec3 sh_alb = textureNoTile_c(shore_albedo, suv);
		vec3 sh_nrm = textureNoTile_n(shore_normal, suv);
		float sh_rgh = clamp(textureNoTile_r(shore_rough, suv) * 0.15 + 0.80, 0.0, 1.0);
		// Smooth blend: full shore at water edge, fading to grass over 15m
		float shore_blend = smoothstep(15.0, 2.0, shore_dist_m) + edge_noise * 0.15;
		shore_blend = clamp(shore_blend, 0.0, 1.0);
		grass_alb = mix(grass_alb, sh_alb, shore_blend);
		grass_nrm = mix(grass_nrm, sh_nrm, shore_blend);
		grass_rgh = mix(grass_rgh, sh_rgh, shore_blend);
	}

	// Water zone (12) — dark muddy ground under/near water surface.
	// Uses shore_distance for smooth proximity (no atlas neighbor sampling needed).
	float water_near = 0.0;
	if (zone_id == 12) {
		water_near = 1.0;
	} else if (shore_dist_m < 3.0) {
		// Very close to water — smooth transition from shore distance field
		water_near = smoothstep(3.0, 0.5, shore_dist_m);
	}
	if (water_near > 0.01) {
		// Underwater/waterside silt/mud: dark brown-gray, organic sediment
		float mud_noise = vnoise(world_pos.xz * 0.3);
		vec3 mud_col = vec3(0.08, 0.07, 0.05) + mud_noise * vec3(0.04, 0.03, 0.02);
		grass_alb = mix(grass_alb, mud_col, clamp(water_near, 0.0, 1.0));
		grass_rgh = mix(grass_rgh, 0.95, clamp(water_near, 0.0, 1.0));
	}

	// Rock on steep slopes + vertex color rock blend — Manhattan schist outcrops
	// Schist: gray base + mica sparkle (slight specular) + rusty weathering patches
	// LiDAR at 2.4m/cell smooths real slopes significantly, so use low thresholds.
	float rock_noise = fbm(world_pos.xz * 0.05, 2) * 0.06;
	float rock_blend = smoothstep(0.10, 0.25, slope + rock_noise);
	// Vertex color B = pre-computed rock blend (slope + atlas, Gaussian smoothed)
	rock_blend = max(rock_blend, rock_w);
	float rock_specular = 0.0;
	if (rock_blend > 0.01) {
		vec2 ruv = world_pos.xz / rock_tile_m;
		vec3 r_alb = textureNoTile_c(rock_albedo, ruv);
		// Manhattan schist: dark silvery-gray metamorphic rock with mica
		// PBR rock textures are warm/sandy — remap to schist using luminance as detail
		float r_lum = dot(r_alb, vec3(0.2126, 0.7152, 0.0722));
		// Remap: dark gray base + texture detail, slight blue cool shift
		vec3 schist_gray = vec3(0.13, 0.14, 0.16) + vec3(0.30, 0.30, 0.32) * r_lum;
		r_alb = mix(r_alb, schist_gray, 0.70);  // 70% schist, 30% original detail
		// Rusty weathering patches — iron oxide staining in crevices
		float rust_noise = fbm(world_pos.xz * 0.08, 2);
		vec3 rust_tint = mix(r_alb, r_alb * vec3(1.12, 0.88, 0.72), smoothstep(0.5, 0.7, rust_noise) * 0.25);
		r_alb = rust_tint;
		vec3 r_nrm = textureNoTile_n(rock_normal, ruv);
		float r_rgh = clamp(textureNoTile_r(rock_rough, ruv) * 0.15 + 0.70, 0.0, 1.0);
		// Glacial striations on flat exposed rock (Wisconsin ice age, ~15° E of N)
		if (terrain_n.y > 0.8) {
			float sa = 0.259; float ca = 0.966;
			float glacial_u = world_pos.x * ca + world_pos.z * sa;
			float groove = sin(glacial_u * 180.0 + vnoise(world_pos.xz * 8.0) * 3.0);
			groove = smoothstep(0.3, 0.8, groove);
			float striation = smoothstep(0.8, 0.95, terrain_n.y) * 0.06;
			r_alb *= (1.0 - groove * striation);
			r_rgh += groove * striation * 0.5;
		}
		// --- Lichen colonies on Manhattan schist ---
		// Three dominant types in Central Park: green foliose (shield lichen),
		// orange crustose (Xanthoria), gray-white crustose (Lecanora).
		// Lichen prefers north-facing + shaded aspects and sheltered crevices.
		float lichen_aspect = smoothstep(-0.2, 0.3, -terrain_n.z);  // north-facing bias
		float lichen_shelter = smoothstep(0.15, 0.40, slope);  // more on vertical faces
		float lichen_base = lichen_aspect * 0.5 + lichen_shelter * 0.5;
		// Large patchy distribution — colonies are irregular, 0.5-3m patches
		float lic_n1 = fbm(world_pos.xz * 0.7, 2);
		float lic_n2 = vnoise(world_pos.xz * 1.8);
		// Green foliose lichen — largest colonies, mid-tone green on shaded rock
		float green_lic = smoothstep(0.45, 0.65, lic_n1) * lichen_base;
		green_lic *= smoothstep(0.3, 0.6, vnoise(world_pos.xz * 3.2));  // sub-patch breakup
		vec3 green_lichen_col = mix(vec3(0.22, 0.28, 0.12), vec3(0.30, 0.38, 0.15), lic_n2);
		r_alb = mix(r_alb, green_lichen_col, green_lic * 0.65);
		r_rgh = mix(r_rgh, 0.88, green_lic * 0.5);  // lichen is matte
		// Orange Xanthoria — small bright patches, scattered, sun-tolerant
		float orange_lic = smoothstep(0.60, 0.78, lic_n2 * 0.7 + vnoise(world_pos.xz * 5.0) * 0.3);
		orange_lic *= (1.0 - lichen_aspect * 0.4);  // slightly less north-bias than green
		orange_lic *= smoothstep(0.02, 0.12, slope);  // needs some slope
		vec3 orange_lichen_col = vec3(0.72, 0.45, 0.08);
		r_alb = mix(r_alb, orange_lichen_col, orange_lic * 0.35);
		r_rgh = mix(r_rgh, 0.92, orange_lic * 0.3);
		// Gray-white Lecanora — tiny pale discs, crustose, on exposed flat tops
		float gray_lic = smoothstep(0.55, 0.72, vnoise(world_pos.xz * 4.5 + 17.3));
		gray_lic *= smoothstep(0.75, 0.90, terrain_n.y);  // prefers flat exposed surfaces
		vec3 gray_lichen_col = vec3(0.68, 0.67, 0.62);
		r_alb = mix(r_alb, gray_lichen_col, gray_lic * 0.30);
		r_rgh = mix(r_rgh, 0.85, gray_lic * 0.2);
		// Darken lichen when wet (rain absorbs into thallus)
		float lichen_total = min(green_lic + orange_lic * 0.5 + gray_lic * 0.3, 1.0);
		r_alb *= mix(1.0, 0.70, lichen_total * rain_wetness);

		grass_alb = mix(grass_alb, r_alb, rock_blend);
		grass_nrm = mix(grass_nrm, r_nrm, rock_blend);
		grass_rgh = mix(grass_rgh, r_rgh, rock_blend);
		// Mica sparkle: slight specular on rock surfaces (reduced where lichen covers)
		float mica = hash2(floor(world_pos.xz * 20.0));
		rock_specular = rock_blend * mix(0.25, 0.55, step(0.92, mica)) * (1.0 - lichen_total * 0.7);
	}

	// --- Structure mask: LiDAR-detected built features get stone/concrete texture ---
	float struct_val = texture(structure_mask, splat_uv).r * 254.0;
	// Suppress near park boundary — prevents LiDAR building detections from
	// painting dark stone in the dilated grass zone under perimeter buildings
	struct_val *= smoothstep(0.3, 0.9, park_inside);
	if (struct_val > 0.5) {
		vec2 stuv = world_pos.xz / path_tile_m;
		float struct_h = struct_val;  // half-feet (val 2 = 1ft, val 20 = 10ft)
		// Use terrain slope to pick material: steep = wall stone, flat = pavement/deck
		float struct_slope = 1.0 - terrain_n.y;  // 0=flat, 1=vertical
		// Large-scale warm/cool variation — some areas sandstone-warm, others schist-gray
		float warmth = fbm(world_pos.xz * 0.004, 2);
		// Vertex color rock areas are Manhattan schist — always cool gray
		if (rock_w > 0.5) warmth = mix(warmth, 0.12, rock_w);
		// Named structure overrides — force warmth for known materials
		// Bethesda Terrace: New Brunswick sandstone (warm mustard-olive)
		float d_beth_s = length(world_pos.xz - vec2(-458.0, 949.0));
		if (d_beth_s < 60.0) warmth = 0.85;
		// Belvedere Castle / Vista Rock: Manhattan schist (cool gray)
		float d_belv = length(world_pos.xz - vec2(-215.0, 372.0));
		if (d_belv < 50.0) warmth = 0.15;
		// Gapstow Bridge area: Manhattan schist (cool gray stone bridge)
		float d_gap = length(world_pos.xz - vec2(-355.0, 1640.0));
		if (d_gap < 25.0) warmth = 0.18;
		// Huddlestone Arch: massive schist boulders (cool gray, no mortar)
		float d_hudd = length(world_pos.xz - vec2(300.0, -1050.0));
		if (d_hudd < 20.0) warmth = 0.10;
		// The Dairy: Victorian Gothic, warm stone + slate
		float d_dairy = length(world_pos.xz - vec2(-500.0, 1425.0));
		if (d_dairy < 25.0) warmth = 0.65;
		// Dana Discovery Center: warm brick + stone (Victorian)
		float d_dana = length(world_pos.xz - vec2(400.0, -1800.0));
		if (d_dana < 20.0) warmth = 0.70;
		// Naumburg Bandshell: warm limestone
		float d_naum = length(world_pos.xz - vec2(-600.0, 1500.0));
		if (d_naum < 15.0) warmth = 0.75;
		vec3 s_tint;
		float tex_layer;
		if (struct_slope > 0.35) {
			// Steep face: stone walls
			tex_layer = 2.0;  // PavingStones as base
			float weather = fbm(world_pos.xz * 0.15, 2);
			vec3 cool_base = mix(vec3(0.32, 0.33, 0.35),  // dark gray schist
			                     vec3(0.38, 0.34, 0.30),   // rusty weathering
			                     smoothstep(0.35, 0.65, weather));
			vec3 warm_base = mix(vec3(0.52, 0.47, 0.35),  // New Brunswick sandstone
			                     vec3(0.56, 0.44, 0.30),   // weathered sandstone
			                     smoothstep(0.35, 0.65, weather));
			s_tint = mix(cool_base, warm_base, smoothstep(0.4, 0.6, warmth));
		} else if (struct_slope > 0.08) {
			// Moderate slope: dressed stone / granite steps
			tex_layer = 2.0;  // PavingStones
			vec3 cool_step = vec3(0.58, 0.56, 0.52);  // gray granite
			vec3 warm_step = vec3(0.62, 0.56, 0.46);  // warm granite
			s_tint = mix(cool_step, warm_step, smoothstep(0.4, 0.6, warmth));
		} else {
			// Flat top: road deck, plaza, terrace top
			if (struct_h > 16.0) {
				tex_layer = 0.0;  // Asphalt for road decks
				s_tint = vec3(0.44, 0.42, 0.40);
			} else {
				tex_layer = 1.0;  // Concrete for plazas/platforms
				s_tint = vec3(0.66, 0.63, 0.58);  // warm gray granite
			}
		}
		vec3 s_alb = texture(path_alb_arr, vec3(stuv, tex_layer)).rgb * s_tint;
		vec3 s_nrm = texture(path_nrm_arr, vec3(stuv, tex_layer)).rgb;
		float s_rgh = clamp(texture(path_rgh_arr, vec3(stuv, tex_layer)).r + 0.08, 0.0, 1.0);
		// Hard blend — structures should look solid
		float s_blend = smoothstep(0.5, 2.0, struct_val);
		grass_alb = mix(grass_alb, s_alb, s_blend);
		grass_nrm = mix(grass_nrm, s_nrm, s_blend);
		grass_rgh = mix(grass_rgh, s_rgh, s_blend);
	}

	// --- Named plaza overrides: herringbone brick at Bethesda Terrace ---
	// Bethesda lower plaza: ~30m radius around fountain at (-458, 949)
	float d_beth = length(world_pos.xz - vec2(-458.0, 949.0));
	if (d_beth < 35.0 && slope < 0.15) {
		// Herringbone Roman brick pattern — terracotta red-brown (#A0522D)
		vec2 brick_uv = world_pos.xz * 4.0;  // ~25cm brick scale
		// Herringbone: alternating 45-degree bricks
		float bx = fract(brick_uv.x * 0.707 + brick_uv.y * 0.707);
		float bz = fract(brick_uv.x * 0.707 - brick_uv.y * 0.707);
		float herring = step(0.5, bx) * step(0.5, bz) + (1.0 - step(0.5, bx)) * (1.0 - step(0.5, bz));
		float mortar = smoothstep(0.02, 0.04, min(fract(bx * 2.0), fract(bz * 2.0)));
		vec3 brick_col = mix(vec3(0.63, 0.32, 0.18), vec3(0.55, 0.28, 0.15), herring);
		// Mortar lines: lighter
		brick_col = mix(vec3(0.72, 0.68, 0.62), brick_col, mortar);
		// Weathering variation
		float wear = fbm(world_pos.xz * 0.3, 2) * 0.15;
		brick_col *= (0.9 + wear);
		float beth_blend = smoothstep(35.0, 28.0, d_beth);
		grass_alb = mix(grass_alb, brick_col, beth_blend);
		grass_rgh = mix(grass_rgh, 0.78, beth_blend);
	}

	// --- Conservatory Garden: formal gravel paths, manicured lawn ---
	// Center of entire garden complex at (1080, -1195), ~80m radius
	float d_cg = length(world_pos.xz - vec2(1080.0, -1195.0));
	if (d_cg < 100.0 && slope < 0.10) {
		// Formal garden lawn: exceptionally green, uniform, desaturated slightly
		float cg_blend = smoothstep(100.0, 70.0, d_cg);
		float sat = dot(grass_alb, vec3(0.299, 0.587, 0.114));
		vec3 formal_green = mix(vec3(sat), grass_alb, 0.80);  // slight desaturation
		formal_green *= 1.08;  // bright, well-maintained
		grass_alb = mix(grass_alb, formal_green, cg_blend);
	}

	// --- Shakespeare Garden: rustic earth tones, wilder character ---
	// Center at (-389, 343), ~40m radius — 4-acre terraced hillside
	float d_shk = length(world_pos.xz - vec2(-389.0, 343.0));
	if (d_shk < 55.0) {
		// Warmer, earthier ground — rustic cottage garden
		float shk_blend = smoothstep(55.0, 35.0, d_shk);
		grass_alb = mix(grass_alb, grass_alb * vec3(1.08, 0.98, 0.85), shk_blend);
		grass_rgh = mix(grass_rgh, grass_rgh + 0.05, shk_blend);
	}

	// --- Cherry Hill: warm earth near Cherry Hill Fountain ---
	// Cherry Hill circular plaza at (-580, 920), ~25m radius
	float d_ch = length(world_pos.xz - vec2(-580.0, 920.0));
	if (d_ch < 30.0 && slope < 0.12) {
		float ch_blend = smoothstep(30.0, 18.0, d_ch);
		vec3 bluestone = vec3(0.42, 0.46, 0.50);  // bluestone paving
		grass_alb = mix(grass_alb, bluestone, ch_blend);
		grass_rgh = mix(grass_rgh, 0.72, ch_blend);
	}

	// Naumburg Bandshell plaza — formal paving around bandshell
	float d_naum_p = length(world_pos.xz - vec2(-600.0, 1500.0));
	if (d_naum_p < 20.0 && slope < 0.10) {
		float naum_blend = smoothstep(20.0, 12.0, d_naum_p);
		vec3 naum_pave = vec3(0.50, 0.48, 0.45);  // light gray stone paving
		grass_alb = mix(grass_alb, naum_pave, naum_blend);
		grass_rgh = mix(grass_rgh, 0.65, naum_blend);
	}

	// The Mall & Literary Walk: formal promenade, well-maintained elm canopy
	// The Mall runs roughly from (-600, 1300) to (-550, 1500) — narrow corridor
	// Literary Walk: southern end, wider, with benches and statues
	float mall_x = world_pos.x;
	float mall_z = world_pos.z;
	bool in_mall_corridor = (mall_x > -680.0 && mall_x < -430.0 && mall_z > 1200.0 && mall_z < 1520.0);
	if (in_mall_corridor && slope < 0.08) {
		// Exceptionally well-maintained formal lawn flanking the promenade
		float mall_blend = 0.35;
		// Formal grass: uniform, rich green, tightly mowed
		vec3 formal_green = grass_alb * vec3(1.0, 1.08, 0.88);  // enhanced green
		float sat = dot(formal_green, vec3(0.299, 0.587, 0.114));
		formal_green = mix(vec3(sat), formal_green, 0.85);  // slight desaturation = uniformity
		grass_alb = mix(grass_alb, formal_green, mall_blend);
		grass_rgh = mix(grass_rgh, grass_rgh * 0.95, mall_blend);  // slightly smoother mow
	}

	// Great Lawn: Kentucky bluegrass — rich maintained green
	float d_gl = length(world_pos.xz - vec2(0.0, 100.0));
	if (d_gl < 200.0 && slope < 0.08) {
		float gl_blend = smoothstep(200.0, 150.0, d_gl);
		// Kentucky bluegrass: deep green, well-maintained (linear PBR values)
		vec3 bluegrass = vec3(0.04, 0.10, 0.03);
		grass_alb = mix(grass_alb, bluegrass, gl_blend * 0.3);
	}

	// Harlem Meer shoreline: naturalistic, darker water-influenced ground
	float d_hm = length(world_pos.xz - vec2(350.0, -1750.0));
	if (d_hm < 80.0) {
		float hm_blend = smoothstep(80.0, 40.0, d_hm);
		grass_alb = mix(grass_alb, grass_alb * vec3(0.92, 1.06, 0.90), hm_blend);
	}

	// Conservatory Water: formal paving surround (flagstone/concrete)
	float d_cw = length(world_pos.xz - vec2(-152.0, 958.0));
	if (d_cw < 45.0 && d_cw > 20.0 && slope < 0.10) {
		float cw_blend = smoothstep(45.0, 35.0, d_cw) * smoothstep(20.0, 28.0, d_cw);
		vec3 flagstone = vec3(0.55, 0.53, 0.50);  // light gray flagstone paving
		grass_alb = mix(grass_alb, flagstone, cw_blend * 0.6);
		grass_rgh = mix(grass_rgh, 0.60, cw_blend * 0.5);
	}

	// Sheep Meadow: well-maintained turf, slightly warmer green
	float d_sm = length(world_pos.xz - vec2(-750.0, 1800.0));
	if (d_sm < 200.0 && slope < 0.06) {
		float sm_blend = smoothstep(200.0, 120.0, d_sm);
		grass_alb = mix(grass_alb, grass_alb * vec3(1.04, 1.02, 0.92), sm_blend);
	}

	// Strawberry Fields: formal, somber, exceptionally maintained memorial garden
	float d_sf = length(world_pos.xz - vec2(-790.0, 820.0));
	if (d_sf < 60.0 && slope < 0.10) {
		float sf_blend = smoothstep(60.0, 30.0, d_sf);
		// Formal, deep green, slightly desaturated (memorial dignity)
		float sf_lum = dot(grass_alb, vec3(0.299, 0.587, 0.114));
		vec3 formal = mix(vec3(sf_lum), grass_alb, 0.80) * vec3(0.98, 1.06, 0.92);
		grass_alb = mix(grass_alb, formal, sf_blend);
		grass_rgh = mix(grass_rgh, grass_rgh * 0.95, sf_blend);
	}

	// North Woods / The Ramble: deeper shade, earthy woodland floor
	float d_ramble = length(world_pos.xz - vec2(-400.0, 600.0));
	float d_nwoods = length(world_pos.xz - vec2(100.0, -1200.0));
	float woodland_prox = min(
		smoothstep(250.0, 100.0, d_ramble),
		1.0
	);
	woodland_prox = max(woodland_prox, smoothstep(300.0, 100.0, d_nwoods));
	if (woodland_prox > 0.01) {
		// Deeper, cooler woodland floor per Olmsted "Picturesque" design
		grass_alb = mix(grass_alb, grass_alb * vec3(0.90, 0.98, 0.95), woodland_prox * 0.5);
		grass_alb *= mix(1.0, 0.88, woodland_prox);  // darker in deep woods
	}

	ALBEDO          = grass_alb;
	vec3 _gn = grass_nrm * 2.0 - 1.0;
	_gn.xy *= 0.8;
	vec3 _gfn = normalize(terr_T * _gn.x + terr_B * _gn.y + terrain_n * _gn.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(_gfn, 0.0)).xyz);
	ROUGHNESS       = grass_rgh;
	SPECULAR        = max(0.15, rock_specular);
	METALLIC        = 0.0;

	// --- Rain wetness: darken surfaces, lower roughness, increase specular ---
	if (rain_wetness > 0.01) {
		// Wet surfaces are darker (water absorption) and glossier
		float wet = rain_wetness;
		// Darken albedo — wet surfaces absorb ~30% more light
		ALBEDO *= mix(1.0, 0.65, wet);
		// Roughness drops dramatically on wet surfaces (puddle-like specular)
		ROUGHNESS = mix(ROUGHNESS, max(ROUGHNESS * 0.3, 0.08), wet);
		// Specular increases — wet surfaces are highly reflective
		SPECULAR = mix(SPECULAR, 0.5, wet);

		// Puddle pooling — standing water collects on flat surfaces
		float flatness = terrain_n.y;
		if (flatness > 0.95) {
			// Procedural puddle mask: low-frequency noise determines puddle locations
			float puddle_noise = fbm(world_pos.xz * 0.06, 3);
			// Puddles form in noise "valleys" — threshold rises with rain intensity
			float puddle_threshold = mix(0.6, 0.25, wet);
			float puddle = smoothstep(puddle_threshold, puddle_threshold - 0.08, puddle_noise);
			puddle *= flatness;  // only on truly flat ground
			if (puddle > 0.01) {
				// Puddle: reflects sky color, dark ground underneath
				float p_sky_lum = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
				float p_night = smoothstep(0.15, 0.02, p_sky_lum);
				vec3 puddle_col = sky_reflect_color * 0.35 + ALBEDO * 0.12;
				// Night puddles reflect city light pollution instead of dark sky
				puddle_col = mix(puddle_col, vec3(0.08, 0.06, 0.03) + ALBEDO * 0.06, p_night);
				ALBEDO = mix(ALBEDO, puddle_col, puddle);
				ROUGHNESS = mix(ROUGHNESS, 0.02, puddle);
				SPECULAR = mix(SPECULAR, 0.8, puddle);
				METALLIC = mix(METALLIC, 0.0, puddle);
				// Flatten normal in puddle areas (still water)
				vec3 puddle_n = normalize((VIEW_MATRIX * vec4(vec3(0.0, 1.0, 0.0), 0.0)).xyz);
				NORMAL = mix(NORMAL, puddle_n, puddle * 0.9);
			}
		}
	}

	// --- Fallen leaf scatter in autumn ---
	// Leaves accumulate on grass near trees, along path edges, and in low areas
	// Wind biases leaf positions — leaves drift downwind over time
	{
		float leaf_autumn = smoothstep(2.0, 2.6, season_t) * (1.0 - smoothstep(3.3, 3.8, season_t));
		if (leaf_autumn > 0.01 && slope < 0.25) {
			// Wind drift: offset noise coordinates so leaves appear to blow downwind
			float wind_str = length(wind_vec);
			vec2 leaf_drift = wind_vec * TIME * 0.015;  // slow drift
			// Multi-scale leaf noise: large clumps + individual leaf scatter
			float leaf_clump = vnoise(world_pos.xz * 0.08 - leaf_drift * 0.3);
			float leaf_detail = vnoise(world_pos.xz * 0.6 - leaf_drift);
			// Leaves accumulate more in woodland
			float gather = is_woodland ? 0.5 : 0.15;
			// Leaves also gather in concave areas (low noise = low ground)
			float topo_low = 1.0 - smoothstep(0.3, 0.6, fbm(world_pos.xz * 0.02, 2));
			gather += topo_low * 0.15;
			// Wind spreads leaves more widely across open ground
			gather += wind_str * 0.08;
			float leaf_mask = smoothstep(0.3, 0.7, leaf_clump) * gather * leaf_autumn;
			leaf_mask *= smoothstep(0.2, 0.5, leaf_detail);  // break up into patches
			if (leaf_mask > 0.01) {
				// Varied leaf colors: amber, brown, red-orange
				float col_var = vnoise(world_pos.xz * 1.2);
				vec3 leaf_col = mix(
					vec3(0.45, 0.28, 0.10),  // brown
					mix(vec3(0.65, 0.35, 0.10), vec3(0.55, 0.20, 0.08), col_var),  // amber ↔ red
					smoothstep(0.3, 0.7, leaf_clump)
				);
				ALBEDO = mix(ALBEDO, leaf_col, leaf_mask * 0.65);
				ROUGHNESS = mix(ROUGHNESS, 0.92, leaf_mask * 0.5);
			}
		}
	}

	// --- Seasonal wildflower color patches ---
	// Central Park meadows bloom with distinct wildflowers throughout the year:
	// Spring: purple violets, white clover | Summer: yellow buttercups, pink clover
	// Late summer: goldenrod, purple asters | Fall: dried seed heads (handled by leaf scatter)
	{
		float spring_bloom = smoothstep(0.0, 0.5, season_t) * smoothstep(1.2, 0.7, season_t);
		float summer_bloom = smoothstep(0.5, 1.0, season_t) * smoothstep(2.3, 1.8, season_t);
		float late_summer = smoothstep(1.3, 1.8, season_t) * smoothstep(2.5, 2.0, season_t);
		float any_bloom = max(spring_bloom, max(summer_bloom, late_summer));
		if (any_bloom > 0.01 && slope < 0.15 && path_proximity < 0.3 && !is_dirt) {
			// Wildflowers prefer meadows, woodland edges, and unmowed areas
			float flower_zone = is_woodland ? 0.30 : (meadow_blend > 0.3 ? 0.60 : 0.15);
			// Noise determines where flowers appear (patchy, natural distribution)
			float f_noise = vnoise(world_pos.xz * 0.25 + vec2(55.0, 88.0));
			float f_detail = hash2(floor(world_pos.xz * 3.0));
			float f_mask = smoothstep(0.35, 0.65, f_noise) * step(0.60, f_detail) * flower_zone;
			if (f_mask > 0.01) {
				// Species selection: deterministic per-patch
				float sp_hash = hash2(floor(world_pos.xz * 0.5 + vec2(33.0)));
				vec3 flower_col;
				if (spring_bloom > 0.1 && sp_hash < 0.35) {
					// Purple violets (Viola sororia) — early spring
					flower_col = vec3(0.35, 0.18, 0.50);
					f_mask *= spring_bloom;
				} else if (spring_bloom > 0.1 && sp_hash < 0.60) {
					// White clover (Trifolium repens) — spring into summer
					flower_col = vec3(0.82, 0.80, 0.75);
					f_mask *= max(spring_bloom, summer_bloom * 0.5);
				} else if (summer_bloom > 0.1 && sp_hash < 0.75) {
					// Yellow buttercups (Ranunculus) — late spring/summer
					flower_col = vec3(0.85, 0.78, 0.15);
					f_mask *= summer_bloom;
				} else if (late_summer > 0.1 && sp_hash < 0.88) {
					// Goldenrod (Solidago) — late summer
					flower_col = vec3(0.80, 0.70, 0.12);
					f_mask *= late_summer;
				} else if (late_summer > 0.1) {
					// Purple asters (Symphyotrichum) — late summer/early fall
					flower_col = vec3(0.52, 0.28, 0.60);
					f_mask *= late_summer;
				} else {
					f_mask = 0.0;
					flower_col = vec3(0.0);
				}
				// Wildflower patches: visible clusters of color in grass
				ALBEDO = mix(ALBEDO, flower_col, f_mask * 0.50);
				// Flower petals are smoother than grass blades
				ROUGHNESS = mix(ROUGHNESS, ROUGHNESS * 0.75, f_mask * 0.35);
			}
		}
	}

	// --- Spring/summer morning dew: grass glistens with tiny water droplets ---
	// Dew appears when rain is recent (wetness > 0) on grass in spring/summer
	{
		float dew_season = smoothstep(0.0, 1.0, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
		if (dew_season > 0.01 && rain_wetness > 0.05 && rain_wetness < 0.5) {
			// After rain stops, residual wetness creates dew-like droplets
			float dew_noise = hash2(floor(world_pos.xz * 12.0));
			float dew = step(0.6, dew_noise) * dew_season * rain_wetness * 2.0;
			ROUGHNESS = mix(ROUGHNESS, 0.12, dew * 0.5);
			SPECULAR = mix(SPECULAR, 0.55, dew * 0.4);
			// Dew brightens grass slightly (moisture vividity)
			ALBEDO *= mix(1.0, 1.06, dew * 0.4);
		}
	}

	// --- Winter ground frost: rime on grass blades in cold weather ---
	// Visible in late autumn and winter mornings — white rime on grass tips
	{
		float frost_season = smoothstep(2.8, 3.5, season_t);
		if (frost_season > 0.01 && snow_cover < 0.3) {
			float frost_noise = hash2(floor(world_pos.xz * 8.0));
			float frost_mask = step(0.4, frost_noise) * frost_season;
			// Frost prefers flat, exposed grass (not under canopy)
			float exposed = is_woodland ? 0.3 : 1.0;
			frost_mask *= exposed * terrain_n.y;
			ALBEDO = mix(ALBEDO, vec3(0.85, 0.88, 0.92), frost_mask * 0.35);
			ROUGHNESS = mix(ROUGHNESS, 0.10, frost_mask * 0.5);
			SPECULAR = mix(SPECULAR, 0.6, frost_mask * 0.4);
		}
	}

	// --- Snow accumulation on flat surfaces ---
	if (snow_cover > 0.01) {
		float flatness = terrain_n.y;  // 1.0=flat, 0.0=vertical
		float snow_noise = fbm(world_pos.xz * 0.08, 2) * 0.25;
		float snow_amt = smoothstep(0.3, 0.7, flatness + snow_noise - 0.2) * snow_cover;
		vec3 snow_col = vec3(0.92, 0.93, 0.96);
		ALBEDO = mix(ALBEDO, snow_col, snow_amt);
		ROUGHNESS = mix(ROUGHNESS, 0.90, snow_amt);
		SPECULAR = mix(SPECULAR, 0.3, snow_amt);
		// Snow sparkle: individual ice crystals catch sunlight
		if (snow_amt > 0.3) {
			float sparkle = hash2(floor(world_pos.xz * 30.0));
			if (sparkle > 0.97) {
				float intensity = (sparkle - 0.97) * 33.3;  // 0-1 for top 3%
				SPECULAR = mix(SPECULAR, 0.95, intensity * snow_amt);
				ROUGHNESS = mix(ROUGHNESS, 0.02, intensity * snow_amt * 0.5);
				ALBEDO += vec3(0.05) * intensity * snow_amt;
			}
		}
	}

	// --- Ambient fill: prevent pitch-black shadows on terrain ---
	// Central Park is never in complete darkness: sky light, bounce light from
	// buildings, and diffuse ambient all contribute. Without this, shadowed
	// grass becomes an opaque black void.
	{
		float sky_lum = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
		float night_t = smoothstep(0.15, 0.02, sky_lum);
		// Day: subtle green-tinted ambient from sky/foliage bounce
		// Night: warm amber from NYC light pollution
		vec3 ambient = mix(ALBEDO * 0.12, vec3(0.020, 0.015, 0.010), night_t);
		EMISSION = ambient;
	}

	// --- Atmospheric distance fade — terrain dissolves into haze ---
	// Matches facade.gdshader haze for visual consistency
	float terr_dist = length(world_pos.xyz - INV_VIEW_MATRIX[3].xyz);
	float terr_fade = smoothstep(200.0, 600.0, terr_dist);
	if (terr_fade > 0.01) {
		float sky_lum2 = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
		vec3 haze_col = mix(vec3(0.58, 0.56, 0.52), sky_reflect_color * 0.8 + vec3(0.20), 0.35);
		float night_t2 = smoothstep(0.15, 0.02, sky_lum2);
		haze_col = mix(haze_col, vec3(0.14, 0.10, 0.06), night_t2 * 0.6);
		// Seasonal haze tint (matching facade shader)
		float autumn_h = smoothstep(1.5, 2.5, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
		haze_col = mix(haze_col, haze_col * vec3(1.10, 1.00, 0.82), autumn_h * 0.4);
		float winter_h = smoothstep(2.5, 3.5, season_t);
		haze_col = mix(haze_col, haze_col * vec3(0.90, 0.95, 1.08), winter_h * 0.3);
		ALBEDO = mix(ALBEDO, haze_col, terr_fade * 0.35);
		ROUGHNESS = mix(ROUGHNESS, 0.95, terr_fade * 0.25);
		EMISSION = mix(EMISSION, haze_col * 0.25, terr_fade * 0.4);
	}

}
