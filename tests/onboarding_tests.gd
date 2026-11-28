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
	Profile.tour_on_reset = true
	_rules(t)
	_saves(t)
	await _notices(t)
	await _solo_tour(t)
	Profile.reset()
	Profile.welcome_granted = true
	Profile.onboarding = Onboarding.finished()
	Profile.tour_on_reset = false


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
	Onboarding.notify(tour, "equipped")
	Onboarding.notify(tour, "watch")
	t.check(Onboarding.current(tour).id == "lane" and Onboarding.catch_up(tour, "plaza")
				and Onboarding.current(tour).id == "contract",
			"standing in the plaza passes the test lane step left behind in the base")
	t.check(not Onboarding.catch_up(tour, "equipped") and Onboarding.current(tour).id == "contract",
			"a fact for a step already passed moves nothing")
	Onboarding.restart(tour)
	Onboarding.skip(tour)
	t.check(tour.state == Onboarding.SKIPPED and not Onboarding.is_active(tour), "and skipped")
	t.check(Onboarding.clean(null) == Onboarding.finished() and Onboarding.clean({"state": "active", "step": "nope"})
				== Onboarding.finished() and Onboarding.clean({"state": "active", "step": "lane"}).step == "lane"
				and Onboarding.clean({"state": "skipped"}).state == Onboarding.SKIPPED,
			"a saved tour is checked; anything odd counts as finished")
	var names := Onboarding.names("X", "1")
	var launch_names := names
	Worlds.choose_offered(true)
	if LaunchScope.on:
		launch_names = Onboarding.names("X", "1")
	Worlds.choose_offered(false)
	var at_launch: Dictionary = {}
	for world in Worlds.raid_worlds():
		if world.id in LaunchScope.worlds():
			at_launch[world.keep_gear_on_death] = at_launch.get(world.keep_gear_on_death, world)
	t.check(at_launch.has(true) and names.gentle_id == at_launch[true].id
				and at_launch.has(false) and names.harsh == at_launch[false].display_name,
			"the tour sends you to the launch's worlds, %s to learn in and %s for full loot, in every build"
			% [names.gentle, names.harsh])
	t.check(launch_names.gentle == names.gentle and launch_names.harsh == names.harsh,
			"and the release build names the same ones")
	var gentle: WorldDef = null
	var harsh: WorldDef = null
	var ordered: Array[WorldDef] = []
	for world in Worlds.raid_worlds():
		if world.id in LaunchScope.worlds():
			ordered.append(world)
	for world in Worlds.raid_worlds():
		if not world.id in LaunchScope.worlds():
			ordered.append(world)
	for world in ordered:
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
		t.check(step.has("mark") and (str(step.mark) != "" or str(step.get("hint", "")) != ""),
				"%s points at something in the world or says what to press" % step.id)
	tour = {"state": Onboarding.ACTIVE, "step": "deploy"}
	t.check(Onboarding.mark(tour, names) == "portal:world:%s" % gentle.id,
			"the deploy step points at the gentle world's gate: %s" % Onboarding.mark(tour, names))
	t.check(Onboarding.locks(tour, harsh) and not Onboarding.locks(tour, gentle)
				and not Onboarding.locks(tour, Worlds.social_world()),
			"while the tour runs the full-loot world is closed, the gentle one and the plaza open")
	t.check(not Onboarding.locks(Onboarding.finished(), harsh) and not Onboarding.locks({"state": Onboarding.SKIPPED, "step": ""}, harsh),
			"finished or skipped, the full-loot world opens")
	tour = {"state": Onboarding.ACTIVE, "step": "watch"}
	t.check(Onboarding.mark(tour, names) == "" and Onboarding.hint(tour, names) == "Press X to raise your watch",
			"the watch step has nothing to walk to and says what to press instead")


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


