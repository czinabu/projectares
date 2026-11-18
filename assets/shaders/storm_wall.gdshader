shader_type spatial;
// The wall of a storm crossing the map, seen from outside (DESIGN.md
// "Weather: ash storms"): a boiling curtain of ash or snow on an open
// cylinder, ragged and churning at the top, solid at the foot. View only.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.18, 0.09, 0.07, 1.0);
uniform vec4 lit : source_color = vec4(0.55, 0.28, 0.16, 1.0);
uniform float opacity = 0.95;
uniform float churn = 1.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	vec2 p = vec2(UV.x * 18.0, h * 2.5);
	float n = texture(noise_tex, p * 0.25 + vec2(TIME * 0.01, TIME * -0.004) * churn).r;
	float n2 = texture(noise_tex, p * 0.9 + vec2(TIME * 0.03, 0.0) * churn).r;
	float billow = n * 0.65 + n2 * 0.35;
	// Solid low down, ragged where the cylinder's v runs out.
	float top = smoothstep(1.0, 0.45, h + (billow - 0.5) * 0.7);
	ALBEDO = mix(tint.rgb, lit.rgb, billow * (1.0 - h) * 0.8);
	ALPHA = clamp(top * mix(0.8, 1.0, billow) * opacity, 0.0, 1.0);
}
