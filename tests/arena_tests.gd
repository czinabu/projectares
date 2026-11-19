extends RefCounted
## The `arena` checks. The test runner finds this file by itself and calls
## `run(t)`.

const StashService := preload("res://core/account/stash_service.gd")
## For its FakeBank, which `_quick_arena` sets up.
const Runner := preload("res://tests/test_runner.gd")


static func run(t: Node) -> void:
	print("Arena: wagers, duels and tournaments")
	var bets := {"cara": [0, 100], "dax": [1, 50], "eve": [0, 50]}
	var paid := Arena.wager_payouts(bets, 0, 0.1)
	# 50 on the losing side, 5 to the house, 45 shared 2:1 by red's backers.
	t.check(paid.get("cara", 0) == 130 and paid.get("eve", 0) == 65 and not paid.has("dax"),
			"backers of the winner split the losing pool by stake, less the house cut")
	paid = Arena.wager_payouts(bets, -1, 0.1)
	t.check(paid.cara == 100 and paid.dax == 50 and paid.eve == 50, "a draw refunds every wager")
	paid = Arena.wager_payouts({"cara": [0, 100]}, 1, 0.1)
	t.check(paid.get("cara", 0) == 100, "with nobody on the other side, the wager comes back")

	var venue := Arena.ArenaVenue.new()
	t.check(venue.gear_at_risk == false and venue.new_raid() is Arena and Worlds.get_world(venue.id) == null,
			"the arena is a gear-safe venue with its own rules, not a deploy target")
	t.check(NetSession.world_for("arena") != null and NetSession.world_for("ashfront") != null,
			"online sessions can run the arena or a world")
	var hp := HealthComponent.new()
	hp.min_health = 1.0
	hp.apply_damage(DamageInfo.make(500.0, null, "blade"))
	t.check(not hp.is_dead and is_equal_approx(hp.health, 1.0), "a floor on health turns a killing blow into a yield")
	hp.free()

	# Solo: you, the stands and bot gladiators.
	Profile.reset()
	var stash_before := Profile.stash.duplicate()
	var arena := Arena.new()
	t.add_child(arena)
	arena.call_time = 0.3
	arena.countdown_time = 0.1
	arena.result_time = 0.1
	arena.exhibition_delay = -1.0
	arena.start_solo(["rifle_carbine", "blade_scrap", "plate_light", "medkit", "bike_scrapper"])
	await t.frames(5)
	var me := arena.player
	t.check(me != null and not Arena.ArenaVenue.in_pit(me.global_position) and me.global_position.y > 2.0,
			"you arrive in the stands")
	t.check(me.weapons.size() == 2 and "medkit" not in me.gear_items and arena.vehicles.is_empty(),
			"you bring your own weapons, but no healing or vehicles into the arena")
	t.check(not Combat.deal(me, DamageInfo.make(30.0, null, "bullet")) and is_equal_approx(me.health.health, me.health.max_health),
			"nobody can hurt the crowd")
	me.global_position = Vector3(0, 0.5, 0)
	await t.frames(2)
	t.check(not Arena.ArenaVenue.in_pit(me.global_position), "spectators who drop into the pit are put back in the stands")
	arena.ask("bet", {"side": 0, "amount": 10})
	t.check(Profile.scrip == StashService.Economy.STARTING_SCRIP, "bets are refused when no bout is being called")
	arena.ask("practice")
	t.check(arena.queue.size() == 1 or arena.bout != null, "you can ask for a practice bout")
	await t._arena_phase(arena, Arena.Phase.CALLING, 30)
	var board := arena.view_board()
	t.check(board.phase == "calling" and board.bout.names[0] == "You" and board.bout.names[1] != "",
			"the bout is called with both fighters' names")
	arena.ask("bet", {"side": 0, "amount": 10})
	t.check(Profile.scrip == StashService.Economy.STARTING_SCRIP and not arena.bout.bets.has("local"),
			"fighters cannot bet on their own bout")
	await t._arena_phase(arena, Arena.Phase.FIGHT)
	var bot: Actor = arena.bout.fighters[1]
	t.check(Arena.ArenaVenue.in_bounds(me.global_position) and bot != null and bot in arena.bots
			and me.health.min_health > 0.0, "the fighters are in the pit and cannot die")
	t.check(Combat.deal(bot, DamageInfo.make(5.0, me, "blade")) and not Combat.deal(me, DamageInfo.make(5.0, null, "fall")),
			"only the two fighters can hurt each other")
	Combat.deal(me, DamageInfo.make(5000.0, bot, "blade"))
	t.check(not me.is_dead and me.health.health <= 1.01, "a beaten fighter yields instead of dying")
	await t._arena_phase(arena, Arena.Phase.IDLE)
	await t.frames(3)
	t.check(Profile.arena_losses == 1 and Profile.arena_wins == 0, "the bout goes on your arena record")
	t.check(not Arena.ArenaVenue.in_pit(me.global_position) and is_equal_approx(me.health.health, me.health.max_health)
			and me.health.min_health == 0.0, "both go back to the stands, patched up")
	t.check(not is_instance_valid(bot) or bot.is_queued_for_deletion() or bot not in arena.bots,
			"the bot gladiator leaves the arena after the bout")
	t.check(me.weapons.size() == 2 and Profile.stash == stash_before, "nothing was lost and the stash is untouched")

	# An exhibition between two bots, with a wager from the crowd.
	arena.exhibition_delay = 0.1
	await t._arena_phase(arena, Arena.Phase.CALLING, 60)
	t.check(arena.bout != null and arena.bout.kind == "exhibition", "with nothing queued, bot gladiators put on an exhibition")
	arena.ask("bet", {"side": 1, "amount": 50})
	t.check(Profile.scrip == StashService.Economy.STARTING_SCRIP - 50 and arena.bout.pools[1] == 50,
			"the crowd can bet while a bout is being called")
	arena.ask("bet", {"side": 0, "amount": 50})
	t.check(arena.bout.pools[0] == 0, "you cannot back both sides")
	arena.exhibition_delay = -1.0
	await t._win_bout(arena, 0)
	t.check(Profile.scrip == StashService.Economy.STARTING_SCRIP, "a wager nobody took the other side of is refunded")
	arena.queue_free()
	await t.frames(3)
	t.check(Profile.stash == stash_before, "leaving the arena takes nothing from the stash")
	Profile.reset()

	# From your base: a portal from the watch opens it, with its own overlay.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(2)
	t.check(main.base.open_portal(Arena.ArenaVenue.ID) == "", "a portal from the base's watch can lead to the arena")
	await t.frames(int(main.base.portal.unfold_time * 60.0) + 4)
	main.base.player.global_position = main.base.portal.global_position
	await t.frames(8)
	t.check(main.raid is Arena and not main.hub.visible and main.base == null
			and main.raid.get_node_or_null("ArenaHud") != null
			and main.controller != null, "walking through it opens the arena")
	var hud: CanvasLayer = main.raid.get_node("ArenaHud")
	await t.frames(20)
	var faces := t.get_tree().get_nodes_in_group("arena_board").filter(func(face: Node) -> bool:
		return main.raid.map.is_ancestor_of(face))
	t.check(faces.size() == Arena.ArenaVenue.BOARD_FACES and faces.all(func(face: Node) -> bool:
			return face.get_children().any(func(c: Node) -> bool: return c is WorldScreen)),
			"the bout is shown on the big board over the pit, on every side")
	var booths := t.get_tree().get_nodes_in_group("arena_booth").filter(func(b: Node) -> bool:
		return main.raid.map.is_ancestor_of(b))
	t.check(booths.size() == Arena.ArenaVenue.BOOTHS, "the stands have bookmakers' booths")
	var booth: Node3D = booths[0]
	t.check(hud.booth_at(main.raid, booth.global_position + Vector3(0.3, 0.1, 0)) == booth
			and hud.booth_at(main.raid, Vector3.ZERO) == null, "a booth is used by standing at it")
	hud.open_booth(booth)
	await t.frames(3)
	t.check(hud.booth_open and hud.booth_screen.get_parent() == booth.get_node("Screen")
			and main.controller.input_blocked and main.get_viewport().get_camera_3d() != main.controller.camera
			and not main.hud.visible, "the booth's screen comes up with the view moved in to it")
	t.check(hud.get("_panel").get_child_count() > 3, "the booth lists what you can do")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	hud.booth_view.push_input(esc, true)
	await t.frames(3)
	t.check(not hud.booth_open and not main.controller.input_blocked and main.hud.visible
			and main.get_viewport().get_camera_3d() == main.controller.camera, "Esc steps away from the booth")
	hud.leave_requested.emit()
	await t.frames(5)
	t.check(main.raid == null and main.base != null and not main.hub.visible, "leaving the arena takes you home")
	# A gate inside a world (the plaza's) opens the arena from there.
	main.start_raid(Worlds.all()[0].id)
	await t.frames(5)
	main.open_arena()
	await t.frames(5)
	t.check(main.raid is Arena and main.raid.player != null, "the arena can be opened from inside a world")
	main.leave_arena()
	await t.frames(3)
	main.queue_free()
	await t.frames(2)
	Profile.reset()

	# A server arena: a staked duel between players, with the crowd betting.
	arena = await t._quick_arena(["Ash", "Bex", "Cy", "Dov"])
	var bank: Runner.FakeBank = arena.bank
	var ash := arena.players[0].actor
	var bex := arena.players[1].actor
	var cy := arena.players[2].actor
	var dov := arena.players[3].actor
	t.check(not arena.request(ash, "challenge", {"to": String(bex.name), "stake": 9999}).ok,
			"a stake above the limit is refused")
	t.check(arena.request(ash, "challenge", {"to": String(bex.name), "stake": 50}).ok, "a player can challenge another")
	var board_b := arena.board_for(bex)
	t.check(board_b.challenges.size() == 1 and board_b.challenges[0].incoming and board_b.challenges[0].from == "Ash",
			"the challenged player sees it on their board")
	t.check(not arena.request(cy, "accept", {"from": String(ash.name)}).ok, "nobody else can accept it")
	t.check(arena.request(bex, "accept", {"from": String(ash.name)}).ok and bank.money.Ash == 450 and bank.money.Bex == 450,
			"accepting puts up both stakes")
	await t._arena_phase(arena, Arena.Phase.CALLING, 30)
	t.check(arena.request(cy, "bet", {"side": 0, "amount": 100}).ok and arena.request(dov, "bet", {"side": 1, "amount": 50}).ok,
			"the crowd bets on both sides")
	t.check(not arena.request(ash, "bet", {"side": 0, "amount": 10}).ok, "a fighter cannot bet on their own duel")
	t.check(not arena.request(cy, "bet", {"side": 0, "amount": 1}).ok, "bets below the minimum are refused")
	await t._arena_phase(arena, Arena.Phase.FIGHT)
	t.check(not Combat.deal(cy, DamageInfo.make(10.0, ash, "blade")), "a fighter cannot hurt the crowd")
	await t._win_bout(arena, 0)
	t.check(bank.money.Ash == 550 and bank.money.Bex == 450, "the winner takes both stakes")
	t.check(bank.money.Cy == 545 and bank.money.Dov == 450, "the winner's backers are paid from the losing pool")
	t.check(bank.wins.get("Ash", 0) == 1 and bank.losses.get("Bex", 0) == 1, "both fighters' records are kept")
	t.check(not ash.is_dead and not bex.is_dead and ash.weapons.size() == 1 and bex.weapons.size() == 1,
			"nobody died and nobody lost a weapon")

	# Leaving mid-bout forfeits it.
	arena.request(cy, "challenge", {"to": String(dov.name), "stake": 0})
	arena.request(dov, "accept", {"from": String(cy.name)})
	await t._arena_phase(arena, Arena.Phase.FIGHT)
	var summary := [{}]
	arena.bout_finished.connect(func(r: Dictionary) -> void: summary[0] = r, CONNECT_ONE_SHOT)
	arena.remove_player(dov)
	await t.frames(2)
	t.check(summary[0].get("winner", "") == "Cy", "a fighter who leaves forfeits the bout")
	await t._arena_phase(arena, Arena.Phase.IDLE)

	# A tournament: three players and a bot gladiator in a four-slot bracket.
	for who in [ash, bex, cy]:
		t.check(arena.request(who, "join_tournament", {}).ok, "%s enters the tournament" % who.display_name)
	t.check(bank.money.Ash == 525 and arena.tournament.pot == 75, "the entry fee goes into the pot")
	t.check(not arena.request(ash, "join_tournament", {}).ok, "nobody enters twice")
	var after_fees := bank.money.duplicate()
	var champion := [""]
	for i in 6:
		if arena.tournament == null:
			break
		await t._arena_phase(arena, Arena.Phase.FIGHT, 120)
		if arena.bout == null:
			break
		# The player on the red side wins each bout, if there is one.
		var side := 0 if arena.bout.sides[0] is Actor else 1
		if arena.tournament != null and arena.tournament.round > 0:
			champion[0] = arena.bout.names[side]
		await t._win_bout(arena, side)
	await t.frames(5)
	t.check(arena.tournament == null and arena.last_result.ends_with("is the champion"),
			"the bracket plays out to a champion (%s)" % arena.last_result)
	var champ_key: String = champion[0]
	t.check(champ_key != "" and bank.money.get(champ_key, 0) == int(after_fees.get(champ_key, 0)) + 75,
			"the champion takes the pot")

	# Shutting the arena down mid-bout hands wagers and stakes back.
	arena.request(ash, "challenge", {"to": String(bex.name), "stake": 20})
	arena.request(bex, "accept", {"from": String(ash.name)})
	await t._arena_phase(arena, Arena.Phase.CALLING, 30)
	arena.request(cy, "bet", {"side": 1, "amount": 30})
	var before := [bank.money.Ash + 20, bank.money.Bex + 20, bank.money.Cy + 30]
	arena.queue_free()
	await t.frames(2)
	t.check(bank.money.Ash == before[0] and bank.money.Bex == before[1] and bank.money.Cy == before[2],
			"an arena that shuts down refunds open wagers and stakes")
