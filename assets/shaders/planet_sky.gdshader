shader_type sky;
// A planet's sky, worked out rather than photographed (`PlanetSky`): a
// gradient from zenith to horizon, the sun's disc and glow, up to two
// bodies hung in the sky (a moon, a ringed giant), a cloud deck and stars.
// It keeps the uniforms `Look.apply_mood` writes (tint, energy, saturation,
// haze_color, haze_height), so a world's calm, war and storm moods grade it
// the way they grade the photographed sky. Nothing here reads TIME, so the
// radiance map is only redrawn when a uniform changes.

uniform vec3 zenith_color : source_color = vec3(0.2, 0.35, 0.65);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.75, 0.8);
// How quickly the horizon colour gives way to the zenith's, upward.
uniform float horizon_fall = 3.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform float saturation = 1.0;
uniform vec3 haze_color : source_color = vec3(0.5);
uniform float haze_height = 0.25;

uniform float sun_disc = 0.025;
uniform float sun_glow = 0.35;
uniform float sun_glow_width = 6.0;

// Body one: may wear bands and a ring.
uniform vec3 body1_dir = vec3(0.0, 0.3, -1.0);
uniform float body1_size = 0.0;
uniform vec3 body1_color : source_color = vec3(0.8, 0.7, 0.6);
uniform vec3 body1_band : source_color = vec3(0.6, 0.45, 0.35);
uniform float body1_bands = 0.0;
uniform vec3 body1_ring_axis = vec3(0.2, 1.0, 0.1);
uniform vec2 body1_ring = vec2(0.0);
uniform vec3 body1_ring_color : source_color = vec3(0.85, 0.8, 0.7);
uniform vec3 body1_glow : source_color = vec3(0.5, 0.6, 0.8);
// Body two: a plain moon.
uniform vec3 body2_dir = vec3(0.5, 0.4, -0.7);
uniform float body2_size = 0.0;
uniform vec3 body2_color : source_color = vec3(0.7, 0.7, 0.72);
// How much the bodies show through daylight (0 hides them behind a bright sky).
uniform float body_daylight = 0.6;

uniform sampler2D cloud_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.0;
uniform float cloud_scale = 0.35;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.45, 0.47, 0.52);
uniform vec2 cloud_offset = vec2(0.0);

uniform float stars = 0.0;

float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

