extends Node3D
## Ashfront's busy low sky (DESIGN.md "The busy low sky", Caleb's call):
## the war overhead, under the flak past the rim (`skyfire.gd`). Gunships
## run in low over the scenery army's far fights and strafe them, with the
## fight's tracer coming back up at them; fighters streak over in pairs;
## and now and then a dropship, hit, falls burning out of the smoke and
## comes down past the rim. More of all of it as the war heats up (the
## map's "war_intensity"), none of it while a storm hides the sky.
##
## View only and never in a server: the map adds it only where `Look` is
## on. Nothing here collides or goes through `Combat.deal`. A strafing run
## only rakes a scenery fight, which is kept well away from every player
## (`battle.gd`), and drops its extras on that screen only; a wreck comes
## down past the rim, where nobody can stand. All tracers are one MultiMesh.

const GameSettings := preload("res://core/settings/game_settings.gd")

## Seconds between gunship runs, fighter pairs and falling dropships, quiet
## and in all-out war.
const GUNSHIP_GAP := Vector2(75.0, 16.0)
const FIGHTER_GAP := Vector2(60.0, 12.0)
const WRECK_GAP := Vector2(240.0, 65.0)
## A gunship's height over the ground it rakes, its speed, how far before
## and after its target its run starts and ends, and the reach within
## which it fires.
const GUNSHIP_HEIGHT := Vector2(60.0, 95.0)
const GUNSHIP_SPEED := 32.0
const GUNSHIP_RUN := 700.0
const STRAFE_REACH := 240.0
## A strafing burst: how long it fires, the rest between, a round's gap,
## how far its rounds scatter and how far a burst walks along the ground.
const STRAFE_BURST := Vector2(0.7, 1.5)
const STRAFE_REST := Vector2(0.5, 1.3)
const STRAFE_EVERY := 0.055
const STRAFE_SCATTER := 4.0
const STRAFE_WALK := 26.0
## How far from a gunship it must be to come back up at it, rounds a
## second (quiet and in all-out war) and how wide they miss (they always do).
const RETURN_REACH := 420.0
const RETURN_RATE := Vector2(4.0, 16.0)
const RETURN_MISS := Vector2(5.0, 26.0)
## Fighters: their height, speed and run, how close to the middle they
## pass, and where the wingman holds off the lead.
const FIGHTER_HEIGHT := Vector2(120.0, 200.0)
const FIGHTER_SPEED := 175.0
const FIGHTER_RUN := 2600.0
const FIGHTER_PASS := 220.0
const WINGMAN := Vector3(28.0, 5.0, 34.0)
## A falling dropship: where it is hit (flat reach and height over the
## floor), how long it falls, and how far past the rim it comes down.
const WRECK_FROM := Vector2(180.0, 360.0)
const WRECK_HEIGHT := Vector2(200.0, 300.0)
const WRECK_FALL := Vector2(13.0, 19.0)
const WRECK_PAST_RIM := Vector2(25.0, 140.0)
const WRECK_BURNS := 40.0
## A tracer's speed, the most kept, the streak's size and its brightness.
const TRACER_SPEED := 320.0
const MAX_TRACERS := 360
const STREAK := Vector3(0.6, 0.6, 9.0)
const TRACER_GLOW := 1.8
const TRACER_COLOURS := [Color(1.0, 0.42, 0.08), Color(0.15, 0.7, 1.0)]
## How far off any of it is still drawn (m).
const SKY_REACH := 2400.0

## Set by the map: the floor past the rim, the field's reach, the scenery
## army (what gunships rake), the soundscape and the plume maker.
var floor_y := 38.0
var field := 276.0
var battle: Node = null
var soundscape: Node = null
var plume_maker := Callable()

var _rng := RandomNumberGenerator.new()
var _gunships: Array[Dictionary] = []
var _pairs: Array[Dictionary] = []
var _wrecks: Array[Dictionary] = []
var _tracers: Array[Dictionary] = []
var _sounds: Array[Array] = []
var _next_gunship := 0.0
var _next_pair := 0.0
var _next_wreck := 0.0
var _tracer_mesh: MultiMesh
var _flashes: Array[MeshInstance3D] = []
var _flash_left: Array[float] = []
var _flash_time: Array[float] = []
var _dust: Array[MeshInstance3D] = []
var _dust_left: Array[float] = []
var _hull: Material


