extends RefCounted
## The `storm` checks. The test runner finds this file by itself and calls
## `run(t)`.


static func run(t: Node) -> void:
	print("A world that never ends")
	var raid: Raid = await t._new_raid(46, false)
	var world := raid.world
	var p := raid.player
	var count := raid.bots.size()
	raid.bots[0].kill("test")
	await t.frames(2)
	t.check(raid.bots.size() == count - 1 and raid._bot_respawns.size() == 1, "a dead bot is queued to be replaced")
	raid._bot_respawns[0] = 0.05
	await t.frames(10)
	var newest: Actor = raid.bots[-1]
	t.check(raid.bots.size() == count and not newest.is_dead and newest.has_node("Brain"),
			"a new bot takes its place")
	t.check(newest.global_position.distance_to(p.global_position) > 20.0, "it arrives away from the player")

	var cache: LootContainer = raid._caches[0].container
	cache.set_items([])
	await t.frames(3)
	t.check(raid._caches[0].refill_in > 0.0, "an emptied cache starts to refill")
	raid._caches[0].refill_in = 0.05
	await t.frames(10)
	t.check(not cache.items.is_empty(), "the cache fills up again")

	var spot: Dictionary = raid._parking[0]
	var bike: Node3D = spot.vehicle
	t.check(raid._is_parked(bike), "a bike waits at each parking spot")
	bike.global_position = p.global_position + Vector3(2.0, 0.5, 0.0)
	# A spot can set its own wait (a strongpoint's is longer).
	spot.empty_for = float(spot.marker.get_meta("respawn", world.vehicle_respawn_time)) - 0.05
	await t.frames(10)
	t.check(spot.vehicle != bike and raid._is_parked(spot.vehicle), "a bike that left its spot is replaced there")
	raid._idle[bike] = world.vehicle_respawn_time
	await t.frames(3)
	t.check(not is_instance_valid(bike) or bike.is_queued_for_deletion(), "a bike nobody rides is cleared away")
	t.check(spot.vehicle in raid.vehicles, "a parked bike is never cleared away")

	var is_bag := func(n: Node) -> bool:
		return n is LootContainer and (n as LootContainer).is_bag and not n.is_queued_for_deletion()
	var old_bags := raid.get_children().filter(is_bag)
	var lifetime := world.bag_lifetime
	world.bag_lifetime = 0.2
	raid.bots[1].kill("test")
	await t.frames(2)
	var bags := raid.get_children().filter(func(n: Node) -> bool: return is_bag.call(n) and n not in old_bags)
	t.check(bags.size() >= 1, "a dead bot drops a bag")
	var bag_ids := bags.map(func(n: Node) -> int: return n.get_instance_id())
	world.bag_lifetime = lifetime
	await t.get_tree().create_timer(0.5).timeout
	await t.frames(2)
	t.check(bag_ids.all(func(id: int) -> bool: return not is_instance_id_valid(id)), "old bags are cleared away")
	raid.clock = 100000.0
	await t.frames(5)
	t.check(not p.is_dead, "no storm ever comes for the player")
	await t._end_raid(raid)
