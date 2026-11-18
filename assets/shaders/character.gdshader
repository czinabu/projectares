shader_type spatial;
// Skinned characters: the pack's own colors, pulled toward worn metal and
// tinted by faction. `flash` whitens the whole model for a hit.

uniform sampler2D base_tex : source_color, hint_default_white;
uniform vec3 base_color : source_color = vec3(1.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float saturation = 0.35;
uniform float brightness = 0.8;
uniform float rough = 0.6;
uniform float metal = 0.5;
uniform vec3 emission_color : source_color = vec3(0.0);
// A chosen colour for this surface (skin tone, hair, dyed cloth). With
// `recolor_shading` the surface's own light and dark panels are kept.
uniform vec3 recolor : source_color = vec3(1.0);
uniform float recolor_amount = 0.0;
uniform float recolor_shading = 0.0;
uniform float flash = 0.0;
// People (see `human.gd`): each vertex carries its place on the body at
// rest in CUSTOM0 (xyz) and how much it is a hand (w), so patterns stay on
// the body as it moves. `surface_kind`: 0 anything else, 1 skin, 2 skin the
// undersuit may cover (below the head), 3 eyes.
uniform int surface_kind = 0;
uniform float has_rest = 0.0;
// The undersuit: a fitted tech layer over bare arms, legs and hands, worn
// under an armor frame (`ActorSkin._update_frame`).
uniform float suit = 0.0;
uniform vec3 suit_color : source_color = vec3(0.075, 0.08, 0.09);
uniform vec3 glove_color : source_color = vec3(0.045, 0.045, 0.05);
uniform vec3 suit_trim : source_color = vec3(0.35, 0.85, 1.0);
uniform float suit_cell = 0.022;
varying vec4 rest;
// Storm readability. Godot drops its own fog once FOG is written, so this
// repeats that curve and then keeps less of it up close. `storm_pop` is 1
// on a character. The rim is a faction accent, strongest at engagement
// range and gone far away, so it never reads through the horizon.
global uniform float storm_fog_active = 0.0;
global uniform vec3 storm_fog_color : source_color = vec3(0.5);
global uniform float storm_fog_density = 0.01;
global uniform float storm_fog_depth = 0.0;
global uniform float storm_fog_begin = 0.0;
global uniform float storm_fog_end = 0.0;
global uniform float storm_fog_curve = 1.0;
global uniform float storm_fog_height = 0.0;
global uniform float storm_fog_height_density = 0.0;
uniform float storm_clear = 16.0;
uniform float storm_full = 72.0;
uniform float storm_keep_near = 0.2;
uniform float storm_rim_strength = 0.75;
uniform float storm_pop = 1.0;
uniform vec3 storm_rim : source_color = vec3(0.3, 0.9, 1.0);

void vertex() {
	rest = CUSTOM0;
}

// Distance to the nearest edge of a hex cell, in cells (0 on the edge).
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 q = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? abs(h.xy) : abs(h.zw);
	return 0.5 - max(dot(q, s * 0.5), q.x);
}

// Bends `n` (view space) as if the surface rose by `h` (meters), from the
// screen-space change of `h`: bump mapping with no tangents needed.
vec3 bump(vec3 n, vec3 pos, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - grad);
}

void fragment() {
	vec3 c = texture(base_tex, UV).rgb * base_color;
	float own = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, recolor * mix(1.0, 0.45 + 1.1 * own, recolor_shading), recolor_amount);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * tint * brightness;
	// Darker in the creases the flat pack colors cannot show.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c *= mix(0.6, 1.0, facing);
	float r = rough;
	float m = metal;
	vec3 glow = vec3(0.0);
	float dist0 = length(VERTEX);
	bool person = has_rest > 0.5;
	// How much of this point the undersuit covers.
	float suited = (person && surface_kind == 2) ? suit : 0.0;
	if (person && surface_kind >= 1 && surface_kind <= 2 && suited < 1.0) {
		// Skin: light passing through it warms the shadow side.
		BACKLIGHT = c * vec3(0.55, 0.22, 0.14) * (1.0 - suited);
		r = mix(r, 0.62, 1.0 - suited);
	}
	if (person && surface_kind == 3) {
		r = 0.12;
		SPECULAR = 0.9;
	}
	if (suited > 0.0) {
		vec3 p = rest.xyz;
		// The face of the rest body this point is on, for a pattern that
		// wraps the limb instead of smearing along it.
		vec3 rn = abs(normalize(cross(dFdx(p), dFdy(p)) + vec3(1e-6)));
		vec2 plane = rn.x > rn.y && rn.x > rn.z ? p.yz : (rn.y > rn.z ? p.xz : p.xy);
		float edge = hex_edge(plane / suit_cell);
		float near = 1.0 - smoothstep(2.5, 6.0, dist0);
		float glove = smoothstep(0.45, 0.6, rest.w);
		vec3 cloth = mix(suit_color, glove_color, glove);
		// Raised cells with sunken seams between them, gloves left smooth.
		float seam = 1.0 - smoothstep(0.03, 0.12, edge);
		cloth *= mix(1.0, 0.62, seam * (1.0 - glove) * near);
		c = mix(c, cloth, suited);
		r = mix(r, mix(0.42, 0.75, glove), suited);
		m = mix(m, 0.15, suited);
		NORMAL = mix(NORMAL, bump(NORMAL, VERTEX, -seam * 0.0012 * (1.0 - glove) * near), suited);
		// A lit trim where the glove meets the sleeve.
		float cuff = smoothstep(0.3, 0.42, rest.w) * (1.0 - smoothstep(0.42, 0.54, rest.w));
		glow += suit_trim * cuff * 1.6 * suited;
	}
	ALBEDO = mix(c, vec3(1.0), flash);
	ROUGHNESS = r;
	METALLIC = m * (1.0 - flash);
	EMISSION = emission_color + glow + vec3(flash) * 1.5;
	float dist = length(VERTEX);
	float edge = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	float band = smoothstep(8.0, 22.0, dist) * (1.0 - smoothstep(46.0, 76.0, dist));
	EMISSION += storm_rim * edge * storm_rim_strength * storm_pop * band;
	float amount = 0.0;
	if (storm_fog_active > 0.5) {
		if (storm_fog_depth > 0.5) {
			float fog_z = smoothstep(storm_fog_begin, storm_fog_end, dist);
			amount = pow(max(fog_z, 0.0), max(storm_fog_curve, 0.001)) * storm_fog_density;
		} else {
			amount = 1.0 - exp(-dist * storm_fog_density);
		}
		float world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float y_dist = world_y - storm_fog_height;
		float vfog = 1.0 - exp(min(0.0, y_dist * storm_fog_height_density));
		amount = max(amount, vfog);
		float far = clamp((dist - storm_clear) / max(storm_full - storm_clear, 0.001), 0.0, 1.0);
		float keep = mix(mix(1.0, storm_keep_near, storm_pop), 1.0, far);
		amount *= keep;
	}
	FOG = vec4(storm_fog_color, clamp(amount, 0.0, 1.0));
}
