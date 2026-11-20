extends RefCounted
## The Dune Sea's haul (DESIGN.md "The Dune Sea"): salvage crates on the
## wreck fields (`SalvageCrate`), lifted in both hands (slow, no weapon, no
## flight), loaded into a vehicle's cargo (a rover holds 4, a bike 1, Caleb's
## call) and banked at a depot; what you haul falls where you die, and you
## keep what you wear. A client is told where every crate is.

const NetSessionScript := preload("res://core/net/net_session.gd")


static func run(t: Node) -> void:
	print("Dune Sea: the haul")
	var world := Worlds.get_world("dunes")
	_settings(t, world)
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 11)
	await t.frames(3)
	var me := raid.player
	for bot in raid.bots:
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	var wanted := 0
	for wreck: Dictionary in raid.map.WRECKS:
		wanted += int(wreck["crates"])
	t.check(raid.crates.size() == wanted and wanted > 0, "a salvage crate stands at every wreck field's spot (%d)" % raid.crates.size())
	await _carry(t, raid, me)
	await _cargo(t, raid, me)
	await _death(t, raid, world)
	_respawn(t, raid)
	_client(t, raid)
	await t._end_raid(raid)


static func _settings(t: Node, world: WorldDef) -> void:
	t.check(world.keep_gear_on_death, "in the Dune Sea you keep what you wear when you die")
	var rng := RandomNumberGenerator.new()
	var value := 0
	var real := true
	for i in 40:
		rng.seed = i
		var items := world.roll_loot("crate", rng)
		real = real and items.size() >= 4 and items.all(func(id: String) -> bool: return ItemDB.has_item(id))
		value += ItemDB.total_value(items)
		rng.seed = i
		real = real and ItemDB.has_tag(world.roll_loot("vehicle", rng)[0], "vehicle")
	var cache := 0
	for i in 40:
		rng.seed = i
		cache += ItemDB.total_value(world.roll_loot("cache", rng))
	t.check(real, "a crate holds four to six real items, and the parked vehicles are vehicles")
	t.check(value > cache * 3, "a crate is worth several caches (%d against %d over 40)" % [value, cache])
	var cargo := {}
	for id: String in ["rover_warden", "bike_scrapper", "bike_raider", "mech_bulwark", "jet_kestrel"]:
		cargo[id] = (ItemDB.item_stats(id).get("cargo_points", []) as Array).size()
	t.check(cargo["rover_warden"] == 4 and cargo["bike_scrapper"] == 1 and cargo["bike_raider"] == 1
			and cargo["mech_bulwark"] == 0 and cargo["jet_kestrel"] == 0,
			"a rover holds four crates, a bike one, the mech and the jet none (%s)" % str(cargo))


## Lifting one: both hands, no weapon, a slow walk, no flight; set down again.
static func _carry(t: Node, raid: Raid, me: Actor) -> void:
	var crate: SalvageCrate = raid.crates[0]
	_stand(raid, me, crate.global_position + Vector3(0, 0, 2.0))
	await t.frames(4)
	t.check(crate.get_prompt() == "Lift salvage crate", "a crate on the sand says you can lift it")
	var why := raid.lift_crate(me, crate)
	t.check(why == "" and me.crate == crate and crate.holder == me, "you lift it in both hands (%s)" % why)
	t.check(crate.collision_layer == 0, "held, it neither blocks nor can be used")
	await t.frames(2)
	t.check(crate.global_position.distance_to(me.global_position) < 1.6, "it is held in front of you")
	var other: SalvageCrate = raid.crates[1]
	t.check(raid.lift_crate(me, other) != "", "and with your hands full you cannot lift another")
	me.cmd.switch_weapon = 0
	await t.frames(30)
	t.check(me.get_active_weapon() == null, "no weapon comes out while you carry it")
	me.cmd.switch_weapon = -1
	me.cmd.move = Vector2(0, 1)
	me.cmd.sprint = true
	await t.frames(40)
	var pace := Vector2(me.velocity.x, me.velocity.z).length()
	t.check(pace < me.walk_speed * 0.7 and pace > 0.5, "you walk it slowly and cannot sprint (%.1f m/s)" % pace)
	me.cmd.move = Vector2.ZERO
	me.cmd.sprint = false
	await t.frames(10)
	t.check(raid.set_down_crate(me, null) == "down" and me.crate == null and crate.holder == null
			and crate.collision_layer & Actor.LAYER_WORLD != 0, "with nothing to load it into, you set it down, solid")
	t.check(absf(crate.global_position.y - SalvageCrate.SIZE.y * 0.5
			- float(raid.map.call("ground_height", crate.global_position.x, crate.global_position.z))) < 0.6,
			"on the ground")


