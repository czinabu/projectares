shader_type spatial;
// Fires burning past a map's rim, seen as a band of glow behind its far
// skyline (`Look.trim("horizon_glow")`, put on an open ring by the map).
// Brightest low down and fading up into the smoke, with a slow uneven
// flicker along the ring so it reads as fire, not a lamp. `strength` is
// the map's to set (the war heats it, a storm hides it).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.32, 0.08, 1.0);
uniform float strength = 0.5;
// World heights: full glow under `bright_to`, none over `fade_to`.
uniform float bright_to = 40.0;
uniform float fade_to = 220.0;

varying float height;

void vertex() {
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float h = smoothstep(fade_to, bright_to, height);
	float around = UV.x * 6.2832;
	float flick = 0.7 + 0.3 * sin(around * 29.0 + TIME * 0.7) * sin(around * 7.0 - TIME * 0.31 + 1.3);
	ALBEDO = tint.rgb * strength * h * h * h * flick;
}
