shader_type spatial;
// The scenery army's far copies (worlds/ashfront/battle.gd): colour baked
// into the vertices, and a dithered dissolve from the instance's custom
// data (r: how much of it is shown), so an extra never pops in or out.
render_mode cull_back, depth_draw_opaque;

varying float shown;

void vertex() {
	shown = INSTANCE_CUSTOM.r;
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
	ALBEDO = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
	ROUGHNESS = 0.85;
	METALLIC = 0.05;
}
