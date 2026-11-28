shader_type canvas_item;
// The passage through a deploy gate (`TransitView`): what fills the view
// between places instead of a dark screen. A tunnel of light in the
// destination world's colour streams past, and at its far end a round
// window onto that world (its sky, a ridge of its rock, its ground) waits.
// While the world is being built the window stays small; as the trip lands
// (`arrive` rising to 1) it opens to fill the view, and the real world fades
// in behind it. A flash in the gate's colour marks the step in.
//
// One full-screen rect, a handful of sines and one noise read a pixel: no
// render target and no 3D, so it holds on the Low preset and keeps moving
// while the next place loads.

uniform vec3 tint : source_color = vec3(1.0, 0.6, 0.3);
uniform vec3 zenith : source_color = vec3(0.3, 0.2, 0.15);
uniform vec3 horizon : source_color = vec3(0.8, 0.45, 0.3);
uniform vec3 rock : source_color = vec3(0.25, 0.2, 0.18);
uniform vec3 ground : source_color = vec3(0.3, 0.25, 0.22);
uniform vec3 glow : source_color = vec3(1.0, 0.35, 0.08);
uniform float glow_amount = 0.0;
// Seconds since the step in.
uniform float t = 0.0;
// 0 in the passage, 1 when the far window fills the view.
uniform float arrive = 0.0;
// Width over height of the view.
uniform float aspect = 1.7778;
uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 31.7) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

// The destination seen through the far window: `q` runs -1..1 across it.
vec3 far_world(vec2 q) {
	// Screen y grows downward; the window's up is -y.
	float up = -q.y;
	vec3 sky = mix(horizon, zenith, clamp(up * 1.4 + 0.1, 0.0, 1.0));
	sky += glow * glow_amount * 0.35 * exp(-abs(up - 0.02) * 9.0);
	float ridge_far = -0.02 + 0.16 * noise1(q.x * 3.0 + 1.7) + 0.05 * noise1(q.x * 9.0);
	float ridge_near = -0.16 + 0.12 * noise1(q.x * 2.2 + 5.3) + 0.04 * noise1(q.x * 7.0 + 2.0);
	vec3 col = sky;
	if (up < ridge_far) {
		col = mix(rock, horizon, 0.45);
	}
	if (up < ridge_near) {
		col = rock;
	}
	if (up < -0.3) {
		float d = clamp((-0.3 - up) * 1.6, 0.0, 1.0);
		col = mix(mix(ground, horizon, 0.3), ground, d);
	}
	return col;
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	// The far window: small in the passage, opening to fill the view.
	float open = arrive * arrive;
	float window_r = mix(0.12 + 0.012 * sin(t * 2.3), 1.25, open);
	// The tunnel: depth grows toward the middle, and it streams past.
	float depth = 0.32 / max(r, 0.002);
	float flow = depth + t * 7.0 * (1.0 + open * 2.0);
	float around = ang / 6.28318 + 0.5;
	// Ribs of the passage's wall, and two layers of light streaking by.
	float ribs = pow(0.5 + 0.5 * sin(flow * 1.6), 6.0);
	float panels = smoothstep(0.42, 0.5, abs(fract(around * 12.0) - 0.5));
	float streak = 0.0;
	for (int layer = 0; layer < 2; layer++) {
		float lanes = layer == 0 ? 40.0 : 23.0;
		float lane = floor(around * lanes);
		float jitter = hash(lane + float(layer) * 91.0);
		float s = pow(max(sin(flow * (0.5 + jitter * 0.6) * (layer == 0 ? 1.0 : 0.6) + jitter * 40.0), 0.0), 14.0);
		s *= smoothstep(0.5, 0.1, abs(fract(around * lanes) - 0.5));
		streak += s * (layer == 0 ? 1.0 : 0.6);
	}
	// Far down the tunnel it blurs to the gate's glow; near the eye it is dim.
	float far = smoothstep(0.75, 0.0, r);
	vec3 wall = mix(vec3(0.025, 0.03, 0.045) + tint * 0.06, tint * 0.3, far);
	wall += tint * (ribs * 0.12 + panels * 0.06) * (0.35 + far);
	vec3 col = wall + tint * streak * (0.45 + far);
	col += tint * 0.5 * exp(-max(r - window_r, 0.0) * 12.0);
	// The window itself, with a bright lip in the gate's colour.
	if (r < window_r) {
		vec2 q = p / window_r;
		col = far_world(q);
		col = mix(col, tint, 0.25 * (1.0 - open));
	}
	col += tint * smoothstep(0.012, 0.0, abs(r - window_r)) * (1.0 - open) * 1.2;
	// The step in: a flash of the gate's colour.
	col = mix(col, tint * 1.4 + vec3(0.25), exp(-t * 7.0) * 0.85);
	// Edges darken, as through a helmet.
	col *= 1.0 - smoothstep(0.55, 1.05, length((UV - 0.5) * vec2(1.25, 1.0))) * 0.6 * (1.0 - open);
	COLOR = vec4(col, COLOR.a);
}
