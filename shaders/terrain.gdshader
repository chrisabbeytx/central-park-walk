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

varying vec3 world_pos;

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
	// No vertex displacement — LiDAR heightmap provides natural terrain variation.
	// Previous noise displacement created visible grid-square artifacts at 2.4m cell size.
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
	vec3 grass_alb = textureNoTile_c(grass_albedo, uv);
	// Natural grass: moderate color correction (texture is quite saturated)
	float grass_lum = dot(grass_alb, vec3(0.299, 0.587, 0.114));
	grass_alb = mix(vec3(grass_lum), grass_alb, 0.88);  // 12% desaturation
	grass_alb.g *= 1.02;  // very mild green boost (was 1.12 — too neon)
	// Large-scale color variation: breaks up uniformity across wide lawns
	float lawn_noise = fbm(world_pos.xz * 0.006, 2);
	float lawn_warm  = fbm(world_pos.xz * 0.003 + vec2(100.0), 2);
	grass_alb *= 0.94 + lawn_noise * 0.12;  // ±6% brightness variation
	grass_alb.r += lawn_warm * 0.015;       // subtle warm/cool patches
	grass_alb.b -= lawn_warm * 0.01;

	// --- Seasonal grass color modulation ---
	// Spring (0-1): fresh bright green, Summer (1-2): rich green (baseline),
	// Autumn (2-3): golden-brown, Winter (3-4): dormant brown
	{
		float spring_t = 1.0 - smoothstep(0.0, 1.0, season_t);
		float autumn_t = smoothstep(2.0, 2.8, season_t) * (1.0 - smoothstep(3.2, 4.0, season_t));
		float winter_t = smoothstep(3.0, 3.5, season_t);
		// Spring: brighter, more yellow-green
		vec3 spring_grass = grass_alb * vec3(1.1, 1.15, 0.75);
		// Autumn: golden-amber, desaturated
		vec3 autumn_grass = grass_alb * vec3(1.3, 0.85, 0.45);
		// Winter: dormant brown, desaturated
		float g_lum = dot(grass_alb, vec3(0.299, 0.587, 0.114));
		vec3 winter_grass = mix(vec3(g_lum), grass_alb, 0.3) * vec3(0.85, 0.78, 0.55);
		grass_alb = mix(grass_alb, spring_grass, spring_t * 0.6);
		grass_alb = mix(grass_alb, autumn_grass, autumn_t * 0.7);
		grass_alb = mix(grass_alb, winter_grass, winter_t * 0.8);
	}

	vec3 grass_nrm = textureNoTile_n(grass_normal, uv);
	float grass_rgh = clamp(textureNoTile_r(grass_rough, uv) * 0.20 + 0.65, 0.0, 1.0);

	// Meadow/wild grass blend — driven by landuse zones from OSM
	// Unzoned areas (0) = woodland/meadow, zoned (garden/grass/pitch) = mowed lawn
	vec2 muv = world_pos.xz / meadow_tile_m;
	float s60 = 0.866; float c60 = 0.5;
	vec2 muv_rot = vec2(muv.x * c60 + muv.y * s60, -muv.x * s60 + muv.y * c60);
	vec3 m_alb = texture(meadow_albedo, muv_rot).rgb;
	vec3 m_nrm_raw = texture(meadow_normal, muv_rot).rgb;
	vec3 m_nrm = vec3(
		(m_nrm_raw.r - 0.5) * c60 + (m_nrm_raw.g - 0.5) * s60 + 0.5,
		-(m_nrm_raw.r - 0.5) * s60 + (m_nrm_raw.g - 0.5) * c60 + 0.5,
		m_nrm_raw.b);
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
	} else if (zone_id == 3 || zone_id == 8) {
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

	// Water zone (12) — dark muddy ground under water surface
	if (zone_id == 12) {
		grass_alb = vec3(0.12, 0.11, 0.08);
		grass_rgh = 0.95;
	}

	// Rock on steep slopes — Manhattan schist outcrops
	// Schist: gray base + mica sparkle (slight specular) + rusty weathering patches
	// LiDAR at 2.4m/cell smooths real slopes significantly, so use low thresholds.
	float slope = 1.0 - terrain_n.y;  // 0=flat, 1=vertical
	float rock_noise = fbm(world_pos.xz * 0.05, 2) * 0.06;
	float rock_blend = smoothstep(0.10, 0.25, slope + rock_noise);
	float rock_specular = 0.0;
	if (rock_blend > 0.01) {
		vec2 ruv = world_pos.xz / rock_tile_m;
		vec3 r_alb = textureNoTile_c(rock_albedo, ruv);
		// Add rusty weathering patches to match Manhattan schist appearance
		float rust_noise = fbm(world_pos.xz * 0.08, 2);
		vec3 rust_tint = mix(r_alb, r_alb * vec3(1.15, 0.85, 0.70), smoothstep(0.5, 0.7, rust_noise) * 0.3);
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
		grass_alb = mix(grass_alb, r_alb, rock_blend);
		grass_nrm = mix(grass_nrm, r_nrm, rock_blend);
		grass_rgh = mix(grass_rgh, r_rgh, rock_blend);
		// Mica sparkle: slight specular on rock surfaces
		float mica = hash2(floor(world_pos.xz * 20.0));
		rock_specular = rock_blend * mix(0.25, 0.55, step(0.92, mica));
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
			vec3 cool_base = mix(vec3(0.42, 0.40, 0.38),  // gray schist
			                     vec3(0.48, 0.36, 0.28),   // rusty weathering
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
		// Kentucky bluegrass: rich green, well-maintained
		vec3 bluegrass = vec3(0.23, 0.49, 0.23);
		grass_alb = mix(grass_alb, bluegrass, gl_blend * 0.4);
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

	// --- Atmospheric distance fade — terrain dissolves into haze ---
	// Matches facade.gdshader haze for visual consistency
	float terr_dist = length(world_pos.xyz - INV_VIEW_MATRIX[3].xyz);
	float terr_fade = smoothstep(200.0, 600.0, terr_dist);
	if (terr_fade > 0.01) {
		float sky_lum = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
		vec3 haze_col = mix(vec3(0.58, 0.56, 0.52), sky_reflect_color * 0.8 + vec3(0.20), 0.35);
		float night_t = smoothstep(0.15, 0.02, sky_lum);
		haze_col = mix(haze_col, vec3(0.14, 0.10, 0.06), night_t * 0.6);
		// Seasonal haze tint (matching facade shader)
		float autumn_h = smoothstep(1.5, 2.5, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
		haze_col = mix(haze_col, haze_col * vec3(1.10, 1.00, 0.82), autumn_h * 0.4);
		float winter_h = smoothstep(2.5, 3.5, season_t);
		haze_col = mix(haze_col, haze_col * vec3(0.90, 0.95, 1.08), winter_h * 0.3);
		ALBEDO = mix(ALBEDO, haze_col, terr_fade * 0.35);
		ROUGHNESS = mix(ROUGHNESS, 0.95, terr_fade * 0.25);
	}

}