func _ready() -> void:
	name = "LowSky"
	_rng.seed = 5309
	_next_gunship = _rng.randf_range(6.0, 18.0)
	_next_pair = _rng.randf_range(4.0, 14.0)
	_next_wreck = _rng.randf_range(40.0, 90.0)
	if not Look.enabled:
		return
	_hull = Look.trim("distant")
	_build_tracers()
	for i in 48:
		_flashes.append(_quad("flash"))
		_flash_left.append(0.0)
		_flash_time.append(1.0)
	for i in 48:
		_dust.append(_quad("flak_smoke"))
		_dust_left.append(0.0)


# --- Pacing -------------------------------------------------------------

func _heat() -> float:
	var map := get_parent()
	return clampf(float(map.get_meta("war_intensity", 0.0)), 0.0, 1.0) if map != null else 0.0


func _centre() -> Vector3:
	var map := get_parent()
	var centre: Variant = map.get_meta("war_centre", Vector3.ZERO) if map != null else Vector3.ZERO
	return centre if centre is Vector3 else Vector3.ZERO


## Seconds to the next of something whose gap is `gap` (quiet, all-out
## war) at war intensity `heat`.
static func gap_at(gap: Vector2, heat: float) -> float:
	return lerpf(gap.x, gap.y, clampf(heat, 0.0, 1.0))


## How many gunships may be up at once at war intensity `heat`.
static func gunships_at(heat: float) -> int:
	return 1 if heat < 0.6 else 2


func _ground(x: float, z: float) -> float:
	var map := get_parent()
	if map != null and map.has_method("scenery_height"):
		return float(map.call("scenery_height", x, z))
	if map != null and map.has_method("ground_height") and Vector2(x, z).length() < field:
		return float(map.call("ground_height", x, z))
	return floor_y


## Whether a strafing round may land at `at`: only as far from every
## player and the camera as a scenery fight is placed.
func may_rake(at: Vector3) -> bool:
	if battle == null:
		return false
	return float(battle.call("nearest_watcher", at)) >= float(battle.get("place_off")) * 0.8


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	var heat := _heat()
	var clear := Look.weather_cover < 0.6
	_next_gunship -= delta
	if _next_gunship <= 0.0:
		_next_gunship = gap_at(GUNSHIP_GAP, heat) / GameSettings.war_share() * _rng.randf_range(0.7, 1.3)
		if clear and _gunships.size() < gunships_at(heat):
			send_gunship()
	_next_pair -= delta
	if _next_pair <= 0.0:
		_next_pair = gap_at(FIGHTER_GAP, heat) / GameSettings.war_share() * _rng.randf_range(0.6, 1.4)
		if clear:
			send_fighters()
	_next_wreck -= delta
	if _next_wreck <= 0.0:
		_next_wreck = gap_at(WRECK_GAP, heat) / GameSettings.war_share() * _rng.randf_range(0.7, 1.3)
		if clear and _wrecks.size() < 2:
			drop_wreck()
	_tick_gunships(delta, heat)
	_tick_pairs(delta)
	_tick_wrecks(delta)
	_tick_tracers(delta)
	_tick_sounds(delta)
	if Look.enabled:
		_fade(delta)
		_draw_tracers()


# --- Gunships -----------------------------------------------------------

## A scenery fight to rake, or the war's centre when there is none.
func _gunship_target() -> Vector3:
	if battle != null:
		var fights: Array = battle.call("fight_list")
		var open: Array = []
		for fight: Dictionary in fights:
			if not fight.ending:
				open.append(fight)
		if not open.is_empty():
			return (open[_rng.randi() % open.size()] as Dictionary).centre
	var centre := _centre()
	return Vector3(centre.x, 0.0, centre.z)


