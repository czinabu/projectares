extends RefCounted
## The `events` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("World events")
	var world := Worlds.get_world("ashfront")
	var rng := RandomNumberGenerator.new()
	var rarity := func(ids: Array) -> int:
		var total := 0
		for id: String in ids:
			total += ItemDB.item_rarity(id)
		return total
	var quiet := 0
	var hot := 0
	for i in 200:
		rng.seed = i
		quiet += rarity.call(world.roll_war_loot("cache", rng, 0.0))
		rng.seed = i
		hot += rarity.call(world.roll_war_loot("cache", rng, 1.0))
	t.check(hot > quiet, "caches hold rarer loot in an all-out war (%d against %d)" % [hot, quiet])
	rng.seed = 5
	var plain := world.roll_loot("cache", rng)
	rng.seed = 5
	t.check(world.roll_war_loot("cache", rng, 0.0) == plain, "a quiet world's loot is unchanged")

	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	raid.start_server(world, 41)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	var feed: Array[String] = []
	raid.war_feed.connect(func(text: String) -> void: feed.append(text))
	var a := raid.add_player([], {}, "Alpha", "acct-a")
	a.set_physics_process(false)
	var before := raid.bots.size()
	t.check(raid.event.is_empty(), "a world starts with no event running")

	# A supply pod.
	t.check(raid.start_event("supply_pod") and raid.event.kind == "supply_pod", "a supply pod can come down")
	var pod: LootContainer = raid._event_pod
	t.check(pod != null and pod.items.size() >= 4 and feed.size() == 1 and feed[0].begins_with("A supply pod came down "),
			"it holds a good haul and everyone hears where it is (%s)" % " / ".join(feed))
	t.check(not raid.start_event("warlord"), "only one event runs at a time")
	pod.set_items([])
	await t.frames(3)
	t.check(raid.event.is_empty(), "the event ends once the pod is emptied")
	await t.frames(2)

	# A warlord and his escort.
	feed.clear()
	t.check(raid.start_event("warlord") and raid.bots.size() == before + 1 + world.warlord_escort, "a warlord arrives with an escort")
	var lord: Actor = raid._event_bots.filter(func(b: Actor) -> bool: return raid.warlords.has(b))[0]
	for bot in raid._event_bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
	t.check(lord.display_name == "Warlord" and lord.health.max_health >= 180.0 and feed[0].begins_with("A warlord has arrived "),
			"the warlord is far tougher than his men (%s, %.0f health)" % [lord.display_name, lord.health.max_health])
	var carried := lord.inventory.items.size()
	t.check(carried >= 3, "the warlord carries loot worth the fight (%d items)" % carried)
	var respawns := raid._bot_respawns.size()
	Combat.deal(lord, DamageInfo.make(9999.0, a, "bullet"))
	await t.frames(3)
	t.check(feed.any(func(t: String) -> bool: return t.begins_with("Alpha") and t.ends_with("killed the warlord")),
			"killing the warlord pays renown and is announced (%d, %s)" % [a.renown, " / ".join(feed)])
	t.check(a.renown >= 310, "the warlord's renown comes on top of the kill (%d)" % a.renown)
	t.check(raid.event.is_empty() and raid._bot_respawns.size() == respawns, "the event ends with him, and nobody takes his place")

	# An event nobody deals with is cleared away.
	raid.start_event("warlord")
	raid.event.ends = raid.clock
	await t.frames(3)
	t.check(raid.event.is_empty() and raid.warlords.size() == raid._bosses.size() and feed.has("The warlord has moved on"),
			"an event nobody answers ends on its own")
	await t.frames(2)
	t.check(raid.bots.size() <= before + world.warlord_escort, "and its bots leave with it")

	# The timer.
	raid._event_in = 0.05
	await t.frames(6)
	t.check(not raid.event.is_empty(), "events come round on their own")
	raid.queue_free()
	await t.frames(2)
