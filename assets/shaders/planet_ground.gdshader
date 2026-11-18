shader_type spatial;
// A planet's ground (`PlanetGround`): one material for the open ground, the
// far horizon and the rocks scattered on it, so they always match. Four
// layers are picked by the surface itself, never painted: the base on level
// ground, rock on slopes, a cap on high ground (snow, ash, frost) and
// patches by a noise field (sand drifts, moss, salt crust, lava). Each layer
// is two colours mixed by large noise, with its own pattern: rock strata,
// wind ripples, cracks that may glow. Detail comes from two normal maps
// sampled biplanar at two scales, faded out with distance so far ground
// stays calm instead of shimmering. No UVs, no splat map, no per-world
// textures: a planet type is its numbers.

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 base_a : source_color = vec3(0.4, 0.33, 0.27);
uniform vec3 base_b : source_color = vec3(0.3, 0.25, 0.22);
uniform float base_rough = 0.92;
uniform vec3 rock_a : source_color = vec3(0.32, 0.29, 0.27);
uniform vec3 rock_b : source_color = vec3(0.2, 0.18, 0.17);
uniform float rock_rough = 0.8;
uniform vec3 cap_color : source_color = vec3(0.9, 0.92, 0.95);
uniform float cap_rough = 0.7;
uniform vec3 patch_a : source_color = vec3(0.6, 0.5, 0.35);
uniform vec3 patch_b : source_color = vec3(0.5, 0.42, 0.3);
uniform float patch_rough = 0.95;

// Where rock takes over, by the surface's up component.
uniform vec2 slope_range = vec2(0.82, 0.68);
// Where the cap starts and is full, in metres up.
uniform vec2 cap_range = vec2(1000.0, 1001.0);
// How much of the cap stays on slopes (0 only flats).
uniform float cap_on_slopes = 0.2;
// Share of the ground under patches, and how sharply they edge.
uniform float patch_amount = 0.0;
uniform float patch_edge = 0.06;
// Patches gather low: 0 anywhere, 1 only in hollows under `patch_low_at` metres.
uniform float patch_low = 0.0;
uniform float patch_low_at = 0.0;

// Rock strata: bands this many metres apart, this strong.
uniform float strata_every = 3.0;
uniform float strata = 0.35;
// Wind ripples in the base and patch layers.
uniform vec2 ripple_dir = vec2(1.0, 0.3);
uniform float ripple_every = 0.6;
uniform float ripples = 0.0;
// Cracks: lines in the base, glowing where `crack_glow` is lit.
uniform float cracks = 0.0;
uniform vec3 crack_glow : source_color = vec3(0.0);
uniform float crack_energy = 0.0;
// Glitter on the cap (snow, salt), and a wet sheen in the patches.
uniform float sparkle = 0.0;
uniform float patch_wet = 0.0;

uniform float detail_scale = 0.35;
uniform float detail_strength = 0.8;
uniform float detail_fade = 70.0;
uniform float saturation = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// Biplanar: the two dominant projections only, cheaper than triplanar.
vec3 bi_normal(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 an = abs(n);
	vec3 ty = texture(t, p.xz).xyz * 2.0 - 1.0;
	vec3 top = vec3(ty.x * s + n.x, abs(ty.z) * n.y, ty.y * s + n.z);
	vec3 side;
	if (an.x > an.z) {
		vec3 tx = texture(t, p.zy).xyz * 2.0 - 1.0;
		side = vec3(abs(tx.z) * n.x, tx.y * s + n.y, tx.x * s + n.z);
	} else {
		vec3 tz = texture(t, p.xy).xyz * 2.0 - 1.0;
		side = vec3(tz.x * s + n.x, tz.y * s + n.y, abs(tz.z) * n.z);
	}
	float wy = pow(an.y, 4.0);
	float ws = pow(max(an.x, an.z), 4.0);
	return normalize((top * wy + side * ws) / (wy + ws));
}

