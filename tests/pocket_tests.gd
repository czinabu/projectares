extends RefCounted
## Encounter pockets (`WorldDef.pocket_wake`, `Raid._tick_pockets`):
## Frostline's guards stand only near a player, sleep when nobody is near,
## come back whole on waking, stay cleared for `guard_respawn_time` once
## killed, and the enemy budget counts only the pockets awake.


static func run(t: Node) -> void:
	print("Encounter pockets")
	var world := Worlds.get_world("frostline")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(world, 7)
	# The raid's own tick is stopped: time is stepped by hand below.
	raid.set_physics_process(false)
	var markers := raid._map_nodes("spawn_guard")
	t.check(raid.pockets_on() and raid.army_size() == 0 and markers.size() > 20,
			"Frostline is pockets only: %d guard spots, no army" % markers.size())
	t.check(raid.bots.size() < markers.size(),
			"only the pockets near the player stand at the start (%d of %d)" % [raid.bots.size(), markers.size()])
	for guard: Dictionary in raid._guards:
		var bot: Variant = guard.bot
		if bot == null:
			continue
		var near := INF
		for m: Node3D in markers:
			if m.global_position.distance_to((bot as Actor).global_position) < 20.0:
				near = minf(near, raid.player.global_position.distance_to(m.global_position))
		t.check(near <= world.pocket_wake + 30.0, "a standing guard is near the player (%.0f m)" % near)
	# Pick a den well away from the start.
	var den: Node3D = null
	for m: Node3D in markers:
		if str(m.get_meta("pocket", "")).begins_with("den") \
				and m.global_position.distance_to(raid.player.global_position) > world.pocket_wake + 80.0:
			den = m
			break
	t.check(den != null, "there is a den out of the player's wake range")
	if den == null:
		await t._end_raid(raid)
		return
	var key: String = den.get_meta("pocket")
	var pocket: Dictionary = raid._pockets[key]
	t.check(not pocket.awake, "a far den sleeps")
	# Walk up to it: it wakes, all three of its Ferals standing.
	raid.player.global_position = den.global_position + Vector3(world.pocket_wake - 20.0, 1, 0)
	raid._tick_guards(Raid.POCKET_EVERY)
	var pack := _standing(raid, pocket)
	t.check(pocket.awake and pack.size() == (pocket.guards as Array).size() and pack.size() == 3,
			"walking up wakes the den with its whole pack (%d)" % pack.size())
	# Leave: a while later it sleeps, quietly.
	var before := raid.bots.size()
	raid.player.global_position = den.global_position + Vector3(world.pocket_wake + Raid.POCKET_SLEEP_MARGIN + 60.0, 1, 0)
	var bags := _bags(raid)
	for i in ceili(Raid.POCKET_SLEEP_AFTER / Raid.POCKET_EVERY) + 2:
		raid._tick_guards(Raid.POCKET_EVERY)
	await t.frames(2)
	t.check(not pocket.awake and _standing(raid, pocket).is_empty() and raid.bots.size() <= before - 3,
			"nobody near for %.0f s: the den sleeps and its pack goes" % Raid.POCKET_SLEEP_AFTER)
	t.check(_bags(raid) == bags, "a pocket going to sleep leaves no bodies or loot")
	# Back again: whole.
	raid.player.global_position = den.global_position + Vector3(world.pocket_wake - 20.0, 1, 0)
	raid._tick_guards(Raid.POCKET_EVERY)
	pack = _standing(raid, pocket)
	t.check(pack.size() == 3 and pack.all(func(b: Actor) -> bool: return b.health.health >= b.health.max_health),
			"it wakes again with its whole pack, unhurt")
	# Hurt in a fight: it does not sleep while one of them has a target.
	var brain := pack[0].get_node("Brain") as BotBrain
	brain.target = raid.player
	raid.player.global_position = den.global_position + Vector3(world.pocket_wake + Raid.POCKET_SLEEP_MARGIN + 60.0, 1, 0)
	for i in ceili(Raid.POCKET_SLEEP_AFTER / Raid.POCKET_EVERY) + 2:
		raid._tick_guards(Raid.POCKET_EVERY)
	t.check(pocket.awake, "a pocket still fighting does not sleep")
	brain.target = null
	# Kill one: cleared stays cleared while you stand there.
	raid.player.global_position = den.global_position + Vector3(8, 1, 0)
	var victim: Actor = _standing(raid, pocket)[0]
	victim.kill("bullet", raid.player)
	await t.frames(1)
	raid._tick_guards(0.1)
	raid._tick_guards(world.guard_respawn_time + 1.0)
	raid._tick_guards(Raid.POCKET_EVERY)
	t.check(_standing(raid, pocket).size() == 2,
			"a killed guard does not come back while a player stands within %.0f m" % Raid.POCKET_REFILL_CLEAR)
	raid.player.global_position = den.global_position + Vector3(Raid.POCKET_REFILL_CLEAR + 15.0, 1, 0)
	raid._tick_guards(0.1)
	t.check(_standing(raid, pocket).size() == 3, "once its time is up and nobody is close, it comes back")
	var spot := den.global_position
	await t._end_raid(raid)

	# The budget counts only pockets awake, nearest first (the Engine's two
	# bosses always stand: 3 left for pockets).
	Raid.enemy_cap = 5
	raid = Raid.new()
	t.add_child(raid)
	raid.start(world, 7)
	raid.set_physics_process(false)
	t.check(raid.bots.size() <= 5, "under a cap of 5, at most 5 stand (%d)" % raid.bots.size())
	for i in ceili(Raid.POCKET_SLEEP_AFTER / Raid.POCKET_EVERY) + 2:
		raid.player.global_position = spot + Vector3(10, 1, 0)
		raid._tick_guards(Raid.POCKET_EVERY)
	await t.frames(1)
	var near_den := raid.bots.filter(func(b: Actor) -> bool: return b.global_position.distance_to(spot) < 25.0)
	t.check(raid.bots.size() <= 5 and near_den.size() == 3,
			"short of room, the den you are at wakes and pockets further off sleep for it (%d there, %d in all)"
			% [near_den.size(), raid.bots.size()])
	Raid.enemy_cap = 0
	await t._end_raid(raid)


static func _standing(raid: Raid, pocket: Dictionary) -> Array:
	var out := []
	for i: int in pocket.guards:
		var bot: Variant = raid._guards[i].bot
		if bot != null and is_instance_valid(bot) and not (bot as Actor).is_dead:
			out.append(bot)
	return out


static func _bags(raid: Raid) -> int:
	return raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer and (n as LootContainer).is_bag).size()
