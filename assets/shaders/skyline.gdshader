shader_type spatial;
// Skyline silhouettes far past a map's rim (`Look.trim("distant")`): dark
// shapes against the sky, the way far buildings read through smoke. The
// haze is done here by hand rather than by the fog, which washed lit boxes
// out to pale tan: thicker toward the foot, where the air is deepest, and
// `haze_amount` follows the mood (`Look.apply_mood`), so a storm still
// swallows them.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec4 dark : source_color = vec4(0.07, 0.035, 0.03, 1.0);
uniform vec4 haze : source_color = vec4(0.3, 0.15, 0.11, 1.0);
uniform float haze_amount = 0.42;
// World heights between which the foot's extra haze thins out.
uniform float low_from = 30.0;
uniform float low_to = 160.0;

varying float height;

void vertex() {
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float low = 1.0 - smoothstep(low_from, low_to, height);
	float amount = clamp(haze_amount * (0.4 + 0.6 * low), 0.0, 1.0);
	// The thicker the air overall, the more even it gets top to bottom.
	amount = mix(amount, haze_amount, smoothstep(0.6, 1.0, haze_amount));
	ALBEDO = mix(dark.rgb, haze.rgb, amount);
}