vec3 frame_x(vec3 c) {
	vec3 up = abs(c.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	return normalize(cross(up, c));
}

// A lit sphere `size` radians across at `dir`; rgb and coverage.
vec4 body(vec3 d, vec3 dir, float size, vec3 col, vec3 band, float bands, vec3 glow, vec3 sun) {
	vec3 c = normalize(dir);
	float r = sin(size);
	vec3 tx = frame_x(c);
	vec3 ty = cross(c, tx);
	float facing = dot(d, c);
	vec2 p = vec2(dot(d, tx), dot(d, ty)) / max(r, 1e-4);
	float q = dot(p, p);
	vec4 out_c = vec4(0.0);
	if (facing > 0.0) {
		// A thin lit limb of atmosphere round the disc.
		float rim = smoothstep(1.12, 1.0, sqrt(q)) * step(1.0, q);
		out_c = vec4(glow * 0.6, rim * rim * 0.3);
		if (q < 1.0) {
			vec3 n = normalize(tx * p.x + ty * p.y - c * sqrt(1.0 - q));
			float lit = clamp(dot(n, sun) * 1.1 + 0.08, 0.0, 1.0);
			vec3 albedo = col;
			if (bands > 0.0) {
				float lat = p.y + 0.015 * sin(p.x * 5.0 + p.y * 11.0);
				float b = 0.5 + 0.5 * sin(lat * bands * 3.14159);
				b *= 0.75 + 0.25 * sin(lat * bands * 7.3 + 1.7);
				albedo = mix(col, band, b);
			}
			// Darker toward the limb, with the atmosphere's glow on the lit edge.
			float limb = sqrt(1.0 - q);
			vec3 shade = albedo * lit * mix(0.55, 1.0, limb) + glow * pow(1.0 - limb, 3.0) * lit * 0.8;
			out_c = vec4(shade + albedo * 0.02, smoothstep(1.0, 0.985, q));
		}
	}
	return out_c;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = normalize(LIGHT0_DIRECTION);
	float up = max(d.y, 0.0);
	vec3 c = mix(horizon_color, zenith_color, 1.0 - exp(-up * horizon_fall));
	float sky_lum = dot(c, vec3(0.299, 0.587, 0.114));

	// Stars where the sky is dark.
	if (stars > 0.0 && d.y > 0.0) {
		vec3 cell = floor(d * 260.0);
		float h = hash31(cell);
		float twinkle = step(0.9965, h) * (h - 0.9965) / 0.0035;
		c += vec3(0.9, 0.95, 1.0) * twinkle * stars * clamp(1.0 - sky_lum * 3.0, 0.0, 1.0) * 2.0;
	}

	float through = mix(1.0, body_daylight, clamp(sky_lum * 1.6, 0.0, 1.0));
	// The ringed body: ring behind, the disc, ring in front.
	if (body1_size > 0.0) {
		vec3 bc = normalize(body1_dir);
		float r = sin(body1_size);
		vec3 axis = normalize(body1_ring_axis);
		float t_ring = dot(bc, axis) / dot(d, axis);
		float ring_a = 0.0;
		vec3 ring_c = vec3(0.0);
		if (body1_ring.y > 0.0 && t_ring > 0.0) {
			float rr = length(d * t_ring - bc) / r;
			if (rr > body1_ring.x && rr < body1_ring.y) {
				float k = (rr - body1_ring.x) / (body1_ring.y - body1_ring.x);
				float lanes = 0.55 + 0.45 * sin(k * 60.0) * sin(k * 17.0 + 1.0);
				lanes *= smoothstep(0.0, 0.08, k) * smoothstep(1.0, 0.85, k);
				lanes *= 1.0 - 0.85 * smoothstep(0.62, 0.64, k) * smoothstep(0.69, 0.67, k);
				ring_a = clamp(lanes, 0.0, 1.0) * 0.85;
				ring_c = body1_ring_color * (0.35 + 0.75 * max(dot(sun, axis) * sign(dot(d, axis)) * 0.5 + 0.6, 0.0));
			}
		}
		// Where the ray meets the sphere (unit distance to its centre).
		float b = dot(d, bc);
		float disc2 = b * b - (1.0 - r * r);
		float t_sphere = disc2 > 0.0 ? b - sqrt(disc2) : 1e6;
		vec4 p = body(d, body1_dir, body1_size, body1_color, body1_band, body1_bands, body1_glow, sun);
		bool ring_front = t_ring < t_sphere;
		if (!ring_front) {
			c = mix(c, ring_c, ring_a * through);
		}
		c = mix(c, p.rgb, p.a * through);
		if (ring_front) {
			c = mix(c, ring_c, ring_a * through);
		}
	}
	if (body2_size > 0.0) {
		vec4 m = body(d, body2_dir, body2_size, body2_color, body2_color, 0.0, vec3(0.6), sun);
		// Craters, roughly.
		vec3 bc = normalize(body2_dir);
		float spots = texture(cloud_noise, vec2(dot(d, frame_x(bc)), d.y) * 9.0).r;
		m.rgb *= mix(0.75, 1.1, smoothstep(0.35, 0.65, spots));
		c = mix(c, m.rgb, m.a * through);
	}

	// The sun's disc and glow (the glow tinted by the sun's own light).
	float cs = dot(d, sun);
	float ang = acos(clamp(cs, -1.0, 1.0));
	vec3 sun_col = LIGHT0_COLOR;
	c += sun_col * sun_glow * exp(-ang * sun_glow_width) * 0.6;
	c += sun_col * sun_glow * 0.25 * exp(-ang * sun_glow_width * 0.25);
	if (!AT_CUBEMAP_PASS) {
		c += sun_col * smoothstep(sun_disc, sun_disc * 0.7, ang) * 6.0;
	}

	// The cloud deck: a plane overhead, thinning toward the horizon.
	if (cloud_cover > 0.0 && d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12) * cloud_scale + cloud_offset;
		float n = texture(cloud_noise, uv * 0.11).r * 0.65 + texture(cloud_noise, uv * 0.37 + 3.1).r * 0.35;
		float cover = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.25, n);
		cover *= smoothstep(0.0, 0.18, d.y);
		float thick = smoothstep(1.0 - cloud_cover, 1.05, n);
		float lit = 0.55 + 0.45 * max(dot(normalize(vec3(sun.x, 0.0, sun.z) + vec3(0.0, 0.3, 0.0)), normalize(vec3(d.x, 0.15, d.z))), 0.0);
		vec3 cc = mix(cloud_color * lit, cloud_shade, thick * 0.7);
		// Edges catch the sun.
		cc += sun_col * 0.25 * (1.0 - thick) * exp(-ang * 2.0);
		c = mix(c, cc, cover * 0.92);
	}

	c = c / (1.0 + c * 0.08);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * tint * energy;
	float h = 1.0 - smoothstep(0.0, haze_height, d.y);
	c = mix(c, haze_color, min(h * h * 0.92 + step(d.y, 0.0), 1.0));
	COLOR = c;
}
