// The lounge window's view out (DESIGN.md "The lounge"): a dusk sky over a
// ridge line with fires on the plain. One panorama on a quad, view only.
shader_type spatial;
render_mode unshaded;

float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise(float x) { float i = floor(x); float f = fract(x); return mix(hash(i), hash(i + 1.0), smoothstep(0.0, 1.0, f)); }

void fragment() {
	vec2 uv = UV;
	float y = 1.0 - uv.y;
	vec3 top = vec3(0.10, 0.08, 0.16);
	vec3 mid = vec3(0.55, 0.25, 0.16);
	vec3 low = vec3(1.0, 0.55, 0.28);
	vec3 sky = mix(low, mid, smoothstep(0.18, 0.45, y));
	sky = mix(sky, top, smoothstep(0.45, 1.0, y));
	float sun = exp(-pow(length((uv - vec2(0.66, 0.70)) * vec2(1.7, 1.0)) * 6.0, 2.0));
	sky += vec3(1.0, 0.7, 0.4) * sun * 0.9;
	// Ash clouds in bands.
	float band = noise(uv.x * 9.0 + y * 3.0) * noise(uv.x * 23.0 - y * 5.0);
	sky = mix(sky, sky * 0.6, smoothstep(0.55, 0.9, y) * band);
	// Far ridge, near ridge.
	float far = 0.24 + 0.06 * noise(uv.x * 7.0) + 0.02 * noise(uv.x * 31.0);
	float near = 0.13 + 0.07 * noise(uv.x * 4.0 + 3.0) + 0.015 * noise(uv.x * 47.0);
	vec3 col = sky;
	if (y < far) col = mix(vec3(0.32, 0.17, 0.14), sky, 0.45);
	// Spires on the far ridge.
	float sp = step(0.985, hash(floor(uv.x * 140.0))) * step(y, far + 0.09 * hash(floor(uv.x * 140.0) + 3.0));
	if (sp > 0.5 && y > near) col = mix(vec3(0.2, 0.12, 0.12), sky, 0.35);
	if (y < near) {
		col = vec3(0.10, 0.06, 0.06);
		// Fires and lights on the plain.
		float cell = floor(uv.x * 90.0) + floor(y * 60.0) * 97.0;
		float fire = step(0.975, hash(cell));
		col += vec3(1.0, 0.5, 0.15) * fire * 1.5;
	}
	// A flash far off.
	float flash = exp(-pow(length((uv - vec2(0.27, 0.75)) * vec2(3.0, 6.0)), 2.0) * 4.0);
	col += vec3(1.0, 0.6, 0.3) * flash * 0.6;

	col += vec3(0.05) * smoothstep(0.3, 0.0, abs(uv.x - uv.y * 0.4 - 0.2));
	ALBEDO = col;
}
