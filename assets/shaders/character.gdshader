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
// A chosen colour for this surface (skin tone, hair, dyed cloth). With
// `recolor_shading` the surface's own light and dark panels are kept.
uniform vec3 recolor : source_color = vec3(1.0);
uniform float recolor_amount = 0.0;
uniform float recolor_shading = 0.0;
uniform float flash = 0.0;
// Storm readability. Godot drops its own fog once FOG is written, so this
// repeats that curve and then keeps less of it up close. `storm_pop` is 1
// on a character. The rim is a faction accent, strongest at engagement
// range and gone far away, so it never reads through the horizon.
global uniform float storm_fog_active = 0.0;
global uniform vec3 storm_fog_color : source_color = vec3(0.5);
global uniform float storm_fog_density = 0.01;
global uniform float storm_fog_depth = 0.0;
global uniform float storm_fog_begin = 0.0;
global uniform float storm_fog_end = 0.0;
global uniform float storm_fog_curve = 1.0;
global uniform float storm_fog_height = 0.0;
global uniform float storm_fog_height_density = 0.0;
uniform float storm_clear = 16.0;
uniform float storm_full = 72.0;
uniform float storm_keep_near = 0.2;
uniform float storm_rim_strength = 0.75;
uniform float storm_pop = 1.0;
uniform vec3 storm_rim : source_color = vec3(0.3, 0.9, 1.0);

void fragment() {
	vec3 c = texture(base_tex, UV).rgb * base_color;
	float own = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, recolor * mix(1.0, 0.45 + 1.1 * own, recolor_shading), recolor_amount);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * tint * brightness;
	// Darker in the creases the flat pack colors cannot show.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c *= mix(0.6, 1.0, facing);
	ALBEDO = mix(c, vec3(1.0), flash);
	ROUGHNESS = rough;
	METALLIC = metal * (1.0 - flash);
	EMISSION = emission_color + vec3(flash) * 1.5;
	float dist = length(VERTEX);
	float edge = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	float band = smoothstep(8.0, 22.0, dist) * (1.0 - smoothstep(46.0, 76.0, dist));
	EMISSION += storm_rim * edge * storm_rim_strength * storm_pop * band;
	float amount = 0.0;
	if (storm_fog_active > 0.5) {
		if (storm_fog_depth > 0.5) {
			float fog_z = smoothstep(storm_fog_begin, storm_fog_end, dist);
			amount = pow(max(fog_z, 0.0), max(storm_fog_curve, 0.001)) * storm_fog_density;
		} else {
			amount = 1.0 - exp(-dist * storm_fog_density);
		}
		float world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float y_dist = world_y - storm_fog_height;
		float vfog = 1.0 - exp(min(0.0, y_dist * storm_fog_height_density));
		amount = max(amount, vfog);
		float far = clamp((dist - storm_clear) / max(storm_full - storm_clear, 0.001), 0.0, 1.0);
		float keep = mix(mix(1.0, storm_keep_near, storm_pop), 1.0, far);
		amount *= keep;
	}
	FOG = vec4(storm_fog_color, clamp(amount, 0.0, 1.0));
}
