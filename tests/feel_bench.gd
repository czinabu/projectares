extends Node
## Measures how movement feels in numbers: flies and runs each rig through set
## moves on flat ground and prints how long each takes to answer, and the
## hardest jolt (the biggest change of velocity in one tick, as m/s²) with
## the move it came in. A jolt far above the rig's own accelerations is a
## snap the player feels as a hitch.
##
##   godot --headless --fixed-fps 60 --path . res://tests/feel_bench.tscn

const RIGS: Array[String] = ["jetpack_mk1", "jetpack_mk2", "wings_glide", "boots_thruster"]

var _actor: Actor
var _last_velocity := Vector3.ZERO
## The hardest jolt in each move: move name -> m/s².
var _jolts := {}
var _move := ""


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(3000, 1, 3000)
	var col := CollisionShape3D.new()
	col.shape = shape
	ground.add_child(col)
	ground.position.y = -0.5
	add_child(ground)
	await _ground()
	for rig in RIGS:
		await _fly(rig)
	get_tree().quit(0)


func _spawn(kit: Array) -> Actor:
	if _actor != null:
		_actor.queue_free()
	_actor = Actor.new()
	add_child(_actor)
	Loadout.equip(_actor, kit)
	_actor.position = Vector3(0, 0.05, 0)
	_last_velocity = Vector3.ZERO
	_jolts.clear()
	return _actor


## The three hardest jolts and the moves they came in.
func _hardest() -> String:
	var moves: Array = _jolts.keys()
	moves.sort_custom(func(a: String, b: String) -> bool: return _jolts[a] > _jolts[b])
	var out: Array[String] = []
	for move: String in moves.slice(0, 3):
		out.append("%s %.0f" % [move, _jolts[move]])
	return ", ".join(out)


## Runs `count` ticks of the move called `move`, tracking the hardest jolt.
func _ticks(count: int, move := "") -> void:
	if move != "":
		_move = move
	for i in count:
		await get_tree().physics_frame
		var change := (_actor.velocity - _last_velocity).length() * Engine.physics_ticks_per_second
		# Bursts, pulses, dashes and jumps are meant to be instant.
		if not _move.begins_with("!"):
			_jolts[_move] = maxf(change, _jolts.get(_move, 0.0))
		_last_velocity = _actor.velocity


func _press_jump() -> void:
	_actor.cmd.jump_pressed = true
	await _ticks(1, "!jump")
	_actor.cmd.jump_pressed = false


func _flat_speed() -> float:
	return Vector2(_actor.velocity.x, _actor.velocity.z).length()


## Ticks until `done` is true, up to `limit`. Returns the seconds it took.
func _until(done: Callable, limit: int, move: String) -> float:
	for i in limit:
		if done.call():
			return float(i) / Engine.physics_ticks_per_second
		await _ticks(1, move)
	return -1.0


func _ground() -> void:
	var a := _spawn(["rifle_scrap"])
	await _ticks(20, "!settle")
	a.cmd.move = Vector2(0, 1)
	a.cmd.sprint = true
	var up := await _until(func() -> bool: return _flat_speed() > a.sprint_speed * 0.95, 200, "start sprinting")
	await _ticks(30)
	var from := a.global_position
	a.cmd.move = Vector2.ZERO
	var stop := await _until(func() -> bool: return _flat_speed() < 0.3, 200, "stop")
	var stop_dist := a.global_position.distance_to(from)
	a.cmd.move = Vector2(0, 1)
	await _ticks(40, "sprint")
	a.cmd.move = Vector2(1, 0)
	a.cmd.sprint = false
	var turn := await _until(func() -> bool: return (a.global_basis.inverse() * a.velocity).x > a.walk_speed * 0.95 \
			and absf((a.global_basis.inverse() * a.velocity).z) < 0.3, 200, "cut sideways")
	a.cmd.move = Vector2(0, 1)
	a.cmd.sprint = true
	await _ticks(40, "sprint")
	await _press_jump()
	var air_from := a.global_position
	var air := await _until(func() -> bool: return a.is_on_floor(), 200, "!jump")
	var air_dist := a.global_position.distance_to(air_from)
	a.cmd.move = Vector2.ZERO
	a.cmd.sprint = false
	await _ticks(20, "stop")
	print("On foot: sprint in %.2f s, stops in %.2f s over %.1f m, cuts sideways in %.2f s, a running jump lasts %.2f s and carries %.1f m. Hardest jolts (m/s²): %s"
			% [up, stop, stop_dist, turn, air, air_dist, _hardest()])