## Loading a rover and a bike, banking the rover's cargo at a depot.
static func _cargo(t: Node, raid: Raid, me: Actor) -> void:
	var depot: Depot = raid.depots[0]
	var rover := raid.spawn_vehicle("rover_warden", depot.global_position + Vector3(0, 0, 14.0), 0.0)
	var bike := raid.spawn_vehicle("bike_scrapper", depot.global_position + Vector3(8.0, 0, 14.0), 0.0)
	await t.frames(4)
	var seat: Interactable = rover.get_node("Seat") if rover.has_node("Seat") else null
	if seat == null:
		for child in rover.get_children():
			if child is Interactable:
				seat = child
				break
	var bike_seat: Interactable = null
	for child in bike.get_children():
		if child is Interactable:
			bike_seat = child
			break
	var loaded := 0
	var picked: Array[SalvageCrate] = []
	var items: Array[String] = []
	for crate: SalvageCrate in raid.crates.duplicate():
		if loaded >= 4:
			break
		_stand(raid, me, crate.global_position + Vector3(0, 0, 1.5))
		await t.frames(3)
		if raid.lift_crate(me, crate) != "":
			continue
		if raid.set_down_crate(me, seat) == "":
			loaded += 1
			picked.append(crate)
			items.append_array(crate.items)
	t.check(loaded == 4 and (rover.get("cargo") as Array).all(func(c: Variant) -> bool: return c != null),
			"a rover takes four crates into its cargo")
	await t.frames(2)
	var points: Array = rover.get("cargo_points")
	t.check(picked[0].global_position.distance_to(rover.global_transform * (points[0] as Vector3)) < 1.0,
			"each rides at its cargo point")
	var fifth: SalvageCrate = null
	for crate: SalvageCrate in raid.crates:
		if crate.holder == null:
			fifth = crate
			break
	_stand(raid, me, fifth.global_position + Vector3(0, 0, 1.5))
	await t.frames(3)
	raid.lift_crate(me, fifth)
	t.check(raid.set_down_crate(me, seat) == "full" and me.crate == fifth, "a fifth will not fit; you keep holding it")
	t.check(raid.set_down_crate(me, bike_seat) == "" and (bike.get("cargo") as Array)[0] == fifth,
			"a bike takes one")
	_stand(raid, me, rover.global_position + Vector3(2.8, 0, 0))
	await t.frames(4)
	me.cmd.yaw = atan2(-(rover.global_position - me.global_position).x, -(rover.global_position - me.global_position).z)
	me.cmd.pitch = -0.25
	t.check(raid.pack_vehicle(me) == "Unload its cargo first", "a vehicle with cargo cannot be packed onto the watch")
	# Unloading one by hand, and loading it back.
	var prompt := picked[3].get_prompt()
	var why := raid.lift_crate(me, picked[3])
	t.check(prompt == "Unload salvage crate" and why == "" and (rover.get("cargo") as Array)[3] == null,
			"a crate can be lifted back out of the cargo (%s, %s)" % [prompt, why])
	raid.set_down_crate(me, seat)
	# Drive it into the depot and hold: the cargo is banked, with the pack.
	rover.global_position = depot.global_position + Vector3(0, -1.0, 0)
	rover.call("mount", me)
	await t.frames(3)
	t.check(SalvageCrate.hauled_by(me).size() == 4, "driving, you haul the rover's four crates")
	var state := raid.state_for(me)
	var before := state.banked.size()
	raid.call("_on_actor_banked", me)
	var banked := state.banked.slice(before)
	t.check(items.all(func(id: String) -> bool: return id in banked) and banked.size() >= items.size(),
			"at a depot the cargo's contents are banked (%d items)" % banked.size())
	await t.frames(2)
	t.check(picked.all(func(c: Variant) -> bool: return not is_instance_valid(c))
			and (rover.get("cargo") as Array).all(func(c: Variant) -> bool: return c == null),
			"and the crates are gone from the cargo")
	rover.call("dismount")
	await t.frames(2)


