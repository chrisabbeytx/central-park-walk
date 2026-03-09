shader_type spatial;
render_mode cull_disabled;

uniform sampler2D tex_alb : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_nrm : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
global uniform float rain_wetness;
global uniform float snow_cover;
global uniform float season_t;

varying vec3 world_pos;
varying vec3 world_nrm;

#include "res://shaders/include/hash_noise.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Triplanar UV: blend XZ (top/ceiling), XY (front/back), YZ (sides)
	vec3 blend = abs(world_nrm);
	blend = pow(blend, vec3(4.0));
	blend /= (blend.x + blend.y + blend.z + 0.001);
	float tile = 2.0;   // 2 m texture tile
	vec3 alb = texture(tex_alb, world_pos.xz / tile).rgb * blend.y
	         + texture(tex_alb, world_pos.xy / tile).rgb * blend.z
	         + texture(tex_alb, world_pos.yz / tile).rgb * blend.x;
	vec3 nrm = texture(tex_nrm, world_pos.xz / tile).rgb * blend.y
	         + texture(tex_nrm, world_pos.xy / tile).rgb * blend.z
	         + texture(tex_nrm, world_pos.yz / tile).rgb * blend.x;
	float rgh = texture(tex_rgh, world_pos.xz / tile).r * blend.y
	          + texture(tex_rgh, world_pos.xy / tile).r * blend.z
	          + texture(tex_rgh, world_pos.yz / tile).r * blend.x;
	ALBEDO     = alb * tint.rgb;
	NORMAL_MAP = nrm;
	ROUGHNESS  = clamp(rgh + 0.05, 0.0, 1.0);
	METALLIC   = 0.0;
	SPECULAR   = 0.10;

	// Mica sparkle: Manhattan schist has visible mica flakes catching light
	float mica = hash2(floor(world_pos.xz * 20.0 + world_pos.yy * 15.0));
	if (mica > 0.92) {
		SPECULAR = mix(SPECULAR, 0.55, (mica - 0.92) * 12.5);
		ALBEDO += vec3(0.03, 0.03, 0.04) * (mica - 0.92) * 12.5;
	}

	// Glacial striations: Wisconsin ice age scoring on exposed horizontal surfaces
	// Direction ~NNE-SSW (15° east of north) — visible on bridge copings, wall tops
	if (world_nrm.y > 0.7) {
		// Rotated UV aligned to glacial flow direction (~15° east of north)
		float sa = 0.259; float ca = 0.966;  // sin/cos(15°)
		float glacial_u = world_pos.x * ca + world_pos.z * sa;
		float glacial_v = -world_pos.x * sa + world_pos.z * ca;
		// Parallel grooves at ~2cm spacing with variation
		float groove = sin(glacial_u * 180.0 + vnoise(vec2(glacial_u, glacial_v) * 8.0) * 3.0);
		groove = smoothstep(0.3, 0.8, groove);
		// Only on relatively flat, exposed stone (bridges, outcrops, wall tops)
		float striation_strength = smoothstep(0.7, 0.95, world_nrm.y) * 0.08;
		ALBEDO *= (1.0 - groove * striation_strength);
		ROUGHNESS += groove * striation_strength * 0.5;
	}

	// Age weathering: dirt accumulation in crevices, staining on faces
	float weather_noise = fbm3(world_pos.xz * 0.12);
	float stain_noise   = fbm3(world_pos.xz * 0.04 + vec2(50.0));
	// Dirt streaks: darker in low areas and crevices (vertical bias)
	float vertical_dirt = (1.0 - world_nrm.y) * 0.15 * weather_noise;
	ALBEDO *= (1.0 - vertical_dirt);
	// Large-scale staining variation: some blocks darker than others
	ALBEDO *= (0.92 + stain_noise * 0.16);

	// Moss growth: north-facing surfaces in shaded, moist areas
	// Moss is more prevalent in spring/summer, dies back in winter
	float spring_summer = smoothstep(0.0, 1.0, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
	float moss_facing = max(0.0, -world_nrm.z) * 0.5 + max(0.0, -world_nrm.x) * 0.3;
	// Moss prefers sheltered lower portions of walls and shaded faces
	float moss_noise = fbm3(world_pos.xz * 0.25 + vec2(100.0));
	float moss_mask = moss_facing * smoothstep(0.4, 0.7, moss_noise) * spring_summer;
	moss_mask *= smoothstep(3.0, 0.5, world_pos.y);  // more at base of structures
	if (moss_mask > 0.01) {
		vec3 moss_col = mix(vec3(0.12, 0.22, 0.08), vec3(0.18, 0.28, 0.10), moss_noise);
		ALBEDO = mix(ALBEDO, moss_col, moss_mask * 0.4);
		ROUGHNESS = mix(ROUGHNESS, 0.92, moss_mask * 0.5);
		SPECULAR = mix(SPECULAR, 0.04, moss_mask * 0.3);
	}

	// Rain: wet stone darkens and gets reflective sheen
	if (rain_wetness > 0.01) {
		ALBEDO *= mix(1.0, 0.60, rain_wetness);
		ROUGHNESS = mix(ROUGHNESS, max(ROUGHNESS * 0.25, 0.06), rain_wetness);
		SPECULAR = mix(SPECULAR, 0.45, rain_wetness);
		// Wet moss becomes more vivid
		if (moss_mask > 0.01) {
			ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.85, 1.15, 0.80), moss_mask * rain_wetness * 0.3);
		}
	}

	// Winter frost on stone — ice crystals in crevices
	float winter_t = smoothstep(2.5, 3.5, season_t);
	if (winter_t > 0.01 && rain_wetness < 0.1) {
		float frost_noise = hash2(floor(world_pos.xz * 6.0));
		float frost = step(0.5, frost_noise) * winter_t * 0.3;
		// Frost prefers upward and sheltered faces
		frost *= (0.3 + world_nrm.y * 0.7);
		ALBEDO = mix(ALBEDO, vec3(0.82, 0.85, 0.90), frost);
		ROUGHNESS = mix(ROUGHNESS, 0.10, frost * 0.5);
		SPECULAR = mix(SPECULAR, 0.5, frost * 0.4);
	}

	// Snow on upward-facing surfaces
	if (snow_cover > 0.01 && world_nrm.y > 0.5) {
		float snow_noise = hash2(floor(world_pos.xz * 3.0)) * 0.2;
		float snow_amt = clamp((world_nrm.y - 0.5) * 2.0 * snow_cover + snow_noise, 0.0, 1.0);
		ALBEDO = mix(ALBEDO, vec3(0.92, 0.93, 0.96), snow_amt * 0.7);
		ROUGHNESS = mix(ROUGHNESS, 0.90, snow_amt);
	}
}