vec3 bi_albedo(sampler2D t, vec3 p, vec3 n) {
	vec3 an = abs(n);
	vec3 top = texture(t, p.xz).rgb;
	vec3 side = an.x > an.z ? texture(t, p.zy).rgb : texture(t, p.xy).rgb;
	float wy = pow(an.y, 4.0);
	float ws = pow(max(an.x, an.z), 4.0);
	return (top * wy + side * ws) / (wy + ws);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(detail_fade * 0.5, detail_fade, dist);

	float big = texture(noise_tex, wpos.xz * 0.0045).r;
	float mid = texture(noise_tex, wpos.xz * 0.021 + 0.37).r;
	float fine = texture(noise_tex, wpos.xz * 0.11 + wpos.y * 0.05).r;

	// Base: two colours over large noise, broken by finer.
	vec3 base = mix(base_a, base_b, smoothstep(0.3, 0.75, big * 0.7 + fine * 0.3));
	float rough = base_rough;
	if (ripples > 0.0) {
		vec2 rd = normalize(ripple_dir);
		float along = dot(wpos.xz, rd) + mid * 6.0;
		float r = sin(along / ripple_every * 6.2832);
		base *= 1.0 + r * 0.08 * ripples * near;
	}
	if (cracks > 0.0) {
		// Thin, branching lines on level ground, in some places only.
		float cn = texture(noise_tex, wpos.xz * 0.043 + 0.61).r;
		float width = 0.012 + 0.012 * smoothstep(0.6, 0.85, big);
		float c = 1.0 - smoothstep(0.0, width, abs(cn - 0.5));
		c *= smoothstep(0.5, 0.68, big + fine * 0.15) * smoothstep(0.85, 0.95, n.y) * cracks;
		base = mix(base, base * 0.25, c);
		EMISSION += crack_glow * crack_energy * c * smoothstep(0.62, 0.8, big);
	}

	// Patches gather where the noise (and, if asked, the hollows) say.
	vec3 col = base;
	float pmask = 0.0;
	if (patch_amount > 0.0) {
		float field = big * 0.55 + mid * 0.45;
		float lowness = patch_low > 0.0 ? smoothstep(patch_low_at + 3.0, patch_low_at - 2.0, wpos.y) : 1.0;
		pmask = smoothstep(1.0 - patch_amount, 1.0 - patch_amount + patch_edge, field) * mix(1.0, lowness, patch_low);
		vec3 pc = mix(patch_a, patch_b, fine);
		if (ripples > 0.0) {
			vec2 rd = normalize(ripple_dir);
			float r = sin((dot(wpos.xz, rd) + mid * 6.0) / (ripple_every * 1.6) * 6.2832);
			pc *= 1.0 + r * 0.1 * ripples * near;
		}
		col = mix(col, pc, pmask);
		rough = mix(rough, mix(patch_rough, 0.08, patch_wet), pmask);
		// A molten patch lights itself.
		EMISSION += crack_glow * crack_energy * pmask * 0.35 * step(0.001, crack_energy) * smoothstep(0.4, 0.8, fine);
	}

	// Rock on slopes, banded by strata.
	float rock = smoothstep(slope_range.x, slope_range.y, n.y + (fine - 0.5) * 0.08);
	// Layers of uneven thickness, gently warped, with thin dark seams.
	float layer = texture(noise_tex, vec2(wpos.y / strata_every * 0.061 + mid * 0.12, 0.71 + big * 0.05)).r;
	float seam = 1.0 - smoothstep(0.0, 0.035, abs(layer - 0.5));
	vec3 rc = mix(rock_a, rock_b, smoothstep(0.3, 0.7, layer * 0.7 + fine * 0.3));
	rc *= 1.0 - strata * 0.55 * seam;
	col = mix(col, rc, rock);
	rough = mix(rough, rock_rough, rock);

	// The cap on high ground.
	float cap = smoothstep(cap_range.x, cap_range.y, wpos.y + (mid - 0.5) * 6.0);
	cap *= mix(cap_on_slopes, 1.0, smoothstep(0.55, 0.8, n.y));
	col = mix(col, cap_color * mix(0.88, 1.0, fine), cap);
	rough = mix(rough, cap_rough, cap);

	// Fine colour from the detail texture, as a gentle multiply.
	vec3 det = bi_albedo(detail_albedo, wpos * detail_scale, n);
	float dl = dot(det, vec3(0.333));
	col *= mix(1.0, clamp(dl * 2.2, 0.6, 1.35), 0.55 * near);

	// Detail normals: the ground's own up close, rock's on the steep.
	vec3 nd = bi_normal(detail_normal, wpos * detail_scale, n, detail_strength * near);
	vec3 nr = bi_normal(rock_normal, wpos * detail_scale * 0.5, n, detail_strength * 1.2 * near);
	vec3 nrm = normalize(mix(nd, nr, rock));

	if (sparkle > 0.0) {
		vec3 v = normalize(CAMERA_POSITION_WORLD - wpos);
		float g = texture(noise_tex, wpos.xz * 2.7 + v.xz * 0.6).r;
		EMISSION += vec3(1.0) * smoothstep(0.86, 0.9, g) * sparkle * near * max(cap, 1.0 - rock) * 0.6;
	}

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(lum), col, saturation);
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
