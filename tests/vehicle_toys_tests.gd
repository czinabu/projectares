extends RefCounted
## The `vehicle_toys` checks. The test runner finds this file by itself and calls
## `run(t)`.

const VehicleScript := preload("res://core/vehicle/vehicle.gd")


static func run(t: Node) -> void:
	print("Vehicles: toys on the watch")
	var toy: Node3D = VehicleScript.toy_model("bike_scrapper")
	t.check(toy.get_node_or_null("Model") != null and is_equal_approx(toy.scale.x, VehicleScript.TOY_SCALE)
			and toy.find_children("*", "CollisionShape3D", true, false).is_empty(),
			"a toy is the vehicle's own model, toy-sized, with no collision")
	toy.free()
	var world := Worlds.get_world("ashfront")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(world, 71, world.starter_loadout() + (["bike_scrapper"] as Array[String]))
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
		bot.global_position += Vector3(0, 0, 3000)
	await t.frames(10)
	var p := raid.player
	var state := raid.state_for(p)
	var before := raid.vehicles.size()
	t.check(raid.stowed_for(p) == (["bike_scrapper"] as Array[String]), "a brought bike starts as a toy on the watch")
	# Stand on a wide open floor, well away from the map.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Actor.LAYER_WORLD
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(80, 1, 80)
	var floor_col := CollisionShape3D.new()
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	raid.add_child(floor_body)
	floor_body.global_position = Vector3(0, 199.5, 2500)
	var wall := StaticBody3D.new()
	wall.collision_layer = Actor.LAYER_WORLD
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(6, 6, 1)
	var wall_col := CollisionShape3D.new()
	wall_col.shape = wall_shape
	wall.add_child(wall_col)
	raid.add_child(wall)
	wall.global_position = Vector3(30, 203, 2500)
	p.global_position = Vector3(0, 200.05, 2500)
	p.velocity = Vector3.ZERO
	await t.frames(5)

	var events := {"thrown": 0, "landed": [], "watch": 0}
	raid.toy_thrown.connect(func(_a: Actor, _id: String, _from: Vector3, _v: Vector3) -> void: events.thrown += 1)
	raid.toy_landed.connect(func(_a: Actor, _id: String, _at: Vector3, ok: bool) -> void: events.landed.append(ok))
	raid.watch_changed.connect(func(_a: Actor) -> void: events.watch += 1)
	t.check(raid.throw_toy(p, "bike_raider") != "" and events.thrown == 0, "a toy that is not on your watch cannot be thrown")
	t._aim_at(p, p.global_position + Vector3(0, 1.6, -10))
	var throws_before := p.toy_throws
	t.check(raid.throw_toy(p, "bike_scrapper") == "" and events.thrown == 0 and raid.toys.size() == 1
			and raid.stowed_for(p).is_empty() and p.toy_in_hand == "bike_scrapper" and p.toy_throws == throws_before + 1,
			"throwing takes the toy off the watch and starts the throw with it in the hand")
	t.check(raid.hold_toy(p, "bike_scrapper") != "" and raid.throw_toy(p, "bike_scrapper") != "",
			"nothing else goes in the hand or is thrown while the arm comes through")
	await t.frames(int(raid.toy_windup * 60.0) - 6)
	t.check(events.thrown == 0 and p.toy_in_hand == "bike_scrapper", "the toy stays in the hand through the windup")
	await t._wait_until(func() -> bool: return events.thrown == 1, 30)
	var flying: Dictionary = raid.toys[0] if not raid.toys.is_empty() else {}
	t.check(events.thrown == 1 and p.toy_in_hand == "" and flying.get("node") != null,
			"then it leaves the hand and flies")
	t.check(is_equal_approx(raid.toy_windup, ActionPose.of(p).toy_release),
			"the toy leaves the hand when the throw shown lets go of it")
	t.check(raid.vehicles.size() == before, "nothing unpacks while the toy is in the air")
	var last_basis := Basis()
	while not raid.toys.is_empty() and raid.toys[0].get("node") != null:
		last_basis = (raid.toys[0].node as Node3D).basis.orthonormalized()
		await t.get_tree().physics_frame
	t.check(last_basis.y.dot(Vector3.UP) > 0.95 and absf(last_basis.z.dot(Basis(Vector3.UP, p.cmd.yaw).z)) > 0.95,
			"the toy turns its flip and comes down level, facing the way it unpacks")
	await t._wait_until(func() -> bool: return not events.landed.is_empty(), 240)
	var bike: Node3D = raid.vehicles[raid.vehicles.size() - 1] if raid.vehicles.size() > before else null
	t.check(events.landed == [true] and bike != null and bike.get("item_id") == "bike_scrapper",
			"the toy unpacks into the bike where it lands")
	if bike != null:
		var away := Vector3(bike.global_position.x - p.global_position.x, 0, bike.global_position.z - p.global_position.z)
		t.check(away.z < -4.0 and away.length() < 25.0 and absf(away.x) < 2.0,
				"it lands ahead of the thrower, where they aimed (%.1f m)" % away.length())
		t.check(float(bike.get("unpack_left")) > 0.0 and not bike.call("mount", p), "it grows from toy size, and cannot be ridden until it has")
		await t.frames(60)
		t.check(float(bike.get("unpack_left")) == 0.0 and bike.get_node("Model").scale.is_equal_approx(Vector3.ONE)
				and bike.is_on_floor(), "then it stands full size on the ground")
		t.check(raid.toy_wait(p) > 0.0, "the watch needs a moment before the next throw")

		# Packing it up again.
		p.global_position = bike.global_position + Vector3(2.0, 0.1, 0)
		t._aim_at(p, bike.global_position + Vector3(0, 0.6, 0))
		await t.frames(2)
		t.check(raid.pack_vehicle(p) == "" and raid.stowed_for(p) == (["bike_scrapper"] as Array[String])
				and raid.vehicles.size() == before, "looking at your bike and packing it puts the toy back on the watch")
		await t.frames(2)
		t.check(raid.throw_toy(p, "bike_scrapper") != "" and raid.stowed_for(p).size() == 1, "you cannot throw again until the watch recharges")
		state.toy_ready_at = raid.clock

	# No room: thrown at the foot of a wall, it comes back.
	p.global_position = Vector3(27.5, 200.05, 2502.2)
	await t.frames(3)
	t._aim_at(p, Vector3(29.4, 200.0, 2501.3))
	events.landed.clear()
	t.check(raid.throw_toy(p, "bike_scrapper") == "", "the toy can be thrown at a wall")
	await t.frames(int(raid.toy_windup * 60.0) + 4)
	t._aim_at(p, Vector3(29.4, 200.0, 2501.3))
	await t._wait_until(func() -> bool: return not events.landed.is_empty(), 240)
	t.check(events.landed == [false] and raid.vehicles.size() == before and raid.stowed_for(p).size() == 1
			and raid.toy_wait(p) == 0.0, "with no room to unpack, the toy jumps back onto the watch")
	t.check(not raid.has_room_to_unpack(p.global_position, 0.0) and raid.has_room_to_unpack(Vector3(-20, 200.0, 2500), 0.0),
			"room means clear of walls, people and other vehicles")

	# Holding a toy up is only the look: it stays on the watch.
	t.check(raid.hold_toy(p, "bike_scrapper") == "" and p.toy_in_hand == "bike_scrapper"
			and raid.stowed_for(p).size() == 1, "a toy taken in hand shows there and stays on the watch")
	t.check(raid.hold_toy(p, "bike_raider") != "" and p.toy_in_hand == "", "only a toy on the watch can be held")
	# Knocked out of the throw: on a vehicle before it leaves the hand.
	p.global_position = Vector3(0, 200.05, 2500)
	var saddle: Node3D = raid.spawn_vehicle("bike_raider", Vector3(3, 200.3, 2500), 0.0)
	await t.frames(10)
	events.thrown = 0
	t.check(raid.throw_toy(p, "bike_scrapper") == "", "a throw starts")
	saddle.call("mount", p)
	await t.frames(int(raid.toy_windup * 60.0) + 4)
	t.check(events.thrown == 0 and raid.stowed_for(p).size() == 1 and raid.toy_wait(p) == 0.0 and p.toy_in_hand == "",
			"a throw cut short before it leaves the hand puts the toy back on the watch")
	saddle.call("dismount")
	raid.remove_vehicle(saddle)

	# Limits.
	p.global_position = Vector3(0, 200.05, 2500)
	var spare: Node3D = raid.spawn_vehicle("bike_raider", Vector3(3, 200.3, 2500), 0.0)
	await t.frames(10)
	t.check(spare.call("mount", p) and raid.throw_toy(p, "bike_scrapper") != "", "you cannot throw from the saddle")
	spare.call("dismount")
	raid.begin_sign_out(p)
	t.check(raid.throw_toy(p, "bike_scrapper") != "", "you cannot throw while signing out")
	raid.cancel_sign_out(p)
	world.vehicle_toys = false
	t.check(raid.throw_toy(p, "bike_scrapper") != "", "a world can keep vehicles on the watch")
	world.vehicle_toys = true
	t._aim_at(p, spare.global_position + Vector3(0, 0.6, 0))
	await t.frames(2)
	t.check(raid.pack_vehicle(p) == "" and raid.stowed_for(p).size() == 2, "a bike found in the field packs onto the watch too")
	var third: Node3D = raid.spawn_vehicle("bike_raider", Vector3(3, 200.3, 2500), 0.0)
	await t.frames(10)
	t._aim_at(p, third.global_position + Vector3(0, 0.6, 0))
	await t.frames(2)
	t.check(raid.pack_vehicle(p) != "" and third in raid.vehicles, "the watch holds only so many (%d)" % raid.watch_capacity)
	t.check(events.watch >= 4, "the watch reports every change")

	# The controller: the watch key takes a toy in hand, fire throws it.
	var controller := PlayerController.new()
	controller.setup(p)
	raid.add_child(controller)
	var asked: Array[String] = []
	controller.toy_throw_requested.connect(func(id: String) -> void: asked.append(id))
	t._aim_at(p, p.global_position + Vector3(0, 1.6, 10))
	# The watch: raised, it shows the toys; the wheel picks, fire takes one.
	var hud := Hud.new()
	hud.setup(raid, controller)
	raid.add_child(hud)
	controller.wrist_raised = true
	t.check(controller.is_browsing_toys(), "raising the watch with toys on it lets you pick one")
	var weapon_before := p.active_weapon_index
	var vehicle_at := Hud.Wrist.SLOTS.find("vehicle")
	t.check(not controller.is_picking_toys() and controller.focused_watch_icon() == "vehicle",
			"the card opens on the vehicles, closed: the toys wait for a click")
	t.check(controller.watch_takes_fire() and controller.click_watch() and controller.watch_open == "vehicle"
			and controller.is_picking_toys() and controller.held_toy == "", "a click opens the vehicle icon's list")
	controller.scroll(1)
	t.check(controller.watch_index == 1 and controller._pending_switch < 0 and p.active_weapon_index == weapon_before,
			"with the list open the wheel turns through the toys, not the weapons")
	controller.scroll(1)
	t.check(controller.watch_focus == vehicle_at and controller.watch_index == 1 and controller.is_picking_toys(),
			"the list stops at its last toy; the wheel never leaves it")
	t.check(controller.close_watch_icon() and controller.watch_open == "" and not controller.is_picking_toys(),
			"a right click closes the list")
	controller.scroll(1)
	t.check(controller.watch_focus == vehicle_at + 1 and controller.watch_index == 1,
			"closed, the wheel steps across the icons and leaves the pick alone")
	controller.scroll(-1)
	t.check(controller.watch_focus == vehicle_at and controller.watch_index == 1, "back on the vehicles, the second toy still picked")
	controller.wrist_raised = false
	controller.scroll(1)
	t.check(controller._pending_switch >= 0, "with the watch down the wheel switches weapons again")
	controller._pending_switch = -1
	controller.wrist_raised = true
	t.check(controller.click_watch() and controller.watch_open == "vehicle", "raised again, a click opens the toys")
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	t.check(hud.wrist.toys_shown() == raid.stowed_for(p) and hud.wrist.get_node("Hologram/Toys").get_child_count() == 2,
			"the watch stands each toy over its hologram")
	var shown := hud.wrist.get_node("Hologram/Toys")
	t.check(shown.get_child(1).scale.x > shown.get_child(0).scale.x and hud.wrist.focused_id() == "vehicle"
			and hud.wrist.text().begins_with("Raider Hoverbike") and shown.visible,
			"the card opens on the vehicles, the picked toy stands out and the watch names it")
	t.check("wheel" in hud.wrist.focused_hints() and "click" in hud.wrist.focused_hints()
			and not hud.wrist.text().contains("click"), "its controls are glyphs, not words")
	t.check(Hud.Wrist.toy_tint(true, true) != Hud.Wrist.toy_tint(true, false), "the toys dim while the watch recharges")
	controller.take_picked_toy()
	t.check(controller.held_toy == "bike_raider" and not controller.wrist_raised and not controller.is_browsing_toys(),
			"fire takes the picked toy into the hand and lowers the wrist")
	controller.hold_toy("")
	# Looking at a bike with the watch up, the click packs it instead.
	var packs := [0]
	controller.pack_requested.connect(func() -> void: packs[0] += 1)
	controller.wrist_raised = true
	t._aim_at(p, third.global_position + Vector3(0, 0.6, 0))
	controller.yaw = p.cmd.yaw
	controller.pitch = p.cmd.pitch
	await t.frames(2)
	t.check(controller.pack_target() == third and controller.click_watch() and packs[0] == 1 and controller.held_toy == "",
			"with the watch up, clicking on a bike asks to pack it")
	hud._process(0.016)
	t.check(hud.wrist.text().begins_with("Pack Raider Hoverbike") and hud.wrist.focused_hints() == ["click"],
			"and the watch says so, with a click glyph")
	t._aim_at(p, p.global_position + Vector3(0, 1.6, 10))
	controller.yaw = p.cmd.yaw
	controller.pitch = p.cmd.pitch
	await t.frames(2)
	controller.wrist_raised = false
	t.check(controller.pack_target() == null and not controller.click_watch(), "with the watch down a click is an ordinary shot")
	hud.queue_free()
	var held_asked: Array[String] = []
	controller.toy_hold_requested.connect(func(id: String) -> void:
		held_asked.append(id)
		raid.hold_toy(p, id))
	controller.hold_toy("bike_scrapper")
	t.check(controller.held_toy == "bike_scrapper" and held_asked == (["bike_scrapper"] as Array[String])
			and p.toy_in_hand == "bike_scrapper", "a toy off the watch goes into the hand, for everyone to see")
	p.cmd.primary_pressed = true
	controller._use_toy_hand(p.cmd)
	t.check(asked == (["bike_scrapper"] as Array[String]) and controller.held_toy == "" and not p.cmd.primary_pressed,
			"fire throws the toy instead of shooting")
	p.cmd.primary_pressed = true
	p.cmd.primary = true
	controller._use_toy_hand(p.cmd)
	t.check(not p.cmd.primary_pressed and not p.cmd.primary, "the weapon takes no fire while the arm comes through the throw")
	controller.hold_toy("bike_scrapper")
	t.check(controller.held_toy == "", "nor does another toy come into the hand mid-throw")
	controller._toy_busy_left = 0.0
	controller.hold_toy("bike_scrapper")
	p.cmd.secondary_pressed = true
	controller._use_toy_hand(p.cmd)
	t.check(controller.held_toy == "" and asked.size() == 1 and held_asked.back() == "" and p.toy_in_hand == "",
			"aim puts the toy back on the watch")
	controller.queue_free()

	# Leaving with toys on the watch takes them home; dying loses them.
	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	raid._leave(state)
	await t.frames(2)
	t.check(results.size() == 1 and "bike_scrapper" in results[0].brought_home and "bike_raider" in results[0].brought_home
			and "bike_scrapper" not in results[0].lost, "signing out takes the toys on your watch home")
	await t._end_raid(raid)

	var raid2 := Raid.new()
	t.add_child(raid2)
	raid2.start(world, 72, world.starter_loadout() + (["bike_scrapper"] as Array[String]))
	for bot in raid2.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(5)
	var results2: Array[Dictionary] = []
	raid2.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results2.append(r))
	raid2.player.kill("test")
	await t.frames(2)
	t.check(results2.size() == 1 and "bike_scrapper" in results2[0].lost and "bike_scrapper" not in results2[0].get("brought_home", []),
			"dying loses the toy on your watch")
	await t._end_raid(raid2)


## The toy in the hand and the throw are one shared pose (`ActionPose`), so
## first and third person and everyone around see the same arm.
