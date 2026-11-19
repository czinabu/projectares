extends RefCounted
## The `vehicle_raids` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("Vehicles: raids")
	var world := Worlds.get_world("ashfront")
	Profile.reset()
	Profile.welcome_granted = true
	Profile.add_to_stash(["bike_raider"])
	t.check(Profile.equip("vehicle", "bike_raider"), "a bike goes in the vehicle slot")
	var kit := Profile.checkout_loadout(world)
	t.check("bike_raider" in kit and "bike_raider" not in Profile.stash, "deploying takes the bike out of the stash")

	var raid := Raid.new()
	t.add_child(raid)
	raid.start(world, 61, kit)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(10)
	var p := raid.player
	t.check(raid.stowed_for(p) == (["bike_raider"] as Array[String]), "your bike rides on your watch as a toy")
	var map_bikes := raid.vehicles.size()
	var own: Array = [raid.spawn_vehicle("bike_raider", p.global_position + Vector3(2.5, 0.3, 0), 0.0)]
	raid.state_for(p).stowed.clear()
	t.check("bike_raider" not in p.gear_items and not p.inventory.has_item("bike_raider"),
			"a bike is not carried and does not drop in your bag")
	t.check(raid.vehicles.size() >= 3, "the map parks abandoned bikes too (%d)" % (raid.vehicles.size() - 1))
	var ramps := raid.map.get_children().filter(func(n: Node) -> bool: return n.is_in_group("spawn_vehicle"))
	t.check(ramps.size() == map_bikes and map_bikes == raid.vehicles.size() - 1, "every vehicle marker gets a bike")

	var results: Array[Dictionary] = []
	raid.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results.append(r))
	var bike = own[0]
	t.check(bike.mount(p), "you can ride your own bike")
	raid.begin_sign_out(p)
	raid.state_for(p).sign_out_left = 0.1
	await t.frames(20)
	t.check(results.size() == 1 and results[0].outcome == "left", "you can sign out in the saddle")
	t.check("bike_raider" in Profile.stash and "bike_raider" in results[0].get("kept_gear", []),
			"riding out takes the bike home")
	await t._end_raid(raid)

	# Deploy with it again and die: the bike stays in the raid for anyone to take.
	t.check(Profile.equip("vehicle", "bike_raider"), "the bike can be equipped again")
	kit = Profile.checkout_loadout(world)
	var raid2 := Raid.new()
	t.add_child(raid2)
	raid2.start(world, 62, kit)
	for bot in raid2.bots:
		bot.get_node("Brain").set_physics_process(false)
	await t.frames(5)
	var results2: Array[Dictionary] = []
	raid2.player_finished.connect(func(_a: Actor, r: Dictionary) -> void: results2.append(r))
	raid2.player.kill("test")
	await t.frames(2)
	t.check(results2.size() == 1 and "bike_raider" in results2[0].lost and "bike_raider" not in Profile.stash,
			"dying loses the bike you brought")
	t.check(Profile.equipped("vehicle") == "", "a lost bike leaves the vehicle slot")
	await t._end_raid(raid2)


## Every world folder must honour the map contract and run a raid headless.
