shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Soft round contact shadow under a billboard character.
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - smoothstep(0.35, 1.0, d)) * 0.55;
}
