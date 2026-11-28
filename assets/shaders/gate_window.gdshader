shader_type spatial;
// The view through a deploy gate (`GateLook.window`): a glimpse of the world
// it leads to, drawn on the flat sheet in the doorway. No geometry and no
// render target: the shader traces the eye's ray through the sheet into a
// made-up scene behind it, so it shifts with the eye like a real window. The
// scene is the world's planet (`PlanetType`): its sky, a far and a near ridge
// of its rock with snow caps or glowing cracks, its ground, and its weather
// drifting on three depths. The edge of the doorway shimmers in the gate's
// colour, brighter while someone stands in it (`lit`).
//
// `mode` 1 is a sealed gate's teaser instead: a frosted shutter with a dim
// hologram of an unknown planet turning on it.
//
// A quad facing +Z, `size` metres, its floor at its bottom edge. Unshaded and
// cheap: a handful of noise reads a pixel, so it holds on the Low preset.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec2 size = vec2(8.2, 11.8);
uniform int mode = 0;
uniform vec3 zenith : source_color = vec3(0.3, 0.2, 0.15);
uniform vec3 horizon : source_color = vec3(0.8, 0.45, 0.3);
uniform vec3 haze : source_color = vec3(0.3, 0.28, 0.27);
uniform vec3 rock : source_color = vec3(0.25, 0.2, 0.18);
uniform vec3 ground : source_color = vec3(0.3, 0.25, 0.22);
// Snow on the ridge tops (0 for none).
uniform vec3 cap : source_color = vec3(1.0);
uniform float cap_amount = 0.0;
// Glowing cracks in the ground and a glow on the horizon (0 for none).
uniform vec3 glow : source_color = vec3(1.0, 0.35, 0.08);
uniform float glow_amount = 0.0;
// A moon or a second sun low in the sky (0 for none).
uniform vec3 moon : source_color = vec3(0.85, 0.85, 0.9);
uniform float moon_size = 0.0;
// How tall the far mountains stand (the planet's horizon peaks, in metres).
uniform float peaks = 140.0;
// What drifts in the air: 0 nothing, 1 embers, 2 ash, 3 snow, 4 rain,
// 5 sand, 6 spores. `air` on the far layer, `storm` on the two near ones.
uniform int air = 0;
uniform int storm = 0;
uniform vec3 air_color : source_color = vec3(1.0);
uniform vec3 storm_color : source_color = vec3(1.0);
uniform vec3 rim : source_color = vec3(1.0, 0.6, 0.3);
uniform float seed = 0.0;
// 1 while someone stands in the doorway.
instance uniform float lit = 0.0;

varying vec3 v_obj;
varying vec3 v_cam;

