shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float barrel_strength = 0.025;
uniform float chroma_strength = 0.0008;

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	float dist2 = dot(uv, uv);
	vec2 warped = uv * (1.0 + barrel_strength * dist2);
	vec2 uv_r = warped * (1.0 + chroma_strength) + 0.5;
	vec2 uv_g = warped + 0.5;
	vec2 uv_b = warped * (1.0 - chroma_strength) + 0.5;
	float r = texture(screen_tex, uv_r).r;
	float g = texture(screen_tex, uv_g).g;
	float b = texture(screen_tex, uv_b).b;
	COLOR = vec4(r, g, b, 1.0);
}
