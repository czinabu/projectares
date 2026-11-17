shader_type spatial;
// Held gear and static props: the model's own colors, worn down. Grime is
// projected in object space so it sticks to the object. Not for skinned
// meshes, where object space does not follow the limbs.

uniform sampler2D base_tex : source_color, hint_default_white;
uniform vec3 base_color : source_color = vec3(1.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform sampler2D grime_albedo : source_color, repeat_enable;
uniform sampler2D grime_rough : hint_default_white, repeat_enable;
uniform sampler2D grime_normal : hint_normal, repeat_enable;
uniform float grime_scale = 2.0;
uniform float wear = 0.6;
uniform float darken = 0.8;
uniform float metal = 0.6;
// Same storm curve as character.gdshader. `storm_pop` stays 0 on props, so a
// crate keeps the world's fog; worn gear sets it to 1.
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
uniform float storm_pop = 0.0;
uniform vec3 storm_rim : source_color = vec3(0.3, 0.9, 1.0);

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 w = pow(abs(normalize(onrm)), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = opos * grime_scale;
	vec3 gcol = texture(grime_albedo, p.zy).rgb * w.x + texture(grime_albedo, p.xz).rgb * w.y + texture(grime_albedo, p.xy).rgb * w.z;
	float grough = texture(grime_rough, p.zy).r * w.x + texture(grime_rough, p.xz).r * w.y + texture(grime_rough, p.xy).r * w.z;
	vec3 base = texture(base_tex, UV).rgb * base_color;
	// Pull the toy-bright pack colors toward worn painted metal.
	float l = dot(base, vec3(0.299, 0.587, 0.114));
	base = mix(vec3(l), base, 0.55) * darken;
	float g = dot(gcol, vec3(0.333));
	float rust = smoothstep(0.35, 0.15, grough) * wear;
	ALBEDO = mix(base * mix(0.6, 1.25, g), gcol * 0.5, rust * 0.5);
	ROUGHNESS = clamp(mix(0.35, 0.9, grough) + rust * 0.2, 0.0, 1.0);
	METALLIC = metal * (1.0 - rust * 0.6);
	EMISSION = emission_color;
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
