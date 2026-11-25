extends RefCounted
## Dune Sea (`worlds/dunes/`), made by `tools/new_world`: the world plugs
## in, its map keeps the contract, its roster spawns and fights, its loot is
## real items and a life can be lived and signed out of. Add a check here
## for each rule the world adds. The runner finds this file by itself.


static func run(t: Node) -> void:
	print("Dune Sea: the world plugs in")
	var world := Worlds.get_world("dunes")
	t.check(world != null and world in Worlds.raid_worlds() and world.id in Portal.destinations(),
			"dunes: the registry finds it and a squad portal can lead there")
	if world == null:
		return
	var rng := RandomNumberGenerator.new()
	var real := true
	for source: String in ["cache", "bot"]:
		for i in 50:
			rng.seed = i
			real = real and world.roll_loot(source, rng).all(func(id: String) -> bool: return ItemDB.has_item(id))
	t.check(real and world.starter_loadout().all(func(id: String) -> bool: return ItemDB.has_item(id)),
			"dunes: every loot table and the starter kit are real items")
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 7)
	await t.frames(3)
	var me := raid.player
	t.check(me != null and not me.is_dead and absf(me.global_position.y - raid.map.call("ground_height",
			me.global_position.x, me.global_position.z)) < 1.0, "dunes: you land on the ground")
	t.check(world.zone_at(me.global_position) == 0 and raid.outpost_at(me.global_position) != null,
			"dunes: you land in the outer ring, inside the gate outpost")
	t.check(not raid.depots.is_empty() and raid.strongpoints.size() == raid.map.SITES.size(),
			"dunes: the map has depots and its strongpoints")
	var kinds := {}
	for bot in raid.bots:
		kinds[bot.get_meta("kind", "")] = true
	t.check(raid.bots.size() >= world.bot_count and kinds.keys().all(func(k: String) -> bool:
			return k in world.ROSTER or k in ["", "burrower"]), "dunes: the roster's bots and the lairs' burrowers spawn (%s)" % ", ".join(kinds.keys()))
	t.check(raid.bots.all(func(b: Actor) -> bool: return b.weapons.size() > 0 and b.faction != me.faction),
			"dunes: every bot is armed and hostile")
	# Signing out works from the landing.
	me.set_physics_process(false)
	var left := []
	raid.player_finished.connect(func(_who: Actor, result: Dictionary) -> void: left.append(result.get("outcome", "")))
	raid.begin_sign_out(me)
	var state := raid.state_for(me)
	if state != null:
		state.sign_out_left = 0.05
	await t.frames(10)
	t.check(left == ["left"], "dunes: a sign-out takes you home")
	await t._end_raid(raid)
