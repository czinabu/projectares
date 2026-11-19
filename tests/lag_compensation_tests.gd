extends RefCounted
## The `lag_compensation` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Lag compensation: hits are tested where the attacker saw the target")
	var arena: Node3D = t._vehicle_arena()
	var shooter := Actor.new()
	arena.add_child(shooter)
	shooter.global_position = arena.global_position
	var target := Actor.new()
	arena.add_child(target)
	target.global_position = arena.global_position + Vector3(0, 0, -8)
	Loadout.equip(shooter, ["rifle_scrap"])
	await t.frames(5)
	var eye := shooter.get_eye_position()
	var chest := Vector3(0, 1.1, 0)
	var now: Vector3 = target.global_position
	var then: Vector3 = now + Vector3(3, 0, 0)
	var hit := Combat.trace(shooter, eye, eye + (now + chest - eye) * 3.0)
	t.check(hit.get("collider") == target, "with nothing to make up, a shot hits where the target is")
	t.check(Combat.positions_seen_by(shooter).is_empty(), "offline nothing is rewound")

	# What a lagging shooter saw: the target three metres to the side.
	Combat.rewind = func(attacker: Actor) -> Dictionary:
		return {target: then} if attacker == shooter else {}
	hit = Combat.trace(shooter, eye, eye + (now + chest - eye) * 3.0)
	t.check(hit.get("collider") != target, "a rewound target is not hit where it has moved on to")
	hit = Combat.trace(shooter, eye, eye + (then + chest - eye) * 3.0)
	t.check(hit.get("collider") == target and hit.position.distance_to(then + chest) < 0.5,
			"a rewound target is hit where the shooter saw it")
	hit = Combat.trace(target, target.get_eye_position(), shooter.global_position + chest)
	t.check(hit.get("collider") == shooter, "anyone without a rewind shoots at the present")
	hit = Combat.trace(shooter, eye, eye + Vector3(0, 0, -1) * 20.0 + Vector3(0, 10, 0))
	t.check(hit.is_empty() or hit.get("collider") is not Actor, "a shot over everyone's head hits nobody")

	# Walls still stop the shot.
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(2, 4, 0.4)
	var wall_col := CollisionShape3D.new()
	wall_col.shape = wall_shape
	wall.add_child(wall_col)
	arena.add_child(wall)
	wall.global_position = arena.global_position.lerp(then, 0.5) + Vector3(0, 1, 0)
	await t.frames(2)
	hit = Combat.trace(shooter, eye, eye + (then + chest - eye) * 3.0)
	t.check(hit.get("collider") == wall, "a wall in front of where the target was still stops the shot")
	wall.queue_free()
	await t.frames(2)

	# The gun uses it.
	var before := target.health.health + target.health.armor
	var dir := (then + chest - eye).normalized()
	shooter.cmd.aim_dir = dir
	shooter.cmd.yaw = t._yaw_toward(dir)
	shooter.cmd.primary = true
	await t.frames(1)
	shooter.cmd.primary = false
	t.check(target.health.health + target.health.armor < before, "a rifle shot at where the target was seen lands")

	# Every attacker has their own view of the others.
	var seen_close := now + Vector3(0, 0, 6.5)
	Combat.rewind = func(attacker: Actor) -> Dictionary:
		return {target: seen_close} if attacker == shooter else {}
	t.check(Combat.positions_seen_by(shooter).get(target) == seen_close and Combat.positions_seen_by(target).is_empty(),
			"each attacker gets their own view of the others")
	Combat.rewind = Callable()
	t.check(Combat.positions_seen_by(shooter).is_empty(), "clearing the rewind goes back to the present")
	arena.queue_free()
	await t.frames(2)
