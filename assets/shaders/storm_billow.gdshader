shader_type spatial;
// The billows heaped on a storm's front (`WeatherView`): big soft puffs
// facing the camera, set round the dome's upper half so its outline is a
// row of rolling heads, never a curve. Each one boils (its edge eaten by
// moving noise), turns slowly and swells and sinks on its own clock.
// Per puff: INSTANCE_CUSTOM.x a seed, .y its size in metres at a 100 m
// storm. View only; out of the world fog, like the dome.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.18, 0.09, 0.07, 1.0);
uniform vec4 lit : source_color = vec4(0.55, 0.28, 0.16, 1.0);
uniform float opacity = 0.95;
// How big the storm is next to the 100 m one the puffs were laid out for.
uniform float size_scale = 1.0;
uniform float clear_near = 20.0;
uniform float clear_far = 80.0;
// Past `fade_near` it sinks into the distance, gone at `fade_far`. The
// world fog is left off it: fog the colour of the sky would wash a storm
// out long before it arrives, and it must read as a dark mass coming.
uniform float fade_near = 700.0;
uniform float fade_far = 1600.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec2 puff;

void vertex() {
	puff = INSTANCE_CUSTOM.xy;
	float clock = TIME * 0.05 + puff.x * 6.28;
	float size = puff.y * size_scale * (1.0 + 0.12 * sin(clock * 1.7));
	// Rising a little and settling back, as a billow does.
	vec3 at = MODEL_MATRIX[3].xyz + vec3(0.0, sin(clock) * 0.08 * size, 0.0);
	float turn = TIME * 0.015 * (puff.x - 0.5) + puff.x * 6.28;
	vec3 right = INV_VIEW_MATRIX[0].xyz * cos(turn) + INV_VIEW_MATRIX[1].xyz * sin(turn);
	vec3 up = INV_VIEW_MATRIX[1].xyz * cos(turn) - INV_VIEW_MATRIX[0].xyz * sin(turn);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * size, 0.0), vec4(up * size, 0.0),
			vec4(INV_VIEW_MATRIX[2].xyz * size, 0.0), vec4(at, 1.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float near = smoothstep(clear_near, clear_far, -VERTEX.z) * (1.0 - smoothstep(fade_near, fade_far, -VERTEX.z));
	// Past its round edge or too near the camera to show: stop before the noise.
	if (near * opacity < 0.004 || dot(p, p) > 2.0) {
		discard;
	}
	vec2 drift = vec2(puff.x * 7.0, puff.x * 3.0) + vec2(TIME * 0.006, -TIME * 0.01);
	float n = texture(noise_tex, UV * 0.6 + drift).r;
	float n2 = texture(noise_tex, UV * 1.7 - drift * 1.6).r;
	float billow = n * 0.65 + n2 * 0.35;
	float shape = smoothstep(1.0, 0.15, length(p) + (billow - 0.5) * 1.1);
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float soft = clamp((-behind.z / behind.w + VERTEX.z) / 14.0, 0.0, 1.0);
	// Lit on its upper side (UV.y runs down the quad), dark underneath.
	float light = clamp((1.0 - UV.y) * 0.7 + (billow - 0.5) * 0.8, 0.0, 1.0);
	ALBEDO = mix(tint.rgb, lit.rgb, light);
	ALPHA = clamp(shape * mix(0.5, 1.0, billow) * soft * near * opacity, 0.0, 1.0);
}