## Sends a gunship on a run over a scenery fight (or the war's centre).
func send_gunship() -> Dictionary:
	var target := _gunship_target()
	target.y = _ground(target.x, target.z)
	var angle := _rng.randf() * TAU
	var way := Vector3(cos(angle), 0.0, sin(angle))
	var high := target.y + _rng.randf_range(GUNSHIP_HEIGHT.x, GUNSHIP_HEIGHT.y)
	var run := {"target": target, "from": Vector3(target.x, high, target.z) - way * GUNSHIP_RUN,
			"way": way, "t": 0.0, "army": _rng.randi() % 2, "firing": 0.0, "rest": 0.0,
			"next": 0.0, "walk": 0.0, "aim": target, "back": 0.0, "node": null}
	if Look.enabled:
		run.node = _build_gunship()
	_gunships.append(run)
	return run


static func gunship_at(run: Dictionary) -> Vector3:
	var t := float(run.t)
	return (run.from as Vector3) + (run.way as Vector3) * GUNSHIP_SPEED * t + Vector3(0, 2.5 * sin(t * 0.6), 0)


func _tick_gunships(delta: float, heat: float) -> void:
	for i in range(_gunships.size() - 1, -1, -1):
		var run: Dictionary = _gunships[i]
		run.t = float(run.t) + delta
		var here := gunship_at(run)
		var way: Vector3 = run.way
		if GUNSHIP_SPEED * float(run.t) > GUNSHIP_RUN * 2.0:
			if run.node != null:
				(run.node as Node3D).queue_free()
			_gunships.remove_at(i)
			continue
		var target: Vector3 = run.target
		var flat := Vector2(here.x - target.x, here.z - target.z).length()
		if run.node != null:
			# It noses down a little into its run and banks gently off it.
			var tilt := 0.12 if flat < STRAFE_REACH else 0.0
			var basis := Basis.looking_at(way) * Basis(Vector3.RIGHT, -tilt) * Basis(Vector3.BACK, 0.08 * sin(float(run.t) * 0.4))
			(run.node as Node3D).global_transform = Transform3D(basis, here)
		_strafe(run, here, flat, delta)
		_shoot_back(run, here, flat, delta, heat)


func _strafe(run: Dictionary, here: Vector3, flat: float, delta: float) -> void:
	var muzzle: Node3D = (run.node as Node3D).get_node_or_null("Muzzle") if run.node != null else null
	if muzzle != null:
		muzzle.visible = false
	if flat > STRAFE_REACH:
		return
	if float(run.firing) <= 0.0:
		run.rest = float(run.rest) - delta
		if float(run.rest) <= 0.0:
			run.firing = _rng.randf_range(STRAFE_BURST.x, STRAFE_BURST.y)
			run.rest = _rng.randf_range(STRAFE_REST.x, STRAFE_REST.y)
			run.walk = 0.0
			var target: Vector3 = run.target
			var way: Vector3 = run.way
			var across := Vector3(-way.z, 0.0, way.x)
			run.aim = target + across * _rng.randf_range(-18.0, 18.0) - way * STRAFE_WALK * 0.5
			_sounds.append([Soundscape.boom_delay(_ear_distance(here)), here])
		return
	run.firing = float(run.firing) - delta
	run.walk = float(run.walk) + delta
	run.next = float(run.next) - delta
	if muzzle != null:
		muzzle.visible = int(float(run.walk) * 30.0) % 2 == 0
	while float(run.next) <= 0.0:
		run.next = float(run.next) + STRAFE_EVERY
		var aim: Vector3 = (run.aim as Vector3) + (run.way as Vector3) * STRAFE_WALK * clampf(float(run.walk) / STRAFE_BURST.y, 0.0, 1.0)
		aim += Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)) * STRAFE_SCATTER
		aim.y = _ground(aim.x, aim.z)
		if not may_rake(aim):
			continue
		var from := muzzle.global_position if muzzle != null else here + Vector3(0, -2.5, 0)
		_fire(from, aim, int(run.army), true)


func _shoot_back(run: Dictionary, here: Vector3, flat: float, delta: float, heat: float) -> void:
	if flat > RETURN_REACH or _rng.randf() >= lerpf(RETURN_RATE.x, RETURN_RATE.y, heat) * delta:
		return
	var target: Vector3 = run.target
	var from := target + Vector3(_rng.randf_range(-22.0, 22.0), 0.0, _rng.randf_range(-22.0, 22.0))
	from.y = _ground(from.x, from.z) + 1.4
	if not may_rake(from):
		return
	# Led a little and always off: up past the hull, never into it.
	var lead := here + (run.way as Vector3) * GUNSHIP_SPEED * (from.distance_to(here) / TRACER_SPEED)
	var miss := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 1), _rng.randf_range(-1, 1)).normalized()
	var aim := lead + miss * _rng.randf_range(RETURN_MISS.x, RETURN_MISS.y)
	_fire(from, from + (aim - from) * 2.2, 1 - int(run.army), false)


