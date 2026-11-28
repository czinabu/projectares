shader_type spatial;
// Skyline silhouettes far past a map's rim (`Look.trim("distant")`): dark
// shapes against the sky, the way far buildings read through smoke. The
// haze is done here by hand rather than by the fog, which washed lit boxes
// out to pale tan: thicker toward the foot, where the air is deepest, and
// `haze_amount` follows the mood (`Look.apply_mood`), so a storm still
// swallows them.
//
// With `lit` on (`Look.trim("distant_lit")`, a ruined city) the walls keep
// a scattering of lit windows and a few floors still burning, flickering,
// laid out in world space so every block shares one material. The haze
// takes them too.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec4 dark : source_color = vec4(0.07, 0.035, 0.03, 1.0);
uniform vec4 haze : source_color = vec4(0.3, 0.15, 0.11, 1.0);
uniform float haze_amount = 0.42;
// World heights between which the foot's extra haze thins out.
uniform float low_from = 30.0;
uniform float low_to = 160.0;
uniform float lit = 0.0;
// With `relief` on (`Look.trim("distant_relief")`, the giants) faces take
// a little light by how they face, so plating and ribs read through the
// haze instead of one flat cutout: tops palest, flanks less, undersides not.
uniform float relief = 0.0;
// A window's cell on a wall (m across, m up), and the share of cells lit.
uniform vec2 cell = vec2(4.5, 3.6);
uniform float windows = 0.07;
uniform float burning = 0.025;
uniform vec4 window_colour : source_color = vec4(1.0, 0.62, 0.3, 1.0);
uniform vec4 fire_colour : source_color = vec4(1.0, 0.32, 0.06, 1.0);

varying float height;
varying vec3 world;
varying vec3 normal_world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = world.y;
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float low = 1.0 - smoothstep(low_from, low_to, height);
	float amount = clamp(haze_amount * (0.4 + 0.6 * low), 0.0, 1.0);
	// The thicker the air overall, the more even it gets top to bottom.
	amount = mix(amount, haze_amount, smoothstep(0.6, 1.0, haze_amount));
	vec3 colour = dark.rgb;
	if (relief > 0.0) {
		float face = 0.9 * max(normal_world.y, 0.0) + 0.45 * abs(normal_world.x) + 0.25 * abs(normal_world.z);
		colour *= 1.0 + relief * face;
	}
	if (lit > 0.0 && abs(normal_world.y) < 0.5) {
		vec2 along = normalize(vec2(-normal_world.z, normal_world.x));
		vec2 uv = vec2(dot(world.xz, along), world.y) / cell;
		vec2 id = floor(uv);
		vec2 f = fract(uv);
		float pane = step(0.3, f.x) * step(f.x, 0.75) * step(0.35, f.y) * step(f.y, 0.8);
		float flick = 0.85 + 0.15 * sin(TIME * (1.0 + hash(id) * 3.0) + hash(id.yx) * 6.28);
		colour += window_colour.rgb * pane * step(hash(id), windows) * 0.9 * flick * lit;
		// A burning floor: a run of cells along one storey, flickering.
		vec2 run = vec2(floor(id.x / 5.0), id.y);
		float fire = step(hash(run + 17.0), burning);
		float lick = 0.6 + 0.4 * sin(TIME * 7.0 + id.x * 1.7) * sin(TIME * 3.1 + id.x * 0.9);
		colour += fire_colour.rgb * fire * (0.6 + 0.8 * (1.0 - f.y)) * lick * 1.6 * lit;
	}
	ALBEDO = mix(colour, haze.rgb, amount);
}
