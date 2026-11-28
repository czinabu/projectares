shader_type spatial;
// Skinned characters: the pack's own colors, pulled toward worn metal and
// tinted by faction. `flash` whitens the whole model for a hit.

uniform sampler2D base_tex : source_color, hint_default_white;
// The detailed bodies' normal and roughness maps (`Look.dress_surfaces`);
// `normal_amount` 0 leaves the mesh's own normals, `rough_from_tex` 0 uses
// `rough`. The roughness is the green of an ORM map.
uniform sampler2D normal_tex : hint_normal;
uniform float normal_amount = 0.0;
uniform sampler2D rough_tex : hint_default_white;
uniform float rough_from_tex = 0.0;
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
// An eye's iris tinted (`Human.iris_for`): the pack's eye texture has the
// iris as a disc in the middle of its UVs; its light and dark are kept.
uniform vec3 iris_color : source_color = vec3(1.0);
uniform float iris_amount = 0.0;
uniform vec2 iris_centre = vec2(0.497, 0.5);
uniform float iris_radius = 0.1;
// People (see `human.gd`): each vertex carries its place on the body at
// rest in CUSTOM0 (xyz) and how much it is a hand (w), so patterns stay on
// the body as it moves. `surface_kind`: 0 anything else, 1 skin, 2 skin the
// undersuit may cover (below the head), 3 eyes.
uniform int surface_kind = 0;
// How a person's bare skin is drawn, the same under every skin's tint.
const float SKIN_SATURATION = 0.85;
const float SKIN_BRIGHTNESS = 0.82;
uniform float has_rest = 0.0;
// The undersuit: a fitted tech layer over bare arms, legs and hands, worn
// under an armor frame (`ActorSkin._update_frame`).
uniform float suit = 0.0;
uniform vec3 suit_color : source_color = vec3(0.075, 0.08, 0.09);
uniform vec3 glove_color : source_color = vec3(0.045, 0.045, 0.05);
uniform vec3 suit_trim : source_color = vec3(0.35, 0.85, 1.0);
uniform float suit_cell = 0.022;
// The suit's fatigue kit, drawn on the rest body (metres, feet at 0, front
// +Z): a belt, cargo pockets down the outer thighs, knee pads, a darker
// yoke over the shoulders, so it reads as
// clothing, not a skin. 0 leaves the plain suit.
uniform float suit_kit = 1.0;
// A pattern printed on the suit in shades of its own colour
// (`Human.PATTERNS`): 0 plain, 1 woodland, 2 digital, 3 tiger stripe,
// 4 splinter. Drawn on the rest body, so it stays put as the body moves.
uniform int suit_pattern = 0;
// The suit's style (`Human.SUIT_STYLES`): its cut (`suit_cut`: the panels,
// seams, pockets, stripes and trims laid out on it) and its cloth
// (`suit_material`: the weave and the sheen). Drawn on the rest body like
// the pattern, and only here: a style never changes the suit's shape, so
// nothing it draws can stand out through armor, and the same body is drawn
// in first and third person. `suit_second` is the style's second colour, a
// shade of the suit's own (`Human.second_shade`), so a style keeps working
// under any dye or armor paint. 0 is the tactical cut and its hex weave.
uniform int suit_cut = 0;
uniform int suit_material = 0;
uniform vec3 suit_second : source_color = vec3(0.04, 0.042, 0.045);
// Where the body is at rest (`Human.body_marks`), so a style sits right on
// either build: (hip, chest and neck heights, how far out the shoulder
// joint is), (the arm's height and front, how far out the elbow and wrist
// are), (how far out a leg is, the knee's and ankle's heights, its front).
uniform vec4 suit_trunk = vec4(0.949, 1.311, 1.52, 0.212);
uniform vec4 suit_arm = vec4(1.4555, 0.065, 0.463, 0.7065);
uniform vec4 suit_leg = vec4(0.114, 0.542, 0.087, 0.036);
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

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

// Smooth noise, 0 to 1.
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// The suit's pattern at rest point `p`: how much lighter or darker the
// cloth is there (1 leaves it).
float suit_print(int kind, vec3 p) {
	if (kind == 1) {
		// Woodland: soft blots in three shades.
		float a = noise3(p * 9.0) * 0.65 + noise3(p * 23.0) * 0.35;
		float b = noise3(p * 11.0 + 17.0) * 0.65 + noise3(p * 27.0 + 5.0) * 0.35;
		return a > 0.56 ? 0.55 : (b > 0.58 ? 1.35 : 1.0);
	}
	if (kind == 2) {
		// Digital: the same blots made of square pixels.
		vec3 q = floor(p / 0.012) * 0.012;
		float a = noise3(q * 10.0) * 0.7 + noise3(q * 30.0) * 0.3;
		float b = noise3(q * 12.0 + 9.0) * 0.7 + noise3(q * 33.0 + 3.0) * 0.3;
		return a > 0.57 ? 0.6 : (b > 0.57 ? 1.3 : 1.0);
	}
	if (kind == 3) {
		// Tiger stripe: broken dark bands across the body.
		float wave = p.y * 38.0 + noise3(p * 7.0) * 5.0 + p.x * 6.0;
		float band = abs(fract(wave / 6.2832) - 0.5);
		float broken = noise3(p * 14.0 + 3.0);
		return band < 0.13 && broken > 0.35 ? 0.5 : 1.0;
	}
	if (kind == 4) {
		// Splinter: sharp-edged shards in three shades.
		float a = floor(dot(p, vec3(9.0, 13.0, 4.0)) + noise3(floor(p * 7.0)) * 3.0);
		float b = floor(dot(p, vec3(-12.0, 7.0, 9.0)));
		float h = hash3(vec3(a, b, 1.0));
		return h < 0.3 ? 0.58 : (h > 0.75 ? 1.3 : 1.0);
	}
	return 1.0;
}

