shader_type spatial;
// A deploy gate's crest (`GateLook.crest`): a glowing emblem of what its
// world is like, in a diamond badge, on a quad. Read from the world's planet
// by `GateLook.crest_kind`, never named: 0 a ringed planet, 1 a flame, 2 a
// snowflake, 3 a spore, 4 dune waves, 5 a burning peak.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform int kind = 0;
uniform vec3 color : source_color = vec3(1.0, 0.6, 0.3);

float line_to(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w * 0.6, w, length(pa - ba * h));
}

float emblem(vec2 p) {
	float t = TIME;
	if (kind == 1) {
		// A flame: a teardrop with a flickering tip and a hollow heart.
		vec2 q = p;
		q.x += sin(q.y * 6.0 + t * 5.0) * 0.03 * (q.y + 0.4);
		float body = length(vec2(q.x * (1.0 + max(q.y, 0.0) * 2.4), min(q.y, 0.0) * 1.1 + max(q.y, 0.0) * 0.45) + vec2(0.0, 0.05));
		float outer = 1.0 - smoothstep(0.3, 0.33, body);
		float inner = 1.0 - smoothstep(0.13, 0.16, length(vec2(q.x * 1.6, q.y + 0.12)));
		return clamp(outer - inner * 0.6, 0.0, 1.0);
	} else if (kind == 2) {
		// A snowflake: six spokes with barbs.
		float a = 0.0;
		for (int i = 0; i < 6; i++) {
			float ang = float(i) * 1.0472 + 1.5708;
			vec2 dir = vec2(cos(ang), sin(ang));
			vec2 side = vec2(-dir.y, dir.x);
			a = max(a, line_to(p, vec2(0.0), dir * 0.36, 0.035));
			a = max(a, line_to(p, dir * 0.2, dir * 0.28 + side * 0.08, 0.03));
			a = max(a, line_to(p, dir * 0.2, dir * 0.28 - side * 0.08, 0.03));
		}
		return a;
	} else if (kind == 3) {
		// A spore: a round head on a stalk, specks drifting off it.
		float a = 1.0 - smoothstep(0.15, 0.18, length(p - vec2(0.0, 0.08)));
		a = max(a, line_to(p, vec2(0.0, 0.0), vec2(0.0, -0.32), 0.04));
		for (int i = 0; i < 4; i++) {
			float f = fract(t * 0.25 + float(i) * 0.25);
			vec2 at = vec2(sin(float(i) * 2.3) * 0.25, 0.1 + f * 0.25);
			a = max(a, (1.0 - smoothstep(0.02, 0.035, length(p - at))) * (1.0 - f));
		}
		return a;
	} else if (kind == 4) {
		// Dune waves under a low sun.
		float a = 1.0 - smoothstep(0.1, 0.12, length(p - vec2(0.12, 0.16)));
		for (int i = 0; i < 3; i++) {
			float y = -0.04 - float(i) * 0.11;
			float wave = y + sin(p.x * 9.0 + float(i) * 1.3) * 0.03;
			a = max(a, (1.0 - smoothstep(0.012, 0.025, abs(p.y - wave))) * step(abs(p.x), 0.34));
		}
		return a;
	} else if (kind == 5) {
		// A peak with fire at its top.
		float a = line_to(p, vec2(-0.34, -0.28), vec2(0.0, 0.18), 0.035);
		a = max(a, line_to(p, vec2(0.34, -0.28), vec2(0.0, 0.18), 0.035));
		a = max(a, line_to(p, vec2(-0.34, -0.28), vec2(0.34, -0.28), 0.035));
		float glow = 1.0 - smoothstep(0.04, 0.09, length(p - vec2(0.0, 0.24 + sin(t * 4.0) * 0.01)));
		return max(a, glow);
	}
	// A ringed planet: the ring passes behind it at the top.
	float disc = 1.0 - smoothstep(0.17, 0.2, length(p));
	float ring = 1.0 - smoothstep(0.015, 0.03, abs(length(p * vec2(1.0, 3.0)) - 0.32));
	return max(disc, ring * (1.0 - disc * step(0.0, p.y)) * step(0.2, length(p)));
}

void fragment() {
	vec2 p = UV - 0.5;
	p.y = -p.y;
	// The diamond badge round it.
	float diamond = abs(p.x) + abs(p.y);
	float edge = 1.0 - smoothstep(0.015, 0.03, abs(diamond - 0.46));
	float inside = step(diamond, 0.46);
	vec3 col = vec3(0.02, 0.02, 0.03) * inside + color * edge * 1.6;
	col += color * emblem(p) * 1.8 * inside;
	if (diamond > 0.5) {
		discard;
	}
	ALBEDO = col;
}
