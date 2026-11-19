shader_type spatial;
// The Spore Marsh's far giants (worlds/marsh/flora.gd): drawn as shapes in
// the haze, not as lit things. Their feet fade into the haze colour and
// their tops stand darker against the sky, their gills glow through, and
// `veil` (close air or a storm round the viewer) hides them. Unshaded and
// with its own haze (thicker with distance), so the depth fog's floor
// cannot wash them out or show them crisp. View only.
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_opaque;

uniform vec4 shade : source_color = vec4(0.1, 0.13, 0.12, 1.0);
uniform vec4 haze : source_color = vec4(0.27, 0.31, 0.25, 1.0);
uniform vec4 glow : source_color = vec4(0.35, 1.0, 0.72, 1.0);
uniform float gills = 0.0;
uniform float foot_y = 0.0;
uniform float fade_height = 160.0;
uniform float veil = 0.0;

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float up = smoothstep(0.0, 1.0, clamp((world.y - foot_y) / fade_height, 0.0, 1.0));
	float far = smoothstep(350.0, 1100.0, length(world - CAMERA_POSITION_WORLD));
	vec3 c = mix(haze.rgb, shade.rgb, up * (0.85 - 0.45 * far));
	// Gills: a slow glow under each cap, banded like ribs.
	float ribs = 0.8 + 0.2 * sin(UV.x * 160.0);
	float pulse = 0.8 + 0.2 * sin(TIME * 0.35 + world.x * 0.004 + world.z * 0.003);
	c = mix(c, glow.rgb * 0.7, gills * (0.12 + 0.3 * COLOR.r) * ribs * pulse * (1.0 - 0.5 * far));
	ALBEDO = c;
	ALPHA = 1.0 - clamp(veil, 0.0, 1.0);
}
