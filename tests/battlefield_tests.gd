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

	# A bike brought along is parked on the ground beside its rider, also on
	# a slope: under the surface it would fall for ever.
	var kit: Array = raid.world.starter_loadout()
	kit.append("bike_scrapper")
	var own_bikes: Array[Node3D] = []
	var above_ground := true
	for i in 8:
		var before := raid.vehicles.size()
		raid.add_player(kit, {}, "Rider")
		for v: Node3D in raid.vehicles.slice(before):
			own_bikes.append(v)
			above_ground = above_ground and v.global_position.y > under.call(v)
	await t.frames(90)
	var resting := 0
	for v in own_bikes:
		if is_instance_valid(v) and absf(v.global_position.y - under.call(v)) < 1.0:
			resting += 1
	t.check(own_bikes.size() == 8 and above_ground and resting == own_bikes.size(),
			"a bike you bring is parked on the ground beside you (%d of %d)" % [resting, own_bikes.size()])

	await _armies(t)
	await _big_battles(t)

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


## What keeps a big battle affordable: bots nobody is near run in longer
## steps, and a player hears less often about what is far away.
static func _big_battles(t: Node) -> void:
	print("Battlefield: big battles")
	var arena: Node3D = t._vehicle_arena()
	var steady := Actor.new()
	var thinned := Actor.new()
	arena.add_child(steady)
	arena.add_child(thinned)
	steady.global_position = arena.global_position + Vector3(-30, 0.1, 40)
	thinned.global_position = arena.global_position + Vector3(-36, 0.1, 40)
	thinned.thin(4, 1)
	await t.frames(20)
	var from_a := steady.global_position
	var from_b := thinned.global_position
	steady.cmd.move = Vector2(0, 1)
	thinned.cmd.move = Vector2(0, 1)
	var steps := 0
	var last := thinned.global_position
	for i in 120:
		await t.frames(1)
		if thinned.global_position.distance_to(last) > 0.001:
			steps += 1
		last = thinned.global_position
	var went_a := steady.global_position.distance_to(from_a)
	var went_b := thinned.global_position.distance_to(from_b)
	t.check(steps <= 32 and steps >= 28, "a thinned actor takes one step in four (%d steps in 120 ticks)" % steps)
	t.check(absf(went_a - went_b) < 0.8 and went_b > 9.0 and thinned.is_on_floor(),
			"and covers the same ground in longer steps (%.1f m and %.1f m)" % [went_a, went_b])
	thinned.thin(1)
	thinned.cmd.move = Vector2.ZERO
	thinned.cmd.jump_pressed = true
	await t.frames(1)
	thinned.cmd.jump_pressed = false
	await t.frames(8)
	t.check(thinned.tick_every == 1 and thinned.global_position.y > arena.global_position.y + 0.4,
			"back at full detail it answers every tick again")
	arena.queue_free()
	await t.frames(2)

	var world := Worlds.get_world("ashfront")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(world, 83)
	await t.frames(20)
	var all_far := raid.bots.all(func(b: Actor) -> bool: return b.tick_every == raid.far_detail_step)
	t.check(all_far and raid.far_detail_step > 1, "with nobody in the world every bot runs in long steps")
	var watcher := raid.add_player([], {}, "Watcher", "watcher")
	var near_bot: Actor = raid.bots[0]
	for bot in raid.bots:
		if bot.global_position.distance_to(watcher.global_position) \
				< near_bot.global_position.distance_to(watcher.global_position):
			near_bot = bot
	watcher.global_position = near_bot.global_position + Vector3(6, 1.0, 0)
	await t.frames(20)
	var full := 0
	var wrong := 0
	for bot in raid.bots:
		var apart := bot.global_position.distance_to(watcher.global_position)
		if bot.tick_every == 1:
			full += 1
		# Leave a margin: bots walk while the check runs.
		if (apart < raid.full_detail_range - 8.0 and bot.tick_every != 1) \
				or (apart > raid.half_detail_range + 8.0 and bot.tick_every != raid.far_detail_step):
			wrong += 1
	t.check(near_bot.tick_every == 1 and full >= 1 and full < raid.bots.size() and wrong == 0,
			"bots near a player run every tick, the far ones do not (%d of %d at full detail)" % [full, raid.bots.size()])
	t.check(watcher.tick_every == 1, "a player is never thinned")
	raid.queue_free()
	await t.frames(2)

	# Who hears about what, and how often.
	var eye := Vector3(10, 0, 10)
	t.check(NetSession.detail_tier(eye, eye + Vector3(NetSession.NEAR_RANGE - 1.0, 0, 0)) == 0
			and NetSession.detail_tier(eye, eye + Vector3(NetSession.NEAR_RANGE + 1.0, 0, 0)) == 1
			and NetSession.detail_tier(eye, eye + Vector3(0, 0, NetSession.MID_RANGE + 1.0)) == 2,
			"an actor is near, in between or far off for each viewer")
	var turns := [0, 0, 0]
	var spread := {}
	for update in 120:
		for tier in 3:
			if NetSession.detail_due(update, 7, tier):
				turns[tier] += 1
		for id in 24:
			if NetSession.detail_due(update, id, 2):
				spread[update] = int(spread.get(update, 0)) + 1
	var busiest := 0
	for update: int in spread:
		busiest = maxi(busiest, spread[update])
	t.check(turns[0] == 120 and turns[1] == 30 and turns[2] == 10,
			"near actors go out in every update, far ones a fraction as often (%d, %d, %d of 120)" % turns)
	t.check(busiest == 2, "far actors take turns instead of going out in one burst (%d of 24 at once)" % busiest)


