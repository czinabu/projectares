shader_type spatial;
// The scenery army's tracers and muzzle flashes: a lit streak in the
// instance's colour (custom data rgb) at its brightness (a).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

varying vec4 glow;

void vertex() {
	glow = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = glow.rgb * glow.a;
}
