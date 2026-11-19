shader_type spatial;
// A great lit sign on a megacity tower (`worlds/plaza/megacity.gd`, view
// only): a tall banner of light with no words, blocks and bars of colour
// that scroll slowly down it and flicker now and then, framed by a bright
// edge. Hazed like the towers it hangs on.
render_mode unshaded, fog_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.25, 0.9, 1.0, 1.0);
uniform float glow = 2.2;
uniform float seed = 0.0;
uniform vec4 haze : source_color = vec4(0.2, 0.15, 0.3, 1.0);
uniform float haze_reach = 700.0;
uniform float haze_max = 0.9;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.05 + seed;
	// Rows of blocks scrolling down, each row its own brightness.
	float row = floor((uv.y + t) * 14.0);
	float col = floor(uv.x * 4.0);
	float block = hash(vec2(row, col) + seed);
	float bright = 0.25 + 0.75 * step(0.45, block);
	float bars = 0.75 + 0.25 * sin((uv.y + t * 3.0) * 180.0);
	float edge = step(uv.x, 0.04) + step(0.96, uv.x) + step(uv.y, 0.02) + step(0.98, uv.y);
	float flicker = 0.85 + 0.15 * step(0.5, fract(sin(floor(TIME * 3.0 + seed) * 12.9898) * 43758.5453));
	vec3 c = color.rgb * glow * (bright * bars * flicker * 0.8 + clamp(edge, 0.0, 1.0) * 1.2);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float amount = (1.0 - exp(-dist / haze_reach)) * haze_max;
	ALBEDO = mix(c, haze.rgb, amount);
}
