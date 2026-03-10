shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform vec3 albedo_tint = vec3(0.28, 0.48, 0.18);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

global uniform vec2 wind_vec;
global uniform float snow_cover;
global uniform float season_t;
global uniform float rain_wetness;

// Species fall colors (12): oak, maple, elm, birch, deciduous, conifer,
// honeylocust, callery_pear, ginkgo, london_plane, linden, cherry
const vec3 FALL_COLORS[12] = vec3[12](
	vec3(0.55, 0.25, 0.12),  // 0 oak: russet red-brown
	vec3(0.85, 0.22, 0.08),  // 1 maple: brilliant red-orange
	vec3(0.78, 0.72, 0.18),  // 2 elm: golden yellow
	vec3(0.82, 0.75, 0.22),  // 3 birch: bright yellow
	vec3(0.65, 0.45, 0.15),  // 4 deciduous: amber
	vec3(0.14, 0.30, 0.10),  // 5 conifer: stays green
	vec3(0.80, 0.75, 0.28),  // 6 honeylocust: clear golden yellow
	vec3(0.72, 0.18, 0.12),  // 7 callery_pear: deep red-purple
	vec3(0.92, 0.85, 0.20),  // 8 ginkgo: brilliant pure yellow
	vec3(0.70, 0.52, 0.18),  // 9 london_plane: tawny brown-gold
	vec3(0.78, 0.70, 0.22),  // 10 linden: warm yellow
	vec3(0.80, 0.30, 0.15)   // 11 cherry: orange-red
);

// Phenology timing per species: (fall_start, fall_peak, bare_start, leaf_start)
const vec4 PHENOLOGY[12] = vec4[12](
	vec4(2.3, 2.7, 3.1, 0.4),  // 0 oak: late, holds leaves
	vec4(2.1, 2.5, 2.9, 0.3),  // 1 maple: classic mid-fall
	vec4(2.2, 2.6, 3.0, 0.3),  // 2 elm: mid-fall
	vec4(2.0, 2.4, 2.8, 0.2),  // 3 birch: early fall, early spring
	vec4(2.2, 2.6, 3.0, 0.3),  // 4 deciduous: average
	vec4(0.0, 0.0, 0.0, 0.0),  // 5 conifer (unused — evergreen)
	vec4(2.0, 2.3, 2.6, 0.4),  // 6 honeylocust: early, drops fast
	vec4(2.3, 2.7, 3.1, 0.3),  // 7 callery_pear: late, persistent
	vec4(2.4, 2.6, 2.8, 0.5),  // 8 ginkgo: very late, drops all at once
	vec4(2.2, 2.6, 3.0, 0.3),  // 9 london_plane: mid-fall, persistent
	vec4(2.1, 2.5, 2.9, 0.3),  // 10 linden: mid-fall
	vec4(2.0, 2.4, 2.8, 0.3)   // 11 cherry: early fall
);

varying float v_leaf_density;
varying vec3 v_leaf_color;
varying float v_blossom;     // 0-1 blossom intensity (cherry/callery pear spring bloom)
varying float v_species_idx; // species index for fragment shader

// Spring blossom colors: cherry = pink, callery_pear = white
const vec3 BLOSSOM_COLORS[12] = vec3[12](
	vec3(0.0),                     // 0 oak: no blossoms
	vec3(0.0),                     // 1 maple: no blossoms
	vec3(0.0),                     // 2 elm: no blossoms
	vec3(0.0),                     // 3 birch: no blossoms
	vec3(0.0),                     // 4 deciduous: no blossoms
	vec3(0.0),                     // 5 conifer: no blossoms
	vec3(0.0),                     // 6 honeylocust: no blossoms
	vec3(0.92, 0.90, 0.85),       // 7 callery_pear: white blossoms (Bradford pear)
	vec3(0.0),                     // 8 ginkgo: no blossoms
	vec3(0.0),                     // 9 london_plane: no blossoms
	vec3(0.0),                     // 10 linden: no blossoms
	vec3(0.88, 0.68, 0.72)        // 11 cherry: Yoshino pale pink blossoms
);

// Blossom timing: (start, peak, end) — before leaf-out
// season_t 0=spring start, 1=summer, 2=autumn, 3=winter
const vec3 BLOSSOM_TIMING[12] = vec3[12](
	vec3(0.0),                     // 0 oak
	vec3(0.0),                     // 1 maple
	vec3(0.0),                     // 2 elm
	vec3(0.0),                     // 3 birch
	vec3(0.0),                     // 4 deciduous
	vec3(0.0),                     // 5 conifer
	vec3(0.0),                     // 6 honeylocust
	vec3(0.15, 0.30, 0.50),       // 7 callery_pear: early spring, short bloom
	vec3(0.0),                     // 8 ginkgo
	vec3(0.0),                     // 9 london_plane
	vec3(0.0),                     // 10 linden
	vec3(0.05, 0.20, 0.42)        // 11 cherry: very early, 2-week bloom peak
);

