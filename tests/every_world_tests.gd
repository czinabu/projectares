extends RefCounted
## The `every_world` checks. The test runner finds this file by itself and calls
## `run(t)`.
##
## Every world folder must honour the map contract and run a raid headless.


static func run(t: Node) -> void:
	print("Every world plugs in")
	t.check(Worlds.raid_worlds().size() >= 2, "registry finds more than one world (%d)" % Worlds.raid_worlds().size())
	var every := true
	for world in Worlds.raid_worlds():
		every = every and world.id in Portal.destinations()
	t.check(every, "a squad portal from the watch can lead to every world")
	for world in Worlds.raid_worlds():
		var kit := world.starter_loadout()
		t.check(not kit.is_empty() and kit.all(func(id: String) -> bool: return id == Loadout.BARE or ItemDB.has_item(id)),
				"%s: starter loadout is valid items" % world.id)
		var raid := world.new_raid()
		t.add_child(raid)
		raid.start(world, 99)
		await t.frames(3)
		t.check(raid.player != null and not raid.player.is_dead, "%s: player spawns" % world.id)
		t.check(raid.bots.size() == world.bot_count + raid._bosses.size() + raid._guards.filter(func(g: Dictionary) -> bool: return g.bot != null).size(), "%s: all bots spawn" % world.id)
		var caches := raid.get_children().filter(func(n: Node) -> bool: return n is LootContainer)
		if world.gear_at_risk:
			# Only where gear is at stake is there loot to find and bank (a
			# race world has none).
			t.check(not raid.depots.is_empty(), "%s: map provides depots" % world.id)
			t.check(caches.size() >= 4, "%s: loot caches are placed (%d)" % [world.id, caches.size()])
		var all_valid := true
		for cache: LootContainer in caches:
			for id in cache.items:
				if not ItemDB.has_item(id):
					all_valid = false
		for bot in raid.bots:
			for id in bot.get_drop_items():
				if not ItemDB.has_item(id):
					all_valid = false
		t.check(all_valid, "%s: every cache and bot carries real items" % world.id)
		for bot in raid.bots:
			t.check(bot.weapons.size() > 0 and bot.faction != raid.player.faction,
					"%s: %s is armed and hostile" % [world.id, bot.display_name])
			break
		await t.frames(120)
		t.check(raid.clock > 1.0 and raid.bots.size() + raid._bot_respawns.size() == world.bot_count + raid._bosses.size()
				+ raid._guards.filter(func(g: Dictionary) -> bool: return g.bot != null).size(),
				"%s: the world runs with bots thinking" % world.id)
		await t._end_raid(raid)
