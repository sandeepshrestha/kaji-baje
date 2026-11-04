shader_type spatial;
// Very plain prototype tiles: flat grey squares with thin grout lines,
// a barely visible per-tile tone shift so the grid reads in perspective.

uniform float tile_size = 2.0;
uniform vec3 tile_color : source_color = vec3(0.50, 0.51, 0.54);
uniform vec3 grout_color : source_color = vec3(0.34, 0.35, 0.38);
uniform float grout = 0.012;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = wpos.xz / tile_size;
	vec2 id = floor(uv);
	vec2 f = fract(uv);
	float edge = step(f.x, grout) + step(1.0 - grout, f.x) + step(f.y, grout) + step(1.0 - grout, f.y);
	float tone = 0.96 + 0.04 * hash(id);
	ALBEDO = mix(tile_color * tone, grout_color, clamp(edge, 0.0, 1.0));
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
