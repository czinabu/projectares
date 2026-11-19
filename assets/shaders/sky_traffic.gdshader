shader_type spatial;
// The Concourse's air traffic (`worlds/plaza/megacity.gd`, view only): every
// craft is one MultiMesh instance flown round a lane by this shader alone,
// from the wall clock, so the CPU never moves one. INSTANCE_CUSTOM holds the
// lane: x its radius, y its height, z its speed in m/s (the sign is the way
// round), w where on the lane it starts (radians). A craft is a lit streak,
// head lamp white, tail lamp the instance colour; the haze is the
// megacity's.
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;

uniform vec4 head : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float glow = 5.0;
uniform vec4 haze : source_color = vec4(0.2, 0.15, 0.3, 1.0);
uniform float haze_reach = 900.0;
uniform float haze_max = 0.8;

varying float along;
varying vec3 tint;
// A monorail car (instance alpha under 1): lit windows down its side.
varying float car;
varying vec2 side_uv;
varying vec3 world_pos;

void vertex() {
	float radius = INSTANCE_CUSTOM.x;
	float height = INSTANCE_CUSTOM.y;
	float speed = INSTANCE_CUSTOM.z;
	float angle = INSTANCE_CUSTOM.w + TIME * speed / radius;
	vec3 centre = vec3(sin(angle) * radius, height, -cos(angle) * radius);
	vec3 forward = normalize(vec3(cos(angle), 0.0, sin(angle))) * sign(speed);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(forward, up));
	// The mesh is a box along local z, 1 long: z -0.5 is the tail, 0.5 the
	// head. The instance's scale is the craft's size; far off it is drawn a
	// little bigger, so a lane still reads as a stream of lights.
	along = VERTEX.z + 0.5;
	vec3 size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	size *= max(1.0, length(centre - CAMERA_POSITION_WORLD) / 450.0);
	tint = COLOR.rgb;
	car = step(COLOR.a, 0.9);
	side_uv = vec2(VERTEX.z + 0.5, VERTEX.y + 0.5);
	vec3 w = centre + right * VERTEX.x * size.x + up * VERTEX.y * size.y + forward * VERTEX.z * size.z;
	world_pos = w;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

void fragment() {
	// A dark hull with a lamp at each end: the tail lamp in the lane's
	// colour, the head lamp white.
	float tail_lamp = 1.0 - smoothstep(0.05, 0.25, along);
	float head_lamp = smoothstep(0.75, 0.95, along);
	vec3 col = vec3(0.04, 0.05, 0.08) + (tint * tail_lamp + head.rgb * head_lamp) * glow;
	if (car > 0.5) {
		float band = step(0.45, side_uv.y) * step(side_uv.y, 0.8);
		float pane = step(0.25, fract(side_uv.x * 9.0));
		col = vec3(0.06, 0.07, 0.1) + tint * band * pane * glow * 0.6;
	}
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float amount = (1.0 - exp(-dist / haze_reach)) * haze_max;
	ALBEDO = mix(col, haze.rgb, amount);
}
