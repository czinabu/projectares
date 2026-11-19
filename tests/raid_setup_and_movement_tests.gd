extends RefCounted
## The `raid_setup_and_movement` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Raid setup and movement")
	var raid: Raid = await t._new_raid(42, false)
	var p := raid.player
	t.check(p != null and p.is_player, "player spawns")
	t.check(raid.bots.size() == raid.world.bot_count + raid._bosses.size() + raid._guards.size(), "all bots spawn")
	t.check(raid.depots.size() >= 2, "map provides depots to bank at")
	var caches := raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer)
	t.check(caches.size() >= 8, "loot caches are placed (%d)" % caches.size())
	t.check(p.weapons.size() == 3 and p.flight.enabled and p.health.armor == 30.0,
			"starter loadout is equipped")

	await t.frames(40)
	t.check(p.is_on_floor(), "player lands on the ground")

	var start := p.global_position
	p.cmd.yaw = 0.0
	p.cmd.move = Vector2(0, 1)
	await t.frames(30)
	p.cmd.move = Vector2.ZERO
	t.check(p.global_position.distance_to(start) > 1.0, "player walks")

	var ground_y := p.global_position.y
	p.cmd.jump_pressed = true
	p.cmd.jump = true
	await t.frames(1)
	p.cmd.jump_pressed = false
	await t.frames(50)
	t.check(p.global_position.y > ground_y + 3.0, "holding jump flies with the jetpack")
	t.check(p.flight.heat > 0.0, "flying builds heat")
	p.cmd.jump = false
	for i in 300:
		await t.get_tree().physics_frame
		if p.is_on_floor():
			break
	t.check(p.is_on_floor(), "player comes back down")
	await t._check_slide(p)
	await t._check_crouch(p)
	await t._end_raid(raid)


## Sliding: only from a fast run on the ground, skids from a burst down to a
## crawl, drops the eyes, and a jump ends it. Checked on the movement step
## itself, then once through the physics loop.
