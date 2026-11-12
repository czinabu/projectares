extends RefCounted
## Checks for open-ground maps: the `Terrain` helper, and Ashfront's
## battlefield built on it. Kept in its own file and called from the test runner.


static func run(t: Node) -> void:
	print("Battlefield: terrain")
	var ground := Terrain.new()
	ground.cell = 2.0
	ground.side = 11
	ground.shape(func(x: float, z: float) -> float: return x * 0.5 + (3.0 if z > 5.0 else 0.0))
	t.check(is_equal_approx(ground.extent(), 20.0), "a terrain knows how wide it is")
	t.check(is_equal_approx(ground.height_at(4.0, 0.0), 2.0) and is_equal_approx(ground.height_at(3.0, 0.0), 1.5),
			"the height between samples is blended")
	t.check(is_equal_approx(ground.height_at(500.0, 0.0), 5.0), "past the edge it answers for the edge")
	t.check(ground.slope_at(0.0, 0.0) > 0.4 and ground.slope_at(0.0, 0.0) < 0.6, "a slope can be measured")
	ground.build(StandardMaterial3D.new())
	t.add_child(ground)
	ground.position = Vector3(0, 0, 3000)
	var walker := Actor.new()
	t.add_child(walker)
	walker.global_position = Vector3(4.0, 8.0, 3000.0)
	await t.frames(90)
	t.check(absf(walker.global_position.y - 2.0) < 0.3,
			"an actor lands on the terrain where the mesh shows it (%.2f)" % walker.global_position.y)
	walker.queue_free()
	ground.queue_free()
	await t.frames(2)

	print("Battlefield: Ashfront")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start(Worlds.get_world("ashfront"), 77)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var map := raid.map
	var field: Terrain = map.get("terrain")
	t.check(field != null and field.extent() >= 600.0, "Ashfront is an open field at least 600 m across")
	var under := func(node: Node3D) -> float:
		return field.height_at(node.global_position.x, node.global_position.z)
	var grouped := func(group: String) -> Array:
		return t.get_tree().get_nodes_in_group(group).filter(func(n: Node) -> bool: return map.is_ancestor_of(n))

	var spawns: Array = grouped.call("spawn_player")
	var spread := 0.0
	var grounded := true
	for a: Node3D in spawns:
		grounded = grounded and absf(a.global_position.y - under.call(a)) < 0.3
		for b: Node3D in spawns:
			spread = maxf(spread, a.global_position.distance_to(b.global_position))
	t.check(spawns.size() >= 8 and spread > 400.0, "players drop in all around the rim (%d spots, %.0f m apart)"
			% [spawns.size(), spread])
	t.check(grounded, "every drop point stands on the ground")

	var sites: Array = grouped.call("strongpoint")
	t.check(sites.size() == 5, "the field has five strongpoints (%d)" % sites.size())
	var named := true
	var served := true
	var names := {}
	for site: Node3D in sites:
		named = named and site.get_meta("name", "") != "" and float(site.get_meta("radius", 0.0)) >= 20.0
		names[site.get_meta("name", "")] = true
		var near := false
		for depot in raid.depots:
			near = near or depot.global_position.distance_to(site.global_position) < float(site.get_meta("radius", 0.0)) + 6.0
		served = served and near
	t.check(named and names.size() == sites.size(), "each strongpoint has its own name and a radius")
	t.check(served and raid.depots.size() == sites.size(), "each strongpoint has a depot of its own")

	var caches: Array = grouped.call("spawn_cache")
	var high := caches.filter(func(c: Node3D) -> bool: return c.get_meta("loot_source", "cache") == "rooftop")
	var out_of_reach := true
	for c: Node3D in high:
		out_of_reach = out_of_reach and c.global_position.y - under.call(c) > 5.0
	t.check(caches.size() >= 30 and high.size() >= 6, "loot is spread over the field (%d caches, %d up high)"
			% [caches.size(), high.size()])
	t.check(out_of_reach, "the best loot sits where only a flight rig reaches")
	t.check(raid.bots.size() == raid.world.bot_count and raid.bots.size() >= 24,
			"the field starts with its garrisons and patrols (%d bots)" % raid.bots.size())
	t.check(grouped.call("spawn_vehicle").size() >= 10, "bikes are parked at the rim and the strongpoints")

	await t.frames(120)
	var p := raid.player
	t.check(p.is_on_floor() and absf(p.global_position.y - under.call(p)) < 0.3, "the player lands on open ground")
	var standing := 0
	for bot in raid.bots:
		if absf(bot.global_position.y - under.call(bot)) < 1.0:
			standing += 1
	t.check(standing == raid.bots.size(), "every bot stands on the ground (%d of %d)" % [standing, raid.bots.size()])

	# The field can be crossed on foot: the navigation mesh joins a drop point
	# on one side to a strongpoint on the other.
	var nav_map := p.get_world_3d().navigation_map
	for i in 600:
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			break
		await t.frames(1)
	# One search only looks so far, so a long march is made in legs: from the
	# rim to the middle, and from the middle out to each strongpoint.
	var middle: Vector3 = sites[0].global_position
	for site: Node3D in sites:
		if site.global_position.length() < middle.length():
			middle = site.global_position
	var reached := 0
	for site: Node3D in sites:
		var to := site.global_position
		var from: Vector3 = spawns[0].global_position if to == middle else middle
		var path := NavigationServer3D.map_get_path(nav_map, from, to, true)
		if path.size() >= 2 and path[path.size() - 1].distance_to(to) < 4.0:
			reached += 1
		else:
			print("    no way to %s (%d points, %.1f m short)" % [site.get_meta("name"), path.size(),
					path[path.size() - 1].distance_to(to) if path.size() > 0 else -1.0])
	t.check(reached == sites.size(), "bots can walk from the rim to every strongpoint (%d of %d)" % [reached, sites.size()])

	# Walking: uphill and down, the ground holds.
	var start := p.global_position
	# Towards the middle, but round the wall the drop point sits behind.
	p.cmd.yaw = atan2(start.x, start.z) + 0.9
	p.cmd.move = Vector2(0, 1)
	p.cmd.sprint = true
	await t.frames(240)
	p.cmd.move = Vector2.ZERO
	p.cmd.sprint = false
	t.check(p.global_position.distance_to(start) > 15.0 and absf(p.global_position.y - under.call(p)) < 0.6,
			"you can run across the open ground (%.0f m)" % p.global_position.distance_to(start))

	# The rim holds: nobody leaves the field, on foot or in the air.
	var edge := field.extent() * 0.5
	p.global_position = Vector3(edge - 14.0, field.height_at(edge - 14.0, 0.0) + 60.0, 0.0)
	p.velocity = Vector3(60.0, 0.0, 0.0)
	await t.frames(60)
	t.check(p.global_position.x < edge and not p.is_dead, "flying at the rim does not get you out of the world")

	# Built once, shared after: a second copy of the map is ready at once.
	var before := Time.get_ticks_msec()
	var again := Raid.new()
	t.add_child(again)
	again.start_server(Worlds.get_world("ashfront"), 78)
	var took := Time.get_ticks_msec() - before
	var twin: Terrain = again.map.get("terrain")
	t.check(twin.heights == field.heights and again.map.nav_region.navigation_mesh == map.nav_region.navigation_mesh,
			"a second copy of the map reuses the ground and the navigation mesh (%d ms)" % took)
	again.queue_free()
	raid.queue_free()
	await t.frames(2)
