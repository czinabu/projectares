extends RefCounted
## Checks the new player's tour (`core/progression/onboarding.gd`): the
## handler's steps finish on the action itself, in order, the objective rides
## on the watch and the visor, the handler writes on the phone offline too,
## Settings skips and replays it, an old save never starts it, and dev mode
## never runs it. Called from the test runner (`-- --groups OnboardingTests`).

const Onboarding := preload("res://core/progression/onboarding.gd")
const DevMode := preload("res://core/dev/dev_mode.gd")


static func run(t: Node) -> void:
	print("Onboarding: the handler walks a new player through the basics")
	_rules(t)
	_saves(t)
	await _solo_tour(t)
	Profile.reset()
	Profile.welcome_granted = true
	Profile.onboarding = Onboarding.finished()


static func _rules(t: Node) -> void:
	var tour := Onboarding.fresh()
	t.check(Onboarding.is_active(tour) and Onboarding.current(tour).id == "gear",
			"a fresh tour starts at putting on your gear")
	t.check(not Onboarding.notify(tour, "watch") and Onboarding.current(tour).id == "gear",
			"an action for a later step does not finish the current one")
	var order: Array[String] = []
	for step: Dictionary in Onboarding.STEPS:
		order.append(step.id)
		t.check(Onboarding.notify(tour, step.event), "%s finishes on its own action (%s)" % [step.id, step.event])
	t.check(order == (["gear", "watch", "lane", "plaza", "contract", "deploy", "bank"] as Array[String]),
			"the steps run gear, watch, lane, plaza, contract, deploy, bank: %s" % [order])
	t.check(tour.state == Onboarding.DONE and not Onboarding.is_active(tour) and Onboarding.current(tour).is_empty(),
			"after the last step the tour is done")
	t.check(not Onboarding.notify(tour, "equipped"), "a done tour takes no more actions")
	Onboarding.restart(tour)
	t.check(Onboarding.current(tour).id == "gear", "it can be played again from the start")
	Onboarding.skip(tour)
	t.check(tour.state == Onboarding.SKIPPED and not Onboarding.is_active(tour), "and skipped")
	t.check(Onboarding.clean(null) == Onboarding.finished() and Onboarding.clean({"state": "active", "step": "nope"})
				== Onboarding.finished() and Onboarding.clean({"state": "active", "step": "lane"}).step == "lane"
				and Onboarding.clean({"state": "skipped"}).state == Onboarding.SKIPPED,
			"a saved tour is checked; anything odd counts as finished")
	var names := Onboarding.names("X", "1")
	var gentle: WorldDef = null
	var harsh: WorldDef = null
	for world in Worlds.raid_worlds():
		if world.keep_gear_on_death and gentle == null:
			gentle = world
		if world.gear_at_risk and not world.keep_gear_on_death and harsh == null:
			harsh = world
	t.check(gentle != null and names.gentle == gentle.display_name and harsh != null
				and names.harsh == harsh.display_name and names.plaza == Worlds.social_world().display_name,
			"the handler names worlds by what they are: %s to learn in, %s full loot, %s to meet people"
			% [names.gentle, names.harsh, names.plaza])
	tour = {"state": Onboarding.ACTIVE, "step": "deploy"}
	var texts := Onboarding.messages(tour, names)
	t.check(texts.size() == Onboarding.index_of("deploy") + 1 and texts[-1].contains(names.gentle)
				and not texts[-1].contains("{"),
			"the messages so far are one per step reached, names filled in")
	t.check(Onboarding.objective(tour, names) == "Go to %s" % names.gentle, "and the objective names the world too")
	for step: Dictionary in Onboarding.STEPS:
		t.check(Onboarding.fill(step.objective, names).length() <= 40,
				"%s's objective is short enough for the watch card" % step.id)


static func _saves(t: Node) -> void:
	Profile.reset()
	t.check(Onboarding.is_active(Profile.onboarding), "a new player starts the tour")
	Profile.onboarding = {"state": Onboarding.ACTIVE, "step": "lane"}
	Profile.load_dict(Profile.to_dict())
	t.check(Profile.onboarding.step == "lane", "how far it got is saved")
	var old := Profile.to_dict()
	old.erase("onboarding")
	old["raids_played"] = 4
	Profile.load_dict(old)
	t.check(Profile.onboarding.state == Onboarding.DONE, "a save from before the tour, with raids played, never starts it")
	old["raids_played"] = 0
	old["loadout"] = {}
	Profile.load_dict(old)
	t.check(Onboarding.is_active(Profile.onboarding), "a brand new player's save from before the tour does")
	Profile.reset()


