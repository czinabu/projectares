// A marsh beast's hide (DESIGN.md "The Spore Marsh", part three): mottled
// patches over a fine speckle, a paler underside, a wet sheen and lit
// freckles that breathe slowly. The pattern is worked out from the piece's
// own space (scaled to metres), so it stays on the body as it moves. View
// only.
shader_type spatial;
render_mode cull_back;

uniform vec4 hide : source_color = vec4(0.3, 0.32, 0.3, 1.0);
uniform vec4 mottle : source_color = vec4(0.2, 0.2, 0.22, 1.0);
uniform vec4 under : source_color = vec4(0.5, 0.45, 0.4, 1.0);
uniform vec4 glow : source_color = vec4(0.5, 1.0, 0.65, 1.0);
// Patches a metre.
uniform float patches = 4.0;
// The share of the hide's cells that carry a lit freckle.
uniform float freckles = 0.0;
uniform float freckle_energy = 1.6;
// 0 dry and dull, 1 slick.
uniform float wet = 0.5;
// A faint lit edge where the hide turns away, like wet skin catching the glow.
uniform float rim = 0.08;

varying vec3 local;
varying vec3 local_normal;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local = VERTEX * scale;
	local_normal = normalize(NORMAL / max(scale, vec3(0.0001)));
}

void fragment() {
	vec3 p = local * patches;
	float n = noise(p) * 0.65 + noise(p * 2.3 + 7.1) * 0.35;
	vec3 c = mix(hide.rgb, mottle.rgb, smoothstep(0.42, 0.62, n));
	float belly = smoothstep(0.1, -0.7, local_normal.y);
	c = mix(c, under.rgb, belly * 0.75);
	float speck = noise(p * 7.0);
	c *= 0.82 + 0.18 * speck;
	// Freckles: one dot a cell, in some cells.
	vec3 cell = local * patches * 2.2;
	vec3 id = floor(cell);
	vec3 off = vec3(hash(id + 3.1), hash(id + 5.7), hash(id + 9.2)) * 0.5 + 0.25;
	float d = length(fract(cell) - off);
	float lit = step(hash(id), freckles) * smoothstep(0.2, 0.07, d) * (1.0 - belly * 0.6);
	float breathe = 0.7 + 0.3 * sin(TIME * 1.1 + hash(id + 1.3) * 6.28);
	ALBEDO = c;
	ROUGHNESS = mix(0.85, 0.32, wet) + 0.1 * speck;
	SPECULAR = 0.35 + 0.25 * wet;
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = glow.rgb * (lit * freckle_energy * breathe + edge * rim);
}
