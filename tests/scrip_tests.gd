extends RefCounted
## The `scrip` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashService := preload("res://core/account/stash_service.gd")


static func run(t: Node) -> void:
	print("Carried scrip")
	var raid := Raid.new()
	t.add_child(raid)
	raid.apply_to_profile = false
	# Tried with an army walking the valley, as Frostline had before its
	# pockets (`pocket_tests` has those): put back at the end.
	var frost := Worlds.get_world("frostline")
	var kept := [frost.bot_count, frost.pocket_wake]
	frost.bot_count = 22
	frost.pocket_wake = 0.0
	raid.start_server(frost, 31)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.set_physics_process(false)
		bot.global_position = Vector3(500, 0, 500)
	var results := {}
	raid.player_finished.connect(func(actor: Actor, result: Dictionary) -> void: results[actor.display_name] = result)
	var a := raid.add_player([], {}, "Alpha", "acct-a")
	var b := raid.add_player([], {}, "Bravo", "acct-b")
	a.set_physics_process(false)
	b.set_physics_process(false)
	a.global_position = Vector3(-200, 0, -200)
	b.global_position = Vector3(-200, 0, -230)
	Combat.deal(raid.bots[0], DamageInfo.make(9999.0, a, "bullet"))
	Combat.deal(raid.bots[0], DamageInfo.make(9999.0, a, "bullet"))
	await t.frames(2)
	t.check(a.scrip == 2 * StashService.Economy.KILL_BOUNTY and "%d scrip" % (2 * StashService.Economy.KILL_BOUNTY) in Hud.wrist_text(raid, a, {}, 0.0) and b.scrip == 0,
			"kills pay scrip that you carry (%d)" % a.scrip)

	# Banking makes it safe.
	var depot := raid.depots[0]
	var k := StashService.Economy.KILL_BOUNTY
	depot.actor_banked.emit(a)
	t.check(a.scrip == 0 and raid.state_for(a).scrip_banked == 2 * k, "a depot banks the scrip you carry")
	Combat.deal(raid.bots[0], DamageInfo.make(9999.0, a, "bullet"))
	await t.frames(2)
	t.check(a.scrip == k, "more kills pay more")

	# Dying drops what was not banked.
	a.protected_left = 0.0
	Combat.deal(a, DamageInfo.make(9999.0, raid.bots[1], "bullet"))
	await t.frames(2)
	var bag: LootContainer = null
	for node in raid.get_children():
		if node is LootContainer and node.is_bag and node.scrip > 0:
			bag = node
	t.check(bag != null and bag.scrip == k and "%d scrip" % k in bag.get_prompt(), "what you carried drops with your bag (%s)" % (bag.get_prompt() if bag else "no bag"))
	t.check(results.has("Alpha") and results.Alpha.scrip == 0 and results.Alpha.scrip_banked == 2 * k and results.Alpha.scrip_lost == k
			and StashService.Economy.payout(results.Alpha) == 2 * k and "Scrip dropped: %d" % k in Hud.death_text(results.Alpha, 0.0),
			"the dead keep only what they banked")
	if bag != null:
		bag.interact(b)
		await t.frames(2)
		t.check(b.scrip == k, "whoever loots the bag takes the scrip (%d)" % b.scrip)

	# Leaving alive carries it home.
	raid._leave(raid.state_for(b))
	t.check(results.has("Bravo") and results.Bravo.scrip == k and StashService.Economy.payout(results.Bravo) == k,
			"signing out carries your scrip home")
	raid.queue_free()
	frost.bot_count = kept[0]
	frost.pocket_wake = kept[1]
	await t.frames(2)
