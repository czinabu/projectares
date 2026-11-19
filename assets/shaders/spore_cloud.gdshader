shader_type spatial;
// A cloud that hangs where it burst (`Raid._show_cloud`): soft puffs facing
// the camera, each drifting and turning slowly about where it was placed,
// so the cloud's edge is ragged and moving, never a shape. Per puff:
// INSTANCE_CUSTOM.x a seed, .y how far it drifts. `alpha` fades the whole
// cloud in and out. View only.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.62, 0.85, 0.3, 1.0);
uniform float alpha = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec4 puff;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	puff = INSTANCE_CUSTOM;
	float t = TIME * 0.25 + puff.x * 6.28;
	vec3 at = MODEL_MATRIX[3].xyz + vec3(sin(t), sin(t * 0.7) * 0.4, cos(t * 0.8)) * puff.y;
	float size = length(MODEL_MATRIX[0].xyz);
	// Facing the camera, turned slowly about the view line.
	float turn = TIME * 0.06 * (puff.x - 0.5) + puff.x * 6.28;
	vec3 right = INV_VIEW_MATRIX[0].xyz * cos(turn) + INV_VIEW_MATRIX[1].xyz * sin(turn);
	vec3 up = INV_VIEW_MATRIX[1].xyz * cos(turn) - INV_VIEW_MATRIX[0].xyz * sin(turn);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * size, 0.0), vec4(up * size, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * size, 0.0), vec4(at, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = fbm(UV * 2.4 + puff.x * 17.0 + vec2(TIME * 0.03, -TIME * 0.05));
	float shape = smoothstep(1.0, 0.1, length(p) + (n - 0.5) * 0.9);
	// Soft where it meets the ground, a wall or a body.
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = clamp((-behind.z / behind.w + VERTEX.z) / 2.5, 0.0, 1.0);
	// And thin up close, so standing in it is a haze, not a wall.
	float near = smoothstep(0.5, 4.0, -VERTEX.z);
	ALBEDO = tint.rgb * (0.7 + 0.6 * n);
	ALPHA = shape * tint.a * alpha * soft * near;
}
