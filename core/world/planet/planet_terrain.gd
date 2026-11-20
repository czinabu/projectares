class_name PlanetTerrain
extends RefCounted
## A planet type's ground as a height function (DESIGN.md "Planet kit"):
## the same recipe answers for the playfield a map builds its `Terrain` from
## and for the far horizon ring round it, so the mountains you see are the
## mountains of that ground, only further off.
##
## Plain data in, a height out: `height_at(x, z)` touches no node and keeps
## its own noise, so a map can call it from `WorldDef.prepare_map` on a
## worker thread. A map stamps its own layout (roads, pads, craters it plays
## around) on top, as Ashfront and Frostline do today; the recipe is only
## the planet's character.
##
## Recipe keys, all optional (a missing one adds nothing):
##   base_amp, base_freq, octaves: rolling ground (metres, 1/m)
##   warp: domain warp in metres, which turns blobby noise into flowing land
##   ridge_amp, ridge_freq, ridge_cover: ridged mountains and where they rise
##     inside the field (0 none, 1 everywhere); outside the field they always do
##   dune_amp, dune_len, dune_dir (degrees), dune_cover: wind-built dunes,
##     steep on the lee side; dune_slip: the share of each dune its lee
##     (slip) face takes (0.22 unless set; more is a gentler face)
##   terrace: metres per step, terrace_sharp: 0 smooth to 1 sheer (mesas),
##     terrace_field: how much of the stepping happens inside the field (0
##     none, 1 all, the default); outside the field it always does
##   floor, floor_soft: low ground filled flat to this height (salt pans, lakes)
##   field: half the width of the play area (metres), field_calm: how much of
##     the relief survives inside it (0 flat, 1 all), rim, rim_ramp: the
##     rising ground past it
##   craters, crater_radius (Vector2), crater_depth

var recipe: Dictionary
var _base := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _mask := FastNoiseLite.new()
var _warp_a := FastNoiseLite.new()
var _warp_b := FastNoiseLite.new()
var _craters: Array[Vector4] = []


func _init(p_recipe: Dictionary, seed_value: int) -> void:
	recipe = p_recipe
	_base.seed = seed_value
	_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_base.frequency = float(recipe.get("base_freq", 0.006))
	_base.fractal_octaves = int(recipe.get("octaves", 4))
	_ridge.seed = seed_value + 1
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = float(recipe.get("ridge_freq", 0.004))
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 5
	_ridge.fractal_gain = 0.5
	_mask.seed = seed_value + 2
	_mask.frequency = 0.0022
	for warp: FastNoiseLite in [_warp_a, _warp_b]:
		warp.seed = seed_value + (3 if warp == _warp_a else 4)
		warp.frequency = 0.004
		warp.fractal_octaves = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5
	var field := float(recipe.get("field", 300.0))
	var radius: Vector2 = recipe.get("crater_radius", Vector2(6.0, 18.0))
	for i in int(recipe.get("craters", 0)):
		_craters.append(Vector4(rng.randf_range(-field, field), rng.randf_range(-field, field),
				rng.randf_range(radius.x, radius.y), float(recipe.get("crater_depth", 3.0)) * rng.randf_range(0.6, 1.2)))


## The planet's ground at (x, z). Thread safe.
func height_at(x: float, z: float) -> float:
	var r := recipe
	var p := Vector2(x, z)
	var warp := float(r.get("warp", 0.0))
	if warp > 0.0:
		p += Vector2(_warp_a.get_noise_2d(x, z), _warp_b.get_noise_2d(x, z)) * warp
	var field := float(r.get("field", 300.0))
	var out := smoothstep(field, field + float(r.get("rim_ramp", 120.0)), maxf(absf(x), absf(z)))
	var calm := lerpf(float(r.get("field_calm", 1.0)), 1.0, out)
	var h := _base.get_noise_2d(p.x, p.y) * float(r.get("base_amp", 0.0)) * calm
	var ridge_amp := float(r.get("ridge_amp", 0.0))
	if ridge_amp > 0.0:
		var ridged := (_ridge.get_noise_2d(p.x, p.y) + 1.0) * 0.5
		var cover := float(r.get("ridge_cover", 0.0))
		var where := smoothstep(1.0 - cover, 1.0 - cover + 0.35, (_mask.get_noise_2d(x, z) + 1.0) * 0.5)
		h += ridged * ridged * ridge_amp * maxf(where * calm, out)
	var dune_amp := float(r.get("dune_amp", 0.0))
	if dune_amp > 0.0:
		var dir := deg_to_rad(float(r.get("dune_dir", 0.0)))
		var along := p.dot(Vector2(cos(dir), sin(dir))) / float(r.get("dune_len", 60.0))
		along += _mask.get_noise_2d(x * 1.7, z * 1.7) * 1.4
		var s := fposmod(along, 1.0)
		# A long windward slope and a short, steep slip face.
		var slip := clampf(float(r.get("dune_slip", 0.22)), 0.05, 0.95)
		var profile := s / (1.0 - slip) if s < 1.0 - slip else (1.0 - s) / slip
		profile = profile * profile * (3.0 - 2.0 * profile)
		var cover := float(r.get("dune_cover", 1.0))
		var where := smoothstep(0.5 - cover * 0.5, 0.8 - cover * 0.5, (_mask.get_noise_2d(z, x) + 1.0) * 0.5)
		h += profile * dune_amp * (0.55 + 0.45 * _base.get_noise_2d(z * 0.5, x * 0.5)) * where * calm
	var step := float(r.get("terrace", 0.0))
	if step > 0.0:
		var t := h / step
		var f := t - floorf(t)
		var sharp := float(r.get("terrace_sharp", 0.6))
		var k := smoothstep(0.5 - (1.0 - sharp) * 0.5, 0.5 + (1.0 - sharp) * 0.5, f)
		h = lerpf(h, (floorf(t) + k) * step, lerpf(float(r.get("terrace_field", 1.0)), 1.0, out))
	if r.has("floor"):
		var floor_h := float(r["floor"])
		var soft := float(r.get("floor_soft", 2.0))
		if h < floor_h + soft:
			var e := maxf(h - floor_h, 0.0) / soft
			h = floor_h + soft * e * e
	for c in _craters:
		var d := Vector2(x - c.x, z - c.y).length() / c.z
		if d < 1.5:
			h += -c.w * (1.0 - d * d) if d < 1.0 else c.w * 0.25 * (1.0 - smoothstep(1.0, 1.5, d))
	h += out * float(r.get("rim", 0.0))
	return h
