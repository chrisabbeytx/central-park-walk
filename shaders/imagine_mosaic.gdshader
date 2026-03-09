shader_type spatial;
render_mode cull_disabled;

void fragment() {
	// UV 0..1, center at 0.5
	vec2 c = UV - 0.5;
	float r = length(c);
	float angle = atan(c.y, c.x);

	// Concentric bands + radial spokes = starburst
	float radial = sin(angle * 16.0);  // 16 radial spokes
	float rings  = sin(r * 40.0);      // concentric rings

	// Combine for mosaic pattern
	float pattern = radial * 0.5 + rings * 0.5;

	// Inner circle: solid with IMAGINE text area
	float inner = smoothstep(0.08, 0.10, r);

	// Outer border ring
	float border = smoothstep(0.46, 0.48, r) * (1.0 - smoothstep(0.49, 0.50, r));

	// Black and warm-white stones
	vec3 white_stone = vec3(0.91, 0.88, 0.82);  // #E8E0D0
	vec3 black_stone = vec3(0.10, 0.10, 0.10);  // #1A1A1A
	vec3 col = mix(black_stone, white_stone, step(0.0, pattern) * inner);

	// Central medallion area (r < 0.10): warm white for text
	col = mix(white_stone, col, inner);

	// Border ring: black
	col = mix(col, black_stone, border);

	// Outside circle: gray path surround
	float outside = smoothstep(0.49, 0.50, r);
	col = mix(col, vec3(0.45, 0.43, 0.40), outside);

	// Subtle stone grain noise
	float grain = fract(sin(dot(UV * 200.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (grain - 0.5) * 0.03;

	ALBEDO = col;
	ROUGHNESS = 0.75;
	METALLIC = 0.0;
	SPECULAR = 0.2;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}
