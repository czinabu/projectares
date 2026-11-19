shader_type spatial;
// A shaft of light in smoke, drawn on an open cone whose top is where the
// light comes from (a lamp, or a break in the smoke): brightest along its
// middle where you look through the most light, easing in from the top over
// `top_fade` so it has no edge there, thinning to `foot` at its far end, and
// thinning close to the eye so standing in one never floods the view.
// (`Look` trims "sun_shaft" and "beam".)
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.48, 1.0);
uniform float strength = 0.05;
// How much of the cone, from the top, the light takes to come in.
uniform float top_fade = 0.45;
// What is left of it where it meets the ground (0 to 1).
uniform float foot = 0.35;
// Within this many metres of the eye it thins out.
uniform float near_fade = 140.0;
// Fades one shaft without a material of its own (1 is fully lit).
instance uniform float fade = 1.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 3.0);
	// A CylinderMesh's side runs UV.y 0 (top) to 0.5 (bottom).
	float t = clamp(UV.y * 2.0, 0.0, 1.0);
	float along = smoothstep(0.0, top_fade, t) * mix(1.0, foot, smoothstep(0.5, 1.0, t));
	float near = smoothstep(near_fade * 0.3, near_fade, -VERTEX.z);
	ALBEDO = tint.rgb * core * along * near * strength * fade;
}
