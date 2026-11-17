shader_type spatial;
// World surfaces: triplanar PBR textures in world space, so a box of any size
// tiles correctly without UVs. Optional layers, all driven by uniforms:
// a second texture blended in by noise, puddles, snow on upward faces, grime
// near the ground, and a window grid for boxes that set `box_size`.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D blend_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D blend_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tex_scale = 0.25;
uniform float rough_mult = 1.0;
uniform float metal = 0.0;
uniform float normal_strength = 1.0;
uniform float blend_amount = 0.0;
uniform float wetness = 0.0;
uniform float snow = 0.0;
uniform float snow_patchy = 0.0;
uniform float saturation = 0.8;
uniform float grime = 0.4;
uniform vec3 window_glow : source_color = vec3(1.0, 0.62, 0.3);
uniform float window_lit_chance = 0.05;
// Set per mesh. Zero height means "not a building": no windows.
instance uniform vec3 box_size = vec3(0.0);
instance uniform float seed = 0.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	lpos = VERTEX;
	lnrm = NORMAL;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

float tri_rough(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy).r * w.x + texture(t, p.xz).r * w.y + texture(t, p.xy).r * w.z;
}

vec3 tri_normal(sampler2D t, vec3 p, vec3 n, vec3 w, float strength) {
	vec3 tx = texture(t, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(t, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(t, p.xy).xyz * 2.0 - 1.0;
	tx.xy *= strength;
	ty.xy *= strength;
	tz.xy *= strength;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * tex_scale;

	vec3 albedo = tri(albedo_tex, p, w).rgb;
	float rough = tri_rough(rough_tex, p, w) * rough_mult;
	vec3 nrm = tri_normal(normal_tex, p, n, w, normal_strength);
	float metallic = metal;

	float big = texture(noise_tex, wpos.xz * 0.013 + wpos.y * 0.02).r;
	float mid = texture(noise_tex, wpos.xz * 0.06 + wpos.y * 0.11).r;

	if (blend_amount > 0.0) {
		float b = smoothstep(0.45, 0.62, big * 0.7 + mid * 0.3 + (blend_amount - 0.5));
		vec3 p2 = wpos * tex_scale * 1.37;
		albedo = mix(albedo, tri(blend_albedo_tex, p2, w).rgb, b);
		nrm = normalize(mix(nrm, tri_normal(blend_normal_tex, p2, n, w, normal_strength), b));
		rough = mix(rough, 0.95, b);
	}
	albedo = mix(vec3(dot(albedo, vec3(0.299, 0.587, 0.114))), albedo, saturation) * tint;
	// Large-scale variation so big surfaces do not look tiled.
	albedo *= mix(0.72, 1.12, big);

	// Dirt climbing up from the ground on walls, and streaks under ledges.
	float wall = 1.0 - abs(n.y);
	float low = exp(-max(wpos.y, 0.0) * 0.55);
	float streak = smoothstep(0.55, 0.8, texture(noise_tex, vec2(wpos.x + wpos.z, 0.0) * 0.21 + vec2(0.0, wpos.y * 0.012)).r);
	float g = grime * wall * clamp(low * 0.8 + streak * 0.45, 0.0, 1.0);
	albedo = mix(albedo, albedo * vec3(0.32, 0.29, 0.27), g);
	rough = mix(rough, 1.0, g * 0.6);

	if (wetness > 0.0) {
		float puddle = smoothstep(0.7, 0.76, mid * 0.5 + big * 0.5 + wetness * 0.25) * smoothstep(0.9, 0.99, n.y);
		albedo = mix(albedo, albedo * 0.5, puddle);
		rough = mix(rough, 0.04, puddle);
		nrm = normalize(mix(nrm, n, puddle));
	}

	vec3 emission = vec3(0.0);
	if (box_size.y > 0.0 && abs(lnrm.y) < 0.5) {
		bool along_z = abs(lnrm.x) > 0.5;
		float u = along_z ? lpos.z : lpos.x;
		float face_w = along_z ? box_size.z : box_size.x;
		float y0 = lpos.y + box_size.y * 0.5;
		float cell_w = 2.3;
		float floor_h = 3.0;
		float cols = max(1.0, floor((face_w - 0.8) / cell_w));
		float uu = (u + cols * cell_w * 0.5) / cell_w;
		float vv = y0 / floor_h;
		float first = box_size.y < 5.0 ? 0.0 : 1.0;
		if (uu > 0.0 && uu < cols && vv >= first && y0 < box_size.y - 0.5) {
			vec2 cell = floor(vec2(uu, vv));
			vec2 f = fract(vec2(uu, vv));
			float face = dot(lnrm, vec3(1.0, 0.0, 3.0));
			float h = hash21(cell + vec2(seed * 17.3 + face * 5.1, seed * 3.7));
			vec2 d = min(f - vec2(0.2, 0.28), vec2(0.8, 0.8) - f);
			float inside = step(0.0, min(d.x, d.y));
			float frame = inside * (1.0 - smoothstep(0.0, 0.035, min(d.x, d.y)));
			float sill = step(0.0, min(f.x - 0.15, 0.85 - f.x)) * step(0.22, f.y) * step(f.y, 0.28);
			if (inside > 0.5) {
				if (h < 0.3) {
					// Blown out: a dark hole.
					albedo = vec3(0.012);
					rough = 1.0;
					metallic = 0.0;
				} else {
					albedo = vec3(0.03, 0.04, 0.05) * mix(0.6, 1.4, mid);
					rough = 0.07 + 0.25 * step(h, 0.55);
					metallic = 0.85;
					if (h > 1.0 - window_lit_chance) {
						float flicker = 0.7 + 0.3 * hash21(cell * 7.1 + seed);
						emission = window_glow * flicker * (0.6 + 0.8 * f.y);
						metallic = 0.0;
					}
				}
				nrm = n;
				albedo = mix(albedo, vec3(0.05), frame);
				rough = mix(rough, 0.6, frame);
			}
			albedo = mix(albedo, albedo * 0.55, sill);
		}
	}

	if (snow > 0.0) {
		float s = snow * smoothstep(0.45, 0.72, n.y + (mid - 0.5) * 0.35);
		s = mix(s, s * smoothstep(0.32, 0.5, big * 0.75 + mid * 0.25), snow_patchy);
		// A little frost on walls too.
		s = max(s, snow * 0.35 * smoothstep(0.5, 0.8, big) * wall);
		albedo = mix(albedo, vec3(0.83, 0.87, 0.92) * mix(0.85, 1.0, mid), s);
		rough = mix(rough, 0.78, s);
		metallic = mix(metallic, 0.0, s);
		nrm = normalize(mix(nrm, n + (nrm - n) * 0.5, s));
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	EMISSION = emission * 1.3;
}
