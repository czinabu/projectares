shader_type spatial;
// The Concourse's megacity (`worlds/plaza/megacity.gd`, view only): dark
// glass towers lit floor by floor with windows worked out from the world
// position, so a tower a kilometre tall needs no more than its boxes.
// Every vertical face is cut into bays `bay` wide and floors `storey` tall;
// a hash of the cell says whether it is lit and in which colour. Where a
// window drops under about a pixel it is drawn as the face's average glow
// instead, so a far tower never shimmers. Every `band_every` floors a lit
// band runs round in the accent colour. The haze is done here, not by the
// fog (which would swallow towers a kilometre out): it thickens with
// distance up to `haze_max`, and more toward the canyon floor, where it
// takes the warm glow of the streets below.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec4 facade : source_color = vec4(0.05, 0.06, 0.1, 1.0);
uniform vec4 facade_top : source_color = vec4(0.11, 0.13, 0.22, 1.0);
uniform vec4 warm : source_color = vec4(1.0, 0.78, 0.5, 1.0);
uniform vec4 cool : source_color = vec4(0.55, 0.85, 1.0, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.35, 0.85, 1.0);
uniform vec4 haze : source_color = vec4(0.33, 0.37, 0.62, 1.0);
uniform vec4 haze_low : source_color = vec4(0.42, 0.3, 0.36, 1.0);
uniform float bay = 2.4;
uniform float storey = 3.6;
uniform float lit_share = 0.3;
uniform float window_glow = 1.6;
uniform float band_every = 24.0;
uniform float band_glow = 2.2;
// Distance at which the haze has taken about two thirds of a colour.
uniform float haze_reach = 900.0;
uniform float haze_max = 0.9;
// Heights (world y) over which the low haze thins out.
uniform float low_from = -320.0;
uniform float low_to = 60.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 col;
	if (abs(n.y) > 0.5) {
		// Roofs and the undersides of setbacks: plain, a touch lighter on top.
		col = n.y > 0.0 ? facade_top.rgb : facade.rgb * 0.6;
	} else {
		vec2 side = normalize(vec2(-n.z, n.x));
		float u = dot(world_pos.xz, side) / bay;
		float v = world_pos.y / storey;
		vec2 cell = floor(vec2(u, v));
		vec2 f = fract(vec2(u, v));
		// Each face of each tower gets its own pattern: blocks of floors lit
		// together, the way a tower's offices and flats are.
		float face_id = floor(dot(world_pos.xz, vec2(n.x, n.z)) * 0.5);
		float tower = hash(vec2(face_id * 0.031, 1.7));
		// Floors lit in runs along the face, the way offices and flats
		// are, in blocks of floors that are busier or quieter.
		float run = floor(cell.x / (2.0 + floor(hash(vec2(cell.y, face_id)) * 5.0)));
		float block = hash(vec2(face_id, floor(cell.y / 7.0)));
		float share = lit_share * (0.3 + 1.1 * block);
		float r = hash(vec2(run, cell.y) + face_id * 0.013);
		float lit = step(r, share);
		float tint_pick = hash(vec2(run, cell.y) + 7.1);
		vec3 tint = tint_pick < 0.62 ? warm.rgb : (tint_pick < 0.93 ? cool.rgb : accent.rgb);
		float dim = 0.55 + 0.45 * hash(vec2(run, cell.y) + 3.3);
		// The pane inside its cell: mullions between bays, a spandrel between floors.
		vec2 px = fwidth(vec2(u, v));
		float pane_x = smoothstep(0.12 - px.x, 0.12 + px.x, f.x) * (1.0 - smoothstep(0.88 - px.x, 0.88 + px.x, f.x));
		float pane_y = smoothstep(0.22 - px.y, 0.22 + px.y, f.y) * (1.0 - smoothstep(0.9 - px.y, 0.9 + px.y, f.y));
		float pane = pane_x * pane_y;
		vec3 near_glow = tint * lit * dim * pane;
		// The average of all that, for windows too small to see one by one.
		vec3 average = mix(warm.rgb, cool.rgb, 0.3) * lit_share * 0.55 * 0.6;
		float small = smoothstep(0.35, 0.9, max(px.x, px.y));
		vec3 glow = mix(near_glow, average, small) * window_glow;
		// The lit band every so many floors.
		float band_v = mod(cell.y + floor(tower * band_every), band_every);
		float band = step(band_v, 0.5) * (1.0 - small * 0.5);
		glow = mix(glow, accent.rgb * band_glow, band * pane_y);
		// The glass catches a little of the sky higher up.
		float sheen = 0.5 + 0.5 * smoothstep(-100.0, 600.0, world_pos.y);
		// Dark panes still catch the sky, so an unlit floor reads as glass.
		vec3 glass = mix(facade.rgb, haze.rgb, 0.35) * pane * (1.0 - lit) * (1.0 - small);
		col = facade.rgb * sheen + glass + glow;
	}
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float low = 1.0 - smoothstep(low_from, low_to, world_pos.y);
	float amount = (1.0 - exp(-dist / haze_reach)) * haze_max;
	amount = clamp(amount + low * 0.35 * smoothstep(80.0, 600.0, dist), 0.0, 0.97);
	vec3 air = mix(haze.rgb, haze_low.rgb, low);
	ALBEDO = mix(col, air, amount);
}
