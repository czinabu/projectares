shader_type spatial;
// Skinned characters: the pack's own colors, pulled toward worn metal and
// tinted by faction. `flash` whitens the whole model for a hit.

uniform sampler2D base_tex : source_color, hint_default_white;
uniform vec3 base_color : source_color = vec3(1.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float saturation = 0.35;
uniform float brightness = 0.8;
uniform float rough = 0.6;
uniform float metal = 0.5;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float flash = 0.0;

void fragment() {
	vec3 c = texture(base_tex, UV).rgb * base_color;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * tint * brightness;
	// Darker in the creases the flat pack colors cannot show.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c *= mix(0.6, 1.0, facing);
	ALBEDO = mix(c, vec3(1.0), flash);
	ROUGHNESS = rough;
	METALLIC = metal * (1.0 - flash);
	EMISSION = emission_color + vec3(flash) * 1.5;
}
