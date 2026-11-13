shader_type spatial;
// The arena's holographic crowd: one quad per spectator, turned to face the
// camera round the vertical, drawn as a glowing head-and-shoulders outline
// with scan lines. Drawn as a MultiMesh: the instance colour is the tint,
// INSTANCE_CUSTOM.x a phase so nobody moves in step, .y how excitable they
// are (how much they bob and sway).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float energy = 1.0;
uniform float bob = 0.08;

varying vec4 tint;
varying float phase;

void vertex() {
	tint = COLOR;
	phase = INSTANCE_CUSTOM.x;
	float lively = INSTANCE_CUSTOM.y;
	// Cheer: a bob with a quick little jump now and then, and a sway.
	float t = TIME * (1.2 + lively) + phase * 6.2831;
	VERTEX.y += (sin(t) * 0.5 + 0.5) * bob * lively * (1.0 + step(0.92, sin(t * 0.37)) * 2.0);
	VERTEX.x += sin(t * 0.5) * 0.04 * lively * UV.y;
	// Face the camera, turning only round the vertical.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// UV: x across, y down. Head near the top, shoulders and body below.
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);
	float head = length((p - vec2(0.0, 0.8)) * vec2(1.0, 0.85)) - 0.13;
	// Shoulders: a rounded block, widest at the top, fading to the seat.
	float half_w = mix(0.2, 0.36, smoothstep(0.0, 0.55, p.y));
	float body = max(abs(p.x) - half_w, p.y - 0.62 + abs(p.x) * 0.35);
	float shape = min(head, body);
	float inside = 1.0 - smoothstep(0.0, 0.015, shape);
	float rim = inside * smoothstep(-0.05, -0.005, shape);
	float scan = 0.65 + 0.35 * sin(FRAGCOORD.y * 1.6 + TIME * 4.0);
	float flicker = 0.85 + 0.15 * sin(TIME * 13.0 + phase * 40.0);
	float fade = smoothstep(0.0, 0.25, p.y);
	float a = (inside * 0.22 * scan + rim * 0.9) * flicker * fade;
	ALBEDO = tint.rgb * a * energy;
}
