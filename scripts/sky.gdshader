shader_type sky;
// One sky for the whole day. Colors, the sun, the moon, and the stars
// are driven from the game as time moves.

uniform vec3 top_color : source_color = vec3(0.28, 0.48, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.82, 0.9);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 moon_color : source_color = vec3(0.85, 0.9, 1.0);
uniform vec3 sun_dir = vec3(0.2, 0.7, -0.6);
uniform vec3 moon_dir = vec3(-0.2, -0.4, 0.4);
uniform float stars = 0.0;
uniform float sun_disc = 1.0;
uniform float moon_disc = 0.0;
uniform float sun_glow = 0.4;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	float h = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(h, 0.45));
	if (stars > 0.01 && EYEDIR.y > 0.04) {
		vec3 cell = floor(EYEDIR * 220.0);
		float s = hash(cell);
		if (s > 0.996) {
			float tw = 0.6 + 0.4 * sin(TIME * (2.0 + s * 5.0) + s * 40.0);
			col += vec3(0.9, 0.92, 1.0) * tw * smoothstep(0.996, 1.0, s) * 3.0 * stars;
		}
	}
	vec3 sd = normalize(sun_dir);
	float ds = dot(EYEDIR, sd);
	col += sun_color * smoothstep(0.9986, 0.9994, ds) * sun_disc * 2.2;
	col += sun_color * pow(max(ds, 0.0), 28.0) * sun_glow * sun_disc;
	vec3 md = normalize(moon_dir);
	float dm = dot(EYEDIR, md);
	col += moon_color * smoothstep(0.99915, 0.99955, dm) * moon_disc * 1.8;
	col += moon_color * pow(max(dm, 0.0), 240.0) * 0.35 * moon_disc;
	if (EYEDIR.y < 0.0) {
		col = horizon_color * 0.55;
	}
	COLOR = col;
}
