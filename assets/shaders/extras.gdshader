shader_type spatial;
// The scenery army's far copies (worlds/ashfront/battle.gd): colour baked
// into the vertices, and a dithered dissolve from the instance's custom
// data (r: how much of it is shown), so an extra never pops in or out.
// They fight out on the battle shelves past the rim, hundreds of metres
// off, so each is grown to stay at least `min_px` pixels tall (a soldier
// at 450 m is otherwise a pixel wide and gone) and darkens to a silhouette
// with distance against the lit far land. The fog would wash them into the
// ground out there, so it is left off and `veil` (an ash storm's cover)
// dissolves them instead.
render_mode cull_back, depth_draw_opaque, fog_disabled;

uniform float min_px = 4.0;
uniform float veil = 0.0;

varying float shown;
varying float far;

void vertex() {
	shown = INSTANCE_CUSTOM.r * (1.0 - veil);
	float d = max(-(MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).z, 0.1);
	float pixel = 2.0 * d / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	VERTEX *= max(1.0, min_px * pixel / 1.8);
	far = smoothstep(120.0, 420.0, d);
}

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i.y * 4 + i.x]) + 0.5) / 16.0;
}

void fragment() {
	if (shown < 0.999 && shown <= bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 c = COLOR.rgb;
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045))) * mix(1.0, 0.3, far);
	ROUGHNESS = 0.85;
	METALLIC = 0.05;
}
