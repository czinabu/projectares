extends RefCounted
## Third person never shows more than the eyes see (Caleb's call): a hostile
## body the eyes have no line to fades out of the third-person view where
## gear is at stake (`PlayerController.PeekFade`). View only.


static func run(t: Node) -> void:
	print("Third-person peek")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 47)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(10)
	var p := raid.player
	p.set_physics_process(false)
	var foe := raid.bots[0]
	foe.set_physics_process(false)
	# Clear ground of our own, far from the map.
	var at := Vector3(0, 400, -4000)
	var floor := _box(raid, Vector3(200, 1, 200), at - Vector3(0, 0.5, 0))
	for bot in raid.bots:
		if bot != foe:
			bot.global_position = at + Vector3(randf_range(-80, 80), 0, 95)
	p.global_position = at
	foe.global_position = at + Vector3(0, 0, -12)
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	controller.set_physics_process(false)
	controller.view_mode = PlayerController.ViewMode.THIRD
	controller.yaw = 0.0
	controller.pitch = 0.0
	await t.frames(20)
	var fade := controller.peek_fade
	t.check(controller.peek_rule_applies(), "the rule applies out in a world where gear is at stake")
	var space := p.get_world_3d().direct_space_state
	t.check(PlayerController.PeekFade.seen_from(space, p.get_eye_position(), foe) and fade.drawn(foe) == 1.0,
			"a foe in plain sight is drawn")

	# A wall between the eyes and the foe: the third-person view loses it.
	var wall := _box(raid, Vector3(6, 4, 0.3), at + Vector3(0, 2, -6))
	await t.frames(45)
	t.check(not PlayerController.PeekFade.seen_from(space, p.get_eye_position(), foe),
			"a wall hides all of the foe from the eyes")
	t.check(fade.drawn(foe) < 0.05, "third person does not draw a foe the eyes cannot see (%.2f)" % fade.drawn(foe))
	# First person draws whatever its camera sees: the rule is left alone.
	controller.view_mode = PlayerController.ViewMode.FIRST
	await t.frames(45)
	t.check(fade.drawn(foe) == 1.0, "first person is left alone")
	controller.view_mode = PlayerController.ViewMode.THIRD
	await t.frames(45)
	t.check(fade.drawn(foe) < 0.05, "back in third person it fades again")

	# Low cover: the head shows over it, so the foe stays drawn.
	wall.queue_free()
	var low := _box(raid, Vector3(6, 1.0, 0.3), at + Vector3(0, 0.5, -6))
	await t.frames(45)
	t.check(PlayerController.PeekFade.seen_from(space, p.get_eye_position(), foe) and fade.drawn(foe) > 0.95,
			"a head over low cover is seen, and the foe is drawn")
	low.queue_free()

	# A dead foe is never faded.
	var wall2 := _box(raid, Vector3(6, 4, 0.3), at + Vector3(0, 2, -6))
	await t.frames(45)
	t.check(fade.drawn(foe) < 0.05, "hidden again behind a wall")
	foe.health.health = 0.0
	foe.is_dead = true
	await t.frames(30)
	t.check(fade.drawn(foe) == 1.0, "a body on the ground is drawn")
	wall2.queue_free()
	floor.queue_free()
	controller.queue_free()
	raid.queue_free()
	await t.frames(2)


static func _box(parent: Node, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	body.global_position = at
	return body
