shader_type spatial;
// Where a shell is about to land (`ShellView`): a column of red light up out
// of the ground on an open cylinder, brightest along its middle and at its
// foot, fading upward, pulsing faster as the shell gets near (`urgency`).
// View only.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.12, 0.04, 1.0);
uniform float strength = 0.9;
uniform float urgency = 0.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 3.0);
	// UV.y runs down the cylinder from its top (0) to the ground (1).
	float along = pow(UV.y, 2.2);
	float beat = 0.6 + 0.4 * sin(TIME * mix(5.0, 22.0, urgency));
	ALBEDO = tint.rgb * core * along * strength * beat;
}
