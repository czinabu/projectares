shader_type spatial;
// A sea of lava: a dark cooled crust broken by bright seams and pools that
// drift slowly. Laid out in world space, so one sheet of any size tiles
// without stretching. (`Look` trim "lava".)

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 crust : source_color = vec3(0.05, 0.025, 0.02);
uniform vec3 hot : source_color = vec3(1.0, 0.32, 0.06);
// How bright the seams and pools burn.
uniform float glow = 2.2;
// How bright the crust between them still glows.
uniform float ember = 0.06;
uniform float scale = 0.007;
uniform float flow = 0.004;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * scale;
	float a = texture(noise_tex, p + vec2(TIME * flow, TIME * flow * 0.6)).r;
	float b = texture(noise_tex, p * 2.7 - vec2(TIME * flow * 1.3, 0.0) + 0.37).r;
	float n = a * 0.65 + b * 0.35;
	// Seams where the noise crosses its middle, pools where it runs high.
	float seam = 1.0 - smoothstep(0.0, 0.035, abs(n - 0.5));
	float pool = smoothstep(0.64, 0.74, n);
	float heat = max(seam, pool);
	ALBEDO = mix(crust, hot * 0.3, heat);
	ROUGHNESS = mix(0.9, 0.35, heat);
	EMISSION = hot * (heat * glow + ember);
}
