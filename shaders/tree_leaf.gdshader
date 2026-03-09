shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform vec3 albedo_tint = vec3(0.28, 0.48, 0.18);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;

global uniform vec2 wind_vec;
global uniform float snow_cover;
global uniform float season_t;

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

void vertex() {
	// Decode per-instance season data (all INSTANCE_CUSTOM reads in vertex only)
	float is_evergreen = INSTANCE_CUSTOM.b;
	int sp_idx = int(INSTANCE_CUSTOM.r * 11.0 + 0.5);
	float timing_off = INSTANCE_CUSTOM.g - 0.5;
	float s = mod(season_t + timing_off, 4.0);

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
	v_leaf_color = leaf_color;

	vec3 tree_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = max(VERTEX.y, 0.0);
	float wind_str = length(wind_vec);
	float rustle = (0.3 + wind_str * 0.7) * mix(0.3, 1.0, leaf_density);
	VERTEX.x += sin(TIME * 0.7 + tree_origin.x * 0.04 + tree_origin.z * 0.06) * 0.09 * sway * rustle;
	VERTEX.z += sin(TIME * 1.1 + tree_origin.z * 0.05) * 0.05 * sway * rustle;
	VERTEX.x += wind_vec.x * sway * 0.18;
	VERTEX.z += wind_vec.y * sway * 0.18;
	float flutter = sin(TIME * 3.5 + VERTEX.x * 11.0 + VERTEX.z * 7.0) * 0.012 * rustle;
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
	ROUGHNESS = 0.88;
	SPECULAR = 0.08;
	METALLIC = 0.0;
	BACKLIGHT = vec3(0.28, 0.20, 0.06) * v_leaf_density;
}
