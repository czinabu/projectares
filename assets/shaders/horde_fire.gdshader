shader_type spatial;
// The horde's fire (worlds/ashfront/horde.gd): each figure's muzzle flashes
// in its army's colour (INSTANCE_CUSTOM.r: the army), in bursts on its own
// clock (g its phase, b its pace), more of them the hotter the war (`heat`);
// a few figures in a hundred are where a shell lands now and then, a big
// slow blast instead. Added light, facing the camera, grown to stay
// `min_px` pixels across; it follows its figure's surge (horde.gdshader).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float min_px = 3.0;
uniform float heat = 0.0;
uniform float veil = 0.0;
uniform vec3 fire_a : source_color = vec3(1.0, 0.42, 0.08);
uniform vec3 fire_b : source_color = vec3(0.15, 0.7, 1.0);

varying vec3 glow;
varying vec2 local;

float hash(float x) {
	return fract(sin(x * 12.9898 + 4.1414) * 43758.5453);
}

void vertex() {
	float army = INSTANCE_CUSTOM.r;
	float phase = INSTANCE_CUSTOM.g;
	float pace = INSTANCE_CUSTOM.b;
	vec2 toward = COLOR.xy;
	float t = TIME * 0.11 * pace + phase * 6.2832;
	float surge = (sin(t) + 0.35 * sin(t * 2.7 + 1.3)) * mix(3.0, 9.0, heat);
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz + vec3(toward.x, 0.0, toward.y) * surge;
	bool blast = phase < 0.015;
	float size;
	float bright;
	if (blast) {
		// A shell: a flash that swells and dies, every 7 to 14 s.
		float cycle = mix(14.0, 7.0, heat) * pace;
		float k = fract(TIME / cycle + phase * 31.0);
		bright = k < 0.12 ? (1.0 - k / 0.12) * 6.0 : 0.0;
		size = mix(6.0, 16.0, k / 0.12);
		origin.y += 3.0;
	} else {
		// A burst every few seconds; within it, rounds flicker.
		float cycle = 3.5 * pace;
		float k = fract(TIME / cycle + phase * 13.0);
		float duty = mix(0.08, 0.3, heat);
		float flicker = step(0.5, fract(TIME * 9.0 + phase * 7.0));
		bright = k < duty ? flicker * 2.2 : 0.0;
		// Only some of the crowd fires at all when the war is quiet.
		bright *= step(hash(phase * 91.0), mix(0.35, 0.9, heat));
		size = 1.2;
		origin.y += 1.4;
	}
	vec3 to_cam = CAMERA_POSITION_WORLD - origin;
	float d = max(length(to_cam), 0.1);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 up = normalize(cross(to_cam, right));
	float pixel = 2.0 * d / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float grow = max(size, min_px * pixel);
	// The quad's own shape is a figure's (0.7 by 1.8, from its feet); a
	// flash is round, centred on the muzzle.
	local = vec2(VERTEX.x / 0.35, (VERTEX.y - 0.9) / 0.9);
	vec3 world = origin + (right * local.x + up * local.y) * grow * 0.5;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	glow = mix(fire_a, fire_b, army) * bright * (1.0 - veil);
	if (blast) {
		glow = vec3(1.0, 0.55, 0.2) * bright * (1.0 - veil);
	}
}

void fragment() {
	float r = length(local);
	float a = max(1.0 - r, 0.0);
	ALBEDO = glow * a * a;
}
