shader_type sky;

uniform vec3 sky_top_color = vec3(0.18, 0.38, 0.72);
uniform vec3 sky_horizon_color = vec3(0.55, 0.58, 0.68);
uniform vec3 ground_bottom_color = vec3(0.10, 0.12, 0.08);
uniform vec3 ground_horizon_color = vec3(0.35, 0.38, 0.30);

uniform float cloud_coverage = 0.65;
uniform float cloud_density = 0.50;
uniform float cloud_speed = 0.004;
uniform vec3 cloud_color_top = vec3(0.90, 0.90, 0.92);
uniform vec3 cloud_color_bottom = vec3(0.45, 0.45, 0.50);

// Scalar hash — used for stars (cell-based)
float sky_hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}
// Gradient hash — returns 2D direction per lattice point
vec2 sky_grad(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)),
	         dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}
// Gradient (Perlin-style) noise — no grid artifacts
float sky_gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Quintic interpolation (C2 continuous — no second-derivative seams)
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(dot(sky_grad(i),                 f),
	               dot(sky_grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
	           mix(dot(sky_grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
	               dot(sky_grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x), u.y);
}
// FBM with per-octave rotation to break any residual grid alignment
float sky_fbm(vec2 p, int oct) {
	float v = 0.0, a = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)); // ~37 deg
	for (int i = 0; i < oct; i++) {
		v += a * sky_gnoise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v * 0.5 + 0.5; // remap [-1,1] → [0,1]
}

void sky() {
	vec3 dir = EYEDIR;
	float elev = dir.y;

	// --- Sky gradient ---
	vec3 sky_col;
	if (elev >= 0.0) {
		float t = clamp(elev * 2.5, 0.0, 1.0);
		sky_col = mix(sky_horizon_color, sky_top_color, t);
	} else {
		float t = clamp(-elev * 4.0, 0.0, 1.0);
		sky_col = mix(ground_horizon_color, ground_bottom_color, t);
	}

	// --- Sun disc + atmospheric scattering ---
	float sun_dot = dot(dir, LIGHT0_DIRECTION);
	float sun_disc = smoothstep(0.9992, 0.9998, sun_dot);
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY * 2.0;
	// Sun glow halo — tight inner core + wider outer aureole
	float sun_glow = pow(max(sun_dot, 0.0), 64.0) * 0.3;
	float sun_aureole = pow(max(sun_dot, 0.0), 8.0) * 0.12;
	sky_col += sun_col * (sun_disc + sun_glow + sun_aureole);

	// Golden hour scatter — warm tint near horizon when sun is low
	float sun_elev = LIGHT0_DIRECTION.y;  // negative = below horizon
	float golden = smoothstep(0.15, -0.05, sun_elev);  // peaks at sunset/sunrise
	if (golden > 0.01 && elev >= 0.0) {
		// Rayleigh-like forward scatter: warm orange glow around sun direction on horizon
		float scatter_dot = max(sun_dot, 0.0);
		float scatter = pow(scatter_dot, 3.0) * golden * 0.35;
		vec3 scatter_col = LIGHT0_COLOR * vec3(1.1, 0.7, 0.4);  // warm orange
		// Stronger near horizon, fades above
		scatter *= (1.0 - smoothstep(0.0, 0.35, elev));
		sky_col += scatter_col * scatter;
	}

	// --- Stars (Bortle 8-9: inner-city light pollution) ---
	// Central Park: nearly starless sky. Only ~10 brightest stars visible on clear nights.
	if (elev > 0.0) {
		float star_fade = smoothstep(0.15, 0.0, LIGHT0_ENERGY);
		if (star_fade > 0.0) {
			vec2 star_uv = dir.xz / (elev + 0.001) * 80.0;
			vec2 star_cell = floor(star_uv);
			float star_rand = sky_hash(star_cell);
			float star_mask = step(0.997, star_rand);  // 0.3% density — only brightest stars
			float star_bright = sky_hash(star_cell + vec2(13.7, 29.3));
			star_bright = star_bright * star_bright * 0.8;  // dimmer through light pollution
			float twinkle = 0.8 + 0.2 * sin(TIME * 2.0 + star_rand * 100.0);
			vec2 star_frac = fract(star_uv) - 0.5;
			float star_point = smoothstep(0.10, 0.02, length(star_frac));
			sky_col += vec3(star_bright * star_mask * star_point * star_fade * twinkle);
		}
		// Light pollution sky glow — warm amber dome
		float lp_fade = smoothstep(0.15, 0.0, LIGHT0_ENERGY);
		vec3 light_pollution = vec3(0.12, 0.08, 0.04);  // warm amber-brown
		float lp_strength = lp_fade * (0.6 + 0.4 * (1.0 - elev));  // stronger near horizon
		sky_col += light_pollution * lp_strength;
	}

	// --- FBM cloud layer ---
	if (elev > -0.05) {
		// Project onto cloud dome — higher elevation = closer to zenith
		float cloud_y = max(elev, 0.01);
		vec2 cloud_uv = dir.xz / (cloud_y + 0.1) * 0.8;
		cloud_uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.7);

		float n = sky_fbm(cloud_uv * 3.0, 5);
		// Coverage threshold — higher coverage = more clouds
		float cloud_mask = smoothstep(1.0 - cloud_coverage - 0.1, 1.0 - cloud_coverage + 0.2, n);
		cloud_mask *= cloud_density;

		// Cloud shading: top lit by sun, bottom darker
		float sun_illum = max(dot(LIGHT0_DIRECTION, vec3(0.0, 1.0, 0.0)), 0.0);
		float edge_lit = pow(max(sun_dot, 0.0), 4.0) * 0.4;
		vec3 cloud_col = mix(cloud_color_bottom, cloud_color_top, sun_illum * 0.4 + 0.25);
		// Sun-facing edges get warm highlight
		cloud_col += LIGHT0_COLOR * edge_lit * 0.5;
		// Golden hour cloud drama: undersides lit warm orange, edges more vivid
		float cloud_golden = smoothstep(0.15, -0.05, LIGHT0_DIRECTION.y);
		if (cloud_golden > 0.01) {
			float rim = pow(max(sun_dot, 0.0), 2.0) * 0.3;
			cloud_col += LIGHT0_COLOR * vec3(1.2, 0.6, 0.3) * rim * cloud_golden;
			// Warmer cloud base at golden hour
			cloud_col = mix(cloud_col, cloud_col * vec3(1.15, 0.9, 0.75), cloud_golden * 0.4);
		}

		// Fade clouds near horizon to blend with haze
		float horizon_fade = smoothstep(0.0, 0.12, elev);
		cloud_mask *= horizon_fade;

		sky_col = mix(sky_col, cloud_col, cloud_mask);
	}

	COLOR = sky_col;
}
