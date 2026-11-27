extends Node3D
## The war in the sky past the rim (DESIGN.md "Scale you can see"): flak
## guns on the far battle lines hosing tracer up into the smoke, shells
## bursting high over the horizon and leaving dark puffs hanging, and, while
## a dropship wing is up, bursts chasing it (never hitting). More of all of
## it as the war heats up (the map's "war_intensity"), and a storm's ash
## hides it (`Look.weather_cover`). View only: the map adds it only where
## `Look` is on. Every tracer is one MultiMesh, so it costs one draw call.

const GameSettings := preload("res://core/settings/game_settings.gd")

## How many flak batteries fire, quiet and in all-out war.
const BATTERIES := Vector2i(1, 6)
## Rounds kept in flight per battery, and the time between them in a burst.
const ROUNDS := 22
const ROUND_EVERY := 0.07
## How long a burst of tracer lasts, and the rest between bursts
## (in all-out war, and when quiet).
const BURST_TIME := Vector2(0.9, 2.2)
const REST_TIME := Vector2(1.2, 6.0)
## A tracer's speed (m/s, slowed so it reads from this far off), how long
## it shows, its droop and its streak's size.
const TRACER_SPEED := 260.0
const TRACER_LIFE := 1.5
const TRACER_DROP := 9.0
const TRACER_SIZE := Vector3(2.2, 2.2, 20.0)
## Where the batteries stand: past the rim, from the map's middle.
const BATTERY_REACH := Vector2(420.0, 620.0)
## Flak clusters a second, quiet and in all-out war, and shells in each.
const FLAK_RATE := Vector2(0.08, 1.1)
const FLAK_CLUSTER := Vector2i(3, 6)
## Where flak bursts: how far out and how high over the floor.
const FLAK_REACH := Vector2(380.0, 700.0)
const FLAK_HEIGHT := Vector2(160.0, 360.0)
## How close a burst comes to a passing dropship (m), and the share of
## clusters that go after it while a wing is up.
const WING_MISS := Vector2(45.0, 110.0)
const WING_SHARE := 0.6
const BURST_TIME_SHOWN := 0.35
const SMOKE_TIME := 7.0
## How far off flak is still drawn (m).
const SKY_REACH := 2000.0

var floor_y := 38.0
var soundscape: Node = null
## The node that knows where the dropships are (`giants.gd`, `wing_lead`).
var giants: Node = null

var _rng := RandomNumberGenerator.new()
var _tracers: MultiMeshInstance3D
## One battery: { at, aim (yaw), lean, firing (s left), rest (s left),
## next (s to the next round), shots: [[age, dir]] }.
var _batteries: Array[Dictionary] = []
var _bursts: Array[MeshInstance3D] = []
var _burst_left: Array[float] = []
var _smoke: Array[MeshInstance3D] = []
var _smoke_left: Array[float] = []
## Shells of a cluster still to burst: [seconds left, where].
var _queued: Array[Array] = []


func _ready() -> void:
	name = "Skyfire"
	_rng.seed = 7171
	for i in BATTERIES.y:
		var angle := _rng.randf() * TAU
		var reach := _rng.randf_range(BATTERY_REACH.x, BATTERY_REACH.y)
		_batteries.append({"at": Vector3(cos(angle) * reach, floor_y, sin(angle) * reach),
				"aim": angle + PI + _rng.randf_range(-0.6, 0.6), "lean": _rng.randf_range(0.9, 1.25),
				"firing": 0.0, "rest": _rng.randf_range(0.0, 4.0), "next": 0.0, "shots": []})
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var streak := BoxMesh.new()
	streak.size = TRACER_SIZE
	streak.material = Look.trim("tracer")
	multi.mesh = streak
	multi.instance_count = BATTERIES.y * ROUNDS
	multi.visible_instance_count = 0
	_tracers = MultiMeshInstance3D.new()
	_tracers.multimesh = multi
	_tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Out past the batteries, so the whole sky stays in one box.
	_tracers.custom_aabb = AABB(Vector3(-900, -100, -900), Vector3(1800, 900, 1800))
	add_child(_tracers)
	for i in 18:
		_bursts.append(_quad("flash"))
		_burst_left.append(0.0)
	for i in 30:
		_smoke.append(_quad("flak_smoke"))
		_smoke_left.append(0.0)


