class_name Weather
extends RefCounted
## A world's weather (DESIGN.md "Weather: ash storms"): at most one storm at
## a time, a cell that crosses the map with the wind. Ashfront's ash storms
## and Frostline's whiteouts are the same thing with a different
## `WorldDef.weather_kind` and numbers.
##
## Plain arithmetic with no nodes, so it runs on a headless server. Only the
## authority calls `tick`, which starts, moves and ends storms; a client
## gets the cell from `NetSession` (`unpack`) and only moves it on between
## updates (`advance`). What it looks like is `WeatherView`.

## The kind of storm the running one is ("ash", "snow"), "" when none runs.
var kind := ""
## The cell's centre, on the ground plane (y is 0).
var centre := Vector3.ZERO
## How the cell moves, metres a second. Its direction is the wind's.
var velocity := Vector3.ZERO
var radius := 150.0
## The storm's own strength, 0 to 1: it builds, holds, then dies away.
var strength := 0.0
## Seconds the running storm has been going, and how long it lasts.
var age := 0.0
var life := 0.0
## Seconds until the next storm starts (authority only).
var next_in := 0.0
## How far in from the edge the storm is at full strength, as a share of
## its radius: the outer 40% is its soft edge.
var core_share := 0.6

var _world: WorldDef
var _rng := RandomNumberGenerator.new()


## Ready for `world`. Nothing runs where the world has no weather.
func setup(world: WorldDef, seed_value: int) -> void:
	_world = world
	_rng.seed = seed_value
	if world != null and world.weather_kind != "":
		next_in = _rng.randf_range(world.weather_first.x, world.weather_first.y)


## True while a storm is running.
func active() -> bool:
	return kind != "" and strength > 0.0


## Authority: counts down to the next storm, moves the running one and ends
## it once it has crossed.
func tick(delta: float) -> void:
	if _world == null or _world.weather_kind == "":
		return
	if kind == "":
		next_in -= delta
		if next_in <= 0.0:
			start()
		return
	age += delta
	centre += velocity * delta
	strength = _strength_for(age)
	if age >= life:
		stop()


## Authority: starts a storm now along the world's path for it.
func start() -> void:
	if _world == null or _world.weather_kind == "":
		return
	var path := _world.weather_path(_rng)
	var from: Vector3 = path[0]
	var to: Vector3 = path[1]
	from.y = 0.0
	to.y = 0.0
	kind = _world.weather_kind
	radius = _world.weather_radius
	centre = from
	var span := maxf(from.distance_to(to), 1.0)
	var speed := maxf(_world.weather_speed, 0.1)
	velocity = (to - from) / span * speed
	life = span / speed
	age = 0.0
	strength = _strength_for(0.0)


## Authority: ends the running storm and waits for the next.
func stop() -> void:
	kind = ""
	strength = 0.0
	age = 0.0
	velocity = Vector3.ZERO
	if _world != null:
		next_in = _rng.randf_range(_world.weather_gap.x, _world.weather_gap.y)


func _strength_for(t: float) -> float:
	var ramp := maxf(_world.weather_ramp if _world != null else 40.0, 0.01)
	return clampf(minf(t / ramp, (life - t) / ramp), 0.0, 1.0)


## Client: carries the cell on with its velocity between the server's updates.
func advance(delta: float) -> void:
	if kind != "":
		centre += velocity * delta


## How strong the weather is at `at`: the storm's strength, full over its
## core and fading to nothing across its soft edge. 0 with no storm.
func strength_at(at: Vector3) -> float:
	if kind == "" or strength <= 0.0:
		return 0.0
	var away := Vector2(at.x - centre.x, at.z - centre.z).length()
	if away >= radius:
		return 0.0
	# No storm reaches inside (`WorldDef.sheltered_at`).
	if _world != null and _world.sheltered_at(at):
		return 0.0
	return strength * (1.0 - smoothstep(radius * core_share, radius, away))


## The share of usual sight left at `at` (1 in clear air), for bots spotting
## and scans reaching.
func sight_at(at: Vector3) -> float:
	var floor_share := _world.weather_sight if _world != null else 1.0
	return lerpf(1.0, floor_share, strength_at(at))


## The share of sight left between two places: the worse of the two, so a
## bot in clear air does not see far into a storm and one in a storm does
## not see far out of it.
func sight_between(a: Vector3, b: Vector3) -> float:
	return minf(sight_at(a), sight_at(b))


## How far a shot made at `at` carries, as a share of usual.
func carry_at(at: Vector3) -> float:
	var floor_share := _world.weather_carry if _world != null else 1.0
	return lerpf(1.0, floor_share, strength_at(at))


## How much faster body heat drains at `at` (1 in clear air).
func cold_at(at: Vector3) -> float:
	var most := _world.weather_cold if _world != null else 1.0
	return lerpf(1.0, most, strength_at(at))


## The wind's push on a flight rig at `at`, as an acceleration (m/s²) for a
## rig with `FlightRig.gust_mult` 1. Mostly along the wind, partly across it
## and up and down, and it rises and falls as you move through the storm.
## It depends only on where you are in the cell, never on a clock, so a
## client predicting its own flight gets the same push the server does.
func gust_at(at: Vector3) -> Vector3:
	var s := strength_at(at)
	if s <= 0.0 or _world == null or _world.weather_gust <= 0.0:
		return Vector3.ZERO
	var wind := Vector3(velocity.x, 0.0, velocity.z)
	wind = wind.normalized() if wind.length_squared() > 0.0001 else Vector3.RIGHT
	var across := Vector3(-wind.z, 0.0, wind.x)
	var local := at - centre
	# Two slow waves laid across the cell: gusts and lulls about 40 m apart.
	var surge := 0.6 + 0.4 * sin(local.x * 0.13 + local.z * 0.07) * sin(local.x * 0.05 - local.z * 0.11 + 1.3)
	var veer := sin(local.z * 0.09 + local.x * 0.04 + 0.7)
	var lift := sin(local.x * 0.08 - local.z * 0.06 + at.y * 0.15)
	return (wind * surge + across * 0.5 * veer + Vector3.UP * 0.35 * lift) * _world.weather_gust * s


## The world's strongest gust, m/s² (`WorldDef.weather_gust`), 0 with no
## weather.
func gust_most() -> float:
	return _world.weather_gust if _world != null else 0.0


## What clients are sent: [kind, centre x, centre z, velocity x, velocity z,
## radius, strength].
func pack() -> Array:
	return [kind, centre.x, centre.z, velocity.x, velocity.z, radius, strength]


## Client: takes the server's word for the cell.
func unpack(data: Array) -> void:
	if data.size() < 7:
		return
	kind = str(data[0])
	centre = Vector3(float(data[1]), 0.0, float(data[2]))
	velocity = Vector3(float(data[3]), 0.0, float(data[4]))
	radius = maxf(float(data[5]), 1.0)
	strength = clampf(float(data[6]), 0.0, 1.0) if kind != "" else 0.0