# --- Fighters -----------------------------------------------------------

## Sends a pair of fighters streaking over, passing near the middle.
func send_fighters() -> Dictionary:
	var angle := _rng.randf() * TAU
	var way := Vector3(cos(angle), 0.0, sin(angle))
	var across := Vector3(-way.z, 0.0, way.x)
	var centre := _centre()
	var past := Vector3(centre.x, 0.0, centre.z) + across * _rng.randf_range(-FIGHTER_PASS, FIGHTER_PASS)
	past.y = floor_y + _rng.randf_range(FIGHTER_HEIGHT.x, FIGHTER_HEIGHT.y)
	var pair := {"from": past - way * FIGHTER_RUN * 0.5, "way": way, "t": 0.0, "heard": false,
			"side": 1.0 if _rng.randf() < 0.5 else -1.0, "nodes": []}
	if Look.enabled:
		pair.nodes = [_build_fighter(), _build_fighter()]
	_pairs.append(pair)
	return pair


static func lead_at(pair: Dictionary) -> Vector3:
	return (pair.from as Vector3) + (pair.way as Vector3) * FIGHTER_SPEED * float(pair.t)


func _tick_pairs(delta: float) -> void:
	for i in range(_pairs.size() - 1, -1, -1):
		var pair: Dictionary = _pairs[i]
		pair.t = float(pair.t) + delta
		if FIGHTER_SPEED * float(pair.t) > FIGHTER_RUN:
			for node: Variant in pair.nodes:
				if is_instance_valid(node):
					(node as Node3D).queue_free()
			_pairs.remove_at(i)
			continue
		var lead := lead_at(pair)
		var way: Vector3 = pair.way
		# A loose roll as they go over, the wingman echeloned off the lead.
		var basis := Basis.looking_at(way) * Basis(Vector3.BACK, 0.25 * sin(float(pair.t) * 0.9) * float(pair.side))
		var nodes: Array = pair.nodes
		for n in nodes.size():
			var at := lead if n == 0 else lead + basis * Vector3(WINGMAN.x * float(pair.side), -WINGMAN.y, WINGMAN.z)
			(nodes[n] as Node3D).global_transform = Transform3D(basis, at)
		_hear_pass(pair, lead)


## The roar of a pass, played from where it comes nearest the ear so it
## swells and goes by.
func _hear_pass(pair: Dictionary, lead: Vector3) -> void:
	if bool(pair.heard):
		return
	var ear := _ear()
	if not ear.is_finite():
		return
	var way: Vector3 = pair.way
	var ahead := (ear - lead).dot(way)
	if ahead > FIGHTER_SPEED * 1.6:
		return
	pair.heard = true
	var nearest := lead + way * maxf(ahead, 0.0)
	Sfx.play("jet_pass", nearest, -2.0, 900.0, 140.0)


# --- Falling dropships --------------------------------------------------

## A dropship hit over the field, falling burning to crash past the rim.
func drop_wreck() -> Dictionary:
	var angle := _rng.randf() * TAU
	var down_at := _rng.randf_range(field + WRECK_PAST_RIM.x, field + WRECK_PAST_RIM.y)
	var lands := Vector3(cos(angle), 0.0, sin(angle)) * down_at
	lands.y = floor_y
	var turn := angle + _rng.randf_range(-0.5, 0.5)
	var from := Vector3(cos(turn), 0.0, sin(turn)) * _rng.randf_range(WRECK_FROM.x, WRECK_FROM.y)
	from.y = floor_y + _rng.randf_range(WRECK_HEIGHT.x, WRECK_HEIGHT.y)
	var wreck := {"from": from, "to": lands, "t": 0.0, "time": _rng.randf_range(WRECK_FALL.x, WRECK_FALL.y),
			"spin": _rng.randf_range(0.5, 1.4) * (1.0 if _rng.randf() < 0.5 else -1.0),
			"down": false, "burning": WRECK_BURNS, "node": null, "plume": null, "glow": null}
	if Look.enabled:
		wreck.node = _build_dropship()
		_flash(from, 50.0, 0.5)
		_flash(from + Vector3(8, 4, -6), 30.0, 0.4)
		if plume_maker.is_valid():
			var plume: GPUParticles3D = plume_maker.call(Vector3.ZERO, 3.0)
			plume.preprocess = 0.0
			plume.amount = 48
			# Its smoke stays where it was let go, a trail down the sky.
			plume.visibility_aabb = AABB(Vector3(-700, -450, -700), Vector3(1400, 1000, 1400))
			add_child(plume)
			plume.global_position = from
			wreck.plume = plume
	if soundscape != null:
		soundscape.call("boom", from)
	_wrecks.append(wreck)
	return wreck