void vertex() {
	v_obj = VERTEX;
	vec3 eye = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_cam = (inverse(MODEL_MATRIX) * vec4(eye, 1.0)).xyz;
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A ridge line: rolling, with sharper peaks where the noise folds.
float ridge(float x) {
	float n = noise1(x) * 0.6 + noise1(x * 2.3 + 7.0) * 0.28 + noise1(x * 5.1 + 3.0) * 0.12;
	return 1.0 - abs(n * 2.0 - 1.0) * 0.55 - 0.2;
}

// One layer of drifting specks at `depth` metres behind the sheet.
vec3 specks(int kind, vec3 tint, float depth, vec3 d, float t) {
	if (kind == 0) {
		return vec3(0.0);
	}
	vec2 q = (v_obj + d * (depth / max(-d.z, 0.05))).xy;
	vec2 vel = vec2(0.3, -1.0);
	vec2 stretch = vec2(1.0);
	float radius = 0.06;
	float bright = 1.0;
	if (kind == 1) { vel = vec2(0.4, 1.3); radius = 0.035; bright = 2.6; }
	else if (kind == 2) { vel = vec2(1.6, -0.7); radius = 0.05; bright = 0.7; }
	else if (kind == 3) { vel = vec2(0.35, -1.1); radius = 0.055; bright = 1.1; }
	else if (kind == 4) { vel = vec2(0.6, -11.0); radius = 0.02; stretch = vec2(1.0, 0.08); bright = 0.6; }
	else if (kind == 5) { vel = vec2(7.0, -0.4); radius = 0.025; stretch = vec2(0.15, 1.0); bright = 0.7; }
	else if (kind == 6) { vel = vec2(0.15, 0.3); radius = 0.045; bright = 1.6; }
	// Cells grow with depth so a far layer looks as thick as a near one,
	// and specks shrink with it.
	float cell = 0.7 * (1.0 + depth * 0.12);
	q = q / cell - vel * t / cell;
	if (kind == 3 || kind == 6) {
		q.x += sin(q.y * 1.7 + t * 0.8) * 0.15;
	}
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	vec2 off = (vec2(hash21(id + seed), hash21(id + 17.3)) - 0.5) * 0.6;
	float there = step(kind == 3 || kind == 2 ? 0.4 : 0.6, hash21(id + 5.1));
	float r = length((f - off) * stretch);
	float a = smoothstep(radius / 0.7, radius / 0.7 * 0.25, r) * there;
	if (kind == 1) {
		a *= 0.5 + 0.5 * sin(t * 6.0 + hash21(id) * 30.0);
	}
	return tint * a * bright / (1.0 + depth * 0.05);
}

vec3 world_view(vec3 d) {
	float floor_y = -size.y * 0.5;
	float t = TIME;
	// The sky, and a moon low in it.
	vec3 col = mix(horizon, zenith, smoothstep(-0.02, 0.55, d.y));
	col += glow * glow_amount * 0.35 * exp(-abs(d.y) * 14.0);
	if (moon_size > 0.0) {
		vec3 at = normalize(vec3(-0.45, 0.32, -1.0));
		float m = smoothstep(1.0 - moon_size * moon_size * 0.5, 1.0 - moon_size * moon_size * 0.42, dot(d, at));
		col = mix(col, moon, m * 0.9);
	}
	// Streaks of cloud across the sky.
	if (d.y > 0.0) {
		vec2 sky = d.xz / (d.y + 0.15);
		float c = noise2(sky * vec2(1.2, 3.0) + vec2(t * 0.02, 0.0));
		col = mix(col, mix(horizon, haze, 0.5), smoothstep(0.55, 0.85, c) * 0.35);
	}
	float hit = 1e9;
	// The far ridge, then the near one, each a cut-out at its depth.
	for (int layer = 0; layer < 2; layer++) {
		float depth = layer == 0 ? 900.0 : 260.0;
		float tall = layer == 0 ? peaks * 1.1 : peaks * 0.32;
		vec3 p = v_obj + d * (depth / max(-d.z, 0.02));
		float h = floor_y + tall * ridge(p.x / (tall * 1.4) + seed + float(layer) * 13.0);
		if (p.y < h) {
			float fog = layer == 0 ? 0.72 : 0.42;
			vec3 face = rock * (0.75 + 0.25 * noise2(p.xy * 0.08));
			float capped = cap_amount * smoothstep(h - tall * 0.35, h - tall * 0.2, p.y);
			face = mix(face, cap, capped);
			col = mix(face, haze, fog);
			hit = depth;
		}
	}
	// The ground in front of the ridges, fading into the haze.
	if (d.y < 0.0) {
		float along = (floor_y - v_obj.y) / d.y;
		vec3 g = v_obj + d * along;
		float depth = -g.z;
		if (depth < hit) {
			float n = noise2(g.xz * 0.12);
			vec3 face = ground * (0.8 + 0.3 * n);
			float crack = 1.0 - smoothstep(0.0, 0.035, abs(noise2(g.xz * 0.09 + seed) - 0.5));
			face += glow * crack * glow_amount * (0.7 + 0.3 * sin(t * 1.3 + n * 9.0));
			col = mix(face, haze, 1.0 - exp(-depth * 0.006));
		}
	}
	// Banks of haze drifting low over the land, in the colour of what blows.
	float bank = noise2(vec2(d.x / max(abs(d.z), 0.1) * 2.0 + t * 0.06, d.y * 9.0 + seed));
	float low = exp(-abs(d.y + 0.02) * 9.0);
	col = mix(col, mix(haze, storm_color, 0.35), smoothstep(0.35, 0.9, bank) * low * 0.55);
	// Weather: the planet's air far off, its storm close by.
	col += specks(air, air_color, 40.0, d, t);
	col += specks(storm, storm_color, 12.0, d, t);
	col += specks(storm, storm_color, 4.0, d, t + 11.0);
	return col;
}

vec3 teaser(vec2 at) {
	float t = TIME;
	// A frosted steel shutter.
	float frost = noise2(at * 2.5) * 0.6 + noise2(at * 9.0) * 0.4;
	vec3 col = vec3(0.035, 0.04, 0.055) + vec3(0.12, 0.15, 0.2) * smoothstep(0.45, 0.95, frost) * 0.5;
	col += vec3(0.05, 0.06, 0.08) * smoothstep(0.3, 0.0, abs(fract(at.y * 0.5) - 0.5));
	// Now and then the hologram slips sideways.
	float slip = step(0.93, hash11(floor(t * 5.0))) * (hash11(floor(at.y * 6.0) + floor(t * 5.0)) - 0.5) * 0.4;
	vec2 c = vec2(at.x + slip, at.y - 0.8) / 2.7;
	float r = length(c);
	float flicker = 0.85 + 0.15 * step(0.2, hash11(floor(t * 14.0)));
	float scan = 0.7 + 0.3 * sin(at.y * 55.0 - t * 4.0);
	vec3 holo = vec3(0.0);
	if (r < 1.0) {
		float z = sqrt(1.0 - r * r);
		float turn = t * 0.22;
		vec3 s = vec3(c.x, c.y, z);
		float lon = atan(s.x * cos(turn) + s.z * sin(turn), s.z * cos(turn) - s.x * sin(turn));
		float lat = asin(clamp(s.y, -1.0, 1.0));
		float grid = max(1.0 - smoothstep(0.0, 0.06, abs(fract(lon * 1.9) - 0.5) * 2.0 - 0.88),
				1.0 - smoothstep(0.0, 0.06, abs(fract(lat * 2.6) - 0.5) * 2.0 - 0.88));
		holo = rim * (0.08 + 0.45 * grid) * (0.35 + 0.65 * z) + rim * pow(1.0 - z, 3.0) * 0.9;
	}
	// A ring round it, and a faint cone of light up from the floor.
	float ring = abs(length(c * vec2(1.0, 3.2)) - 1.35);
	holo += rim * (1.0 - smoothstep(0.0, 0.05, ring)) * 0.5 * step(0.0, c.y * -1.0 + 0.4 * (1.0 - step(0.0, c.y)));
	float cone = smoothstep(2.6, 0.0, abs(at.x) * (1.0 + (at.y + size.y * 0.5) * 0.1)) * smoothstep(-size.y * 0.5 + 2.6, -size.y * 0.5, at.y);
	holo += rim * cone * 0.12;
	col += holo * flicker * scan * 0.9;
	// Hazard stripes along the foot.
	float foot = step(at.y, -size.y * 0.5 + 0.7);
	col = mix(col, vec3(0.5, 0.36, 0.08) * step(0.5, fract((at.x + at.y) * 0.9)) + 0.03, foot);
	return col;
}

void fragment() {
	vec3 col;
	vec2 at = v_obj.xy;
	if (mode == 1) {
		col = teaser(at);
	} else {
		vec3 d = normalize(v_obj - v_cam);
		col = world_view(d);
		// A shimmer runs up the doorway, like looking through a heat haze.
		col *= 0.94 + 0.06 * sin(at.y * 18.0 - TIME * 3.0 + sin(at.x * 2.0));
		// The top of the doorway shades over, so the gate's lines read on it.
		col = mix(col, col * 0.12, smoothstep(size.y * 0.5 - 2.6, size.y * 0.5 - 1.9, at.y));
	}
	// The doorway's edge glows in the gate's colour.
	vec2 half_size = size * 0.5;
	float edge = min(half_size.x - abs(at.x), half_size.y - abs(at.y));
	float glow_edge = exp(-max(edge, 0.0) * (3.0 - lit * 1.2));
	col = mix(col, col * 0.35, smoothstep(1.6, 0.0, edge) * 0.6);
	col += rim * glow_edge * (0.45 + lit * 0.9);
	col *= 1.0 + lit * 0.3;
	ALBEDO = col;
}