## A new player solo: the base, the watch, the lane, Settings, dev mode, then
## a world and a depot.
static func _solo_tour(t: Node) -> void:
	Profile.reset()
	Profile.welcome_granted = false
	Profile.grant_welcome_crate()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(20)
	var phone: Node = main.phone
	t.check(Profile.onboarding.step == "gear" and _handler_texts(phone).size() == 1,
			"first spawn: the handler's welcome is waiting on the phone")
	t.check(phone.conversations().has(Onboarding.HANDLER_ID) and phone.unread_from(Onboarding.HANDLER_ID) == 1,
			"offline too, as an unread message in Messages")
	t.check(main.base_hud.objective == "Put on your gear in the armory" and main.base_hud.wrist.objective == main.base_hud.objective,
			"the objective is on the watch card: %s" % main.base_hud.objective)
	phone.open("messages")
	phone.open_chat(Onboarding.HANDLER_ID)
	await t.frames(3)
	t.check(phone._compose == null and phone.unread_from(Onboarding.HANDLER_ID) == 0,
			"the handler's chat reads, with no box to reply in")
	phone.close()
	var rifle: Node = main.base.display_for("rifle_carbine")
	t.check(rifle != null, "the welcome rifle hangs in the armory")
	if rifle == null:
		main.queue_free()
		await t.frames(5)
		return
	rifle.interact(main.base.player)
	await t.frames(5)
	t.check(Profile.onboarding.step == "watch" and _handler_texts(phone).size() == 2,
			"putting on a weapon finishes the step and the handler sends the next")
	main.controller.wrist_raised = true
	await t.frames(3)
	main.controller.wrist_raised = false
	t.check(Profile.onboarding.step == "lane", "raising the watch finishes its step")
	main.base.target_hit.emit()
	await t.frames(2)
	t.check(Profile.onboarding.step == "plaza" and main.base_hud.objective.begins_with("Head out to "),
			"a hit on the test lane sends you out to the plaza")

	phone.tour_requested.emit("skip")
	await t.frames(2)
	t.check(Profile.onboarding.state == Onboarding.SKIPPED and main.base_hud.objective == "" and not phone.tour_running,
			"Settings skips the tour: the objective goes")
	t.check(_handler_texts(phone)[-1] == Onboarding.SKIP_MESSAGE, "and the handler signs off")
	phone.tour_requested.emit("replay")
	await t.frames(2)
	t.check(Onboarding.is_active(Profile.onboarding) and Profile.onboarding.step == "watch" and phone.tour_running,
			"playing it again starts over, passing what is already done (the rifle is on): %s" % Profile.onboarding.step)
	var again := _handler_texts(phone)
	t.check(again.size() == 2 and again[0].begins_with("Welcome home"),
			"with the old messages cleared: the welcome again, then the step it passed to (%d)" % again.size())

	# DEV MODE: the tour never runs in dev mode.
	DevMode.enabled = true
	main._tour_show()
	main._tour_event("watch")
	t.check(main.base_hud.objective == "" and Profile.onboarding.step == "watch" or not DevMode.available(),
			"dev mode hides the tour and it takes no actions")
	DevMode.enabled = false
	main._tour_show()

	var gentle := ""
	for world in Worlds.raid_worlds():
		if world.keep_gear_on_death:
			gentle = world.id
			break
	Profile.onboarding = {"state": Onboarding.ACTIVE, "step": "deploy"}
	main.start_raid(gentle)
	await t.frames(10)
	t.check(Profile.onboarding.step == "bank" and main.hud != null and main.hud.objective == "Bank your loot at a depot",
			"arriving in a world finishes the deploy step, and the objective rides on the raid's watch and visor")
	if main.raid != null and main.raid.player != null:
		main.raid.player_banked.emit(main.raid.player, ["medkit"])
		await t.frames(2)
	t.check(Profile.onboarding.state == Onboarding.DONE and main.hud.objective == ""
				and _handler_texts(phone)[-1].contains("full loot"),
			"banking at a depot ends the tour with the full-loot warning")
	main.queue_free()
	await t.frames(5)


static func _handler_texts(phone: Node) -> Array[String]:
	var out: Array[String] = []
	for message: Dictionary in phone.local_messages:
		if message.from == Onboarding.HANDLER_ID:
			out.append(message.text)
	return out