## Where a falling dropship is `p` of the way down (0 hit, 1 down): it
## carries on across, dropping faster and faster.
static func wreck_point(from: Vector3, to: Vector3, p: float) -> Vector3:
	p = clampf(p, 0.0, 1.0)
	var flat := Vector3(from.x, 0.0, from.z).lerp(Vector3(to.x, 0.0, to.z), p * (1.6 - 0.6 * p))
	return Vector3(flat.x, lerpf(from.y, to.y, p * p), flat.z)


func _tick_wrecks(delta: float) -> void:
	for i in range(_wrecks.size() - 1, -1, -1):
		var wreck: Dictionary = _wrecks[i]
		wreck.t = float(wreck.t) + delta
		var p := float(wreck.t) / float(wreck.time)
		var plume: Variant = wreck.plume
		if not bool(wreck.down):
			var here := wreck_point(wreck.from, wreck.to, p)
			var ahead := wreck_point(wreck.from, wreck.to, p + 0.01) - here
			if wreck.node != null and ahead.length() > 0.01:
				var roll := float(wreck.spin) * pow(float(wreck.t), 1.4) * 0.35
				var basis := Basis.looking_at(ahead.normalized()) * Basis(Vector3.BACK, roll)
				(wreck.node as Node3D).global_transform = Transform3D(basis, here)
				for fire: Node in (wreck.node as Node3D).get_children():
					if fire.name.begins_with("Fire"):
						(fire as Node3D).scale = Vector3.ONE * _rng.randf_range(0.75, 1.25)
			if is_instance_valid(plume):
				(plume as Node3D).global_position = here
			if p >= 1.0:
				_crash(wreck)
			continue
		wreck.burning = float(wreck.burning) - delta
		var glow: Variant = wreck.get("glow")
		if is_instance_valid(glow):
			var left := clampf(float(wreck.burning) / WRECK_BURNS, 0.0, 1.0)
			(glow as Node3D).scale = Vector3.ONE * 70.0 * _rng.randf_range(0.85, 1.1)
			(glow as GeometryInstance3D).transparency = 1.0 - (0.35 + 0.4 * left) * (1.0 - Look.weather_cover)
		if is_instance_valid(plume) and float(wreck.burning) < 12.0:
			(plume as GPUParticles3D).emitting = false
		if float(wreck.burning) <= 0.0:
			if is_instance_valid(plume):
				(plume as Node).queue_free()
			if is_instance_valid(glow):
				(glow as Node).queue_free()
			_wrecks.remove_at(i)


func _crash(wreck: Dictionary) -> void:
	wreck.down = true
	var at: Vector3 = wreck.to
	if wreck.node != null:
		(wreck.node as Node3D).queue_free()
		wreck.node = null
	# It comes down behind the rim's crest, so the fireball rises well over
	# it and the wreck's fire glows on over the ridge while it burns.
	_flash(at + Vector3(0, 35, 0), 170.0, 1.4)
	for k in 3:
		_flash(at + Vector3(_rng.randf_range(-35, 35), _rng.randf_range(20, 60), _rng.randf_range(-35, 35)), 80.0, 0.9 + 0.35 * k)
	if Look.enabled:
		var glow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.material = Look.trim("flash")
		glow.mesh = quad
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.visibility_range_end = SKY_REACH
		add_child(glow)
		glow.global_position = at + Vector3(0, 30, 0)
		wreck.glow = glow
	if soundscape != null:
		soundscape.call("boom", at)