## How many batteries fire at war intensity `heat` (0 to 1).
static func batteries_at(heat: float) -> int:
	return BATTERIES.x + int(round(clampf(heat, 0.0, 1.0) * (BATTERIES.y - BATTERIES.x)))


## Flak clusters a second at war intensity `heat`.
static func flak_rate(heat: float) -> float:
	return lerpf(FLAK_RATE.x, FLAK_RATE.y, clampf(heat, 0.0, 1.0))


## Where a tracer fired from `from` along `dir` is `age` seconds later:
## straight out, drooping a little as it goes.
static func tracer_point(from: Vector3, dir: Vector3, age: float) -> Vector3:
	return from + dir * TRACER_SPEED * age + Vector3.DOWN * TRACER_DROP * age * age


## Where a shell aimed near `target` bursts: off it by `miss` metres in a
## direction picked by `spin` and `tilt` (0 to 1), never on it.
static func near_miss(target: Vector3, miss: float, spin: float, tilt: float) -> Vector3:
	var up := lerpf(-0.6, 0.8, tilt)
	var flat := sqrt(1.0 - up * up)
	return target + Vector3(cos(spin * TAU) * flat, up, sin(spin * TAU) * flat) * miss


func _quad(kind: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.material = Look.trim(kind)
	node.mesh = quad
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drawn as far as the sky goes (a 1 m quad would otherwise be cut off
	# close by, `Look._limit_draw_distance`).
	node.visibility_range_end = SKY_REACH
	add_child(node)
	return node


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	var map := get_parent()
	var heat := clampf(float(map.get_meta("war_intensity", 0.0)), 0.0, 1.0) if map != null else 0.0
	var seen := 1.0 - Look.weather_cover
	_fire_tracers(delta, heat, seen)
	_fire_flak(delta, heat)
	_fade(delta, seen)


func _fire_tracers(delta: float, heat: float, seen: float) -> void:
	var multi := _tracers.multimesh
	var live := ceili(batteries_at(heat) * GameSettings.war_share())
	var shown := 0
	for b in _batteries.size():
		var battery: Dictionary = _batteries[b]
		var shots: Array = battery["shots"]
		for shot: Array in shots:
			shot[0] += delta
		while not shots.is_empty() and float(shots[0][0]) > TRACER_LIFE:
			shots.pop_front()
		battery["aim"] = float(battery["aim"]) + delta * 0.08 * sin(Time.get_ticks_msec() * 0.0003 + b)
		if b < live:
			if float(battery["firing"]) > 0.0:
				battery["firing"] = float(battery["firing"]) - delta
				battery["next"] = float(battery["next"]) - delta
				if float(battery["next"]) <= 0.0:
					battery["next"] = ROUND_EVERY
					# The gun walks its stream across the sky as it fires.
					var sweep := float(battery["aim"]) + 0.25 * sin(float(battery["firing"]) * 2.3)
					var lean := float(battery["lean"]) + 0.12 * sin(float(battery["firing"]) * 3.1)
					var dir := Vector3(cos(sweep) * cos(lean), sin(lean), sin(sweep) * cos(lean))
					shots.append([0.0, dir])
					if shots.size() > ROUNDS:
						shots.pop_front()
			else:
				battery["rest"] = float(battery["rest"]) - delta
				if float(battery["rest"]) <= 0.0:
					battery["firing"] = _rng.randf_range(BURST_TIME.x, BURST_TIME.y)
					battery["rest"] = _rng.randf_range(lerpf(REST_TIME.y, REST_TIME.x, heat), REST_TIME.y)
					battery["aim"] = float(battery["aim"]) + _rng.randf_range(-0.4, 0.4)
		var from: Vector3 = battery["at"]
		for shot: Array in shots:
			var age := float(shot[0])
			var dir: Vector3 = shot[1]
			var here := tracer_point(from, dir, age)
			var heading := (tracer_point(from, dir, age + 0.05) - here).normalized()
			var fade := (1.0 - age / TRACER_LIFE) * seen
			multi.set_instance_transform(shown, Transform3D(Basis.looking_at(heading), here))
			multi.set_instance_color(shown, Color(1, 1, 1, fade))
			shown += 1
	multi.visible_instance_count = shown


func _fire_flak(delta: float, heat: float) -> void:
	for i in range(_queued.size() - 1, -1, -1):
		_queued[i][0] -= delta
		if float(_queued[i][0]) <= 0.0:
			_burst(_queued[i][1])
			_queued.remove_at(i)
	if _rng.randf() >= flak_rate(heat) * GameSettings.war_share() * delta:
		return
	var target := Vector3.INF
	var lead: Vector3 = giants.call("wing_lead") if giants != null else Vector3.INF
	if lead.is_finite() and _rng.randf() < WING_SHARE:
		target = lead
	var shells := _rng.randi_range(FLAK_CLUSTER.x, FLAK_CLUSTER.y)
	if not target.is_finite():
		var angle := _rng.randf() * TAU
		var reach := _rng.randf_range(FLAK_REACH.x, FLAK_REACH.y)
		target = Vector3(cos(angle) * reach, floor_y + _rng.randf_range(FLAK_HEIGHT.x, FLAK_HEIGHT.y), sin(angle) * reach)
	for s in shells:
		var miss := _rng.randf_range(WING_MISS.x, WING_MISS.y)
		_queued.append([s * _rng.randf_range(0.12, 0.3), near_miss(target, miss, _rng.randf(), _rng.randf())])
	if soundscape != null and _rng.randf() < 0.5:
		soundscape.call("boom", target)


func _burst(at: Vector3) -> void:
	var flash := _free_slot(_burst_left)
	if flash >= 0:
		_bursts[flash].position = at
		_bursts[flash].scale = Vector3.ONE * _rng.randf_range(24.0, 40.0)
		_bursts[flash].visible = true
		_burst_left[flash] = BURST_TIME_SHOWN
	var puff := _free_slot(_smoke_left)
	if puff >= 0:
		_smoke[puff].position = at
		_smoke[puff].visible = true
		_smoke_left[puff] = SMOKE_TIME


func _free_slot(left: Array[float]) -> int:
	for i in left.size():
		if left[i] <= 0.0:
			return i
	return -1


func _fade(delta: float, seen: float) -> void:
	for i in _bursts.size():
		if _burst_left[i] <= 0.0:
			continue
		_burst_left[i] -= delta
		var t := clampf(_burst_left[i] / BURST_TIME_SHOWN, 0.0, 1.0)
		_bursts[i].transparency = 1.0 - t * t * seen
		_bursts[i].visible = _burst_left[i] > 0.0
	for i in _smoke.size():
		if _smoke_left[i] <= 0.0:
			continue
		_smoke_left[i] -= delta
		var age := 1.0 - clampf(_smoke_left[i] / SMOKE_TIME, 0.0, 1.0)
		# The puff blooms out fast, then drifts and thins.
		_smoke[i].scale = Vector3.ONE * lerpf(14.0, 40.0, sqrt(age))
		_smoke[i].position.y += delta * 1.5
		# It thickens as the flash dies, so it never blots its own flash.
		var thick := minf(age * SMOKE_TIME / BURST_TIME_SHOWN, 1.0)
		_smoke[i].transparency = 1.0 - thick * (1.0 - age) * seen
		_smoke[i].visible = _smoke_left[i] > 0.0
