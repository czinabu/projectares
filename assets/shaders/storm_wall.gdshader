shader_type spatial;
// The body of a storm crossing the map, seen from outside (DESIGN.md
// "Weather: ash storms"): a churning mass of ash or snow on a steep dome
// as wide as the cell. It has no hard outline anywhere: faces seen edge on
// (its sides and its crown) fade to nothing, the top is eaten away by the
// billows, it is soft where it meets the ground or a building, and it thins
// as the camera nears it so walking in is a thickening haze, never a
// plane. Only its outside is drawn: from inside, the storm's fog is the
// storm (and the dome has thinned away by then). It keeps out of
// the world fog and sinks into the distance on its own (`fade_near`).
// View only.
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.18, 0.09, 0.07, 1.0);
uniform vec4 lit : source_color = vec4(0.55, 0.28, 0.16, 1.0);
uniform float opacity = 0.95;
uniform float churn = 1.0;
uniform float seed = 0.0;
// The camera this close sees through it; it is whole from `clear_far` out.
uniform float clear_near = 20.0;
uniform float clear_far = 80.0;
// Past `fade_near` it sinks into the distance, gone at `fade_far`. The
// world fog is left off it: fog the colour of the sky would wash a storm
// out long before it arrives, and it must read as a dark mass coming.
uniform float fade_near = 700.0;
uniform float fade_far = 1600.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);
	// Where nothing of it would show (too near the camera, too far, over
	// the crown or seen edge on), stop before the noise: the dome can fill
	// the screen, and most of it there is clear.
	float near = smoothstep(clear_near, clear_far, -VERTEX.z) * (1.0 - smoothstep(fade_near, fade_far, -VERTEX.z));
	float facing = dot(normalize(NORMAL), normalize(VIEW));
	if (near * opacity < 0.004 || h > 0.995 || facing < 0.015) {
		discard;
	}
	float t = TIME * churn;
	// Every sample takes a whole number of turns round the dome in u, so the
	// seam where u wraps does not show. The billows roll upward and along.
	vec2 slow = vec2(UV.x * 2.0, h * 0.4);
	vec2 warp = vec2(
			texture(noise_tex, slow + vec2(t * 0.004, -t * 0.006) + seed).r,
			texture(noise_tex, slow + vec2(0.37, 0.71) + vec2(-t * 0.004, -t * 0.003) + seed).r) - 0.5;
	vec2 big = vec2(UV.x * 6.0, h * 1.0) + warp * 0.25 + vec2(seed, -t * 0.01);
	float n = texture(noise_tex, big).r;
	float n2 = texture(noise_tex, vec2(UV.x * 14.0, h * 2.4) + warp * 0.4 + vec2(t * 0.012, -t * 0.02)).r;
	float billow = smoothstep(0.25, 0.75, n * 0.75 + n2 * 0.25);
	// A billow lit from above: brighter where it swells upward (the same
	// noise a little lower down is thinner), dark in the folds under it.
	float below = texture(noise_tex, big - vec2(0.0, 0.05)).r;
	float relief = clamp((n - below) * 7.0 + 0.5, 0.0, 1.0);
	// Edge on, it is gone: no rim at the sides or over the top.
	float edge = smoothstep(0.03, 0.45, facing + (billow - 0.5) * 0.4);
	// Thinner going up and gone over the crown, torn ragged by the billows:
	// the billows heaped there (`storm_billow.gdshader`) are its top.
	float top = smoothstep(0.92, 0.5, h + (billow - 0.5) * 0.6) * smoothstep(1.0, 0.8, h);
	// Soft where it meets the ground, a ridge or a building.
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = clamp((-behind.z / behind.w + VERTEX.z) / 14.0, 0.0, 1.0);
	float dense = mix(1.0, 1.4, billow);
	// Dark at the foot and in the folds, lit on the crowns of the billows.
	float light = clamp((0.25 + 0.75 * relief * mix(0.6, 1.0, billow)) * (0.4 + 0.6 * h), 0.0, 1.0);
	ALBEDO = mix(tint.rgb, lit.rgb, light);
	ALPHA = clamp(top * edge * dense * soft * near * opacity, 0.0, 1.0);
}
