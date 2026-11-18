shader_type spatial;
// A solid crowd in the stands (Crowd, core/visual/crowd.gd): one low-poly
// figure per spectator in a MultiMesh. The instance colour is their
// clothes, INSTANCE_CUSTOM.x a phase so nobody moves in step, .y how
// excitable they are and .z whether they hold up a light stick (the
// stick's vertices have UV.x over 1). Everyone sways; people near `hype_at`
// (the viewer, set each frame) jump and wave, so a stand cheers as you pass.
// View only.
render_mode cull_back;

uniform vec3 hype_at = vec3(0.0, -1000.0, 0.0);
uniform float hype_near = 25.0;
uniform float hype_far = 70.0;
uniform vec3 stick_color : source_color = vec3(0.3, 0.85, 1.0);
uniform float stick_energy = 5.0;

varying vec3 clothes;
varying float is_stick;

void vertex() {
	clothes = COLOR.rgb;
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float lively = INSTANCE_CUSTOM.y;
	is_stick = step(1.0, UV.x);
	if (is_stick > 0.5 && INSTANCE_CUSTOM.z < 0.5) {
		// No stick: fold it away inside the body.
		VERTEX = vec3(0.0, 0.9, 0.0);
	}
	float dist = distance((MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz, hype_at);
	float hype = 1.0 - smoothstep(hype_near, hype_far, dist);
	float t = TIME * (1.4 + lively * 1.5 + hype * 2.5) + phase;
	float up = VERTEX.y / 1.6;
	// A sway from the hips, more the higher up the body.
	VERTEX.x += sin(t * 0.6) * 0.05 * up * (0.4 + lively);
	// Jumps and bobs: now and then for the lively, all the time near the viewer.
	float jump = max(sin(t), 0.0);
	float now_and_then = step(0.85, sin(t * 0.23 + phase));
	VERTEX.y += jump * (0.03 + 0.25 * hype + 0.12 * lively * now_and_then);
	// A stick waves overhead.
	if (is_stick > 0.5) {
		VERTEX.x += sin(t * 1.3) * 0.3 * (0.3 + hype) * (VERTEX.y - 1.2);
	}
}

void fragment() {
	if (is_stick > 0.5) {
		ALBEDO = stick_color;
		EMISSION = stick_color * stick_energy;
	} else {
		ALBEDO = clothes;
		ROUGHNESS = 0.85;
	}
}
