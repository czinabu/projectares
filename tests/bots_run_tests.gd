extends RefCounted
## The `bots_run` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Bot AI")
	var raid: Raid = await t._new_raid(47, true)
	var starts := {}
	for bot in raid.bots:
		starts[bot] = bot.global_position
	# Bring one bot face to face with the player to exercise the fight logic.
	var p := raid.player
	await t.frames(40)
	var bot := raid.bots[0]
	var arena: Vector3 = t._open_ground(raid)
	p.global_position = Vector3(arena.x, arena.y - 1.9, arena.z + 3.0)
	bot.global_position = Vector3(arena.x, arena.y - 1.9, arena.z - 5.0)
	var health_before := p.health.health + p.health.armor
	await t.frames(360)
	var moved := 0
	for b: Actor in starts:
		if is_instance_valid(b) and b.global_position.distance_to(starts[b]) > 1.5:
			moved += 1
	t.check(moved >= 3, "bots patrol (%d moved)" % moved)
	t.check(p.health.health + p.health.armor < health_before, "a bot that sees the player attacks")
	await t._end_raid(raid)