## The two armies: who they are, what they hold, how they are reinforced and
## where they are sent.
static func _armies(t: Node) -> void:
	print("Battlefield: armies")
	var world := Worlds.get_world("ashfront")
	var raid := Raid.new()
	t.add_child(raid)
	raid.start_server(world, 81)
	for bot in raid.bots:
		bot.get_node("Brain").set_physics_process(false)
	var legion := raid.bots.filter(func(b: Actor) -> bool: return b.faction == "legion")
	var tide := raid.bots.filter(func(b: Actor) -> bool: return b.faction == "tide")
	t.check(legion.size() == tide.size() and legion.size() + tide.size() == raid.bots.size() and legion.size() >= 12,
			"the field starts with two armies of equal size (%d and %d)" % [legion.size(), tide.size()])
	t.check(not world.can_damage(legion[0], legion[1], null) and world.can_damage(legion[0], tide[0], null)
			and world.can_damage(tide[0], legion[0], null), "soldiers fight the other army, never their own")
	var held := {}
	for point in raid.strongpoints:
		held[point.holder] = int(held.get(point.holder, 0)) + 1
	t.check(held.get("faction:legion", 0) == 2 and held.get("faction:tide", 0) == 2 and held.get("", 0) == 1,
			"each army starts with two strongpoints and one is nobody's")
	var west := 0.0
	for bot: Actor in legion:
		west += bot.global_position.x / legion.size()
	var east := 0.0
	for bot: Actor in tide:
		east += bot.global_position.x / tide.size()
	t.check(west < -80.0 and east > 80.0, "the armies start on opposite sides of the field")

	# A bot rebuilt from what the server sends a client is the same soldier.
	var original: Actor = tide[0]
	var copy := raid.spawn_bot("Copy", original.global_position + Vector3(0, 40, 0), raid.bot_seeds[original],
			false, original.faction)
	t.check(copy.faction == original.faction and copy.display_name == original.display_name
			and copy.health.max_health == original.health.max_health, "a client builds the same soldier from its seed and army")
	raid.bots.erase(copy)
	copy.queue_free()

	# Orders: garrisons stay on what their army holds, the rest march on the
	# nearest site it does not.
	raid._orders_in = 0.0
	raid._tick_orders(0.1)
	var middle: Raid.Strongpoint = null
	for point in raid.strongpoints:
		if point.holder == "":
			middle = point
	var marching := {"legion": 0, "tide": 0}
	var guarding := {"legion": 0, "tide": 0}
	for bot in raid.bots:
		var post: Vector3 = (bot.get_node("Brain") as BotBrain).home()
		if post.distance_to(middle.global_position) < 1.0:
			marching[bot.faction] += 1
		else:
			for point in raid.strongpoints:
				if point.holder == "faction:" + bot.faction and post.distance_to(point.global_position) < 1.0:
					guarding[bot.faction] += 1
	t.check(guarding.legion == 2 * world.garrison_size and guarding.tide == 2 * world.garrison_size,
			"each army keeps a garrison on the sites it holds")
	t.check(marching.legion == legion.size() - guarding.legion and marching.tide == tide.size() - guarding.tide
			and marching.legion > 0, "and sends everyone else against the site between them (%d and %d)"
			% [marching.legion, marching.tide])

	# Reinforcements follow the war.
	t.check(raid.bot_target() == world.bot_count, "a quiet world keeps its usual number of bots")
	raid.war.intensity = 1.0
	t.check(raid.bot_target() == world.bot_count + world.war_reinforcements, "a world at war wants more")
	var before := raid.bots.size()
	for i in 4:
		raid.war.intensity = 1.0
		raid._reinforce_in = 0.0
		raid._tick_bots(0.1)
		raid._tick_bots(0.1)
	for bot in raid.bots:
		if bot.has_node("Brain"):
			bot.get_node("Brain").set_physics_process(false)
	var after_legion := raid.bots.filter(func(b: Actor) -> bool: return b.faction == "legion").size()
	t.check(raid.bots.size() == before + 4 and after_legion == legion.size() + 2,
			"reinforcements arrive one at a time, shared between the armies (%d to %d)" % [before, raid.bots.size()])
	raid.war.intensity = 0.0
	raid.war.scale = 0.0
	raid.bots[0].kill("bullet", null)
	await t.frames(2)
	t.check(raid._bot_respawns.is_empty(), "once it cools, the extra bots are not replaced")
	while raid.bots.size() >= world.bot_count:
		raid.bots[0].kill("bullet", null)
	await t.frames(2)
	t.check(raid._bot_respawns.size() == 1, "but the world never drops below its usual number")

	# Nobody arrives inside a site their army has lost.
	var lost: Raid.Strongpoint = null
	for point in raid.strongpoints:
		if point.holder == "faction:legion":
			lost = point
			break
	lost.hold("faction:tide", "the Tide", false)
	for bot in raid.bots.duplicate():
		if bot.faction == "legion":
			raid.bots.erase(bot)
	var safe := true
	for marker in raid._reinforcement_spawns():
		safe = safe and marker.get_meta("faction", "") == "legion" and not lost.covers(marker.global_position)
	t.check(safe, "reinforcements join the weaker army, away from the sites it has lost")
	raid.queue_free()
	await t.frames(2)