## The phone's pop-ups come one at a time in the order sent, and a keyed one
## (the tour's step) replaces its stale self instead of waiting behind it.
static func _notices(t: Node) -> void:
	var PhoneScript: GDScript = load("res://core/phone/phone.gd")
	var phone: CanvasLayer = PhoneScript.new()
	t.add_child(phone)
	await t.frames(2)
	phone.show_notice("one")
	phone.show_notice("two")
	phone.show_notice("two")
	t.check(phone.notice_showing() == "one" and phone.notices_waiting() == (["two"] as Array[String]),
			"a pop-up sent while another is up waits its turn, and the same words are not queued twice")
	phone.show_notice("Handler: step A", -1.0, "tour", true)
	phone.show_notice("Handler: step B", -1.0, "tour", true)
	t.check(phone.notices_waiting() == (["Handler: step B", "two"] as Array[String]),
			"the tour's step goes ahead of other news, and a newer step replaces one not yet shown: %s"
			% [phone.notices_waiting()])
	phone._notice_left = 0.01
	phone._tick_notice(0.02)
	t.check(phone.notice_showing() == "Handler: step B", "when one goes the next comes up, in order")
	phone.show_notice("Handler: step C", -1.0, "tour", true)
	t.check(phone.notice_showing() == "Handler: step C" and phone.notices_waiting() == (["two"] as Array[String]),
			"a step up now is replaced in place by the next one")
	phone.notices_paused = true
	var left: float = phone._notice_left
	phone._tick_notice(1.0)
	t.check(is_equal_approx(phone._notice_left, left), "between places a pop-up keeps its time")
	phone.notices_paused = false
	phone.drop_notice("tour")
	t.check(phone.notice_showing() == "two" and phone.notices_waiting().is_empty(),
			"a tour that ends takes its pop-up down")
	for i in 10:
		phone.show_notice("news %d" % i)
	t.check(phone.notices_waiting().size() == phone.notices_kept and phone.notices_waiting()[-1] == "news 9",
			"at most %d wait, the oldest dropped" % phone.notices_kept)
	phone.queue_free()
	await t.frames(2)


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
	main._tour_guide_tick(0.1)
	var guide: Node3D = main._tour_guide
	var rack: Node3D = main.base.display_for("rifle_carbine")
	t.check(guide != null and rack != null and guide.get_parent() == main.base
				and guide.target.is_equal_approx(rack.global_position)
				and guide.words().begins_with("Put on your gear"),
			"the guide's light stands on the welcome rifle with the step written over it")
	t.check(phone.notice_showing() == "Handler: Put on your gear in the armory" or phone.notices_paused
				or "Handler: Put on your gear in the armory" in phone.notices_waiting(),
			"the handler's pop-up says the step")
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
	main._tour_guide_tick(0.1)
	t.check(main._tour_guide == null and main.base_hud.tour_hint.begins_with("Press "),
			"with nothing to walk to, the guide goes and the key to press waits under the crosshair")
	t.check(not phone.notices_waiting().any(func(text: String) -> bool: return text.contains("Put on your gear")),
			"the step already done is never told")
	main.controller.wrist_raised = true
	await t.frames(3)
	main.controller.wrist_raised = false
	t.check(Profile.onboarding.step == "lane", "raising the watch finishes its step")
	main.base.target_hit.emit()
	await t.frames(2)
	t.check(Profile.onboarding.step == "plaza" and main.base_hud.objective.begins_with("Head out to "),
			"a hit on the test lane sends you out to the plaza")
	main._tour_guide_tick(0.1)
	t.check(main._tour_guide != null and main._tour_guide.target.is_equal_approx(main.base.door.global_position),
			"and the guide moves to the base's way out")

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

	Profile.onboarding = {"state": Onboarding.ACTIVE, "step": "bank"}
	main._tour_show()
	main._tour_guide_tick(0.1)
	t.check(main._tour_guide != null and main._tour_guide.target.is_equal_approx(main.base.door.global_position)
				and main._tour_guide.words().contains("first"),
			"a step out in a world, seen from home, leads to the way out first")
	# With the firing range built the lane is gone: the guide stands on the
	# range's targets instead.
	Profile.onboarding = {"state": Onboarding.ACTIVE, "step": "lane"}
	main._tour_show()
	main.base.show_gear(main.hub.stash_items(), main.hub.current_loadout(), ["firing_range"])
	await t.frames(2)
	main._tour_show()
	main._tour_guide_tick(0.1)
	t.check(main.base.lane_targets.is_empty() and not main.base.targets.is_empty() and main._tour_guide != null
				and main.base.targets.any(func(target: Variant) -> bool:
					return is_instance_valid(target) and (target as Node3D).global_position.is_equal_approx(main._tour_guide.target))
				and main._tour_guide.words().contains("firing range"),
			"with the firing range built, the lane step's guide stands on the range's targets")
	main.base.show_gear(main.hub.stash_items(), main.hub.current_loadout(), [])
	await t.frames(2)
	Profile.onboarding = {"state": Onboarding.ACTIVE, "step": "watch"}
	main._tour_show()

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
	for world in Worlds.raid_worlds():
		if Onboarding.locks(Profile.onboarding, world):
			main.start_raid(world.id)
			await t.frames(2)
			t.check(main.raid == null and phone.notices_waiting().any(func(text: String) -> bool: return text.contains("full loot"))
						or phone.notice_showing().contains("full loot"),
					"a new player is turned back from %s, and the handler says why" % world.display_name)
			break
	main.start_raid(gentle)
	await t.frames(10)
	t.check(Profile.onboarding.step == "bank" and main.hud != null and main.hud.objective == "Bank your loot at a depot",
			"arriving in a world finishes the deploy step, and the objective rides on the raid's watch and visor")
	main._tour_guide_tick(0.1)
	t.check(main._tour_guide != null and main._tour_guide.get_parent() == main.raid,
			"out in the world the guide stands on the nearest depot")
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
