shader_type spatial;
// The horde's crowd (worlds/ashfront/horde.gd): one dark figure per
// instance, out on the battle shelves past the rim. Each turns to face the
// camera about the upright, grows to stay at least `min_px` pixels tall,
// and surges back and forth toward its army's line (COLOR.xy, the way to
// the line in the ground's plane) on its own clock (INSTANCE_CUSTOM: g its
// phase, b its pace). A storm's `veil` dissolves it. No fog: at this range
// the fog would wash it into the ground; it is dark against the lit land.
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform float min_px = 3.0;
uniform float heat = 0.0;
uniform float veil = 0.0;

varying float shown;

void vertex() {
	float phase = INSTANCE_CUSTOM.g;
	float pace = INSTANCE_CUSTOM.b;
	vec2 toward = COLOR.xy;
	// Surging: forward in a rush, back a little, the hotter the war the more.
	float t = TIME * 0.11 * pace + phase * 6.2832;
	float surge = (sin(t) + 0.35 * sin(t * 2.7 + 1.3)) * mix(3.0, 9.0, heat);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + vec3(toward.x, 0.0, toward.y) * surge;
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	float d = max(length(to_cam), 0.1);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	float pixel = 2.0 * d / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float grow = max(1.0, min_px * pixel / 1.8);
	vec3 world = origin + right * VERTEX.x * grow + vec3(0.0, VERTEX.y * grow, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	shown = 1.0 - veil;
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
	ALBEDO = vec3(0.03, 0.025, 0.025);
}
