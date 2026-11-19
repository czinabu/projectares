shader_type spatial;
// A shell's blast cloud (`ShellView`): soft puffs facing the camera, thrown
// out from the blast's heart to where each was placed as `age` runs on,
// swelling, rising and fading. Per puff: COLOR its smoke, CUSTOM.x a seed,
// .y how much fire lights it from below (dying fast), .z how fast it rises,
// .w how long it lasts. View only.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float age = 0.0;
uniform vec3 centre;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec4 smoke;
varying vec4 puff;
varying float fade;

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
	smoke = COLOR;
	puff = INSTANCE_CUSTOM;
	vec3 home = MODEL_MATRIX[3].xyz;
	float thrown = 1.0 - exp(-age * 5.0);
	vec3 at = mix(centre, home, thrown) + vec3(0.0, age * puff.z, 0.0);
	float size = length(MODEL_MATRIX[0].xyz) * (0.3 + 0.7 * thrown) * (1.0 + age * 0.08);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * size, INV_VIEW_MATRIX[1] * size,
			INV_VIEW_MATRIX[2] * size, vec4(at, 1.0));
	fade = 1.0 - smoothstep(puff.w * 0.45, puff.w, age);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float n = fbm(UV * 2.6 + puff.x * 13.0 + vec2(0.0, age * 0.15));
	float shape = smoothstep(1.0, 0.25, length(p) + (n - 0.5) * 0.8);
	// Soft where it meets the ground or a wall.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = clamp((-behind.z / behind.w + VERTEX.z) / 2.0, 0.0, 1.0);
	vec3 colour = smoke.rgb * (0.65 + 0.7 * n);
	float fire = puff.y * exp(-age * 2.5);
	colour += fire * vec3(1.0, 0.42, 0.12) * (0.4 + smoothstep(-0.4, 0.9, p.y)) * (0.5 + n);
	ALBEDO = min(colour, vec3(2.0, 1.1, 0.6));
	ALPHA = shape * smoke.a * fade * soft;
}
