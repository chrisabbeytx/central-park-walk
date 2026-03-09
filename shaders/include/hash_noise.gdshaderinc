// Shared hash and value noise functions.
// Used by terrain, stone, facade, path, tree_bark, imagine_mosaic, water shaders.

float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i+vec2(1.,0.)), u.x),
	           mix(hash2(i+vec2(0.,1.)), hash2(i+vec2(1.,1.)), u.x), u.y);
}
float fbm3(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.13) * 0.3 + vnoise(p * 4.57) * 0.2;
}