void vertex() {
	// Decode per-instance season data (all INSTANCE_CUSTOM reads in vertex only)
	float is_evergreen = INSTANCE_CUSTOM.b;
	int sp_idx = int(INSTANCE_CUSTOM.r * 11.0 + 0.5);
	float timing_off = INSTANCE_CUSTOM.g - 0.5;
	float s = mod(season_t + timing_off, 4.0);
	v_species_idx = float(sp_idx);

	// Compute leaf density for vertex shrinking and fragment alpha
	float leaf_density = 1.0;
	if (is_evergreen < 0.5) {
		vec4 ph = PHENOLOGY[sp_idx];
		float shedding = 1.0 - smoothstep(ph.z - 0.2, ph.z + 0.3, s);
		float regrowth = smoothstep(ph.w - 0.1, ph.w + 0.3, s);
		leaf_density = max(shedding, regrowth);
		leaf_density = clamp(leaf_density, 0.08, 1.0);
	}
	v_leaf_density = leaf_density;

	// Spring blossom phase (cherry, callery pear)
	float blossom = 0.0;
	vec3 bt = BLOSSOM_TIMING[sp_idx];
	if (bt.y > 0.0) {  // species has blossoms
		// Ramp up to peak, then fade
		float bloom_up = smoothstep(bt.x, bt.y, s);
		float bloom_dn = 1.0 - smoothstep(bt.y, bt.z, s);
		blossom = bloom_up * bloom_dn;
		// Blossoms boost density during bloom (full canopy of flowers)
		leaf_density = max(leaf_density, blossom * 0.85);
		v_leaf_density = leaf_density;
	}
	v_blossom = blossom;

	// Compute seasonal leaf color in vertex, pass to fragment via varying
	vec3 leaf_color = albedo_tint;
	if (is_evergreen < 0.5) {
		vec4 ph = PHENOLOGY[sp_idx];
		vec3 fall_col = FALL_COLORS[sp_idx];
		vec3 spring_tint = albedo_tint * vec3(1.15, 1.2, 0.7);
		float spring_t = smoothstep(ph.w, ph.w + 0.4, s);
		leaf_color = mix(spring_tint, albedo_tint, spring_t);
		float fall_t = smoothstep(ph.x, ph.y, s);
		leaf_color = mix(leaf_color, fall_col, fall_t);
		float late_fall = smoothstep(ph.y, ph.z, s);
		leaf_color = mix(leaf_color, fall_col * 0.5, late_fall * 0.6);
	}
	// Blend blossom color during bloom
	if (blossom > 0.01) {
		vec3 blossom_col = BLOSSOM_COLORS[sp_idx];
		// Per-tree variation: some trees slightly pinker/whiter
		blossom_col += (timing_off * 0.06) * vec3(0.08, -0.04, -0.02);
		leaf_color = mix(leaf_color, blossom_col, blossom * 0.9);
	}
	v_leaf_color = leaf_color;

	vec3 tree_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = max(VERTEX.y, 0.0);
	float wind_str = length(wind_vec);
	float rustle = (0.3 + wind_str * 0.7) * mix(0.3, 1.0, leaf_density);
	// Base sway: gentle continuous oscillation
	VERTEX.x += sin(TIME * 0.7 + tree_origin.x * 0.04 + tree_origin.z * 0.06) * 0.09 * sway * rustle;
	VERTEX.z += sin(TIME * 1.1 + tree_origin.z * 0.05) * 0.05 * sway * rustle;
	// Wind push: constant lean in wind direction
	VERTEX.x += wind_vec.x * sway * 0.18;
	VERTEX.z += wind_vec.y * sway * 0.18;
	// Wind gusts: periodic stronger push that travels across the canopy
	float gust_phase = tree_origin.x * 0.02 + tree_origin.z * 0.03;  // spatial wave
	float gust = sin(TIME * 0.3 + gust_phase) * 0.5 + 0.5;  // 0-1 gust intensity
	gust = gust * gust * gust;  // sharpen peaks: brief strong gusts, long calm
	float gust_strength = gust * wind_str * 0.25;
	VERTEX.x += wind_vec.x * sway * gust_strength;
	VERTEX.z += wind_vec.y * sway * gust_strength;
	// Leaf flutter: high-frequency per-leaf vibration
	float flutter = sin(TIME * 3.5 + VERTEX.x * 11.0 + VERTEX.z * 7.0) * 0.012 * rustle;
	flutter += sin(TIME * 5.7 + VERTEX.z * 17.0) * 0.006 * gust_strength;  // gust flutter
	VERTEX.y += flutter * sway;

	// Winter: shrink canopy toward trunk
	if (is_evergreen < 0.5 && leaf_density < 0.5) {
		float shrink = mix(0.4, 1.0, leaf_density * 2.0);
		VERTEX.xz *= shrink;
	}
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float lum = dot(tex.rgb, vec3(0.3, 0.6, 0.1));
	float alpha = tex.a * v_leaf_density;
	if (alpha < alpha_scissor) discard;

	vec3 col = v_leaf_color * (0.6 + lum * 0.8);
	int sp = int(v_species_idx + 0.5);

	// --- Species-specific material properties ---
	// Broad-leaved trees (maple, london plane) have smoother, more reflective leaves
	// Compound-leaved (honeylocust) and small-leaved (birch) are finer-textured
	float rough = 0.88;
	float spec = 0.08;
	if (sp == 1) { rough = 0.78; spec = 0.12; }        // maple: waxy broad leaf
	else if (sp == 3) { rough = 0.92; spec = 0.06; }    // birch: small matte leaves
	else if (sp == 5) { rough = 0.95; spec = 0.04; }    // conifer: needle texture
	else if (sp == 6) { rough = 0.90; spec = 0.07; }    // honeylocust: tiny compound leaflets
	else if (sp == 8) { rough = 0.75; spec = 0.14; }    // ginkgo: smooth fan-shaped
	else if (sp == 9) { rough = 0.80; spec = 0.11; }    // london plane: large waxy leaves

	// --- Blossom rendering: petals are smoother, more translucent ---
	if (v_blossom > 0.01) {
		// Petals have a delicate translucent quality
		rough = mix(rough, 0.55, v_blossom);    // smooth petal surface
		spec = mix(spec, 0.22, v_blossom);       // subtle sheen on petals
		// Slight per-petal color variation from texture luminance
		float petal_var = lum * 0.15;
		col += vec3(petal_var, petal_var * 0.8, petal_var * 0.7) * v_blossom;
	}

	// Snow accumulation
	if (snow_cover > 0.01) {
		vec3 world_n = mat3(INV_VIEW_MATRIX) * NORMAL;
		float upward = max(world_n.y, 0.0);
		vec3 tree_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float noise = sin(tree_pos.x * 0.3 + tree_pos.z * 0.4) * 0.15;
		float snow_amt = clamp((0.3 + upward * 0.7 + noise) * snow_cover, 0.0, 1.0);
		col = mix(col, vec3(0.92, 0.93, 0.96), snow_amt * 0.65);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = 0.0;

	// Rain: wet leaves darken and get glossier (water film on surface)
	if (rain_wetness > 0.01) {
		ALBEDO *= mix(1.0, 0.70, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, 0.25, rain_wetness);
		SPECULAR = mix(SPECULAR, 0.35, rain_wetness);
		// Rain droplets clinging to leaf surfaces — individual water beads
		float droplet = sin(UV.x * 28.0) * sin(UV.y * 35.0);
		droplet = smoothstep(0.85, 0.95, droplet) * rain_wetness;
		ROUGHNESS = mix(ROUGHNESS, 0.04, droplet * 0.3);
		SPECULAR = mix(SPECULAR, 0.50, droplet * 0.4);
	}

	// Ambient emission for shadow fill — leaves should never be pitch black
	EMISSION = ALBEDO * 0.08;

	// --- Enhanced subsurface scattering ---
	// Light passing through thin leaves creates warm glow
	// Stronger in spring (fresh thin leaves), reduced in fall (dry/thick), absent in winter
	vec3 backlight_col = vec3(0.28, 0.20, 0.06);  // base warm SSS
	// Tint backlight with leaf color: autumn leaves glow warm amber/red
	backlight_col = mix(backlight_col, v_leaf_color * 0.5, 0.4);
	float sss_strength = v_leaf_density;
	// Spring leaves are thinner, more translucent
	float spring_boost = (1.0 - smoothstep(0.3, 0.8, season_t)) * 0.3;
	sss_strength += spring_boost;
	// Conifer needles have minimal SSS
	if (sp == 5) sss_strength *= 0.3;
	// Blossom petals: strong pink/white translucency (backlit cherry blossoms are iconic)
	if (v_blossom > 0.01) {
		vec3 petal_sss = BLOSSOM_COLORS[sp] * 0.7;  // petal color glows through
		backlight_col = mix(backlight_col, petal_sss, v_blossom);
		sss_strength = mix(sss_strength, 1.2, v_blossom);  // petals are very translucent
	}
	BACKLIGHT = backlight_col * sss_strength;
}