# --- Tracers and blasts -------------------------------------------------

## Sends a round from `from` to `to` in army `army`'s colour; one that
## `lands` throws up a flash and dust there and drops the extras by it.
func _fire(from: Vector3, to: Vector3, army: int, lands: bool) -> void:
	if _tracers.size() >= MAX_TRACERS:
		return
	var line := to - from
	var length := line.length()
	if length < 1.0:
		return
	_tracers.append({"from": from, "dir": line / length, "travel": 0.0, "reach": length,
			"colour": TRACER_COLOURS[army % 2], "lands": lands, "to": to})


func _tick_tracers(delta: float) -> void:
	for i in range(_tracers.size() - 1, -1, -1):
		var tracer: Dictionary = _tracers[i]
		tracer.travel = float(tracer.travel) + TRACER_SPEED * delta
		if float(tracer.travel) < float(tracer.reach):
			continue
		if bool(tracer.lands):
			_hit_ground(tracer.to)
		_tracers.remove_at(i)


func _hit_ground(at: Vector3) -> void:
	if _rng.randf() < 0.35:
		_flash(at + Vector3(0, 1.0, 0), _rng.randf_range(4.0, 7.0), 0.15)
	if _rng.randf() < 0.3:
		var puff := _free_slot(_dust_left)
		if puff >= 0:
			_dust[puff].position = at + Vector3(0, 1.5, 0)
			_dust[puff].visible = true
			_dust_left[puff] = 3.0
	if battle != null and _rng.randf() < 0.12:
		battle.call("shell_landed", at)


func _tick_sounds(delta: float) -> void:
	for i in range(_sounds.size() - 1, -1, -1):
		_sounds[i][0] -= delta
		if _sounds[i][0] <= 0.0:
			Sfx.play("far_fire", _sounds[i][1], _rng.randf_range(-6.0, -2.0), 600.0, 40.0)
			_sounds.remove_at(i)


func _ear() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.INF


func _ear_distance(at: Vector3) -> float:
	var ear := _ear()
	return ear.distance_to(at) if ear.is_finite() else 0.0


func _flash(at: Vector3, size: float, time: float) -> void:
	var slot := _free_slot(_flash_left)
	if slot < 0:
		return
	_flashes[slot].position = at
	_flashes[slot].scale = Vector3.ONE * size
	_flashes[slot].visible = true
	_flash_left[slot] = time
	_flash_time[slot] = time


func _free_slot(left: Array[float]) -> int:
	for i in left.size():
		if left[i] <= 0.0:
			return i
	return -1


func _fade(delta: float) -> void:
	var seen := 1.0 - Look.weather_cover
	for i in _flashes.size():
		if _flash_left[i] <= 0.0:
			continue
		_flash_left[i] -= delta
		var t := clampf(_flash_left[i] / _flash_time[i], 0.0, 1.0)
		_flashes[i].transparency = 1.0 - t * t * seen
		_flashes[i].visible = _flash_left[i] > 0.0
	for i in _dust.size():
		if _dust_left[i] <= 0.0:
			continue
		_dust_left[i] -= delta
		var age := 1.0 - clampf(_dust_left[i] / 3.0, 0.0, 1.0)
		_dust[i].scale = Vector3.ONE * lerpf(3.0, 9.0, sqrt(age))
		_dust[i].transparency = 1.0 - (1.0 - age) * 0.8 * seen
		_dust[i].visible = _dust_left[i] > 0.0


func _draw_tracers() -> void:
	if _tracer_mesh == null:
		return
	var seen := 1.0 - Look.weather_cover
	var n := 0
	for tracer in _tracers:
		if n >= MAX_TRACERS:
			break
		var dir: Vector3 = tracer.dir
		var travel := float(tracer.travel)
		var tail := maxf(0.0, travel - STREAK.z)
		var mid: Vector3 = (tracer.from as Vector3) + dir * (tail + travel) * 0.5
		var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
		basis = basis.scaled_local(Vector3(STREAK.x, STREAK.y, maxf(travel - tail, 0.5)))
		_tracer_mesh.set_instance_transform(n, Transform3D(basis, mid))
		var colour: Color = tracer.colour
		_tracer_mesh.set_instance_custom_data(n, Color(colour.r, colour.g, colour.b, TRACER_GLOW * seen))
		n += 1
	_tracer_mesh.visible_instance_count = n


