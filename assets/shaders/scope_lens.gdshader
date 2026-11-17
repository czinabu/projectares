// A scope's eyepiece seen from the eye: the magnified picture rendered for
// it, a fine black crosshair with heavier posts toward the rim, a lit centre
// dot, and the rim darkening into the tube. Drawn on the real scope's glass
// (`PlayerController._update_scope`), never over the screen.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D view : source_color, filter_linear;
uniform vec4 dot_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	if (r > 1.0) {
		discard;
	}
	vec3 col = texture(view, UV).rgb;
	float aa = fwidth(r) * 1.5;
	// Fine lines through the middle, posts from halfway out.
	float wide_x = abs(c.x) > 0.5 ? 0.025 : 0.004;
	float wide_y = abs(c.y) > 0.5 ? 0.025 : 0.004;
	float line = max(1.0 - smoothstep(wide_x, wide_x + aa, abs(c.y)),
			1.0 - smoothstep(wide_y, wide_y + aa, abs(c.x)));
	col = mix(col, vec3(0.02), line);
	float dot_mask = 1.0 - smoothstep(0.012, 0.012 + aa, r);
	col = mix(col, dot_color.rgb, dot_mask);
	// The rim falls off into the dark of the tube.
	col *= smoothstep(1.0, 0.86, r);
	ALBEDO = col;
}
