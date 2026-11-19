class_name RaceDriver
extends RefCounted
## An AI racer's hands (DESIGN.md section 9, "Live races"): drives a stock
## machine round a `RaceTrack` by setting its rider's `ActorCommand`, the
## same keys a player presses, so it races on the same machine, the same
## race profile and the same rules as anyone. Nothing here moves a machine
## itself or bends a rule: no extra speed, no catching up, no cut corners.
##
## The line is the track's racing line (`RaceTrack.line_offset`) a little
## ahead, further at speed. It brakes where the corner ahead is tighter than
## the machine can turn at its speed (its radius is speed over `turn_rate`),
## within `pace` of that limit, and throws a drift where the bend is tighter
## than the grip if it is good enough to. It moves off the line to get past
## a slower machine ahead and keeps its distance beside one.
##
## How good it is comes from one number, `skill` (0 a rookie, 1 the best):
## how near the limit it brakes, how tidy its line is, how quick it is off
## the lights, how often it makes a mistake (a late brake, a lift), and
## whether it drifts. At `skill` 1 it drives exactly as the time-trial bench
## does (`tests/race_bench.gd` uses the same `steer`), which is the fastest
## clean lap a machine has, so no AI ever beats a perfect run.
##
## Authority only: the `Race` that owns a grid asks `drive` every tick.

## Corner speed kept under the machine's limit: at skill 0 and at skill 1.
const PACE_ROOKIE := 0.72
const PACE_BEST := 0.9
## Seconds after the lights go out before the throttle goes down.
const REACT_ROOKIE := 0.55
const REACT_BEST := 0.12
## How far the line wanders either side, in metres.
const WANDER_ROOKIE := 1.6
const WANDER_BEST := 0.2
## Seconds between mistakes, on average.
const MISTAKE_ROOKIE := 22.0
const MISTAKE_BEST := 140.0
## Skill from which it drifts where a drift pays (wheels only: a hover
## slides through every turn anyway).
const DRIFTS_FROM := 0.55
## The share of its machine's boost speed it dares hold: a rookie lifts
## early, the best holds it flat out.
const NERVE_ROOKIE := 0.86
const NERVE_BEST := 1.0
## A machine ahead nearer than this, and within `PASS_WIDTH` of its line,
## is one to get past.
const PASS_LOOK := 16.0
const PASS_WIDTH := 2.4
## How far off the line it goes to pass, and how fast it moves across.
const PASS_OFFSET := 3.0
const PASS_RATE := 2.5
## Room kept from the road's edge, in metres.
const EDGE_ROOM := 1.6

var skill := 0.5
## Kept under its machine's corner limit (`PACE_ROOKIE` to `PACE_BEST`).
var pace := 0.8
var reaction := 0.3
var wander := 0.8
var mistake_every := 60.0
var drifts := false
var nerve := 1.0

var _rng := RandomNumberGenerator.new()
var _hint := -1
var _pass := 0.0
var _wander_phase := 0.0
var _mistake_in := 0.0
var _mistake_left := 0.0
var _mistake_kind := ""
var _racing_for := 0.0


## A driver of `p_skill` (0 to 1), its quirks from `p_seed` so a grid is
## the same every time it is made from the same seed.
static func make(p_skill: float, p_seed: int) -> RaceDriver:
	var driver := RaceDriver.new()
	driver.skill = clampf(p_skill, 0.0, 1.0)
	driver._rng.seed = p_seed
	var s := driver.skill
	driver.pace = lerpf(PACE_ROOKIE, PACE_BEST, s)
	driver.reaction = lerpf(REACT_ROOKIE, REACT_BEST, s) * driver._rng.randf_range(0.8, 1.2)
	driver.wander = lerpf(WANDER_ROOKIE, WANDER_BEST, s)
	driver.mistake_every = lerpf(MISTAKE_ROOKIE, MISTAKE_BEST, s)
	driver.drifts = s >= DRIFTS_FROM
	driver.nerve = lerpf(NERVE_ROOKIE, NERVE_BEST, s)
	driver._wander_phase = driver._rng.randf() * TAU
	driver._mistake_in = driver._next_mistake()
	return driver


## One tick: sets `actor`'s command to drive `bike` round `track`. `racing`
## is false while the lights are on (nothing is pressed); `others` are the
## other machines on the track, to get past and keep clear of.
func drive(actor: Actor, bike: Node3D, track: RaceTrack, racing: bool, others: Array, delta: float) -> void:
	var cmd := actor.cmd
	_hint = track.locate(bike.global_position, _hint)
	if not racing or _hint < 0:
		_racing_for = 0.0
		cmd.move = Vector2.ZERO
		cmd.sprint = false
		cmd.jump = false
		return
	_racing_for += delta
	if _racing_for < reaction:
		cmd.move = Vector2.ZERO
		return
	_tick_mistakes(delta)
	_tick_pass(bike, track, others, delta)
	var margin := pace
	if _mistake_kind == "late":
		margin = minf(pace + 0.1, 1.0)
	_wander_phase += delta * 0.35
	var lateral := _pass + sin(_wander_phase) * wander
	# A racer, unlike the bench at the limit, keeps to the line every machine
	# can take (a hover over the Spillway's gap needs its speed; a lift
	# there would drop it in).
	var drive := steer(bike, track, _hint, margin, lateral, drifts, false)
	if _mistake_kind == "lift":
		drive.y = minf(drive.y, 0.25)
	# Past the speed it dares, it lifts.
	var top := float(bike.get("boost_speed")) * nerve
	var boost := drive.y > 0.0
	if nerve < 1.0 and absf(float(bike.get("speed"))) >= top:
		drive.y = minf(drive.y, 0.0)
		boost = false
	cmd.move = drive
	cmd.sprint = boost
	var wheels := not bool(bike.get("hovers"))
	cmd.jump = drifts and wheels and _mistake_kind == "" and drift_for(bike, track, _hint)