## Dying: the pack in a bag, the gear kept, and every crate hauled falls.
static func _death(t: Node, raid: Raid, world: WorldDef) -> void:
	var me := raid.player
	var rover: Node3D = null
	for vehicle in raid.vehicles:
		if vehicle.get("item_id") == "rover_warden":
			rover = vehicle
	var loaded: Array[SalvageCrate] = []
	for crate: SalvageCrate in raid.crates.duplicate():
		if loaded.size() >= 2 or crate.holder != null:
			continue
		_stand(raid, me, crate.global_position + Vector3(0, 0, 1.5))
		await t.frames(3)
		raid.lift_crate(me, crate)
		for child in rover.get_children():
			if child is Interactable:
				raid.set_down_crate(me, child)
				break
		loaded.append(crate)
	me.global_position = rover.global_position + Vector3(3, 0, 0)
	await t.frames(2)
	rover.call("mount", me)
	await t.frames(2)
	var worn := me.gear_items.duplicate()
	var finished := []
	raid.player_finished.connect(func(_who: Actor, result: Dictionary) -> void: finished.append(result), CONNECT_ONE_SHOT)
	me.kill("test")
	await t.frames(3)
	t.check(loaded.size() == 2 and loaded.all(func(c: SalvageCrate) -> bool:
			return is_instance_valid(c) and c.holder == null and c.collision_layer & Actor.LAYER_WORLD != 0)
			and (rover.get("cargo") as Array).all(func(c: Variant) -> bool: return c == null),
			"killed at the wheel, every crate in your vehicle falls to the sand")
	var kept: Array = finished[0].get("kept", []) if not finished.is_empty() else []
	t.check(not finished.is_empty() and worn.all(func(id: String) -> bool:
			return ItemDB.has_tag(id, "starter") or id in kept), "and you keep what you wore")


## A marker whose crate is gone gets a new one in time; a crate left lying
## elsewhere is cleared away.
static func _respawn(t: Node, raid: Raid) -> void:
	var spots: Array = raid.get("_crate_spots")
	var empty := 0
	for spot: Dictionary in spots:
		var crate: Variant = spot.crate
		if crate == null or not is_instance_valid(crate) or (crate as SalvageCrate).holder != null \
				or (crate as SalvageCrate).global_position.distance_to((spot.marker as Node3D).global_position) > 3.0:
			empty += 1
	var before := raid.crates.size()
	raid.call("_tick_crates", raid.world.crate_respawn_time + 1.0)
	t.check(empty > 0 and raid.crates.size() >= before + empty - 1, "an emptied spot gets a new crate (%d spots)" % empty)
	var stray := raid.spawn_crate(["scrap_metal"], raid.player.global_position + Vector3(40, 0, 0))
	raid.call("_tick_crates", raid.world.crate_lifetime + 1.0)
	t.check(stray.is_queued_for_deletion(), "a crate left lying away from the wrecks is cleared in time")


## A client hears of each crate and where it is, never what is inside.
static func _client(t: Node, raid: Raid) -> void:
	var session := NetSessionScript.new()
	var client := Raid.new()
	t.add_child(client)
	client.start_client(raid.world)
	session.raid = client
	session.call("_crate", 900, [Vector3(5, 2, 5), 0, -1, -1])
	var crates: Dictionary = session.get("_crates")
	var crate: SalvageCrate = crates.get(900)
	t.check(crate != null and crate.items.is_empty() and crate.global_position.is_equal_approx(Vector3(5, 2, 5)),
			"a client is told where a crate stands, not what is in it")
	var carrier := Actor.new()
	client.add_child(carrier)
	(session.get("_actors") as Dictionary)[901] = carrier
	session.call("_crate_moved", 900, [Vector3.ZERO, 1, 901, -1])
	t.check(carrier.crate == crate and crate.holder == carrier, "and who carries it, so their walk is predicted slow")
	session.call("_crate_moved", 900, [Vector3(1, 0, 1), 0, -1, -1])
	t.check(carrier.crate == null and crate.holder == null, "and when it is set down")
	session.call("_crate_gone", 900)
	t.check(not (session.get("_crates") as Dictionary).has(900), "and when it is gone")
	session.call("_crate_moved", 900, [Vector3.ZERO])
	t.check(true, "a malformed message is ignored")
	session.free()
	client.queue_free()


## Puts `me` on the ground at `at`'s spot.
static func _stand(raid: Raid, me: Actor, at: Vector3) -> void:
	me.global_position = Vector3(at.x, float(raid.map.call("ground_height", at.x, at.z)) + 0.05, at.z)
	me.velocity = Vector3.ZERO
