extends RefCounted
## Checks for the enemy AI pass's foundations: smoke hides people from bots
## as it hides them from eyes (`Smoke`, `Raid.smoke`, a shell's column), a
## world can give a kind its own senses (metas "sight", "fov", "reach",
## "far_notice" read by `BotBrain`), and Frostline's factions build for the
## duel bench. Kept in its own file and called from the test runner.

const KIT: Array[String] = ["rifle_scrap", "blade_scrap"]


static func run(t: Node) -> void:
	_smoke_shape(t)
	await _smoke_hides(t)


static func _smoke_shape(t: Node) -> void:
	print("Enemy AI: smoke")
	var smoke := Smoke.new()
	smoke.add(Vector3.ZERO, 6.0, 14.0, 13.0)
	smoke.tick(3.0)
	t.check(smoke.blocks(Vector3(-20, 1.6, 0), Vector3(20, 1.4, 0)), "a line through a cloud is hidden")
	t.check(not smoke.blocks(Vector3(-20, 1.6, 15), Vector3(20, 1.4, 15)), "a line beside it is not")
	t.check(not smoke.blocks(Vector3(-20, 30, 0), Vector3(20, 30, 0)), "nor one over its top")
	t.check(not smoke.blocks(Vector3(-2, 1.6, 0), Vector3(2, 1.4, 0)),
			"two people inside one, close up, still make each other out")
	smoke.tick(11.0)
	t.check(smoke.clouds.is_empty() and not smoke.blocks(Vector3(-20, 1.6, 0), Vector3(20, 1.4, 0)),
			"and once it has blown away, nothing is hidden")
	t.check(is_equal_approx(Smoke.segment_gap(Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(5, -1, 3), Vector3(5, 1, 3)), 3.0),
			"the gap between two lines is measured right")


static func _smoke_hides(t: Node) -> void:
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(Worlds.get_world("ashfront"), 71)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(600, 0, 600)
	var me := raid.add_player(KIT, {}, "Walker", "walker")
	await t.frames(3)
	var spot := raid._stand(Vector3(-150, 0, 40))
	me.global_position = spot
	me.protected_left = 0.0
	# Open ground with nothing between: try a few bearings until the line is clear.
	var space := me.get_world_3d().direct_space_state
	var chest := me.global_position + Vector3(0, me.body_height() * 0.6, 0)
	var from := Vector3.ZERO
	for i in 16:
		var at := raid._stand(spot + Vector3(sin(i * TAU / 16.0), 0, cos(i * TAU / 16.0)) * 22.0)
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.6, 0), chest, Actor.LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			from = at
			break
	var bot := raid.spawn_bot("Looker", from, 5, false, "legion", 1)
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.seed_value = 5
	bot.add_child(brain)
	brain.set_physics_process(false)
	var to := me.global_position - bot.global_position
	bot.cmd.yaw = atan2(-to.x, -to.z)
	await t.frames(2)
	t.check(brain._find_target() == me, "a bot sees a player in the open")
	raid.shelling.land(raid, (spot + from) * 0.5)
	t.check(raid.smoke.clouds.size() == 1, "a shell that lands leaves a column of smoke")
	t.check(brain._find_target() == null, "and the bot cannot see the player through it")
	raid.smoke.clear()
	t.check(brain._find_target() == me, "once it clears, it can again")
	# Senses a world gives a kind.
	var eyed := raid.spawn_bot("Eyed", raid._stand(spot + Vector3(30, 0, 0)), 6, false, "legion", 1)
	eyed.set_meta("sight", 72.0)
	eyed.set_meta("fov", 90.0)
	eyed.set_meta("reach", 60.0)
	eyed.set_meta("far_notice", 2.2)
	var sharp := BotBrain.new()
	sharp.name = "Brain"
	eyed.add_child(sharp)
	t.check(sharp.sight_range == 72.0 and sharp.fov_deg == 90.0 and sharp.attack_range == 60.0
			and sharp.far_notice_mult == 2.2, "a world can give a kind its own senses")
	t.check(brain.sight_range == 38.0, "and a kind it gives none keeps the usual")
	raid.queue_free()
	await t.frames(2)
	# Frostline's factions build from their markers, for the duel bench.
	var frost := Raid.new()
	t.add_child(frost)
	frost.start_server(Worlds.get_world("frostline"), 72)
	var warden := frost.spawn_bot("W", Vector3(0, 40, 0), 3, false, "warden", 0)
	var feral := frost.spawn_bot("F", Vector3(5, 40, 0), 4, false, "feral", 2)
	t.check(warden.faction == "warden" and warden.get_active_weapon() is Gun, "a Warden marker builds a Warden")
	t.check(feral.faction == "feral" and feral.get_active_weapon() is MeleeWeapon, "a Feral den builds a Feral")
	frost.queue_free()
	await t.frames(2)
