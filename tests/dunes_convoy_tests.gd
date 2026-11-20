extends RefCounted
## The Dune Sea's convoys (DESIGN.md "The Dune Sea (part three)", Caleb's
## call: a hauler convoy, roof guns on the rovers): a world event of armed
## vehicles driven by bots along one of the map's roads, the hauler's cargo
## full of crates. Drop its driver and the crates spill and the escort gets
## off to fight; let it through and it is gone.


static func run(t: Node) -> void:
	print("Dune Sea: convoys")
	var world := Worlds.get_world("dunes")
	var raid := world.new_raid()
	t.add_child(raid)
	raid.start(world, 5)
	await t.frames(3)
	var me := raid.player
	me.global_position += Vector3(0, 0, 60)
	me.set_physics_process(false)
	t.check(raid.start_event("convoy"), "a convoy can be called as a world event")
	var convoy: Dictionary = raid.convoy
	var vehicles: Array = convoy.vehicles
	var hauler: Node3D = vehicles[0]
	t.check(vehicles.size() == world.convoy_vehicles.size(), "the hauler and its escort are on the road (%d)" % vehicles.size())
	var full := (hauler.get("cargo") as Array).all(func(c: Variant) -> bool: return c is SalvageCrate)
	t.check(full, "the hauler's cargo is full of salvage crates")
	var driven := true
	for i in vehicles.size():
		driven = driven and (vehicles[i] as Node3D).get("rider") == convoy.drivers[i]
	t.check(driven, "a bot drives each vehicle")
	var escort: Node3D = vehicles[1]
	var gunner: Variant = (escort.get("passengers") as Array)[0]
	t.check(gunner is Actor and (gunner as Actor).get_active_weapon() != null
			and (gunner as Actor).get_active_weapon().item_id == "mount_roof_gun",
			"an escort rover's gunner is on its roof gun")
	var route: Array = convoy.route
	# The roof gun is anyone's who climbs up.
	await _roof_gun(t, raid, me)
	# Someone standing by the road gets the roof gun turned on them.
	var gun: Gun = (gunner as Actor).get_active_weapon()
	me.protected_left = 0.0
	me.set_physics_process(true)
	me.global_position = raid.call("_stand", escort.global_position + Vector3(22, 0, 8))
	await t.frames(300)
	t.check(gun.ammo_in_mag < gun.mag_size, "the escort's gunner opens up on someone by the road (%d of %d left)" % [gun.ammo_in_mag, gun.mag_size])
	me.health.health = me.health.max_health
	me.global_position += Vector3(0, 0, 400)
	me.set_physics_process(false)
	await t.frames(300)
	t.check(int(convoy.next[0]) >= 2 and int(convoy.next[1]) >= 2,
			"the convoy drives its road, the escort behind the hauler (%d, %d of %d points)"
			% [int(convoy.next[0]), int(convoy.next[1]), route.size()])
	var gap := hauler.global_position.distance_to(escort.global_position)
	t.check(gap > 6.0 and gap < 60.0, "keeping its distance (%.0f m)" % gap)
	# Drop the hauler's driver: the crates spill and the escort gets off.
	var crates: Array = (hauler.get("cargo") as Array).duplicate()
	var bots_before := raid.bots.size()
	var driver: Actor = convoy.drivers[0]
	Combat.deal(driver, DamageInfo.make(9999.0, me, "bullet"))
	await t.frames(3)
	t.check(crates.all(func(c: Variant) -> bool: return is_instance_valid(c) and (c as SalvageCrate).holder == null),
			"drop the hauler's driver and its crates spill on the sand")
	t.check(raid.event.is_empty(), "the convoy is stopped: the event is over")
	var aboard := 0
	for vehicle: Variant in vehicles:
		if is_instance_valid(vehicle):
			aboard += (vehicle.get("passengers") as Array).filter(func(a: Variant) -> bool: return a != null).size()
			aboard += 1 if vehicle.get("rider") != null else 0
	t.check(aboard == 0 and raid.bots.size() == bots_before - 1,
			"its escort gets off to fight and stays in the world (%d aboard, %d bots of %d)" % [aboard, raid.bots.size(), bots_before])
	t.check(vehicles.all(func(v: Variant) -> bool: return is_instance_valid(v) and raid.vehicles.has(v)),
			"and its vehicles stay, anyone's to drive off in")
	await _through(t, raid)
	await t._end_raid(raid)


## A player on a rover's gunner seat draws its roof gun, and has their own
## back when they get off.
static func _roof_gun(t: Node, raid: Raid, me: Actor) -> void:
	var rover := raid.spawn_vehicle("rover_warden", me.global_position + Vector3(4, 0.5, 0), 0.0)
	await t.frames(2)
	var held := me.get_active_weapon()
	var count := me.weapons.size()
	t.check(rover.call("mount", me, true, 0), "a player climbs onto a rover's roof gun")
	var gun := me.get_active_weapon()
	t.check(gun is Gun and gun.item_id == "mount_roof_gun" and me.weapons.size() == count + 1,
			"and has its gun in hand")
	t.check(not me.gear_items.has("mount_roof_gun"), "never theirs to keep")
	rover.call("get_off", me)
	t.check(me.weapons.size() == count and me.get_active_weapon() == held,
			"getting off leaves the gun on the rover, their own back in hand (%d/%d, %s)" % [me.weapons.size(), count,
			str(me.active_weapon_index)])
	raid.remove_vehicle(rover)


## A convoy that gets through drives off the map, crates and all.
static func _through(t: Node, raid: Raid) -> void:
	t.check(raid.start_event("convoy"), "another convoy sets out")
	var convoy: Dictionary = raid.convoy
	var vehicles: Array = (convoy.vehicles as Array).duplicate()
	var crates: Array = ((vehicles[0] as Node3D).get("cargo") as Array).duplicate()
	for i in vehicles.size():
		convoy.next[i] = (convoy.route as Array).size()
	await t.frames(3)
	await t.frames(2)
	t.check(raid.event.is_empty() and vehicles.all(func(v: Variant) -> bool: return not is_instance_valid(v) or (v as Node).is_queued_for_deletion()),
			"a convoy that gets through is gone with its vehicles")
	t.check(crates.all(func(c: Variant) -> bool: return not is_instance_valid(c) or (c as Node).is_queued_for_deletion()),
			"and its crates")
