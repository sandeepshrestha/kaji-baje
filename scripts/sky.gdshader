shader_type sky;
// Night sky: deep gradient, hashed stars that twinkle, and a soft moon.

uniform vec3 top_color : source_color = vec3(0.01, 0.015, 0.05);
uniform vec3 horizon_color : source_color = vec3(0.05, 0.07, 0.16);
uniform vec3 moon_dir = vec3(-0.45, 0.55, -0.7);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	float h = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(h, 0.5));
	vec3 cell = floor(EYEDIR * 220.0);
	float s = hash(cell);
	if (s > 0.996 && EYEDIR.y > 0.02) {
		float tw = 0.6 + 0.4 * sin(TIME * (2.0 + s * 5.0) + s * 40.0);
		col += vec3(0.9, 0.92, 1.0) * tw * smoothstep(0.996, 1.0, s) * 3.0;
	}
	vec3 md = normalize(moon_dir);
	float d = dot(EYEDIR, md);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9993, 0.9996, d) * 2.0;
	col += vec3(0.25, 0.32, 0.55) * pow(max(d, 0.0), 300.0) * 0.6;
	if (EYEDIR.y < 0.0) {
		col = horizon_color * 0.6;
	}
	COLOR = col;
}
