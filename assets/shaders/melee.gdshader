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

varying vec3 opos;
varying vec3 onrm;

void vertex() {
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
	float pulse = 0.8 + 0.2 * sin(TIME * pulse_speed + opos.y * seam_scale * 0.5);
	// A faint charge across the whole edge part, bright at the edges.
	vec3 glow = energy_color * (0.12 + rim * 4.0) * edge_part * pulse;
	// Seams: thin bright bands around grips and fittings.
	float band = abs(fract(opos.y * seam_scale) - 0.5);
	float seam = smoothstep(0.43, 0.48, band) * (1.0 - edge_part);
	glow += energy_color * seam * 1.6 * pulse;
	EMISSION = glow * energy;
}
