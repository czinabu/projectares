shader_type sky;
// A photographed sky, graded per world: tint, saturation and a haze band
// that hides the horizon line and matches the fog color.

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform float saturation = 1.0;
uniform vec3 haze_color : source_color = vec3(0.5);
uniform float haze_height = 0.25;
uniform float rotation = 0.0;

void sky() {
	vec2 uv = SKY_COORDS;
	uv.x = fract(uv.x + rotation);
	vec3 c = texture(panorama, uv).rgb;
	// Compress the sun so it does not blow out after tinting.
	c = c / (1.0 + c * 0.08);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * tint * energy;
	float h = 1.0 - smoothstep(0.0, haze_height, EYEDIR.y);
	c = mix(c, haze_color, h * h * 0.92 + step(EYEDIR.y, 0.0));
	COLOR = c;
}