# --- Building -----------------------------------------------------------

func _build_tracers() -> void:
	_tracer_mesh = MultiMesh.new()
	_tracer_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_tracer_mesh.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_tracer_mesh.mesh = box
	_tracer_mesh.instance_count = MAX_TRACERS
	_tracer_mesh.visible_instance_count = 0
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/tracer_streak.gdshader") as Shader
	var node := MultiMeshInstance3D.new()
	node.name = "Tracers"
	node.multimesh = _tracer_mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-1400, -100, -1400), Vector3(2800, 800, 2800))
	add_child(node)


func _quad(kind: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.material = Look.trim(kind)
	node.mesh = quad
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = SKY_REACH
	add_child(node)
	return node


func _craft(label: String) -> Node3D:
	var craft := Node3D.new()
	craft.name = label
	add_child(craft)
	return craft


func _box(size: Vector3, at: Vector3, parent: Node3D) -> void:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = _hull
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = SKY_REACH
	parent.add_child(node)


func _light(kind: String, size: float, at: Vector3, parent: Node3D, label := "") -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = Look.trim(kind)
	node.mesh = quad
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = SKY_REACH
	if label != "":
		node.name = label
	parent.add_child(node)
	return node


## A gunship, nose to -Z: a heavy hull on stub wings with an engine pod on
## each tip, a tail boom, and a gun under the chin.
func _build_gunship() -> Node3D:
	var ship := _craft("Gunship")
	_box(Vector3(5, 3.6, 15), Vector3.ZERO, ship)
	_box(Vector3(3.4, 2.4, 4), Vector3(0, -0.4, -9), ship)
	_box(Vector3(1.6, 1.6, 10), Vector3(0, 0.6, 12), ship)
	_box(Vector3(0.4, 4.2, 3), Vector3(0, 2.6, 16), ship)
	_box(Vector3(7, 0.4, 2.4), Vector3(0, 1.2, 16), ship)
	_box(Vector3(15, 0.6, 3.2), Vector3(0, 0.8, 1), ship)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(2.6, 2.6, 6.5), Vector3(side * 8.5, 0.8, 1), ship)
		_light("halo", 3.5, Vector3(side * 8.5, 0.8, 4.6), ship)
	_box(Vector3(0.6, 0.6, 3), Vector3(0, -2.2, -9.5), ship)
	_light("halo", 2.0, Vector3(0, -1, -11.2), ship)
	var muzzle := _light("flash", 4.5, Vector3(0, -2.2, -11.5), ship, "Muzzle")
	muzzle.visible = false
	return ship


## A fighter, nose to -Z: a slim fuselage on a swept wing, twin fins and a
## bright engine.
func _build_fighter() -> Node3D:
	var jet := _craft("Fighter")
	_box(Vector3(1.6, 1.3, 13), Vector3.ZERO, jet)
	_box(Vector3(11, 0.25, 4.5), Vector3(0, -0.1, 2.2), jet)
	_box(Vector3(4.6, 0.2, 2), Vector3(0, 0.1, 6), jet)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.2, 2.2, 2.2), Vector3(side * 1.2, 1.2, 5.6), jet)
	_light("flash", 4.0, Vector3(0, 0, 7.0), jet)
	_light("halo", 6.0, Vector3(0, 0, 7.6), jet)
	return jet


## A dropship like the capital ship's (`giants.gd`), already burning.
func _build_dropship() -> Node3D:
	var ship := _craft("Wreck")
	_box(Vector3(8, 5, 26), Vector3.ZERO, ship)
	_box(Vector3(28, 1.2, 9), Vector3(0, 0.5, 3), ship)
	_box(Vector3(5, 3, 8), Vector3(0, 3.5, 6), ship)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(3.5, 3.5, 9), Vector3(side * 12, 0, 5), ship)
	_light("flash", 16.0, Vector3(12, 1, 8), ship, "Fire1")
	_light("flash", 11.0, Vector3(-3, 3, -4), ship, "Fire2")
	_light("flash", 8.0, Vector3(-12, 0, 4), ship, "Fire3")
	return ship
