shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
global uniform vec3 sky_reflect_color;
global uniform float season_t;
global uniform float lightning_flash;

void fragment() {
	vec3 c = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;

	// Time-of-day detection from sky luminance
	float sky_lum = dot(sky_reflect_color, vec3(0.2126, 0.7152, 0.0722));
	float night_t  = smoothstep(0.15, 0.02, sky_lum);  // 1.0 at night
	float golden_t = smoothstep(0.1, 0.3, sky_lum) * smoothstep(0.5, 0.3, sky_lum);  // warm hours

	// Season detection
	float autumn_s = smoothstep(1.5, 2.5, season_t) * (1.0 - smoothstep(2.5, 3.5, season_t));
	float winter_s = smoothstep(2.5, 3.5, season_t);
	float spring_s = smoothstep(1.0, 0.0, season_t) + smoothstep(3.5, 4.0, season_t);
	spring_s = clamp(spring_s, 0.0, 1.0);

	// Warm dark floor — keep shadow detail, NYC is never pitch black
	// Slightly brighter floor at night (city light pollution)
	vec3 dark_floor = mix(vec3(0.018, 0.014, 0.012), vec3(0.022, 0.018, 0.016), night_t);
	c = max(c, dark_floor);
	// Gentle shadow shaping — softer at night to preserve detail
	c = pow(c, vec3(mix(1.06, 1.02, night_t)));

	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));

	// Split-tone: tints shift with time and season
	vec3 shadow_tint = vec3(0.85, 0.92, 1.10);    // base: teal-blue shadows
	vec3 highlight_tint = vec3(1.12, 1.04, 0.86);  // base: amber highlights

	// Night: cooler shadows, neutral highlights
	shadow_tint    = mix(shadow_tint, vec3(0.80, 0.85, 1.15), night_t);
	highlight_tint = mix(highlight_tint, vec3(1.05, 0.95, 0.85), night_t);

	// Golden hour: warmer everything
	shadow_tint    = mix(shadow_tint, vec3(0.95, 0.88, 1.02), golden_t * 0.5);
	highlight_tint = mix(highlight_tint, vec3(1.18, 1.06, 0.78), golden_t * 0.6);

	// Autumn: push amber/brown
	if (autumn_s > 0.01) {
		shadow_tint    = mix(shadow_tint, vec3(0.92, 0.86, 0.95), autumn_s * 0.3);
		highlight_tint = mix(highlight_tint, vec3(1.20, 1.02, 0.72), autumn_s * 0.4);
	}
	// Winter: desaturated, cool steel-blue
	if (winter_s > 0.01) {
		shadow_tint    = mix(shadow_tint, vec3(0.82, 0.88, 1.12), winter_s * 0.3);
		highlight_tint = mix(highlight_tint, vec3(1.02, 1.02, 0.96), winter_s * 0.3);
	}

	float shadow_blend = 1.0 - smoothstep(0.0, 0.25, lum);
	float highlight_blend = smoothstep(0.40, 0.75, lum);
	c *= mix(vec3(1.0), shadow_tint, shadow_blend * 0.45);
	c *= mix(vec3(1.0), highlight_tint, highlight_blend * 0.40);

	// Enrich greens — lush foliage (less at night, more in spring)
	float green_boost = 0.14 * (1.0 - night_t * 0.7);
	green_boost *= (1.0 + spring_s * 0.3);            // spring: lusher greens
	green_boost *= (1.0 - winter_s * 0.5);            // winter: muted foliage
	c.g *= 1.0 + green_boost * smoothstep(0.08, 0.4, c.g);
	// Deepen blues — rich sky and shadows
	float blue_boost = 0.12 * (1.0 - night_t * 0.5);
	c.b *= 1.0 + blue_boost * smoothstep(0.06, 0.35, c.b);
	// Soften reds toward warm brown (less at night)
	float red_excess = max(c.r - (c.g + c.b) * 0.5, 0.0);
	c.r -= red_excess * mix(0.20, 0.10, night_t);
	c.g += red_excess * 0.05;

	// Softer S-curve — luminous midtones, visible shadows
	c = c * c / (c * c + 0.08) * 1.08;

	// Saturate — reduce at night and winter for mood
	float lum2 = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float sat = 1.35;
	sat = mix(sat, 1.10, night_t);     // less saturated at night
	sat = mix(sat, sat * 0.85, winter_s * 0.4);  // cooler winter
	c = mix(vec3(lum2), c, sat);

	// Warm amber cast — less at night (more blue-gray)
	vec3 cast = mix(vec3(1.05, 1.01, 0.92), vec3(0.98, 0.98, 1.02), night_t);
	// Golden hour: stronger warm cast
	cast = mix(cast, vec3(1.10, 1.03, 0.86), golden_t * 0.4);
	c *= cast;

	// Eye adaptation — lift shadows in very dark scenes (NYC never pitch black)
	float scene_lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float lift = smoothstep(0.04, 0.0, scene_lum) * night_t * 0.015;
	c += lift;

	// Vignette — darker edges deepen the tunnel-vision glow
	// Stronger at night (lamplight pools), softer during day
	vec2 vig_uv = SCREEN_UV * 2.0 - 1.0;
	float vig_strength = mix(0.18, 0.28, night_t);
	float vig = 1.0 - dot(vig_uv, vig_uv) * vig_strength;
	c *= vig;

	// Lightning flash — bright white wash, reduced vignette, desaturated
	if (lightning_flash > 0.01) {
		float lf = lightning_flash;
		// Wash toward blue-white (lightning color temperature ~15000K)
		vec3 flash_col = vec3(0.85, 0.88, 1.0);
		c = mix(c, flash_col, lf * 0.4);
		// Brighten
		c += flash_col * lf * 0.15;
		// Desaturate during flash (bright light washes out color)
		float flash_lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c = mix(c, vec3(flash_lum), lf * 0.5);
	}

	// Film grain — subtle photographic texture, more visible at night
	float grain_seed = dot(SCREEN_UV, vec2(12.9898, 78.233)) + TIME * 0.1;
	float grain = fract(sin(grain_seed) * 43758.5453) - 0.5;
	float grain_strength = mix(0.012, 0.025, night_t);  // subtler in daylight
	c += grain * grain_strength;

	COLOR = vec4(c, 1.0);
}
