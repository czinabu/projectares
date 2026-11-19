extends RefCounted
## Every place and every screen, opened and closed with nothing logged: the
## home base (its stations, the gunsmith bench and the plan table), each
## world, and in each of them the phone's apps and settings tabs and the
## watch's icons, in both views. A screen that throws an error when it
## opens is the first thing a tester meets, so not one error may be logged
## anywhere (`ErrorSpamTests.watch`).
## Called from the test runner (`-- --only` does not reach this file; the
## runner calls `run`).

const ErrorSpamTests := preload("res://tests/error_spam_tests.gd")
const PhoneScript := preload("res://core/phone/phone.gd")


static func run(t: Node) -> void:
	print("Screen sweep: every place and every screen opens and closes cleanly")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	t.add_child(main)
	await t.frames(10)
	await _sweep_base(t, main)
	for world: WorldDef in Worlds.all():
		await _sweep_world(t, main, world.id)
	main.queue_free()
	await t.frames(5)


static func _sweep_base(t: Node, main: Node) -> void:
	main.go_home()
	await t.frames(10)
	var base: HomeBase = main.base
	t.check(base != null and main.controller != null, "the home base opens")
	if base == null or main.controller == null:
		return
	var errors := ErrorSpamTests.watch()
	var stations: Array = HomeBase.STATIONS.keys()
	stations.append(HomeBase.CRAFT_ID)
	var opened: Array[String] = []
	for id: String in stations:
		if base.station(id) == null:
			continue
		main.open_station(id)
		await t.frames(5)
		if main.hub.is_open():
			opened.append(id)
		main.hub.close()
		await t.frames(3)
	t.check(not opened.is_empty() and main.station_screen == null and not main.hub.is_open(),
			"the base's stations open and close (%s)" % ", ".join(opened))
	for target: String in ["bench", "plan"]:
		main.open_bench(target)
		await t.frames(10)
		var view: Node = main.bench_view
		t.check(view != null, "the %s view opens" % target)
		if view != null:
			view.leave()
			await t.frames(10)
		t.check(main.bench_view == null, "and closes again (%s)" % target)
	await _sweep_hand(t, main, "the home base")
	OS.remove_logger(errors)
	t.check(errors.count == 0, "the home base's screens log no errors (%s)" % errors.said())


static func _sweep_world(t: Node, main: Node, world_id: String) -> void:
	main.start_raid(world_id)
	await t.frames(15)
	var raid: Raid = main.raid
	var name := world_id
	if raid != null and raid.world != null:
		name = raid.world.display_name
	t.check(raid != null and raid.player != null and main.controller != null, "%s opens" % name)
	if raid == null or raid.player == null or main.controller == null:
		_leave(main)
		await t.frames(5)
		return
	var errors := ErrorSpamTests.watch()
	for view in 2:
		await t.frames(30)
		await _sweep_hand(t, main, "%s (%s)" % [name, "third person" if view == 1 else "first person"])
		main.controller.toggle_view()
	await t.frames(5)
	OS.remove_logger(errors)
	t.check(errors.count == 0, "%s and its screens log no errors in either view (%s)" % [name, errors.said()])
	_leave(main)
	await t.frames(10)


## Out of a solo world without a result, the way the game goes home.
static func _leave(main: Node) -> void:
	if main.raid != null:
		main._show_hub({})


## What is in the hand: every phone app and settings tab, then the watch
## raised and every icon on its card brought up, opened where it opens and
## closed again. Nothing is clicked, so nothing is used.
static func _sweep_hand(t: Node, main: Node, where: String) -> void:
	var context: Dictionary = main.report_context()
	t.check(str(context.get("place", "")) != "" and context.has("fps"),
			"%s: a bug report says where the player is (%s)" % [where, context.get("place", "")])
	var phone: CanvasLayer = main.phone
	if phone != null:
		if not phone.is_open:
			phone.toggle()
		await t.frames(3)
		var pages := 0
		for tab: String in phone.settings_tabs():
			phone.open_settings_tab(tab)
			await t.frames(2)
			pages += 1
		for app_name: String in PhoneScript.APPS:
			phone.open_app(app_name)
			await t.frames(2)
			pages += 1
		phone.close()
		await t.frames(3)
		t.check(not phone.is_open and pages == phone.settings_tabs().size() + PhoneScript.APPS.size(),
				"%s: every phone app and settings tab opens, and the phone puts away" % where)
	var controller: PlayerController = main.controller
	if controller == null or not is_instance_valid(controller):
		return
	controller.wrist_raised = true
	await t.frames(10)
	var slots: Array = Hud.Wrist.SLOTS
	controller.watch_focus = 0
	controller.watch_focus_moved = true
	var seen: Array[String] = []
	for i in slots.size():
		await t.frames(2)
		var icon := controller.focused_watch_icon()
		if icon != "":
			seen.append(icon)
		if icon != "" and controller.watch_entries(icon) > 1:
			controller.watch_open = icon
			await t.frames(3)
			controller.step_watch(1)
			await t.frames(2)
			controller.close_watch_icon()
		controller.step_watch(1)
	controller.wrist_raised = false
	await t.frames(5)
	t.check(seen.size() == slots.size(), "%s: the wheel reaches every watch icon (%d of %d)"
			% [where, seen.size(), slots.size()])
	# Emotes are for every place you stand (Caleb's call): the quick wheel
	# comes up, a pick plays on the body, and it puts away again.
	var p: Actor = controller.actor
	controller.open_emote_wheel()
	await t.frames(5)
	var up := controller.emote_wheel_open
	controller.emote_wheel_pick = Emotes.IDS.find("wave")
	controller.close_emote_wheel(true)
	await t.frames(30)
	t.check(up and controller.emote_playing == "wave" and p.cmd.emote == Emotes.number_of("wave")
			and ActionPose.of(p).emote > 0.5, "%s: the emote wheel plays an emote on the body" % where)
	controller.stop_emote()
	await t.frames(10)
