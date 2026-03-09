shader_type spatial;
render_mode cull_disabled;

uniform sampler2D tex_alb : source_color,      filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_nrm : hint_normal,        filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 world_pos;
varying vec3 world_nrm;

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
}
