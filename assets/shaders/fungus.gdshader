shader_type spatial;
// Giant fungus (a marsh map's stalks): mottled flesh, darker and wetter at
// the foot, paler and pored up the cap, and glowing gills underneath that
// pulse slowly. `gills` picks the underside's look. Patterns come from the
// world position, so stalks that share a mesh still differ. View only.

uniform float gills = 0.0;
uniform vec4 flesh_light : source_color = vec4(0.5, 0.42, 0.46, 1.0);
uniform vec4 flesh_dark : source_color = vec4(0.16, 0.12, 0.15, 1.0);
uniform vec4 foot : source_color = vec4(0.08, 0.1, 0.07, 1.0);
uniform vec4 glow : source_color = vec4(0.35, 1.0, 0.72, 1.0);
uniform float glow_energy = 0.55;

varying vec3 world;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}
float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float mottle = fbm3(world * 0.35);
	float fine = noise3(world * 2.6);
	if (gills > 0.5) {
		// Gills: dark ribs with the glow between them, breathing slowly.
		// Gills run out from the stem: fine ribs round the cap (UV.x goes
		// once round), broken up a little so they are not ruled.
		float ribs = 0.5 + 0.5 * sin(UV.x * 6.2832 * 48.0 + mottle * 4.0);
		ribs = mix(0.45, 1.0, ribs) * (0.7 + 0.3 * fine);
		float breath = 0.75 + 0.25 * sin(TIME * 0.6 + mottle * 12.0);
		ALBEDO = mix(flesh_dark.rgb * 0.6, glow.rgb * 0.35, ribs);
		EMISSION = glow.rgb * glow_energy * breath * (0.15 + 0.85 * ribs);
		ROUGHNESS = 0.5;
	} else {
		float up = clamp(UV.y, 0.0, 1.0);
		vec3 flesh = mix(flesh_dark.rgb, flesh_light.rgb, smoothstep(0.3, 0.75, mottle));
		// Wet and moss-dark where it stands in the water.
		flesh = mix(foot.rgb, flesh, smoothstep(0.0, 0.18, up));
		// Pores: pale flecks, a few of them faintly lit.
		float pore = smoothstep(0.78, 0.86, fine);
		ALBEDO = flesh * (0.85 + 0.3 * fine) + pore * 0.08;
		EMISSION = glow.rgb * pore * smoothstep(0.6, 1.0, up) * 0.35;
		ROUGHNESS = mix(0.35, 0.8, smoothstep(0.0, 0.3, up));
		SPECULAR = 0.4;
	}
}
