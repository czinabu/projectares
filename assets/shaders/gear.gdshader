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
}
