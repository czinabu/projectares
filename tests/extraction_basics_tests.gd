extends RefCounted
## The `extraction_basics` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Depots and signing out")
	Profile.reset()
	var raid: Raid = await t._new_raid(44, false)
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var p := raid.player
	p.inventory.add_item("reactor_core")
	p.inventory.add_item("medkit")
	var bot := raid.bots[0]
	var depot_pos := raid.depots[1].global_position
	p.global_position = Vector3(depot_pos.x, depot_pos.y - 1.8, depot_pos.z)
	bot.global_position = Vector3(depot_pos.x + 2.0, depot_pos.y - 1.8, depot_pos.z)
	await t.frames(60)
	t.check(raid.bank_progress() > 0.0, "standing in a depot starts the hold")
	t.check(Profile.stash.is_empty(), "banking is not instant")
	t.check(is_zero_approx(raid.depots[1].progress_for(bot)), "a bot cannot use a depot")
	await t.frames(240)
	t.check("reactor_core" in Profile.stash and not p.inventory.has_item("reactor_core"),
			"the depot sends the backpack to the stash")
	t.check(p.inventory.has_item("medkit") and "medkit" not in Profile.stash, "healing stays with you")
	t.check(results.is_empty() and not p.is_dead, "banking does not end your stay")
	await t.frames(30)
	t.check(is_zero_approx(raid.bank_progress()), "with nothing left to bank the depot does nothing")

	t.check(raid.begin_sign_out(p) and raid.sign_out_progress(p) >= 0.0, "a sign-out starts out of a fight")
	Combat.deal(p, DamageInfo.make(5.0, bot, "bullet"))
	t.check(raid.sign_out_progress(p) < 0.0, "taking a hit cancels the sign-out")
	t.check(not raid.begin_sign_out(p), "a sign-out cannot start in a fight")
	raid.clock += raid.world.combat_time + 1.0
	p.inventory.add_item("alloy_ingot")
	t.check(raid.begin_sign_out(p), "once the fight is over it can")
	raid.cancel_sign_out(p)
	t.check(raid.sign_out_progress(p) < 0.0, "a sign-out can be called off")
	raid.begin_sign_out(p)
	raid.state_for(p).sign_out_left = 0.2
	await t.frames(30)
	t.check(results.size() == 1 and results[0].outcome == "left", "a finished sign-out ends the life as left")
	t.check("reactor_core" in results[0].banked and results[0].banked_value == ItemDB.item_value("reactor_core"),
			"the result lists what was banked")
	t.check("alloy_ingot" in Profile.stash and "medkit" in Profile.stash, "what you carried comes home")
	t.check(Profile.stash.size() == 3, "the free scrap kit is never stashed")
	t.check(Profile.raids_extracted == 1, "the profile records leaving alive")
	await t._end_raid(raid)
