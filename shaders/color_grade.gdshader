shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

void fragment() {
	vec3 c = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;

	// Warm dark floor — keep some shadow detail
	c = max(c, vec3(0.012, 0.009, 0.007));
	// Gentle shadow shaping
	c = pow(c, vec3(1.06));

	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));

	// Split-tone: deep teal-blue shadows, toasty amber highlights
	vec3 shadow_tint = vec3(0.85, 0.92, 1.10);
	vec3 highlight_tint = vec3(1.12, 1.04, 0.86);
	float shadow_blend = 1.0 - smoothstep(0.0, 0.25, lum);
	float highlight_blend = smoothstep(0.40, 0.75, lum);
	c *= mix(vec3(1.0), shadow_tint, shadow_blend * 0.45);
	c *= mix(vec3(1.0), highlight_tint, highlight_blend * 0.40);

	// Enrich greens — lush summer foliage
	c.g *= 1.0 + 0.14 * smoothstep(0.08, 0.4, c.g);
	// Deepen blues — rich sky and shadows
	c.b *= 1.0 + 0.12 * smoothstep(0.06, 0.35, c.b);
	// Soften reds toward warm brown
	float red_excess = max(c.r - (c.g + c.b) * 0.5, 0.0);
	c.r -= red_excess * 0.20;
	c.g += red_excess * 0.05;

	// Softer S-curve — luminous midtones, visible shadows
	c = c * c / (c * c + 0.12) * 1.12;

	// Saturate — colors glow against the dark background
	float lum2 = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(lum2), c, 1.35);

	// Warm amber cast
	c *= vec3(1.05, 1.01, 0.92);

	// Vignette — darker edges deepen the tunnel-vision glow
	vec2 vig_uv = SCREEN_UV * 2.0 - 1.0;
	float vig = 1.0 - dot(vig_uv, vig_uv) * 0.20;
	c *= vig;

	COLOR = vec4(c, 1.0);
}
