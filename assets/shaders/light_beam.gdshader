shader_type spatial;
// A soft shaft of light in the haze, drawn on an open cone: brightest along
// its middle where you look straight through the most light, fading to its
// edges and toward its far end, so it has no hard sides.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform float strength = 0.045;

void fragment() {
	// How square-on this bit of the cone is to the view: its edges glance off.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.5);
	// UV.y runs down the cone from the lamp (0) to its far end (1).
	float along = (1.0 - UV.y) * smoothstep(0.0, 0.08, UV.y);
	ALBEDO = tint.rgb * core * along * strength;
}
