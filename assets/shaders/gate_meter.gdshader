shader_type spatial;
// A tall panel beside a deploy gate (`GateLook.meter`): a stack of lit slats,
// one for each place in the world the gate leads to, lit as far up as it is
// full (`filled`, a share), breathing gently. A band of light runs up it when
// someone steps into the gate (`pulse`, 0 to 1 on its way up, below 0 for
// none). On a sealed gate (`idle`) a dim scan crawls up it instead.
// On a BoxMesh's or a QuadMesh's front, read from the vertex's height.
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.6, 0.3);
uniform float height = 11.0;
uniform float width = 3.0;
// How many slats it has.
uniform float slats = 20.0;
// 0 for a bare strip of light (a fin's trim), 1 for slats.
uniform float slatted = 1.0;
instance uniform float filled = 0.0;
instance uniform float pulse = -1.0;
instance uniform float idle = 0.0;

varying vec2 v_at;

void vertex() {
	v_at = VERTEX.xy;
}

void fragment() {
	float up = clamp(v_at.y / height + 0.5, 0.0, 1.0);
	float across = v_at.x / width + 0.5;
	float row = floor(up * slats);
	float inside = fract(up * slats);
	float slat = mix(1.0, step(0.2, inside) * step(inside, 0.8) * step(0.14, across) * step(across, 0.86), slatted);
	float lit = step(row + 0.5, filled * slats);
	float breathe = 0.85 + 0.15 * sin(TIME * 1.6 - row * 0.35);
	vec3 col = vec3(0.02, 0.018, 0.03);
	col += color * slat * mix(0.09, 1.4 * breathe, lit);
	// A frame round the slats.
	float frame = slatted * (1.0 - step(0.04, across) * step(across, 0.96) * step(0.01, up) * step(up, 0.99));
	col += color * frame * 0.5;
	if (pulse >= 0.0) {
		float band = exp(-pow((up - pulse) * 7.0, 2.0)) * (1.0 - pulse * 0.4);
		col += color * band * (0.6 + slat * 2.2);
	}
	if (idle > 0.0) {
		float scan = exp(-pow((up - fract(TIME * 0.07)) * 9.0, 2.0));
		col = vec3(0.02, 0.018, 0.03) + color * slat * (0.05 + scan * 0.35) + color * frame * 0.2;
	}
	ALBEDO = col;
}
