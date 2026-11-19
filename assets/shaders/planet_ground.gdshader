shader_type spatial;
// A planet's ground (`PlanetGround`): one material for the open ground, the
// far horizon and the rocks scattered on it, so they always match. Four
// layers are picked by the surface itself, never painted: the base on level
// ground, rock on slopes, a cap on high ground (snow, ash, frost) and
// patches by a noise field (sand drifts, moss, salt crust, lava). Each layer
// is two colours mixed by large noise, with its own pattern: rock strata,
// wind ripples, cracks that may glow. Each layer may also wear a scanned
// surface (`PlanetType.surfaces`, CC0 sets in assets/textures): its colour
// map is used only for its detail, relative to its own average (the
// smallest mip), so the planet's colours still decide the hue, and its
// normal map for the relief. Both are sampled biplanar (no UVs), at a
// second, coarser scale far off so the tiling never shows, and the relief
// fades with distance so far ground stays calm instead of shimmering. A
// layer is sampled only where it shows. No splat map, no per-world art: a
// planet type is its numbers and its four surfaces.

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cap_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cap_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D patch_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D patch_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Which layers wear a surface (1) and which are colour only (0: lava, water).
uniform vec4 textured = vec4(0.0);
// Each layer's surface tile, in metres.
uniform vec4 tile = vec4(3.0, 6.0, 4.0, 3.0);
// How much of the scan's own colour variation shows (0 its brightness only).
uniform float photo_chroma = 0.45;
// How strongly the scan's detail marks the colour.
uniform float photo_detail = 0.85;

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
// A band of the base's growth along a patch's edge (a marsh's moss banks):
// how strong, how wide (in the patch field's units) and its colour.
uniform float bank = 0.0;
uniform float bank_width = 0.1;
uniform float bank_rise = 2.5;
uniform vec3 bank_color : source_color = vec3(0.3, 0.4, 0.15);
// Rock far off (the horizon's mountains) takes its scan again at
// `vast_tile` times its tile, so cliffs a kilometre away keep their faces
// instead of going smooth. It fades in from `vast_from` metres, and only
// where the ground already leans.
uniform float vast_from = 350.0;
uniform float vast_tile = 45.0;
uniform float vast_relief = 1.6;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// A normal map texel as a tangent-space normal. The map may be stored as
// two channels (RGTC), so z is rebuilt from x and y.
vec3 unpack(vec4 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// Biplanar: the two dominant projections only, cheaper than triplanar.
vec3 bi_normal(sampler2D t, vec3 p, vec3 n, float s) {
	vec3 an = abs(n);
	vec3 ty = unpack(texture(t, p.xz));
	vec3 top = vec3(ty.x * s + n.x, ty.z * n.y, ty.y * s + n.z);
	vec3 side;
	if (an.x > an.z) {
		vec3 tx = unpack(texture(t, p.zy));
		side = vec3(tx.z * n.x, tx.y * s + n.y, tx.x * s + n.z);
	} else {
		vec3 tz = unpack(texture(t, p.xy));
		side = vec3(tz.x * s + n.x, tz.y * s + n.y, tz.z * n.z);
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

// A surface's detail as a multiplier round 1: the scan against its own
// average, at the tile near and a coarser tile far, mostly its brightness.
vec3 scan_detail(sampler2D t, vec3 p, vec3 n, float tile_m, float far) {
	vec3 avg = max(textureLod(t, vec2(0.5), 12.0).rgb, vec3(0.04));
	vec3 near_s = bi_albedo(t, p / tile_m, n);
	vec3 far_s = bi_albedo(t, p / (tile_m * 4.7) + 0.31, n);
	vec3 rel = mix(near_s, far_s, far) / avg;
	float lum = dot(rel, vec3(0.299, 0.587, 0.114));
	rel = mix(vec3(lum), rel, photo_chroma);
	return clamp(mix(vec3(1.0), rel, photo_detail), 0.25, 2.2);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(detail_fade * 0.5, detail_fade, dist);
	float far = smoothstep(detail_fade * 0.25, detail_fade * 1.5, dist);

	float big = texture(noise_tex, wpos.xz * 0.0045).r;
	float mid = texture(noise_tex, wpos.xz * 0.021 + 0.37).r;
	float fine = texture(noise_tex, wpos.xz * 0.11 + wpos.y * 0.05).r;

	// Base: two colours over large noise, broken by finer.
	vec3 base = mix(base_a, base_b, smoothstep(0.3, 0.75, big * 0.7 + fine * 0.3));
	if (ripples > 0.0) {
		vec2 rd = normalize(ripple_dir);
		float along = dot(wpos.xz, rd) + mid * 6.0;
		float r = sin(along / ripple_every * 6.2832);
		base *= 1.0 + r * 0.08 * ripples * near;
	}
	float crack = 0.0;
	if (cracks > 0.0) {
		// Thin, branching lines on level ground, in some places only.
		float cn = texture(noise_tex, wpos.xz * 0.043 + 0.61).r;
		float width = 0.012 + 0.012 * smoothstep(0.6, 0.85, big);
		crack = 1.0 - smoothstep(0.0, width, abs(cn - 0.5));
		crack *= smoothstep(0.5, 0.68, big + fine * 0.15) * smoothstep(0.85, 0.95, n.y) * cracks;
		base = mix(base, base * 0.25, crack);
	}

	// Patches gather where the noise (and, if asked, the hollows) say.
	float pmask = 0.0;
	vec3 pc = vec3(0.0);
	if (patch_amount > 0.0) {
		float field = big * 0.55 + mid * 0.45;
		float lowness = patch_low > 0.0 ? smoothstep(patch_low_at + 3.0, patch_low_at - 2.0, wpos.y) : 1.0;
		float lift = 1.0 - patch_amount;
		pmask = smoothstep(lift, lift + patch_edge, field) * mix(1.0, lowness, patch_low);
		if (bank > 0.0) {
			float wide = patch_low > 0.0 ? smoothstep(patch_low_at + 3.0 + bank_rise, patch_low_at - 2.0, wpos.y) : 1.0;
			float band = smoothstep(lift - bank_width, lift, field) * mix(1.0, wide, patch_low);
			band = clamp(band - pmask, 0.0, 1.0);
			base = mix(base, bank_color * mix(0.85, 1.1, fine), band * bank);
		}
		pc = mix(patch_a, patch_b, fine);
		if (ripples > 0.0) {
			vec2 rd = normalize(ripple_dir);
			float r = sin((dot(wpos.xz, rd) + mid * 6.0) / (ripple_every * 1.6) * 6.2832);
			pc *= 1.0 + r * 0.1 * ripples * near;
		}
	}

	// Far off, the rock's coarse relief breaks up the slope test too, so
	// snow and scree lie on ledges of a far cliff, not in smooth blobs.
	float vast = textured.y > 0.5 ? smoothstep(vast_from * 0.6, vast_from, dist) : 0.0;
	float vt = tile.y * vast_tile;
	vec3 vn = vast > 0.001 ? bi_normal(rock_normal, wpos / vt, n, vast_relief) : n;
	// Only ground that already leans takes the coarse relief into its slope
	// test, so a far flat (a salt pan, a lake bed) never turns to rock.
	float lean = smoothstep(0.995, 0.93, n.y);
	vec3 sn = normalize(mix(n, vn, vast * lean));
	// Rock on slopes, banded by strata.
	float rock = smoothstep(slope_range.x, slope_range.y, sn.y + (fine - 0.5) * 0.08);
	// Layers of uneven thickness, gently warped, with thin dark seams.
	float layer = texture(noise_tex, vec2(wpos.y / strata_every * 0.061 + mid * 0.12, 0.71 + big * 0.05)).r;
	float seam = 1.0 - smoothstep(0.0, 0.035, abs(layer - 0.5));
	vec3 rc = mix(rock_a, rock_b, smoothstep(0.3, 0.7, layer * 0.7 + fine * 0.3));
	rc *= 1.0 - strata * 0.55 * seam;

	// The cap on high ground.
	float cap = smoothstep(cap_range.x, cap_range.y, wpos.y + (mid - 0.5) * 6.0);
	cap *= mix(cap_on_slopes, 1.0, smoothstep(0.55, 0.8, sn.y));
	vec3 cc = cap_color * mix(0.88, 1.0, fine);

	// How much each layer shows, in the order they cover one another.
	float w_cap = cap;
	float w_rock = rock * (1.0 - cap);
	float w_patch = pmask * (1.0 - rock) * (1.0 - cap);
	float w_base = (1.0 - pmask) * (1.0 - rock) * (1.0 - cap);

	// Each layer's scan, sampled only where the layer shows.
	float s = detail_strength * near;
	vec3 nrm = n * 0.0001;
	if (w_base > 0.003) {
		if (textured.x > 0.5) {
			base *= scan_detail(base_albedo, wpos, n, tile.x, far);
			nrm += bi_normal(base_normal, wpos / tile.x, n, s) * w_base;
		} else {
			nrm += n * w_base;
		}
	}
	if (w_rock > 0.003) {
		if (textured.y > 0.5) {
			vec3 rd = vast < 0.999 ? scan_detail(rock_albedo, wpos, n, tile.y, far) : vec3(1.0);
			vec3 rn = vast < 0.999 ? bi_normal(rock_normal, wpos / tile.y, n, s * 1.2) : n;
			if (vast > 0.001) {
				vec3 vd = scan_detail(rock_albedo, wpos, n, vt, 0.0);
				rd = mix(rd, vd * vd, vast);
				rn = normalize(mix(rn, vn, vast));
			}
			rc *= rd;
			nrm += rn * w_rock;
		} else {
			nrm += n * w_rock;
		}
	}
	if (w_cap > 0.003) {
		if (textured.z > 0.5) {
			cc *= scan_detail(cap_albedo, wpos, n, tile.z, far);
			nrm += bi_normal(cap_normal, wpos / tile.z, n, s) * w_cap;
		} else {
			nrm += n * w_cap;
		}
	}
	if (w_patch > 0.003) {
		if (textured.w > 0.5) {
			pc *= scan_detail(patch_albedo, wpos, n, tile.w, far);
			nrm += bi_normal(patch_normal, wpos / tile.w, n, s) * w_patch;
		} else {
			nrm += n * w_patch;
		}
	}
	nrm = normalize(nrm);

	vec3 col = base * w_base + pc * w_patch + rc * w_rock + cc * w_cap;
	float rough = base_rough * w_base + mix(patch_rough, 0.08, patch_wet) * w_patch
		+ rock_rough * w_rock + cap_rough * w_cap;
	EMISSION += crack_glow * crack_energy * crack * smoothstep(0.62, 0.8, big) * w_base;
	// A molten patch lights itself.
	EMISSION += crack_glow * crack_energy * w_patch * 0.35 * step(0.001, crack_energy) * smoothstep(0.4, 0.8, fine);

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
