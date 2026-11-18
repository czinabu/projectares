shader_type spatial;
// Edge ink: a thin dark line round the outline of anything standing against
// something farther away, faded in with distance, so a soldier or a building
// at 50 m reads as a shape against the haze instead of melting into it.
// Drawn on a quad that covers the screen (`Look.edge_ink`), from the depth
// buffer only, so it is the same in every view and changes nothing but the
// picture. Flat ground and walls get none: the test is on 1/depth, which is
// linear across any flat surface on screen, so only a real step in depth
// (a silhouette) leaves a mark. It needs a depth texture to read, which a
// view drawn with MSAA does not give it (`GameSettings.ink_shown`).
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// How dark the ink is at full strength, 0 to 1.
uniform float strength = 0.8;
// The ink fades in from `begin` to `full` meters, so nothing near is outlined.
uniform float begin = 14.0;
uniform float full = 55.0;
// And out again from `fade` to `gone`, where fog has the last word.
uniform float fade = 380.0;
uniform float gone = 700.0;
// How big a step in depth (as a share of the nearer side) counts as an edge.
uniform float step_low = 0.04;
uniform float step_high = 0.3;
uniform vec3 ink : source_color = vec3(0.015, 0.012, 0.012);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float inv_depth(vec2 uv, mat4 inv_proj) {
	float raw = texture(depth_tex, uv).r;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return max(-view.w / view.z, 0.0);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float c = inv_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float l = inv_depth(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float r = inv_depth(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float d = inv_depth(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float u = inv_depth(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	// Negative where this pixel is nearer than the line through its
	// neighbours: the near side of an outline.
	float bend = (l + r - 2.0 * c) + (d + u - 2.0 * c);
	float edge = smoothstep(step_low, step_high, -bend / max(c, 1e-6));
	float dist = 1.0 / max(c, 1e-6);
	float near_far = smoothstep(begin, full, dist) * (1.0 - smoothstep(fade, gone, dist));
	ALBEDO = ink;
	ALPHA = edge * near_far * strength;
}