func _next_mistake() -> float:
	return _rng.randf_range(0.5, 1.5) * mistake_every


func _tick_mistakes(delta: float) -> void:
	if _mistake_left > 0.0:
		_mistake_left -= delta
		if _mistake_left <= 0.0:
			_mistake_kind = ""
		return
	_mistake_in -= delta
	if _mistake_in <= 0.0:
		_mistake_in = _next_mistake()
		_mistake_left = _rng.randf_range(0.6, 1.3)
		_mistake_kind = "late" if _rng.randf() < 0.5 else "lift"


## Moves off the line to get by a machine ahead in the way, and back on it
## once the way is clear.
func _tick_pass(bike: Node3D, track: RaceTrack, others: Array, delta: float) -> void:
	var at: Vector3 = bike.global_position
	var fwd := track.forward(_hint)
	var side := track.side(_hint)
	var my_lat := (at - track.points[_hint]).dot(side)
	var want := 0.0
	var nearest := INF
	for other: Variant in others:
		if not is_instance_valid(other) or other == bike:
			continue
		var d: Vector3 = (other as Node3D).global_position - at
		var ahead := d.dot(fwd)
		var across := d.dot(side)
		if ahead < -2.0 or ahead > PASS_LOOK or absf(across) > PASS_WIDTH or absf(d.y) > 4.0:
			continue
		if ahead >= nearest:
			continue
		nearest = ahead
		# Go by on the side with more road, away from it.
		var their_lat := my_lat + across
		var room_left := track.width * 0.5 + their_lat
		var room_right := track.width * 0.5 - their_lat
		want = (PASS_OFFSET if room_right >= room_left else -PASS_OFFSET) + (their_lat - track.line_offset(_hint, false))
		want = clampf(want, -PASS_OFFSET * 1.5, PASS_OFFSET * 1.5)
	_pass = move_toward(_pass, want, PASS_RATE * delta)


## The driving: x is the steer (+1 right), y the throttle (-1 brakes). It
## aims at the racing line a little ahead (moved `lateral` metres across,
## kept off the edges), and brakes where the corner ahead is tighter than
## `margin` of the machine's limit at its speed allows. `drift` brakes later
## for a drift's tighter turn.
static func steer(bike: Node3D, track: RaceTrack, hint: int, margin := PACE_BEST, lateral := 0.0,
		drift := false, hover_line := true) -> Vector2:
	var n := track.points.size()
	var speed := absf(float(bike.get("speed")))
	var drift_mult := float(bike.get("drift_turn")) if drift and bool(bike.get("handbrake")) else 1.0
	var brake := float(bike.get("brake_decel"))
	var at: Vector3 = bike.global_position
	var ahead := 3 + int(speed * 0.35 / RaceTrack.STEP)
	var ti := (hint + ahead) % n
	var across := track.line_offset(ti, hover_line and bool(bike.get("hovers")))
	if lateral != 0.0:
		var edge := maxf(track.width * 0.5 - EDGE_ROOM, 0.0)
		across = clampf(across + lateral, -edge, edge)
	var target := track.points[ti] + track.side(ti) * across
	var heading := float(bike.get("heading")) + float(bike.get("slip"))
	var facing := Basis(Vector3.UP, heading) * Vector3.FORWARD
	var want := Vector3(target.x - at.x, 0.0, target.z - at.z).normalized()
	var angle := facing.signed_angle_to(want, Vector3.UP)
	var steering := clampf(-angle * 3.0, -1.0, 1.0)
	var throttle := 1.0
	var reach := int((speed * speed / (2.0 * maxf(brake, 1.0)) + 20.0) / RaceTrack.STEP)
	for j in range(2, reach, 2):
		var i := (hint + j) % n
		var allowed := corner_speed(bike, radius_at(track, i), drift_mult) * margin
		var dist := j * RaceTrack.STEP
		if speed * speed - allowed * allowed > 2.0 * brake * dist:
			throttle = -1.0
			break
	return Vector2(steering, throttle)


## The handbrake: held through a bend tighter than the machine can turn at
## its speed, and through the drift until the line ahead is open enough.
static func drift_for(bike: Node3D, track: RaceTrack, hint: int) -> bool:
	if not bool(bike.get("handbrake")):
		return false
	var speed := float(bike.get("speed"))
	if speed < float(bike.get("drift_min_speed")) + 2.0:
		return false
	var n := track.points.size()
	var tightest := INF
	for j in range(0, 8, 2):
		tightest = minf(tightest, radius_at(track, (hint + j) % n))
	var grip := corner_speed(bike, tightest, 1.0)
	if bool(bike.get("drifting")):
		return grip < speed * 0.9
	return grip < speed * 0.95


## The fastest a machine takes a bend of `radius` at its turn rate; `mult`
## widens it for a drift.
static func corner_speed(bike: Node3D, radius: float, mult: float) -> float:
	return radius * float(bike.get("turn_rate")) * mult


## The track's turning radius about point `i`, from the bend over 12 m.
static func radius_at(track: RaceTrack, i: int) -> float:
	var n := track.points.size()
	var a := track.forward((i - 3 + n) % n)
	var b := track.forward((i + 3) % n)
	var bend := absf(Vector2(a.x, a.z).angle_to(Vector2(b.x, b.z)))
	return 6.0 * RaceTrack.STEP / maxf(bend, 0.001)