// 1 within `w` of a distance `d` of 0, its edge smoothed over a pixel.
float aa_in(float d, float w) {
	float f = max(fwidth(d), 1e-5);
	return 1.0 - smoothstep(w - f, w + f, d);
}

// Between `lo` and `hi`.
float within(float v, float lo, float hi) {
	return aa_in(abs(v - (lo + hi) * 0.5), (hi - lo) * 0.5);
}

// Inside a box (centre `c`, half size `h`), and on its outline `w` wide.
float in_box(vec2 q, vec2 c, vec2 h) {
	vec2 e = abs(q - c) - h;
	return aa_in(max(e.x, e.y), 0.0);
}

float box_line(vec2 q, vec2 c, vec2 h, float w) {
	vec2 e = abs(q - c) - h;
	return aa_in(abs(max(e.x, e.y)), w);
}

// Distance from `q` to the segment `a` to `b`.
float seg(vec2 q, vec2 a, vec2 b) {
	vec2 pa = q - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// A row of round studs or buttons `gap` apart along `along`, `size` across.
float dots(float along, float across, float gap, float size) {
	float d = length(vec2((fract(along / gap) - 0.5) * gap, across));
	return aa_in(d, size);
}

// What a style draws at a point of the suit.
struct SuitLook {
	float second; // the style's second colour
	float paint; // the trim colour as cloth: piping, braid, thread, stripes
	float glow; // the trim colour lit
	float light; // off-white: a shirt, reflective tape
	float line; // seams and stitching, darker
	float tone; // lighter or darker cloth
	float height; // how far it stands up, metres, for the light
	float rough; // smoother (below 0) or rougher
	float metal; // zips, studs, buttons, buckles
};

// The suit's cut at rest point `p` (`rn` the face it is on): see
// `Human.SUIT_STYLES` for which outfit wears which. Each part of the body
// (`Human.SLOTS`) is its own surface with its own cut, so a top and legs of
// different styles mix; each cut draws the whole body and a part shows
// what falls on it.
SuitLook suit_style(int cut, vec3 p, vec3 rn) {
	SuitLook s = SuitLook(0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0);
	float x = abs(p.x);
	float hip = suit_trunk.x;
	float chest = suit_trunk.y;
	float neck = suit_trunk.z;
	float sh = suit_trunk.w;
	// The top's lowest edge, and the bottom's waistband.
	float hem = hip + 0.1;
	float waist = hip + 0.05;
	// Widths across the trunk, narrower on the narrower build.
	float wide = mix(1.0, sh / 0.212, 0.5);
	float arm = smoothstep(sh - 0.005, sh + 0.005, x) * smoothstep(chest - 0.06, chest - 0.04, p.y);
	float trunk = (1.0 - arm) * step(hip - 0.06, p.y);
	float legs = 1.0 - step(hip - 0.06, p.y);
	float front = step(0.0, p.z);
	// Round each arm (held out at rest, so 0 is the top, the outer side
	// when it hangs) and each leg (0 the outer side, pi/2 the front).
	vec2 ad = vec2(p.y - suit_arm.x, p.z - suit_arm.y);
	float arm_r = length(ad);
	float arm_out = abs(atan(ad.y, ad.x)) * arm_r;
	vec2 ld = vec2(x - suit_leg.x, p.z - suit_leg.w);
	float leg_r = length(ld);
	float leg_ang = atan(ld.y, ld.x);
	float leg_out = abs(leg_ang) * leg_r;
	float leg_front = abs(leg_ang - 1.5708) * leg_r;
	float elbow = suit_arm.z;
	float wrist = suit_arm.w;
	float knee = suit_leg.y;
	float ankle = suit_leg.z;
	vec2 q = vec2(x, p.y);
	if (cut == 0) {
		// Tactical: a belt, cargo pockets down the outer thighs, knee pads,
		// a yoke over the shoulders.
		float t = 1.0 - smoothstep(0.2, 0.24, x);
		float belt = within(p.y, waist - 0.024, waist + 0.024) * t;
		float buckle = belt * aa_in(x, 0.025) * front;
		float side = step(rn.z, rn.x) * step(0.075, x) * step(x, 0.26) * legs;
		vec2 pq = vec2(p.z + 0.01, p.y);
		vec2 pc = vec2(0.0, knee + 0.16);
		float pocket = side * in_box(pq, pc, vec2(0.065, 0.1));
		float flap = pocket * step(knee + 0.225, p.y);
		float pocket_edge = side * box_line(pq, pc, vec2(0.065, 0.1), 0.003);
		vec2 knee_at = vec2((x - suit_leg.x + 0.01) / 0.065, (p.y - knee + 0.04) / 0.07);
		float pad = (1.0 - smoothstep(0.85, 1.0, length(knee_at))) * smoothstep(-0.07, -0.05, p.z) * legs;
		float yoke_line = p.y - (neck - 0.14);
		float yoke = smoothstep(-0.004, 0.004, yoke_line) * t;
		s.tone = mix(1.0, 0.82, yoke) * mix(1.0, 0.86, pocket) * mix(1.0, 0.72, flap);
		s.line = max(pocket_edge, aa_in(abs(yoke_line), 0.003) * t);
		s.second = max(pad, belt);
		s.rough = -0.2 * max(pad, belt);
		s.height = pad * 0.004 + flap * 0.0015;
		s.metal = buckle;
	} else if (cut == 1) {
		// Pressure suit: light side panels, ribbed elbows and knees, a collar
		// ring and lit piping down the outside of each arm and leg.
		float side = trunk * smoothstep(0.1 * wide, 0.11 * wide, x) * step(hem, p.y);
		float shoulder = trunk * step(neck - 0.09, p.y) * smoothstep(0.08, 0.1, x);
		float collar = within(p.y, neck - 0.06, neck - 0.035) * trunk;
		float ribs_e = arm * within(x, elbow - 0.04, elbow + 0.04) * step(0.5, fract(x / 0.011));
		float ribs_k = legs * within(p.y, knee - 0.06, knee + 0.04) * step(0.5, fract(p.y / 0.011));
		float rib = max(ribs_e, ribs_k);
		float pipe = max(arm * aa_in(arm_out, 0.0028) * step(x, wrist - 0.03),
				legs * aa_in(leg_out, 0.0028) * step(ankle + 0.05, p.y));
		float chest_line = trunk * front * aa_in(abs(p.y - (chest + 0.07) + x * 0.5), 0.004) * step(x, 0.1 * wide);
		s.second = max(max(side, shoulder), collar);
		s.line = max(rib * 0.6, max(aa_in(abs(x - 0.1 * wide), 0.003) * trunk * step(hem, p.y), chest_line));
		s.height = rib * 0.0025 + collar * 0.003;
		s.glow = pipe + chest_line * 0.6;
		s.rough = -0.1 * s.second;
	} else if (cut == 2) {
		// Field jacket: a buttoned placket, two chest pockets with flaps,
		// raglan seams, banded cuffs and hem; the trousers carry cargo
		// pockets and knee patches.
		float placket = trunk * front * aa_in(x, 0.016) * step(hem, p.y);
		vec2 pc = vec2(0.085 * wide, chest + 0.0);
		float pocket = trunk * front * in_box(q, pc, vec2(0.042 * wide, 0.05));
		float flap = trunk * front * in_box(q, pc + vec2(0.0, 0.04), vec2(0.046 * wide, 0.016));
		float edges = trunk * front * max(box_line(q, pc, vec2(0.042 * wide, 0.05), 0.0025),
				box_line(q, pc + vec2(0.0, 0.04), vec2(0.046 * wide, 0.016), 0.0025));
		float raglan = trunk * aa_in(seg(q, vec2(0.07 * wide, neck - 0.03), vec2(sh + 0.01, suit_arm.x - 0.07)), 0.0025);
		float cuff = arm * within(x, wrist - 0.075, wrist - 0.025);
		float band = trunk * within(p.y, hem, hem + 0.045);
		float side = step(rn.z, rn.x) * legs;
		vec2 lq = vec2(p.z + 0.01, p.y);
		vec2 lc = vec2(0.0, knee + 0.17);
		float cargo = side * in_box(lq, lc, vec2(0.06, 0.09));
		float cargo_edge = side * box_line(lq, lc, vec2(0.06, 0.09), 0.0025);
		float patch = legs * aa_in(leg_front, 0.05) * within(p.y, knee - 0.09, knee + 0.05);
		float buttons = placket * dots(p.y, x, 0.06, 0.006);
		s.second = max(max(flap, cuff), max(band, patch * 0.7));
		s.tone = mix(1.0, 0.9, max(pocket, cargo));
		s.line = max(max(edges, raglan), max(cargo_edge, aa_in(abs(x - 0.016), 0.002) * trunk * front * step(hem, p.y)));
		s.height = (flap + pocket * 0.5 + cargo * 0.5) * 0.0015;
		s.metal = buttons;
	} else if (cut == 3) {
		// Hoodie: a pouch pocket across the belly, a ribbed hem and cuffs, a
		// hood's collar and drawstrings; joggers with ribbed ankles and a
		// drawstring waist.
		float py0 = hem + 0.045;
		float py1 = hem + 0.18;
		float slope = (p.y - py0) * 0.3;
		float pouch_in = trunk * front * within(p.y, py0, py1) * aa_in(x, 0.115 * wide - slope);
		float pouch_edge = trunk * front * within(p.y, py0 - 0.002, py1 + 0.002)
				* max(aa_in(abs(x - (0.115 * wide - slope)), 0.0025), aa_in(abs(p.y - py1), 0.0025) * step(x, 0.115 * wide - slope));
		float opening = trunk * front * aa_in(abs(x - (0.085 * wide - slope * 0.4)), 0.003) * within(p.y, py0 + 0.02, py1 - 0.01);
		float rib_hem = trunk * within(p.y, hem, hem + 0.045);
		float rib_cuff = arm * within(x, wrist - 0.075, wrist - 0.02);
		float rib_ankle = legs * within(p.y, ankle + 0.03, ankle + 0.11);
		float rib_waist = legs * within(p.y, hip - 0.02, hip + 0.06);
		float rib = max(max(rib_hem, rib_cuff), max(rib_ankle, rib_waist));
		float hood = trunk * step(neck - 0.06, p.y);
		float strings = trunk * front * aa_in(abs(x - 0.035), 0.004) * within(p.y, neck - 0.2, neck - 0.05);
		float tip = trunk * front * aa_in(length(vec2(x - 0.035, p.y - (neck - 0.2))), 0.008);
		float wstring = legs * front * aa_in(abs(x - 0.03), 0.003) * within(p.y, hip - 0.06, hip + 0.02);
		float ribs = rib * (0.5 + 0.5 * sin((arm > 0.5 ? arm_out * 6.0 : (legs > 0.5 ? leg_out * 4.0 : x)) * 1500.0));
		s.second = max(rib * 0.6, hood * 0.8);
		s.tone = mix(1.0, 0.93, pouch_in) * mix(1.0, 0.9, ribs);
		s.line = max(max(pouch_edge, opening), aa_in(abs(p.y - (neck - 0.06)), 0.003) * trunk);
		s.paint = max(strings, max(tip, wstring));
		s.height = pouch_in * 0.002 + ribs * 0.0006 + hood * 0.004;
		s.rough = 0.05 * rib;
	} else if (cut == 4) {
		// Track suit: a zip up the front, a collar band, shoulders in the
		// second colour and two stripes down the outside of each arm and leg
		// in the trim colour.
		float zip = trunk * front * aa_in(x, 0.0035) * step(hem, p.y);
		float collar = trunk * within(p.y, neck - 0.055, neck);
		float yoke = trunk * step(chest + 0.1 + x * 0.25, p.y) + arm * aa_in(arm_out, 0.03) * step(x, elbow - 0.06);
		float d = arm > 0.5 ? arm_out : leg_out;
		float on = arm > 0.5 ? step(x, wrist - 0.03) : legs * step(ankle + 0.04, p.y);
		float stripes = on * (within(d, 0.004, 0.011) + within(d, 0.017, 0.024));
		float side_stripe = trunk * step(rn.z, rn.x) * (within(p.z, -0.01, -0.003) + within(p.z, 0.003, 0.01)) * step(hem, p.y);
		float cuff = arm * within(x, wrist - 0.05, wrist - 0.02) + legs * within(p.y, ankle + 0.02, ankle + 0.06);
		s.second = max(max(collar, yoke), max(cuff, trunk * within(p.y, hem, hem + 0.035)));
		s.paint = min(stripes + side_stripe, 1.0);
		s.metal = zip;
		s.line = aa_in(abs(x - 0.006), 0.0015) * trunk * front * step(hem, p.y);
		s.height = zip * 0.001;
		s.rough = -0.05;
	} else if (cut == 5) {
		// Leather jacket: an off-centre zip running up to one shoulder, a
		// wide lapel, studs across the shoulders, stitched panels; moto
		// trousers with ribbed knees and a studded belt.
		vec2 sq = vec2(p.x, p.y);
		vec2 za = vec2(-0.03 * wide, hem);
		vec2 zb = vec2(0.075 * wide, neck - 0.05);
		float zd = seg(sq, za, zb);
		float zip = trunk * front * aa_in(zd, 0.0035);
		float side_of = (sq.x - za.x) * (zb.y - za.y) - (sq.y - za.y) * (zb.x - za.x);
		float lapel = trunk * front * step(chest - 0.02, p.y) * step(0.0, side_of) * aa_in(zd, 0.06);
		float lapel_edge = trunk * front * step(chest - 0.02, p.y) * step(0.0, side_of) * aa_in(abs(zd - 0.06), 0.0025);
		float studs = trunk * dots(x, p.y - (neck - 0.075), 0.022, 0.0045) * within(x, 0.06, sh + 0.02);
		float panel = trunk * aa_in(abs(p.y - (chest - 0.06)), 0.0025) * step(hem, p.y);
		float knee_ribs = legs * aa_in(leg_front, 0.045) * within(p.y, knee - 0.06, knee + 0.06) * step(0.5, fract(p.y / 0.014));
		float seam = legs * aa_in(leg_front, 0.0025) + legs * aa_in(leg_out, 0.0025);
		float belt = legs * within(p.y, hip + 0.0, hip + 0.045);
		float bstuds = belt * dots(p.x + p.z, p.y - (hip + 0.0225), 0.025, 0.006);
		float cuffzip = arm * aa_in(abs(atan(ad.y, ad.x) + 1.57) * arm_r, 0.0025) * within(x, wrist - 0.12, wrist - 0.02);
		s.second = max(lapel, belt);
		s.line = max(max(lapel_edge, panel), max(seam, knee_ribs * 0.7));
		s.metal = max(max(zip, studs), max(bstuds, cuffzip));
		s.height = knee_ribs * 0.002 + lapel * 0.002 + studs * 0.003;
		s.tone = mix(1.0, 0.9, knee_ribs);
	} else if (cut == 6) {
		// Work bib: a bib over the chest with straps over the shoulders,
		// stitched in the trim colour, a bib pocket and buckles; the
		// trousers have a stitched outer seam and knee patches.
		float bib_top = chest + 0.06;
		float bib = trunk * front * aa_in(x, 0.105 * wide) * within(p.y, hem - 0.02, bib_top);
		float stitch = trunk * front * within(p.y, hem - 0.02, bib_top) * aa_in(abs(x - 0.098 * wide), 0.0018);
		stitch += trunk * front * aa_in(x, 0.098 * wide) * aa_in(abs(p.y - (bib_top - 0.008)), 0.0018);
		float strap_x = 0.085 * wide;
		float strap = trunk * step(bib_top, p.y) * aa_in(abs(x - strap_x), 0.018) * (front + (1.0 - front) * 1.0);
		strap = max(strap, trunk * (1.0 - front) * aa_in(abs(x - strap_x * (1.0 - (p.y - hem) * 0.0)), 0.018) * step(chest - 0.05, p.y));
		float buckle = trunk * front * aa_in(length(vec2(x - strap_x, p.y - bib_top)), 0.012);
		vec2 pc = vec2(0.0, chest - 0.03);
		float pocket = trunk * front * box_line(vec2(p.x, p.y), pc, vec2(0.045, 0.04), 0.0016);
		float roll = arm * within(x, elbow - 0.01, elbow + 0.05);
		float seam = legs * aa_in(leg_out, 0.0018) * step(ankle + 0.03, p.y);
		float patch = legs * aa_in(leg_front, 0.045) * within(p.y, knee - 0.08, knee + 0.05);
		float patch_edge = legs * aa_in(abs(leg_front - 0.045), 0.0018) * within(p.y, knee - 0.08, knee + 0.05);
		s.second = max(max(bib, strap), max(roll, patch));
		s.paint = min(stitch + pocket + seam + patch_edge, 1.0) * 0.85;
		s.metal = buckle;
		s.height = bib * 0.0015 + strap * 0.002 + roll * 0.004;
	} else if (cut == 7) {
		// Formal: lapels in the second colour over a shirt and a tie in the
		// trim colour, two buttons, faint pinstripes, shirt cuffs; creased
		// trousers.
		float v_low = hem + 0.13;
		float lap_in = (p.y - v_low) * 0.32;
		float lap_out = lap_in + 0.05 * wide;
		float upper = trunk * front * step(v_low, p.y);
		float shirt = upper * aa_in(x, lap_in);
		float tie = shirt * aa_in(x, 0.012 + (neck - p.y) * 0.04) * step(p.y, neck - 0.04);
		float lapel = upper * step(lap_in, x) * aa_in(x - lap_out, 0.0);
		float lapel_edge = upper * aa_in(abs(x - lap_out), 0.002);
		float buttons = trunk * front * aa_in(x, 0.02) * (aa_in(length(vec2(x, p.y - (v_low - 0.03))), 0.007)
				+ aa_in(length(vec2(x, p.y - (v_low - 0.1))), 0.007));
		float pin_coord = arm > 0.5 ? arm_out : (legs > 0.5 ? leg_out : x);
		float pin = aa_in(abs(fract(pin_coord / 0.018) - 0.5) * 0.018, 0.0006);
		float crease = legs * aa_in(leg_front, 0.0018);
		float cuff = arm * within(x, wrist - 0.035, wrist - 0.012);
		s.second = lapel;
		s.light = max(shirt - tie, cuff);
		s.paint = tie;
		s.metal = buttons;
		s.tone = mix(1.0, 1.18, pin * (1.0 - shirt));
		s.line = max(lapel_edge, crease * 0.8);
		s.height = lapel * 0.0015 + crease * 0.001;
		s.rough = -0.15 * lapel;
	} else if (cut == 8) {
		// Breton: broad stripes round the body and sleeves in the second
		// colour, rolled sleeves; trousers rolled at the shin.
		float coord = arm > 0.5 ? x : p.y;
		float stripes = (1.0 - legs) * step(0.62, fract(coord / 0.045)) * step(hem + 0.02, p.y) * step(p.y, chest + 0.1 + (arm > 0.5 ? 1.0 : 0.0));
		float roll = arm * within(x, elbow + 0.02, elbow + 0.08);
		float roll_edge = arm * aa_in(abs(x - (elbow + 0.02)), 0.003);
		float cuff = legs * within(p.y, ankle + 0.12, ankle + 0.2);
		float cuff_edge = legs * aa_in(abs(p.y - (ankle + 0.2)), 0.003);
		float neckline = trunk * within(p.y, neck - 0.045, neck - 0.02);
		float lace = legs * front * aa_in(abs(x - 0.025), 0.0025) * within(p.y, hip - 0.04, hip + 0.03);
		s.second = max(stripes, neckline);
		s.tone = mix(1.0, 0.85, max(roll, cuff));
		s.line = max(roll_edge, cuff_edge);
		s.height = (roll + cuff) * 0.006;
		s.paint = lace;
	} else if (cut == 9) {
		// Warlord: a quilted coat edged in braid in the trim colour down the
		// front, round the hem, collar and cuffs, a sash across the chest;
		// braid down the outside of the legs.
		float braid = trunk * front * aa_in(x, 0.014) * step(hem, p.y);
		braid += trunk * within(p.y, hem, hem + 0.025) + trunk * within(p.y, neck - 0.05, neck - 0.02);
		braid += arm * within(x, wrist - 0.06, wrist - 0.03);
		braid += legs * aa_in(leg_out, 0.008) * step(ankle + 0.03, p.y);
		float sash = trunk * aa_in(abs((p.y - hem - 0.04) - (p.x + 0.12) * 1.6) / 1.88, 0.04) * step(hem + 0.03, p.y);
		float sash_edge = trunk * aa_in(abs(abs((p.y - hem - 0.04) - (p.x + 0.12) * 1.6) / 1.88 - 0.04), 0.0025) * step(hem + 0.03, p.y);
		float clasp = trunk * front * aa_in(length(vec2(x, p.y - (chest + 0.02))), 0.016);
		s.paint = min(braid, 1.0) * (1.0 - sash);
		s.second = sash;
		s.line = sash_edge;
		s.metal = clasp;
		s.height = min(braid, 1.0) * 0.002 + sash * 0.003;
		s.rough = -0.2 * min(braid, 1.0);
	} else if (cut == 10) {
		// Hi-vis work suit: reflective tape round the body, arms and shins,
		// edged in the trim colour; a second colour over the shoulders.
		float bands = trunk * (within(p.y, hem + 0.07, hem + 0.1) + within(p.y, chest - 0.02, chest + 0.01));
		bands += arm * within(x, sh + 0.08, sh + 0.11) + arm * within(x, elbow + 0.08, elbow + 0.11);
		bands += legs * (within(p.y, ankle + 0.13, ankle + 0.16) + within(p.y, ankle + 0.2, ankle + 0.23));
		bands = min(bands, 1.0);
		float yoke = trunk * step(chest + 0.07, p.y) + arm * step(x, sh + 0.05);
		float kneepad = legs * aa_in(leg_front, 0.04) * within(p.y, knee - 0.06, knee + 0.04);
		float zip = trunk * front * aa_in(x, 0.003) * step(hem, p.y);
		s.light = bands;
		s.glow = bands * 0.12;
		s.second = max(yoke * (1.0 - bands), kneepad);
		s.metal = zip;
		s.rough = -0.35 * bands - 0.1 * kneepad;
		s.height = kneepad * 0.004;
	} else if (cut == 11) {
		// Sellsword: a quilted gambeson, laced at the front in the trim
		// colour, with two leather straps crossed over the chest and a
		// buckle where they meet; legs wrapped from the knee down.
		float lace_zone = trunk * front * aa_in(x, 0.016) * step(hem, p.y) * step(p.y, neck - 0.04);
		float zig = abs(fract(p.y / 0.03) - 0.5) * 0.032;
		float lace = lace_zone * aa_in(abs(x - zig), 0.0018);
		float slit = lace_zone * 0.6;
		float a1 = abs((p.y - hem) - (p.x + 0.13 * wide) * 2.2) / 2.42;
		float a2 = abs((p.y - hem) - (-p.x + 0.13 * wide) * 2.2) / 2.42;
		float strap = trunk * step(hem, p.y) * max(aa_in(a1, 0.016), aa_in(a2, 0.016));
		float buckle = trunk * front * aa_in(length(vec2(x, p.y - (hem + 0.13 * wide * 2.2))), 0.016);
		float wraps = legs * step(p.y, knee - 0.02) * step(ankle + 0.04, p.y);
		float wrap_line = wraps * aa_in(abs(fract((p.y + leg_ang * 0.012) / 0.028) - 0.5) * 0.028, 0.0018);
		s.second = max(strap, wraps * 0.5);
		s.paint = lace;
		s.tone = mix(1.0, 0.75, slit);
		s.metal = buckle;
		s.line = wrap_line;
		s.height = strap * 0.003 + wraps * 0.002;
		s.rough = -0.25 * strap;
	} else if (cut == 12) {
		// Mystic: a front panel of chevrons in the trim colour, a sash, and
		// lit bands of glyphs round the hem, cuffs and ankles.
		float panel = trunk * front * aa_in(x, 0.05 * wide) * step(hem, p.y) * step(p.y, neck - 0.06);
		float chevron = panel * step(fract((p.y + x * 1.2) / 0.06), 0.14);
		float sash = trunk * within(p.y, hem + 0.03, hem + 0.08);
		float h_band = trunk * within(p.y, hem + 0.0, hem + 0.022);
		float c_band = arm * within(x, wrist - 0.07, wrist - 0.045);
		float a_band = legs * within(p.y, ankle + 0.05, ankle + 0.075);
		float glyph_coord = arm > 0.5 ? arm_out : (legs > 0.5 ? leg_out : p.x + p.z);
		float cell = floor(glyph_coord / 0.014);
		float glyph = step(0.35, fract(sin(cell * 12.9898) * 43758.5453)) * step(0.25, fract(glyph_coord / 0.014));
		float bands = min(h_band + c_band + a_band, 1.0);
		float panel_seam = legs * aa_in(leg_front, 0.002);
		s.second = max(panel, sash);
		s.paint = chevron;
		s.glow = bands * glyph;
		s.line = max(trunk * front * aa_in(abs(x - 0.05 * wide), 0.002) * step(hem, p.y) * step(p.y, neck - 0.06), panel_seam);
		s.height = sash * 0.003;
		s.tone = mix(1.0, 0.7, bands * (1.0 - glyph));
	} else if (cut == 13) {
		// Envoy: a high-collared tunic closed off-centre, piped in the trim
		// colour with a row of buttons, piped cuffs and shoulder boards;
		// piped trousers with a pressed crease.
		vec2 sq = vec2(p.x, p.y);
		float pipe_x = 0.065 * wide;
		float d = min(seg(sq, vec2(0.0, neck - 0.045), vec2(pipe_x, chest + 0.0)), seg(sq, vec2(pipe_x, chest), vec2(pipe_x, hem)));
		float pipe = trunk * front * aa_in(d, 0.003);
		float buttons = trunk * front * aa_in(abs(p.x - pipe_x - 0.016), 0.01) * step(hem + 0.02, p.y) * step(p.y, chest)
				* dots(p.y, p.x - pipe_x - 0.016, 0.045, 0.006);
		float collar = trunk * within(p.y, neck - 0.05, neck);
		float collar_pipe = trunk * aa_in(abs(p.y - (neck - 0.05)), 0.0025);
		float board = trunk * within(x, sh - 0.07, sh) * step(neck - 0.08, p.y);
		float cuff = arm * within(x, wrist - 0.07, wrist - 0.02);
		float cuff_pipe = arm * aa_in(abs(x - (wrist - 0.07)), 0.0025);
		float leg_pipe = legs * aa_in(leg_out, 0.0035) * step(ankle + 0.03, p.y);
		float crease = legs * aa_in(leg_front, 0.0018);
		s.second = max(max(collar, cuff), board);
		s.paint = min(pipe + collar_pipe + cuff_pipe + leg_pipe, 1.0);
		s.metal = buttons;
		s.line = crease;
		s.height = collar * 0.003 + board * 0.002 + crease * 0.0008;
		s.rough = -0.1;
	} else if (cut == 50) {
		// Boots: a darker toe cap and heel, a welt seam and the sole.
		float sole = 1.0 - step(0.028, p.y);
		float welt = aa_in(abs(p.y - 0.028), 0.0025);
		float cap = step(p.y, 0.07) * step(suit_leg.w + 0.1, p.z);
		s.tone = mix(1.0, 0.45, sole) * mix(1.0, 0.8, cap);
		s.line = welt;
		s.rough = -0.15 * cap;
	}
	return s;
}

// The suit's cloth at rest point `p`: x how much lighter or darker, y its
// roughness, z how far it stands up (metres). `around` runs round the
// limb or across the trunk, `near` fades the finest weave with distance.
vec3 suit_weave(int kind, vec3 p, vec2 plane, float around, float near) {
	if (kind == 0) {
		// Tech weave: a fine hex.
		float seam = 1.0 - smoothstep(0.03, 0.12, hex_edge(plane / suit_cell));
		return vec3(1.0 - 0.14 * seam * near, 0.82, -seam * 0.0004 * near);
	}
	if (kind == 1) {
		// Canvas: a tight plain weave.
		float w = sin(plane.x * 2100.0) * sin(plane.y * 2100.0);
		return vec3(1.0 - 0.06 * w * near, 0.88, w * 0.00012 * near);
	}
	if (kind == 2) {
		// Knit: soft ribs.
		float r = 0.5 + 0.5 * sin(around * 1800.0);
		return vec3(mix(0.93, 1.03, mix(0.5, r, near)), 0.96, r * 0.00025 * near);
	}
	if (kind == 3) {
		// Leather: a fine grain, worn lighter in broad patches.
		float grain = noise3(p * 700.0);
		float worn = noise3(p * 14.0);
		return vec3(0.88 + 0.22 * worn, 0.62 + 0.12 * grain, (grain - 0.5) * 0.00012 * near);
	}
	if (kind == 4) {
		// Satin: smooth, with a soft sheen.
		return vec3(1.0, 0.6, 0.0);
	}
	if (kind == 5) {
		// Quilted: stitched diamonds, each puffed up.
		float u = (plane.x + plane.y) / 0.05;
		float v = (plane.x - plane.y) / 0.05;
		float e = min(abs(fract(u) - 0.5), abs(fract(v) - 0.5));
		float puff = smoothstep(0.0, 0.22, e);
		return vec3(mix(0.68, 1.04, puff), 0.78, puff * 0.0018);
	}
	if (kind == 6) {
		// Rubberised: smooth and a little shiny.
		float n = noise3(p * 120.0);
		return vec3(0.96 + 0.06 * n, 0.64, 0.0);
	}
	if (kind == 7) {
		// Denim: a diagonal twill, heathered.
		float twill = sin((plane.x + plane.y * 2.0) * 2600.0);
		float heather = noise3(p * 260.0);
		return vec3(0.86 + 0.2 * heather - 0.05 * twill * near, 0.92, twill * 0.0001 * near);
	}
	if (kind == 8) {
		// Worsted wool: smooth and matte.
		return vec3(0.98 + 0.04 * noise3(p * 400.0), 0.66, 0.0);
	}
	if (kind == 9) {
		// Linen: uneven slubs along the threads.
		float slub = noise3(vec3(p.x * 30.0, p.y * 500.0, p.z * 30.0));
		return vec3(0.9 + 0.16 * slub, 0.9, 0.0);
	}
	if (kind == 10) {
		// Channel quilting: puffed rows.
		float e = abs(fract(around / 0.032) - 0.5);
		float puff = smoothstep(0.0, 0.2, e);
		return vec3(mix(0.72, 1.04, puff), 0.8, puff * 0.0016);
	}
	return vec3(1.0, 0.82, 0.0);
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
	if (iris_amount > 0.0) {
		float in_iris = 1.0 - smoothstep(iris_radius - 0.012, iris_radius + 0.004, distance(UV, iris_centre));
		c = mix(c, iris_color * (0.35 + 1.6 * own), in_iris * iris_amount);
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// The faction's tint, saturation and brightness dress the clothes and
	// gear, never a person's skin: skin keeps its own tone in every army.
	vec3 dressed = mix(vec3(l), c, saturation) * tint * brightness;
	float bare_skin = has_rest > 0.5 ? (surface_kind == 1 ? 1.0 : (surface_kind == 2 ? 1.0 - suit : 0.0)) : 0.0;
	c = mix(dressed, mix(vec3(l), c, SKIN_SATURATION) * SKIN_BRIGHTNESS, bare_skin);
	// Darker in the creases the flat pack colors cannot show.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c *= mix(0.6, 1.0, facing);
	float r = mix(rough, texture(rough_tex, UV).g, rough_from_tex);
	if (normal_amount > 0.0) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_amount;
	}
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
		float near = 1.0 - smoothstep(2.5, 6.0, dist0);
		float glove = smoothstep(0.45, 0.6, rest.w);
		vec3 cloth = mix(suit_color, glove_color, glove);
		// A flat pack outfit's own panels kept as tone, so pads and seams
		// still read; a detailed body's texture is skin, so it is left out
		// and its normal map, softened a lot (the cloth hangs over it), gives the suit its form.
		if (normal_amount <= 0.0) {
			cloth *= mix(0.7 + 0.9 * own, 1.0, glove);
		} else {
			NORMAL_MAP_DEPTH = mix(normal_amount, normal_amount * 0.15, suited);
		}
		float bare = 1.0 - glove;
		// Round the limb, or across the trunk, for weaves that run that way.
		float around = rest.y < suit_trunk.x - 0.06 ? atan(p.z - suit_leg.w, abs(p.x) - suit_leg.x) * 0.06
				: (abs(p.x) > suit_trunk.w && rest.y > suit_trunk.y - 0.05 ? abs(p.x) : (rn.x > rn.z ? p.z : p.x));
		vec3 weave = suit_weave(suit_material, p, plane, around, near);
		cloth *= mix(1.0, weave.x, bare);
		if (suit_pattern > 0) {
			cloth *= mix(1.0, suit_print(suit_pattern, p), bare);
		}
		float trim_paint = 0.0;
		float metal_at = 0.0;
		float rough_at = mix(weave.y, 0.7, glove);
		float height = weave.z * bare;
		if (suit_kit > 0.0) {
			SuitLook s = suit_style(suit_cut, p, rn);
			float k = bare * suit_kit;
			cloth *= mix(1.0, s.tone, k);
			// Seams darken the cloth, but on near-black cloth they show as
			// lighter stitching instead, so a dark suit keeps its cut.
			float line = clamp(s.line, 0.0, 1.0) * k;
			float dark = 1.0 - smoothstep(0.04, 0.12, dot(suit_color, vec3(0.299, 0.587, 0.114)));
			cloth = mix(cloth * (1.0 - 0.42 * line), cloth + vec3(0.07) * line, dark);
			cloth = mix(cloth, suit_second, clamp(s.second, 0.0, 1.0) * k);
			cloth = mix(cloth, suit_trim * 0.8, clamp(s.paint, 0.0, 1.0) * k);
			cloth = mix(cloth, vec3(0.8, 0.8, 0.78), clamp(s.light, 0.0, 1.0) * k);
			cloth = mix(cloth, vec3(0.5, 0.5, 0.48), clamp(s.metal, 0.0, 1.0) * k);
			glow += suit_trim * clamp(s.glow, 0.0, 1.0) * 1.4 * k * suited;
			metal_at = clamp(s.metal, 0.0, 1.0) * k;
			rough_at = clamp(rough_at + s.rough * k, 0.08, 1.0);
			height += s.height * k - line * 0.0004;
		}
		c = mix(c, cloth, suited);
		r = mix(r, mix(rough_at, 0.3, metal_at), suited);
		m = mix(m, 0.0, suited);
		m = mix(m, 0.85, metal_at * suited);
		NORMAL = mix(NORMAL, bump(NORMAL, VERTEX, height), suited);
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
