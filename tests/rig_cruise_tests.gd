extends RefCounted
## Checks for the rigs' cruises (Caleb's call: every rig has its own
## sustained forward flight, DESIGN.md "Cruising"): the jetpack's rocket
## cruise (its boost, level at 16 m/s on a little heat), the boots' skate
## (low over whatever is below at 18 m/s, for nothing) and the wings' soar
## (level at glide speed on glide stamina, climbing slowly when pulled up).
## Run from the main test runner. Nothing here starts a server.


static func run(t: Node) -> void:
	print("Rig cruises")
	await _jetpack(t)
	await _boots(t)
	await _wings(t)


## A flat floor `size` wide at `at`, with a step `step` high from `step_z`
## on (0: none).
static func _arena(t: Node, at: Vector3, step := 0.0, step_z := -60.0) -> Node3D:
	var arena := Node3D.new()
	t.add_child(arena)
	arena.position = at
	for part: Array in [[Vector3(80, 1, 600), Vector3(0, -0.5, -280.0)], [Vector3(80, step, 100), Vector3(0, step * 0.5, step_z - 50.0)]]:
		var size: Vector3 = part[0]
		if size.y <= 0.0:
			continue
		var ground := StaticBody3D.new()
		ground.collision_layer = Actor.LAYER_WORLD
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		ground.add_child(col)
		ground.position = part[1]
		arena.add_child(ground)
	return arena


static func _actor(arena: Node3D, kit: Array) -> Actor:
	var actor := Actor.new()
	arena.add_child(actor)
	Loadout.equip(actor, ["pistol_service"] + kit)
	actor.position = Vector3(0, 0.05, 0)
	actor.ground_map = arena
	return actor


static func _flat_speed(p: Actor) -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()


## The jetpack's cruise is its boost: level along the view at 16 m/s, on
## 0.18x the hover's heat.
static func _jetpack(t: Node) -> void:
	var arena := _arena(t, Vector3(0, 0, 12000))
	var p := _actor(arena, ["jetpack_mk1"])
	var f := p.flight
	await t.frames(5)
	p.global_position.y = 20.0
	p.velocity = Vector3.ZERO
	await t.frames(2)
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	p.cmd.sprint_pressed = true
	await t.frames(1)
	p.cmd.sprint_pressed = false
	await t.frames(120)
	var y := p.global_position.y
	var heat := f.heat
	await t.frames(120)
	t.check(f.is_boosting and absf(_flat_speed(p) - 16.0) < 0.3 and absf(p.global_position.y - y) < 0.3,
			"the jetpack cruises level at 16 m/s on held Shift (%.1f m/s)" % _flat_speed(p))
	var rate := (f.heat - heat) / 2.0
	t.check(absf(rate - f.heat_per_sec * f.boost_heat_mult) < 0.2,
			"a cruise costs %.2f heat a second, a bar in about 45 s" % rate)
	p.cmd = ActorCommand.new()
	arena.queue_free()
	await t.frames(2)


## Boots skate: held Shift in the air flies them `skate_height` over what is
## below at 18 m/s, up a step and on, steady to aim from, until back is held.
static func _boots(t: Node) -> void:
	var arena := _arena(t, Vector3(300, 0, 12000), 1.5, -80.0)
	var p := _actor(arena, ["boots_thruster"])
	var f := p.flight
	await t.frames(5)
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	await t.frames(30)
	t.check(not f.is_skating, "sprinting on the ground is only a sprint")
	p.cmd.jump_pressed = true
	await t.frames(1)
	p.cmd.jump_pressed = false
	await t.frames(150)
	var height := p.height_above_ground(10.0)
	t.check(f.is_skating and absf(_flat_speed(p) - f.skate_speed) < 0.5 and absf(height - f.skate_height) < 0.3,
			"a sprinting jump goes into a skate %.1f m up at %.1f m/s" % [height, _flat_speed(p)])
	t.check(p.air_aim() == f.flight_aim and f.flight_aim == 0.0, "skating is as steady to aim from as a boots dash")
	var charges := f.charges
	# On past the step: it rides up over it and keeps its height.
	var past := await _until(t, func() -> bool: return p.global_position.z - arena.global_position.z < -95.0, 10.0)
	height = p.height_above_ground(10.0)
	t.check(past < INF and f.is_skating and p.global_position.y > 1.5 + f.skate_height - 0.4,
			"it rides up a step and on over it (%.1f m over the top)" % height)
	t.check(f.charges >= charges, "a skate costs no charges")
	# A kick hops off it; back down in reach, the skate goes on.
	p.cmd.jump_pressed = true
	await t.frames(1)
	p.cmd.jump_pressed = false
	await t.frames(20)
	var hopped := p.height_above_ground(20.0)
	var back := await _until(t, func() -> bool: return f.is_skating and absf(p.height_above_ground(10.0) - f.skate_height) < 0.4, 5.0)
	t.check(hopped > f.skate_reach and back < INF, "a kick hops %.1f m off the skate and it picks up again" % hopped)
	p.cmd.move = Vector2(0, -1)
	await t.frames(2)
	t.check(not f.is_skating, "holding back brakes out of it")
	p.cmd = ActorCommand.new()
	arena.queue_free()
	await t.frames(2)


## Wings soar: held Shift in a glide holds them level at glide speed on glide
## stamina, and a pull up climbs at `soar_climb` at most; let go, they glide
## down again.
static func _wings(t: Node) -> void:
	var arena := _arena(t, Vector3(600, 0, 12000))
	var p := _actor(arena, ["wings_glide"])
	var f := p.flight
	await t.frames(5)
	p.global_position.y = 15.0
	p.velocity = Vector3(0, -1, -22)
	p.cmd.jump = true
	await t.frames(30)
	t.check(f.is_gliding, "the wings glide")
	p.cmd.sprint = true
	await t.frames(60)
	p.cmd.jump = false
	var y := p.global_position.y
	var heat := f.heat
	await t.frames(180)
	t.check(f.is_soaring and f.is_gliding and absf(p.global_position.y - y) < 0.5 and absf(_flat_speed(p) - 22.0) < 0.5,
			"held Shift soars level at 22 m/s, jump let go (%.1f m/s, %.1f m)" % [_flat_speed(p), p.global_position.y - y])
	var rate := (f.heat - heat) / 3.0
	t.check(absf(rate - f.glide_heat) < 0.1, "a soar spends glide stamina, %.1f a second, a bar in about 62 s" % rate)
	p.cmd.move = Vector2(0, -1)
	await t.frames(30)
	y = p.global_position.y
	await t.frames(60)
	var climb := p.global_position.y - y
	t.check(climb > 1.0 and climb <= f.soar_climb + 0.2 and _flat_speed(p) > 22.0 * f.glide_stall,
			"pulled up, it climbs %.1f m in a second and keeps flying" % climb)
	p.cmd.move = Vector2.ZERO
	p.cmd.sprint = false
	p.cmd.jump = true
	await t.frames(30)
	y = p.global_position.y
	await t.frames(60)
	t.check(not f.is_soaring and p.global_position.y < y - 0.5, "without Shift the wings glide down again")
	p.cmd = ActorCommand.new()
	arena.queue_free()
	await t.frames(2)


## Ticks until `done` is true (at most `limit` seconds); returns the seconds.
static func _until(t: Node, done: Callable, limit: float) -> float:
	var tps := Engine.physics_ticks_per_second
	for i in int(limit * tps):
		await t.get_tree().physics_frame
		if done.call():
			return float(i + 1) / tps
	return INF
