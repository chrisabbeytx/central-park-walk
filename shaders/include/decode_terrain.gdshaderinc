// Terrain height sampling from 16-bit heightmap texture.
// Requires uniforms: heightmap_tex, hm_world_size, hm_min_h, hm_range, hm_res

float decode_h(vec4 s) {
	return s.r * (255.0 / 256.0) + s.g * (1.0 / 256.0);
}
float sample_terrain(vec2 world_xz) {
	float half_ws = hm_world_size * 0.5;
	vec2 grid = (world_xz + half_ws) / hm_world_size * (hm_res - 1.0);
	vec2 gi = floor(grid);
	vec2 gf = grid - gi;
	vec2 uv00 = (gi + 0.5) / hm_res;
	vec2 uv10 = (gi + vec2(1.5, 0.5)) / hm_res;
	vec2 uv01 = (gi + vec2(0.5, 1.5)) / hm_res;
	vec2 uv11 = (gi + vec2(1.5, 1.5)) / hm_res;
	float h00 = hm_min_h + decode_h(texture(heightmap_tex, uv00)) * hm_range;
	float h10 = hm_min_h + decode_h(texture(heightmap_tex, uv10)) * hm_range;
	float h01 = hm_min_h + decode_h(texture(heightmap_tex, uv01)) * hm_range;
	float h11 = hm_min_h + decode_h(texture(heightmap_tex, uv11)) * hm_range;
	float fx = gf.x;
	float fz = gf.y;
	if (fz <= fx) {
		return h00 + (h10 - h00) * fx + (h11 - h10) * fz;
	} else {
		return h00 + (h11 - h01) * fx + (h01 - h00) * fz;
	}
}
