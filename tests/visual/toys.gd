extends RefCounted
## `--toys-only`, a mode `visual_check.gd` finds by itself.
## `-- <output_dir> --toys-only` shows the toy vehicles: on the watch, in
## the hand, in the air, unpacking and unpacked.


static func shoot(v: Node, out_dir: String, _args: PackedStringArray) -> void:
	var raid := Raid.new()
	v.add_child(raid)
	var world := Worlds.get_world("ashfront")
	raid.start(world, 42, world.starter_loadout() + (["bike_scrapper"] as Array[String]))
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	raid.state_for(raid.player).stowed.append("bike_raider")
	var controller := PlayerController.new()
	controller.setup(raid.player)
	raid.add_child(controller)
	controller.toy_hold_requested.connect(func(id: String) -> void: raid.hold_toy(raid.player, id))
	controller.toy_throw_requested.connect(func(id: String) -> void: raid.throw_toy(raid.player, id))
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	await v._settle(90)
	for view in ["first", "third"]:
		if view == "third":
			controller.toggle_view()
			await v._settle(30)
		var state := raid.state_for(raid.player)
		state.toy_ready_at = raid.clock
		controller.pitch = 0.0
		controller.wrist_raised = true
		controller.watch_focus_moved = false
		controller.click_watch()
		await v._settle(40)
		await v._shot(out_dir.path_join("toys_watch_%s.png" % view))
		if view == "first":
			controller.watch_index = 1
			await v._settle(20)
			await v._shot(out_dir.path_join("toys_watch_picked_second.png"))
		controller.watch_index = 0
		controller.take_picked_toy()
		# The weapon goes away, then the toy digitizes into the hand.
		await v._settle(24)
		await v._shot(out_dir.path_join("toys_%s_1_digitizing.png" % view))
		await v._settle(30)
		await v._shot(out_dir.path_join("toys_%s_2_in_hand.png" % view))
		controller.pitch = -0.1
		await v._settle(5)
		controller.throw_held_toy()
		# The throw, frame by frame at 60 fps: drawn back, coming through,
		# let go, the follow-through.
		var frames := [7, 5, 4, 4, 6]
		var names := ["3_drawn_back", "4_coming_through", "5_let_go", "6_follow_through", "7_toy_away"]
		for i in frames.size():
			await v._settle(frames[i])
			await v._shot(out_dir.path_join("toys_%s_%s.png" % [view, names[i]]))
		for i in 200:
			if raid.toys.is_empty():
				break
			await v._settle(1)
		await v._settle(4)
		await v._shot(out_dir.path_join("toys_%s_8_unpacking.png" % view))
		await v._settle(60)
		await v._shot(out_dir.path_join("toys_%s_9_unpacked.png" % view))
		# Pack it again for the next view.
		var bike: Node3D = raid.vehicles[raid.vehicles.size() - 1]
		raid.remove_vehicle(bike)
		state.parked.erase(bike)
		state.stowed.insert(0, "bike_scrapper")
		await v._settle(10)
	raid.queue_free()
	await v._settle(2)