func _fly(rig: String) -> void:
	var a := _spawn(["rifle_scrap", rig])
	var f := a.flight
	await _ticks(20, "!settle")
	var notes: Array[String] = []
	if f.can_hover():
		a.global_position.y = 60.0
		a.velocity = Vector3.ZERO
		await _ticks(3, "!lift")
		await _press_jump()
		await _ticks(30, "light the jets")
		a.cmd.move = Vector2(0, 1)
		var up := await _until(func() -> bool: return _flat_speed() > f.fly_speed * 0.95, 300, "cruise off")
		await _ticks(30, "cruise")
		var from := a.global_position
		a.cmd.move = Vector2.ZERO
		var stop := await _until(func() -> bool: return _flat_speed() < 0.3, 300, "stop dead")
		notes.append("cruise in %.2f s, stops in %.2f s over %.1f m" % [up, stop, a.global_position.distance_to(from)])
		a.cmd.move = Vector2(0, 1)
		await _ticks(90, "cruise")
		a.cmd.move = Vector2(1, 0)
		var heading := func() -> float: return (a.global_basis.inverse() * a.velocity).normalized().x
		var turn := await _until(func() -> bool: return heading.call() > 0.99, 600, "quarter turn")
		notes.append("a quarter turn at cruise takes %.2f s" % turn)
		a.cmd.move = Vector2(-1, 0)
		var back := await _until(func() -> bool: return heading.call() < -0.99 and _flat_speed() > f.fly_speed * 0.95, 600, "reverse")
		notes.append("reversing takes %.2f s" % back)
		a.cmd.move = Vector2.ZERO
		await _ticks(60, "stop dead")
		a.cmd.jump = true
		var climb := await _until(func() -> bool: return a.velocity.y > f.max_rise_speed * 0.95, 300, "climb")
		a.cmd.jump = false
		var level := await _until(func() -> bool: return absf(a.velocity.y) < 0.2, 300, "level off")
		a.cmd.descend = true
		var sink := await _until(func() -> bool: return a.velocity.y < -f.descend_speed * 0.95, 300, "coast down")
		a.cmd.descend = false
		await _ticks(40, "level off")
		notes.append("climbs in %.2f s, levels in %.2f s, sinks in %.2f s" % [climb, level, sink])
		if f.boost_speed > 0.0:
			a.cmd.move = Vector2(0, 1)
			await _ticks(60, "cruise")
			f.heat = 0.0
			a.cmd.sprint = true
			var boost := await _until(func() -> bool: return _flat_speed() > f.boost_speed * 0.95, 300, "boost")
			a.cmd.sprint = false
			var ease := await _until(func() -> bool: return _flat_speed() < f.fly_speed * 1.05, 300, "end boost")
			notes.append("boost in %.2f s, back to cruise in %.2f s" % [boost, ease])
			a.cmd.move = Vector2.ZERO
	if f.can_glide():
		a.global_position.y = 400.0
		a.velocity = Vector3(0, -1, 0)
		await _ticks(3, "!lift")
		a.cmd.jump = true
		var up := await _until(func() -> bool: return _flat_speed() > f.glide_speed * 0.95, 300, "wings bite")
		await _ticks(60, "glide")
		a.cmd.move = Vector2(1, 0)
		var before := Vector3(a.velocity.x, 0, a.velocity.z).normalized()
		var turn := await _until(func() -> bool: return before.dot(Vector3(a.velocity.x, 0, a.velocity.z).normalized()) < 0.0, 300, "bank")
		a.cmd.move = Vector2.ZERO
		await _ticks(30, "level the wings")
		a.cmd.move = Vector2(0, 1)
		var dive := await _until(func() -> bool: return a.velocity.y < -f.glide_dive_fall * 0.95, 300, "dive")
		await _ticks(120, "dive")
		var top := _flat_speed()
		a.cmd.move = Vector2.ZERO
		await _ticks(40, "level out of a dive")
		a.cmd.move = Vector2(0, 1)
		await _ticks(120, "dive")
		a.cmd.move = Vector2(0, -1)
		var low := a.global_position.y
		await _until(func() -> bool: return a.velocity.y <= 0.0 and a.global_position.y > low + 1.0, 600, "pull up")
		var gained := a.global_position.y - low
		a.cmd.move = Vector2.ZERO
		await _ticks(90, "glide")
		f.heat = 0.0
		await _press_jump()
		await _ticks(60, "after a pulse")
		a.cmd.move = Vector2(0, -1)
		await _ticks(240, "hold back to the stall")
		a.cmd.move = Vector2.ZERO
		await _ticks(120, "recover from the stall")
		notes.append("wings bite in %.2f s, a quarter turn takes %.2f s, a dive sets in over %.2f s and tops out at %.1f m/s, pulling up from it gains %.1f m"
				% [up, turn, dive, top, gained])
		a.cmd.jump = false
	if f.can_skim():
		a.global_position.y = 3.0
		a.velocity = Vector3.ZERO
		await _ticks(3, "!lift")
		a.cmd.jump = true
		await _ticks(30, "start a skim")
		a.cmd.move = Vector2(0, 1)
		var up := await _until(func() -> bool: return _flat_speed() > f.skim_speed * 0.95, 300, "skim off")
		await _ticks(30, "skim")
		var from := a.global_position
		a.cmd.move = Vector2.ZERO
		var stop := await _until(func() -> bool: return _flat_speed() < 0.3, 300, "stop dead")
		var stop_dist := a.global_position.distance_to(from)
		a.cmd.move = Vector2(0, 1)
		await _ticks(40, "skim")
		a.cmd.move = Vector2(1, 0)
		var cut := await _until(func() -> bool: return (a.global_basis.inverse() * a.velocity).x > f.skim_speed * 0.95 \
				and absf((a.global_basis.inverse() * a.velocity).z) < 0.5, 300, "cut sideways")
		a.cmd.move = Vector2.ZERO
		await _ticks(30, "stop dead")
		f.heat = 0.0
		var height := a.global_position.y
		await _press_jump()
		await _until(func() -> bool: return a.velocity.y <= 0.0, 300, "after a kick")
		var kick := a.global_position.y - height
		await _ticks(30, "hold height")
		a.cmd.descend = true
		await _ticks(20, "sink")
		a.cmd.descend = false
		await _ticks(20, "hold height")
		a.cmd.jump = false
		notes.append("skims in %.2f s, stops in %.2f s over %.1f m, cuts sideways in %.2f s, a kick lifts %.1f m" % [up, stop, stop_dist, cut, kick])
	print("%s: %s. Hardest jolts (m/s²): %s" % [f.display_name, ", ".join(notes), _hardest()])
