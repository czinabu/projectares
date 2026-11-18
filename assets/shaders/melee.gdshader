shader_type spatial;
// Melee weapons, restyled as tech: the pack model's light parts (blades,
// heads) become machined alloy with an energy edge, mid greys (guards,
// fittings) dark gunmetal, and the rest (wood, leather, wraps) black polymer
// with thin glowing seams. Look picks the part from the model's own color
// (`part`), so any pack model works. Grime is projected in object space like
// gear.gdshader.

uniform sampler2D base_tex : source_color, hint_default_white;
uniform vec3 base_color : source_color = vec3(1.0);
uniform vec3 energy_color : source_color = vec3(0.3, 0.85, 1.0);
uniform float energy = 1.0;
// 1 for an edge (alloy), 0.5 for a fitting (gunmetal), 0 for a grip (polymer).
uniform float part = 1.0;
uniform sampler2D grime_albedo : source_color, repeat_enable;
uniform sampler2D grime_rough : hint_default_white, repeat_enable;
uniform float grime_scale = 2.0;
uniform float wear = 0.4;
// Seam bands on the grip per object-space unit (Look sets it so there are
// a few per meter), and how fast the glow pulses.
uniform float seam_scale = 6.0;
uniform float pulse_speed = 2.2;
// How brightly the outline glows where the surface turns from the view.
uniform float rim_glow = 0.7;
// The part's own object-space bounds, so the energy edge can run along the
// outer edges of a flat blade whatever the angle it is seen from.
// `edge_axis` is the mesh axis the blade is wide along (Look.blade_axes),
// and -1 for a part that is not flat or not edged (a hammer head), which
// gets no cutting edge.
uniform vec3 box_min = vec3(-1.0);
uniform vec3 box_max = vec3(1.0);
uniform int edge_axis = -1;
// The blade's thin axis (the flat's normal), from Look.blade_axes.
uniform int flat_axis = -1;
// The mesh axis that runs up the weapon, which the grip's seams ring.
uniform int length_axis = 1;

// Folding away (Look.set_extend): at `extend` 0 the part of the mesh more
// than nothing along `fold_axis` past `fold_origin` (object space) slides in:
// the first `fold_slide` of it shrinks to `fold_keep` of its length and the
// rest moves down with it. A blade folds all of itself into the hilt.
uniform float extend = 1.0;
// Same storm curve as character.gdshader. Worn blades set `storm_pop`.
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
uniform float storm_pop = 0.0;
uniform vec3 storm_rim : source_color = vec3(0.3, 0.9, 1.0);
uniform vec3 fold_origin = vec3(0.0);
uniform vec3 fold_axis = vec3(0.0, 1.0, 0.0);
uniform float fold_slide = 0.0;
uniform float fold_keep = 1.0;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	if (fold_slide > 0.0 && extend < 1.0) {
		float d = dot(VERTEX - fold_origin, fold_axis);
		if (d > 0.0) {
			float k = mix(fold_keep, 1.0, extend);
			float folded = d < fold_slide ? d * k : d - fold_slide * (1.0 - k);
			VERTEX += fold_axis * (folded - d);
		}
	}
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 w = pow(abs(normalize(onrm)), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = opos * grime_scale;
	vec3 gcol = texture(grime_albedo, p.zy).rgb * w.x + texture(grime_albedo, p.xz).rgb * w.y + texture(grime_albedo, p.xy).rgb * w.z;
	float grough = texture(grime_rough, p.zy).r * w.x + texture(grime_rough, p.xz).r * w.y + texture(grime_rough, p.xy).r * w.z;
	float edge_part = step(0.75, part);
	float fitting = step(0.25, part) * (1.0 - edge_part);
	float g = dot(gcol, vec3(0.333));
	float scuff = smoothstep(0.35, 0.15, grough) * wear;

	vec3 alloy = vec3(0.6, 0.64, 0.7) * mix(0.85, 1.1, g);
	vec3 gunmetal = vec3(0.2, 0.21, 0.24) * mix(0.85, 1.15, g);
	vec3 polymer = vec3(0.06, 0.065, 0.075) * mix(0.8, 1.3, g);
	ALBEDO = mix(mix(polymer, gunmetal, fitting), alloy, edge_part) * (1.0 - scuff * 0.3);
	METALLIC = mix(mix(0.3, 0.85, fitting), 0.95, edge_part);
	ROUGHNESS = clamp(mix(mix(0.6, 0.35, fitting), 0.2, edge_part) + scuff * 0.25, 0.0, 1.0);

	// Energy edge: the blade glows where its surface turns away from the
	// view, which traces its edges and outline whatever the model.
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed + dot(opos, vec3(float(length_axis == 0), float(length_axis == 1), float(length_axis == 2))) * seam_scale * 0.5);
	// The cutting edge: the outer tenth of the part's width, either side.
	float cutting = 0.0;
	if (edge_axis >= 0) {
		// Axes picked by a dot product, never a dynamic index (some Vulkan
		// drivers cannot compile one).
		vec3 ax = vec3(float(edge_axis == 0), float(edge_axis == 1), float(edge_axis == 2));
		float half_w = max(dot(box_max - box_min, ax) * 0.5, 1e-4);
		float across = abs(dot(opos - (box_max + box_min) * 0.5, ax)) / half_w;
		cutting = smoothstep(0.8, 0.97, across);
		// A curved blade's edge is not at the ends of its box, so also light
		// any face that turns away from the flat of the blade.
		vec3 flat_n = vec3(float(flat_axis == 0), float(flat_axis == 1), float(flat_axis == 2));
		cutting = max(cutting, smoothstep(0.75, 0.95, 1.0 - abs(dot(normalize(onrm), flat_n))) * 0.8);
	}
	// A faint charge across the whole edge part and a bright cutting edge;
	// the flat of the blade stays machined alloy (the weapon pass: light in
	// trim, never a whole part aglow, like the guns' finish).
	vec3 glow = energy_color * (0.04 + rim * rim_glow + cutting * 2.4) * edge_part * pulse;
	// Seams: thin bright bands around grips and fittings.
	vec3 len_n = vec3(float(length_axis == 0), float(length_axis == 1), float(length_axis == 2));
	float band = abs(fract(dot(opos, len_n) * seam_scale) - 0.5);
	float seam = smoothstep(0.43, 0.48, band) * (1.0 - edge_part);
	glow += energy_color * seam * 1.6 * pulse;
	EMISSION = glow * energy;
	float dist = length(VERTEX);
	float storm_edge = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	float storm_band = smoothstep(8.0, 22.0, dist) * (1.0 - smoothstep(46.0, 76.0, dist));
	EMISSION += storm_rim * storm_edge * storm_rim_strength * storm_pop * storm_band;
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
