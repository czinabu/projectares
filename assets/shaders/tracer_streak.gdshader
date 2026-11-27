shader_type spatial;
// The scenery army's tracers and muzzle flashes: a lit streak in the
// instance's colour (custom data rgb) at its brightness (a).
// Only the front faces: added twice, a closed box would wash out white.
// Far off on the battle shelves a streak is widened to stay `min_px`
// pixels thick (a short one, a muzzle flash, grows every way), and `veil`
// (an ash storm's cover) dims it.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform float min_px = 1.6;
uniform float veil = 0.0;

varying vec4 glow;

void vertex() {
	glow = INSTANCE_CUSTOM;
	glow.a *= 1.0 - veil;
	float d = max(-(MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).z, 0.1);
	float pixel = 2.0 * d / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float thick = length(MODEL_MATRIX[0].xyz);
	float grow = max(1.0, min_px * pixel / max(thick, 0.01));
	VERTEX.xy *= grow;
	if (length(MODEL_MATRIX[2].xyz) < 2.0) {
		VERTEX.z *= grow;
	}
}

void fragment() {
	ALBEDO = glow.rgb * glow.a;
}
